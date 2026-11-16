-- Guild Bank Enhanced 1.0.1
do
-- Pure in-tab sort planning. It never calls a move API or changes live slots.
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local Planner={}; Planner.__index=Planner
function Planner.New(api)
    return setmetatable({api=api},Planner)
end

local function validItem(d)
    return d.link and d.itemID and d.name and d.itemType and d.itemSubType and d.maxStack and d.maxStack>=1
end
function Planner:Collect(tab,provided)
    local slots=provided or self.api.getSlots(tab); local sorted={}
    if not provided then
        for slot=1,98 do
            if self.api.getItemInfo(tab,slot) and not slots[slot] then
                return nil,nil,"Item link is not loaded on tab "..tab.." slot "..slot.."."
            end
        end
    end
    for _,item in pairs(slots) do
        if not validItem(item) then
            return nil,nil,"Item information is not loaded on tab "..tab..". Try again after the items load."
        end
        sorted[#sorted+1]=item
    end
    return slots,sorted
end
function Planner:FindStack(tab,slots)
    for dst=1,98 do
        local target=slots[dst]
        if target and target.maxStack>1 and target.count<target.maxStack then
            for src=dst+1,98 do
                local source=slots[src]
                if source and source.link==target.link and source.count<source.maxStack then
                    return {kind="stack",tab=tab,src=src,dst=dst,source=source,target=target,max=target.maxStack}
                end
            end
        end
    end
end
function Planner:FirstIncorrect(slots,sorted)
    for pos=1,98 do
        local physical=self.api.physicalSlot(pos)
        if not self.api.same(slots[physical],sorted[pos]) then return pos,sorted[pos] end
    end
end
function Planner:FindSource(slots,sorted,first,want)
    for pos=first+1,98 do
        local physical=self.api.physicalSlot(pos)
        if self.api.same(slots[physical],want) and not self.api.same(slots[physical],sorted[pos]) then return physical end
    end
end
function Planner:NextDestination(held,shadow,sorted)
    local emptyChoice
    for pos=1,98 do
        local physical=self.api.physicalSlot(pos); local before=shadow[physical]
        if self.api.same(held,sorted[pos]) and not self.api.same(before,sorted[pos]) then
            if before then return physical end
            emptyChoice=emptyChoice or physical
        end
    end
    return emptyChoice
end
local function wouldMergeUnexpectedly(before,held)
    return before and before.link==held.link and before.count<(before.maxStack or 1)
        and before.count+held.count<=(before.maxStack or 1)
end
function Planner:BuildChain(tab,slots,sorted,src)
    local shadow={}; for slot,item in pairs(slots) do shadow[slot]=item end
    local held=shadow[src]; shadow[src]=nil; local steps={}
    for _=1,98 do
        local dst=self:NextDestination(held,shadow,sorted)
        if not dst then return nil,"Could not complete the ordering chain on tab "..tab.."." end
        local before=shadow[dst]
        if wouldMergeUnexpectedly(before,held) then
            return nil,"Ordering chain would unexpectedly merge matching stacks on tab "..tab..". Rescan and retry."
        end
        steps[#steps+1]={dst=dst,before=before,after=held}
        shadow[dst]=held; held=before
        if not held then
            return {kind="order",tab=tab,src=src,dst=steps[1].dst,source=slots[src],target=steps[1].before,steps=steps}
        end
    end
    return nil,"Ordering chain exceeded the number of tab slots."
end
function Planner:FindOrder(tab,slots,sorted)
    table.sort(sorted,self.api.compare)
    local first,want=self:FirstIncorrect(slots,sorted)
    if not first then return nil,nil end
    if not want then return nil,"Ordering plan has an unexpected empty destination." end
    local src=self:FindSource(slots,sorted,first,want)
    if not src then return nil,"Could not find a misplaced stack for ordering on tab "..tab.."." end
    return self:BuildChain(tab,slots,sorted,src)
end
function Planner:Find(tab,provided,stackOnly)
    local slots,sorted,err=self:Collect(tab,provided)
    if err then return nil,err end
    local stack=self:FindStack(tab,slots)
    if stack then return stack end
    if stackOnly then return nil,nil end
    return self:FindOrder(tab,slots,sorted)
end
local function copySlots(data)
    local slots={}
    for slot,item in pairs(data) do
        local copy={}; for key,value in pairs(item) do copy[key]=value end
        slots[slot]=copy
    end
    return slots
end
local function simulateStack(slots,op)
    local total=op.source.count+op.target.count
    op.target.count=math.min(op.max,total)
    if total>op.max then op.source.count=total-op.max else slots[op.src]=nil end
end
local function simulateOrder(slots,op)
    local held=slots[op.src]; slots[op.src]=nil
    for _,step in ipairs(op.steps) do local previous=slots[step.dst]; slots[step.dst]=held; held=previous end
    return not held
end
function Planner:Estimate(tab,stackOnly)
    local slots,_,err=self:Collect(tab)
    if err then return nil end
    slots=copySlots(slots)
    local stack,order=0,0
    for _=1,500 do
        local op,why=self:Find(tab,slots,stackOnly)
        if why then return nil end
        if not op then return stack,order end
        if op.kind=="stack" then stack=stack+1; simulateStack(slots,op)
        else order=order+#op.steps; if not simulateOrder(slots,op) then return nil end end
    end
    return nil
end
modules.SortPlanner=Planner

end

do
-- Select a routing destination without performing any bank moves.
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local Selector={}; Selector.__index=Selector
function Selector.New(api) return setmetatable({api=api},Selector) end
function Selector:Primary(batch)
    local anyLocked=false
    for i=batch.index,#batch.moves do
        local move=batch.moves[i]; local free,locked=self.api.tabSpace(move.toTab)
        local merge=not free and self.api.findMerge(batch,move,move.toTab) or nil
        if free or merge then return {index=i,target=move.toTab,merge=merge} end
        anyLocked=anyLocked or locked
    end
    if anyLocked then return nil,"Target has locked empty slots; inspect tabs and retry." end
end
local function eligible(move,tab,secondary,overflow)
    if tab==move.fromTab or tab==move.toTab then return false end
    if secondary and overflow==move.fromTab then return false end
    return true
end
function Selector:Alternative(batch,candidate,overflow)
    local tab=candidate.tab; local free,locked=self.api.tabSpace(tab)
    if locked and not free then return nil,"Overflow/fallback has locked empty slots; inspect tabs and retry." end
    for i=batch.index,#batch.moves do
        local move=batch.moves[i]
        if eligible(move,tab,candidate.secondary,overflow) then
            local merge=not free and self.api.findMerge(batch,move,tab) or nil
            if free or merge then
                return {index=i,target=tab,merge=merge,overflow=true,secondary=candidate.secondary}
            end
        end
    end
end
function Selector:Choose(batch,overflow,fallback)
    local choice,err=self:Primary(batch)
    if choice or err then return choice,err end
    local candidates={}
    if overflow then candidates[#candidates+1]={tab=overflow,secondary=false} end
    if fallback and fallback~=overflow then candidates[#candidates+1]={tab=fallback,secondary=overflow~=nil} end
    for _,candidate in ipairs(candidates) do
        choice,err=self:Alternative(batch,candidate,overflow)
        if choice or err then return choice,err end
    end
end
modules.RouteSelector=Selector

end

-- Guild Bank Enhanced for WoW 3.3.5a

local GBS = {}
_G["GuildBankEnhanced"] = GBS
_G["GuildBankSorter"] = GBS

-- ============================================================
-- DB / Config
-- ============================================================
GBSCharDB = GBSCharDB or {}
local function NormaliseDelay(value,default)
    if type(value)~="number" or value~=value then value=default end
    value=math.max(0,math.min(1,value))
    return math.floor(value*20+0.5)/20
end
GBSCharDB.moveDelay=NormaliseDelay(GBSCharDB.moveDelay,0.1)
GBSCharDB.scanDelay=NormaliseDelay(GBSCharDB.scanDelay,0.3)
GBSCharDB.tabAssignments = GBSCharDB.tabAssignments or {}
if not GBSCharDB.sortDir then GBSCharDB.sortDir="col" end -- row=-> down, col= down->, row_rev=<- down, snake=zigzag

local NUM_TABS = 6
local BANK_COLS, BANK_ROWS, SLOT_SIZE, SLOT_GAP = 14, 7, 34, 3

local function GetMoveDelay() return GBSCharDB.moveDelay or 0.1 end
local function GetScanDelay() return GBSCharDB.scanDelay or 0.3 end
GBS.GetMoveDelay = GetMoveDelay
GBS.GetScanDelay = GetScanDelay

GBS.isRunning = false
GBS.cancelRequested = false
local function UpdateStopButtons() if GBS.Bank and GBS.Bank.UpdateProcessing then GBS.Bank:UpdateProcessing() end end
GBS.UpdateStopButtons=UpdateStopButtons
GBS.queue = {}
GBS.queueIndex = 1
GBS.totalSteps = 0
GBS.doneSteps = 0
GBS.timer = 0
GBS.currentPhase = ""
GBS.scanData = nil
GBS.otherTab = nil
GBS.globalOtherTab = nil
GBS.categoryOtherTabs = {}
GBS.categoryOtherKeywords = {}
GBS.tabKeywords = {}
GBS.tabNames = {}
GBS.tabNumSlots = {}

local UpdateBankPanelTabs -- forward
local UpdateSortControls -- forward
local CreateBankPanel
local SkinGuildBank
local SkinScroll
local function Chat(msg, r,g,b) DEFAULT_CHAT_FRAME:AddMessage("[GBE] "..msg, r,g,b) end

local function SaveFramePos(frame, key)
    if not frame or not key then return end
    local left,bottom=frame:GetLeft(),frame:GetBottom()
    local rootLeft,rootBottom=UIParent:GetLeft(),UIParent:GetBottom()
    if left and bottom and rootLeft and rootBottom then
        local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        GBSCharDB[key]={point="BOTTOMLEFT",x=left*scale-rootLeft,y=bottom*scale-rootBottom}
    else
        local point, relative, relativePoint, x, y=frame:GetPoint()
        if point and relative==UIParent and relativePoint==point then GBSCharDB[key]={point=point,x=x,y=y} end
    end
end
local function RestoreFramePos(frame, key, defaultPoint, defaultX, defaultY)
    local pos=GBSCharDB[key]
    if pos and pos.point then
        frame:ClearAllPoints(); frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    elseif defaultPoint then
        frame:ClearAllPoints(); frame:SetPoint(defaultPoint, UIParent, defaultPoint, defaultX or 0, defaultY or 0)
    end
end

local function Log(msg, r,g,b) if GBS.logFrame and GBS.logFrame.addMessage then GBS.logFrame:addMessage(msg,r,g,b) end end

local function Trim(s) if not s then return "" end; if type(s)~="string" then s=tostring(s) end; return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function Lower(s) if not s then return "" end; if type(s)~="string" then s=tostring(s) end; return string.lower(s) end

-- ============================================================
-- Interface styles
-- ============================================================
-- Use the real addon directory when the loader supplies it; do not assume
-- that the user extracted the folder under a particular name.
local addonName = ...
if type(addonName) ~= "string" or addonName == "" then addonName = "GuildBankEnhanced" end
local requestedFont = "Interface\\AddOns\\"..addonName.."\\Fonts\\PTSansNarrow-Bold.ttf"
local GBS_FONT_SIZE=14
local GBS_VERSION="1.0.1"
local GBSFont=CreateFont("GBSFont")
GBSFont:SetShadowOffset(0,0); GBSFont:SetShadowColor(0,0,0,0)
local function SetFontAndCheck(object,path)
    if not path then return false end
    local ok=pcall(object.SetFont,object,path,GBS_FONT_SIZE,"")
    if not ok then return false end
    -- Old clients may return nil even on success; query the resulting font.
    local gotOK,actual=pcall(object.GetFont,object)
    return gotOK and type(actual)=="string" and actual~=""
end
local fontAvailable=SetFontAndCheck(GBSFont,requestedFont)
local GBS_FONT=requestedFont
if not fontAvailable then
    local defaultFont=GameFontNormal and GameFontNormal:GetFont()
    GBS_FONT=defaultFont or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    SetFontAndCheck(GBSFont,GBS_FONT)
end
local function CreateGBSFontString(parent,layer)
    -- Start with a Blizzard font template, then apply our actual font object
    -- explicitly. A missing addon font must never leave a string uninitialized.
    local fs=parent:CreateFontString(nil,layer,"GameFontNormal")
    if GBSFont:GetFont() then fs:SetFontObject(GBSFont) end
    return fs
end
local E = {
    bg={0.10,0.10,0.10,0.96}, bg2={0.13,0.13,0.13,1}, bg3={0.07,0.07,0.07,1},
    border={0.22,0.22,0.22,1}, accent={0.18,0.62,0.42},
    text={0.92,0.92,0.92}, muted={0.55,0.55,0.55},
}
local function StyleBackdrop(f, alpha)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    f:SetBackdropColor(E.bg[1],E.bg[2],E.bg[3], alpha or E.bg[4])
    f:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1)
end
local function StyleInset(f) StyleBackdrop(f,1); f:SetBackdropColor(E.bg3[1],E.bg3[2],E.bg3[3],1) end
local function StyleSeparator(parent, y)
    local t=parent:CreateTexture(nil,"OVERLAY"); t:SetTexture("Interface\\Buttons\\WHITE8x8"); t:SetVertexColor(E.border[1],E.border[2],E.border[3],0.9)
    t:SetHeight(1); t:SetPoint("LEFT",parent,"LEFT",1,0); t:SetPoint("RIGHT",parent,"RIGHT",-1,0); t:SetPoint("TOP",parent,"TOP",0,y); return t
end
local function StyleButton(btn, isPrimary)
    if not btn then return end
    btn:SetNormalFontObject("GBSFont"); btn:SetHighlightFontObject("GBSFont"); btn:SetDisabledFontObject("GBSFont")
    local buttonText=btn:GetFontString(); if buttonText then buttonText:SetFont(GBS_FONT,GBS_FONT_SIZE,""); buttonText:SetTextColor(0.95,0.95,0.95) end
    btn:SetNormalTexture(""); btn:SetPushedTexture(""); btn:SetHighlightTexture(""); btn:SetDisabledTexture("")
    if btn.Left then btn.Left:Hide() end; if btn.Middle then btn.Middle:Hide() end; if btn.Right then btn.Right:Hide() end
    StyleBackdrop(btn,1)
    if isPrimary then
        btn:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1)
        btn:SetBackdropBorderColor(E.accent[1]*0.7,E.accent[2]*0.7,E.accent[3]*0.7,1)
        local fs=btn:GetFontString(); if fs then fs:SetTextColor(1,1,1) end
        btn:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(1,1,1,0.6) end)
        btn:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(E.accent[1]*0.7,E.accent[2]*0.7,E.accent[3]*0.7,1) end)
    else
        btn:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1)
        btn:HookScript("OnEnter", function(s) s:SetBackdropColor(0.18,0.18,0.18,1); s:SetBackdropBorderColor(0.45,0.45,0.45,1) end)
        btn:HookScript("OnLeave", function(s) s:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); s:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1) end)
    end
    btn:HookScript("OnDisable", function(s) s:SetBackdropColor(0.10,0.10,0.10,1); s:SetBackdropBorderColor(0.16,0.16,0.16,1); local fs=s:GetFontString(); if fs then fs:SetTextColor(0.45,0.45,0.45) end end)
    btn:HookScript("OnEnable", function(s) if isPrimary then s:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1); local fs=s:GetFontString(); if fs then fs:SetTextColor(1,1,1) end else s:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); local fs=s:GetFontString(); if fs then fs:SetTextColor(0.95,0.95,0.95) end end end)
end
local function StyleThinBar(parent,w,h)
    local bar=CreateFrame("StatusBar",nil,parent); bar:SetSize(w,h); bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0,100); bar:SetValue(0); bar:SetStatusBarColor(E.accent[1],E.accent[2],E.accent[3],1)
    StyleInset(bar); bar:SetBackdropColor(0.08,0.08,0.08,1); return bar
end
SkinScroll = function(scroll)
    if not scroll or not scroll.GetName then return end
    pcall(function()
        local name=scroll:GetName(); if not name then return end
        local bar=_G[name.."ScrollBar"]; if not bar then return end
        bar:SetWidth(8)
        local up=_G[name.."ScrollBarScrollUpButton"]; local down=_G[name.."ScrollBarScrollDownButton"]
        if up then up:Hide(); up:SetAlpha(0); up:SetSize(1,1) end
        if down then down:Hide(); down:SetAlpha(0); down:SetSize(1,1) end
        bar:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=0,right=0,top=0,bottom=0}})
        bar:SetBackdropColor(0.08,0.08,0.08,1); bar:SetBackdropBorderColor(0.22,0.22,0.22,0.9)
        local thumb=bar:GetThumbTexture(); if thumb then thumb:SetTexture("Interface\\Buttons\\WHITE8x8"); thumb:SetVertexColor(0.35,0.35,0.35,1); thumb:SetWidth(8) end
        bar:Show()
    end)
end
GBS.SkinScroll = SkinScroll

local function CreateTitleClose(frame,titleBar)
    local close=CreateFrame("Button",nil,titleBar)
    close:SetSize(20,20); close:SetPoint("RIGHT",titleBar,"RIGHT",-2,0)
    local text=CreateGBSFontString(close,"OVERLAY")
    text:SetPoint("CENTER",close,"CENTER",0,2); text:SetText("X"); text:SetTextColor(0.75,0.75,0.75)
    close:SetScript("OnEnter",function() text:SetTextColor(1,0.35,0.35) end)
    close:SetScript("OnLeave",function() text:SetTextColor(0.75,0.75,0.75) end)
    close:SetScript("OnClick",function() frame:Hide() end)
    return close
end

-- Plain, theme-matched text inputs; avoid Blizzard's InputBoxTemplate caps.
local function CreateGBSInput(parent,w,h)
    local eb=CreateFrame("EditBox",nil,parent)
    eb:SetSize(w,h); eb:SetAutoFocus(false); eb:SetFont(GBS_FONT,GBS_FONT_SIZE,"")
    eb:SetTextInsets(6,6,0,0); eb:SetTextColor(0.95,0.95,0.95,1)
    StyleBackdrop(eb,1); eb:SetBackdropColor(0.07,0.07,0.07,1)
    return eb
end

local function CreateGBSFrameBase(name,w,h, lvl)
    local f=CreateFrame("Frame",name,UIParent); f:SetSize(w,h); StyleBackdrop(f,0.96); f:SetBackdropBorderColor(0,0,0,1)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(false); if lvl then f:SetFrameLevel(lvl) end
    f:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end); f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local n=s:GetName(); if n=="GBSBankPanel" then SaveFramePos(s,"panelPos") elseif n=="GBSCustomBank" then SaveFramePos(s,"bankPos") elseif n=="GBSMoneyBox" then SaveFramePos(s,"moneyPos") end end)
    f:SetClampedToScreen(true); if f.SetClampedRectInsets then f:SetClampedRectInsets(0,0,0,0) end
    local titleBar=CreateFrame("Frame",nil,f); titleBar:SetFrameLevel(f:GetFrameLevel()+1); titleBar:SetHeight(22); titleBar:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1); titleBar:SetPoint("TOPRIGHT",f,"TOPRIGHT",-1,-1)
    titleBar:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"}); titleBar:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); f.titleBar=titleBar
    local close=CreateTitleClose(f,titleBar)
    f.closeBtn=close; f.close=close
    return f
end

-- ============================================================
-- Categories (single source for Assign UI + matching)
-- ============================================================
local CATEGORIES = {
    { name="Trade Goods", color="7ab26d", subs={"Herb","Cloth","Leather","Metal & Stone","Meat","Cooking","Elemental","Jewelcrafting","Enchanting","Inscription","Parts","Devices","Explosives","Materials","Other"} },
    { name="Armor",       color="6b8fb0", subs={"Cloth","Leather","Mail","Plate","Shield","Librams","Idols","Totems","Sigils","Relic"} },
    { name="Weapon",      color="b08a6b", subs={"One-Handed Axes","Two-Handed Axes","Bows","Guns","One-Handed Maces","Two-Handed Maces","Polearms","One-Handed Swords","Two-Handed Swords","Staves","Fist Weapons","Daggers","Thrown","Crossbows","Wands","Fishing Poles"} },
    { name="Consumable",  color="b06b6b", subs={"Potion","Elixir","Flask","Food & Drink","Bandage","Scroll"} },
    { name="Container",   color="8a8a8a", subs={"Bag","Soul Bag","Herb Bag","Enchanting Bag","Engineering Bag","Gem Bag","Mining Bag","Leatherworking Bag","Inscription Bag"} },
    { name="Gem",         color="8b6bb0", subs={"Red","Blue","Yellow","Purple","Green","Orange","Meta","Prismatic"} },
    { name="Recipe",      color="b0a66b", subs={"Book","Leatherworking","Tailoring","Engineering","Blacksmithing","Alchemy","First Aid","Fishing","Mining","Enchanting","Inscription","Jewelcrafting","Cooking"} },
    { name="Reagent",     color="7a7a7a", subs={} },
    { name="Glyph",       color="6b9b8b", subs={} },
    { name="Quest",       color="8a9b6b", subs={} },
    { name="Key",         color="6b6b6b", subs={} },
    { name="Miscellaneous",color="8a8a8a", subs={"Junk"} },
    { name="Projectile",  color="8a9b6b", subs={"Arrow","Bullet"} },
    { name="Quiver",      color="6b8a6b", subs={"Ammo Pouch"} },
}
GBS.CATEGORIES = CATEGORIES

-- Sort direction helpers
GBS.SortDirections = {
    {id="row", label="RIGHT > DOWN", desc="Left to right, top to bottom."},
    {id="row_up", label="RIGHT > UP", desc="Left to right, bottom to top."},
    {id="row_rev", label="LEFT > DOWN", desc="Right to left, top to bottom."},
    {id="row_rev_up", label="LEFT > UP", desc="Right to left, bottom to top."},
    {id="col", label="DOWN > RIGHT", desc="Top to bottom, left to right."},
    {id="col_left", label="DOWN > LEFT", desc="Top to bottom, right to left."},
    {id="col_up", label="UP > RIGHT", desc="Bottom to top, left to right."},
    {id="col_up_left", label="UP > LEFT", desc="Bottom to top, right to left."},
    {id="snake", label="ZIGZAG", desc="Alternate row direction while moving down."},
}
function GBS:GetPhysicalSlot(logical)
    local dir=GBSCharDB.sortDir or "col"; local n=logical-1
    local row,col
    if dir=="col" or dir=="col_left" or dir=="col_up" or dir=="col_up_left" then
        col=math.floor(n/BANK_ROWS); row=n%BANK_ROWS
        if dir=="col_left" or dir=="col_up_left" then col=BANK_COLS-1-col end
        if dir=="col_up" or dir=="col_up_left" then row=BANK_ROWS-1-row end
    else
        row=math.floor(n/BANK_COLS); col=n%BANK_COLS
        if dir=="row_up" or dir=="row_rev_up" then row=BANK_ROWS-1-row end
        if dir=="row_rev" or dir=="row_rev_up" or (dir=="snake" and row%2==1) then col=BANK_COLS-1-col end
    end
    return row*BANK_COLS+col+1
end
function GBS:GetLogicalSlot(phys)
    local dir=GBSCharDB.sortDir or "col"; local row=math.floor((phys-1)/BANK_COLS); local col=(phys-1)%BANK_COLS
    if dir=="col" or dir=="col_left" or dir=="col_up" or dir=="col_up_left" then
        if dir=="col_left" or dir=="col_up_left" then col=BANK_COLS-1-col end
        if dir=="col_up" or dir=="col_up_left" then row=BANK_ROWS-1-row end
        return col*BANK_ROWS+row+1
    end
    if dir=="row_rev" or dir=="row_rev_up" or (dir=="snake" and row%2==1) then col=BANK_COLS-1-col end
    if dir=="row_up" or dir=="row_rev_up" then row=BANK_ROWS-1-row end
    return row*BANK_COLS+col+1
end


-- ============================================================
-- Matching
-- ============================================================
local function KeywordMatches(keyword, itemType, itemSubType)
    if not keyword or keyword=="" then return false end
    local kw=Lower(keyword)
    local t=Lower(itemType or "")
    local s=Lower(itemSubType or "")
    if kw==t or kw==s then return true end
    if string.find(t, kw, 1, true) or string.find(s, kw, 1, true) then return true end
    local kw2=kw:gsub("&","and")
    local t2=t:gsub("&","and"); local s2=s:gsub("&","and")
    if kw2==t2 or kw2==s2 then return true end
    return false
end
local function KeywordMatchScore(keyword, itemType, itemSubType)
    if not keyword then return 0 end
    local kw=Lower(keyword); local t=Lower(itemType or ""); local s=Lower(itemSubType or "")
    if kw==s then return 2 end
    if kw==t then return 1 end
    if s~="" and string.find(s,kw,1,true) then return 2 end
    if t~="" and string.find(t,kw,1,true) then return 1 end
    return 0
end
GBS.KeywordMatches=KeywordMatches; GBS.KeywordMatchScore=KeywordMatchScore

local CLOTH_TIER = { linen=1, wool=2, silk=3, mageweave=4, runecloth=5, netherweave=6, frostweave=7, embersilk=8, windwool=9, ["heavy silken"]=3.5, ["rune thread"]=10 }
local VENDOR_KEYWORDS = {"thread","dye","flux","salt","vial","parchment","ink","dust","powder","spices","spice","hot spices","soothing spices","mild spices","holiday spices","coarse thread","fine thread","silken thread","heavy silken thread","enchanted thread","rune thread","bleach"}
local CRAFTED_KEYWORDS = {"bolt","bar","ingot","grinding","enchanted","coarse","heavy","solid","dense","fel","adamantite","cobalt","saronite","stone","grinding stone","sharpening stone","weightstone","chain","wire","oil","transmute"}
local function GetClothTier(name, subtype) if Lower(subtype or "")~="cloth" then return 50 end; local n=Lower(name or ""); for k,v in pairs(CLOTH_TIER) do if string.find(n,k,1,true) then return v end end; return 50 end
local function GetItemCategory(name, subtype, itemType) local n=Lower(name or ""); for _,kw in ipairs(VENDOR_KEYWORDS) do if string.find(n,kw,1,true) then return 3 end end; for _,kw in ipairs(CRAFTED_KEYWORDS) do if string.find(n,kw,1,true) then return 2 end end; return 1 end
GBS.GetClothTier=GetClothTier; GBS.GetItemCategory=GetItemCategory; GBS.VENDOR_KEYWORDS=VENDOR_KEYWORDS; GBS.CRAFTED_KEYWORDS=CRAFTED_KEYWORDS; GBS.CLOTH_TIER=CLOTH_TIER

-- ============================================================
-- WoW API Wrappers
-- ============================================================
local function GetTabInfo(tab)
    if type(GetGuildBankTabInfo)=="function" then local ok,n,icon,isViewable,canDeposit,numWithdrawals,remaining=pcall(GetGuildBankTabInfo,tab); if ok then return n,icon,isViewable end end
    return nil
end
local function SafeSelectGuildBankTab(tab) if type(SetCurrentGuildBankTab)=="function" then pcall(SetCurrentGuildBankTab, tab) end; if type(QueryGuildBankTab)=="function" then pcall(QueryGuildBankTab, tab) end; if type(SelectGuildBankTab)=="function" then pcall(SelectGuildBankTab, tab) end end
local function ParseItemIDFromLink(link) if not link then return nil end; local id=link:match("item:(%d+)"); if id then return tonumber(id) end; return nil end
local function GetSlotCount(tab, slot) if type(GetGuildBankItemInfo)~="function" then return 1 end; local ok,a,b=pcall(GetGuildBankItemInfo,tab,slot); if not ok then return 1 end; if type(b)=="number" then return b end; return 1 end
local function GetSlotData(tab, slot)
    if type(GetGuildBankItemLink)~="function" then return nil end
    local ok,link=pcall(GetGuildBankItemLink,tab,slot); if not ok or not link then return nil end
    local itemID=ParseItemIDFromLink(link); local count=GetSlotCount(tab,slot)
    if type(GetItemInfo)~="function" then return {tab=tab,slot=slot,link=link,itemID=itemID,count=count or 1} end
    local ok2,name,_,rarity,itemLevel,itemMinLevel,itemType,itemSubType,stackCount=pcall(GetItemInfo, link)
    if not ok2 then name=nil end
    if not name and itemID then local ok3; ok3,name,_,rarity,itemLevel,itemMinLevel,itemType,itemSubType,stackCount=pcall(GetItemInfo,itemID); if not ok3 then name=nil end end
    return {tab=tab,slot=slot,link=link,itemID=itemID,count=count or 1,name=name,rarity=rarity,itemLevel=itemLevel,itemType=itemType,itemSubType=itemSubType,maxStack=stackCount}
end
local function FindEmptySlot(tab) for s=1,98 do local texture=GetGuildBankItemInfo(tab,s); if not texture and not GetGuildBankItemLink(tab,s) then return s end end; return nil end
local function GetTabSlotsData(tab) local out={}; for s=1,98 do local d=GetSlotData(tab,s); if d then out[s]=d end end; return out end
local function CountItemsInTab(tab) local n=0; for s=1,98 do if GetGuildBankItemInfo(tab,s) or GetGuildBankItemLink(tab,s) then n=n+1 end end; return n end
local function UpdateTabCounts(...)
    if not GBS.Bank then return end
    GBS.Bank.knownCounts=GBS.Bank.knownCounts or {}
    for i=1,select("#",...) do local tab=select(i,...); if tab then GBS.Bank.knownCounts[tab]=CountItemsInTab(tab) end end
    GBS.Bank:RefreshTabs()
end
local function SafePickupGuildBankItem(tab,slot) if type(PickupGuildBankItem)=="function" then pcall(PickupGuildBankItem,tab,slot) end end
local function SafeGetCursorInfo() if type(GetCursorInfo)=="function" then local ok, t=pcall(GetCursorInfo); if ok then return t end end; return nil end

-- ============================================================
-- Assignment DB (OOP: GBS.Assign)
-- ============================================================
GBS.Assign = {}
local function TypeKey(name) return "type:"..Lower(name) end
local function SubKey(parent,name) return "sub:"..Lower(parent)..":"..Lower(name) end
local function NormalType(name) return Lower(Trim(name or "")):gsub("%s*&%s*"," and ") end
local function AssignmentScore(key,itemType,itemSubType)
    if type(key)~="string" then return 0 end
    local parent,sub=key:match("^sub:([^:]+):(.+)$")
    if parent then
        if NormalType(parent)==NormalType(itemType) and NormalType(sub)==NormalType(itemSubType) then return 2 end
        return 0
    end
    parent=key:match("^type:(.+)$")
    if parent and NormalType(parent)==NormalType(itemType) then return 1 end
    return 0
end
function GBS.Assign:Set(tab,keywords,isOther,isOverflow)
    GBS.scanData=nil
    if isOther then GBSCharDB.otherTab=tab; GBSCharDB.tabAssignments[tab]=nil
    else if GBSCharDB.otherTab==tab then GBSCharDB.otherTab=nil end; GBSCharDB.tabAssignments[tab]=keywords and #keywords>0 and keywords or nil end
    if isOverflow~=nil then
        if isOverflow then GBSCharDB.overflowTab=tab elseif GBSCharDB.overflowTab==tab then GBSCharDB.overflowTab=nil end
    end
    if GBS.UpdateSortControls then GBS.UpdateSortControls() end
end
function GBS.Assign:Get(tab) return GBSCharDB.tabAssignments[tab] end
function GBS.Assign:IsOther(tab) return GBSCharDB.otherTab==tab end
function GBS.Assign:IsOverflow(tab) return GBSCharDB.overflowTab==tab end
function GBS.Assign:Describe(tab)
    local lines={}; local set={}; for _,key in ipairs(self:Get(tab) or {}) do set[key]=true end
    for _,cat in ipairs(CATEGORIES) do
        local subs={}; for _,sub in ipairs(cat.subs) do if set[SubKey(cat.name,sub)] then subs[#subs+1]=sub end end
        local all=set[TypeKey(cat.name)]
        if all or #subs>0 then
            lines[#lines+1]=cat.name..(all and " (all)" or "")
            for _,sub in ipairs(subs) do lines[#lines+1]="  "..sub end
        end
    end
    if self:IsOther(tab) then lines[#lines+1]="Fallback (unmatched items)" end
    if self:IsOverflow(tab) then lines[#lines+1]="Overflow (full targets)" end
    if #lines==0 then lines[1]="No assignments" end
    return lines
end

function GBS:CheckOtherTab()
    self.otherTab=nil; self.globalOtherTab=nil; self.overflowTab=nil; self.categoryOtherTabs={}; self.categoryOtherKeywords={}
    self.tabNames={}; self.tabNumSlots={}; self.tabKeywords={}; self.noTabsReason=nil
    local count=0
    if type(GetNumGuildBankTabs)=="function" then
        local ok,n=pcall(GetNumGuildBankTabs)
        if ok and type(n)=="number" then count=math.min(NUM_TABS,math.max(0,n)) end
    end
    for tab=1,count do
        local name=GetTabInfo(tab)
        self.tabNames[tab]=(name and name~="") and name or ("Tab "..tab)
        self.tabNumSlots[tab]=98
        if GBSCharDB.tabAssignments[tab] then self.tabKeywords[tab]=GBSCharDB.tabAssignments[tab] end
    end
    if GBSCharDB.otherTab and self.tabNames[GBSCharDB.otherTab] then self.globalOtherTab=GBSCharDB.otherTab end
    self.otherTab=self.globalOtherTab
    if GBSCharDB.overflowTab and self.tabNames[GBSCharDB.overflowTab] then self.overflowTab=GBSCharDB.overflowTab end
    if count==0 then self.noTabsReason="Waiting for guild bank tab information." end
    if UpdateSortControls then UpdateSortControls() end
    return self.otherTab
end

-- ============================================================
-- Queue (OnUpdate, 3.3.5 no C_Timer)
-- ============================================================
local processorFrame=CreateFrame("Frame","GBSProcessor",UIParent); processorFrame:Hide()
processorFrame:SetScript("OnUpdate", function(self, elapsed)
    if not GBS.isRunning then self:Hide(); return end
    if GBS.cancelRequested then GBS:Stop("Cancelled by user."); return end
    GBS.timer=GBS.timer-elapsed; if GBS.timer>0 then return end
    if GBS.queueIndex > #GBS.queue then local phase=GBS.currentPhase; local cb=GBS.onQueueDone; GBS.queue={}; GBS.queueIndex=1; GBS.onQueueDone=nil; if cb then cb() end; return end
    local step=GBS.queue[GBS.queueIndex]; GBS.queueIndex=GBS.queueIndex+1; GBS.doneSteps=GBS.doneSteps+1; GBS:UpdateProgress()
    local ok,err=pcall(step.fn); if not ok then Log("Error in "..tostring(step.label)..": "..tostring(err),1,0.3,0.3); Chat("Error: "..tostring(err),1,0.3,0.3); GBS:Stop("Stopped after an error."); return end
    GBS.timer=step.delay or GetMoveDelay()
end)
function GBS:Enqueue(fn,label,delay) table.insert(self.queue,{fn=fn,label=label,delay=delay}) end
function GBS:RunQueue(onDone) self.queueIndex=1; self.totalSteps=#self.queue; self.doneSteps=0; self.onQueueDone=onDone; self.timer=0; processorFrame:Show(); self:UpdateProgress() end
function GBS:UpdateProgress()
    if self.Bank and self.Bank.UpdateProcessing then self.Bank:UpdateProcessing() end
end
function GBS:Stop(msg)
    self.isRunning=false; self.cancelRequested=false; processorFrame:Hide()
    UpdateStopButtons()
    if UpdateSortControls then UpdateSortControls() end
    if msg then Log(msg,0.6,0.8,1) end
    self:UpdateProgress()
end

-- ============================================================
-- Scan / Routing
-- ============================================================
function GBS:ScanAllTabs(onDone)
    self:CheckOtherTab()
    local tabList={}
    for tab=1,NUM_TABS do if self.tabNumSlots[tab] then table.insert(tabList, tab) end end
    if #tabList==0 then Log("No tabs to scan.",1,0.4,0.4); if onDone then onDone(nil) end; return end
    self.currentPhase="Scanning..."
    Log(string.format("Scanning %d tabs...", #tabList),0.6,0.85,1)
    self.queue={}
    for _,tab in ipairs(tabList) do
        local t=tab
        self:Enqueue(function() SafeSelectGuildBankTab(t) end, "Open tab "..t, GetScanDelay())
    end
    self:Enqueue(function()
        local items={}; local tabsScanned={}
        for _,tab in ipairs(tabList) do
            local cnt=0
            for s=1,98 do local d=GetSlotData(tab,s); if d then table.insert(items,d); cnt=cnt+1 end end
            local occupied=CountItemsInTab(tab); tabsScanned[tab]=occupied
            Log(string.format("  Tab %d (%s): %d occupied slots", tab, self.tabNames[tab] or "?", occupied),0.7,0.7,0.7)
            if cnt<occupied then Log(string.format("  Tab %d: %d occupied slots have unloaded item links.",tab,occupied-cnt),1,0.7,0.3) end
        end
        self.scanData={items=items, tabsScanned=tabsScanned}
        if self.Bank then self.Bank.knownCounts=tabsScanned; self.Bank:RefreshTabs() end
    end, "Collect", 0)
    self:RunQueue(function() if self.scanData and self.scanData.items then
        if onDone and self.scanData then onDone(self.scanData) end
    end end)
end
function GBS:DetermineTargetTab(item)
    if not item.itemType or not item.itemSubType then return nil end
    local bestTab,bestScore=nil,0
    for tab=1,NUM_TABS do
        for _,key in ipairs(self.tabKeywords[tab] or {}) do
            local score=AssignmentScore(key,item.itemType,item.itemSubType)
            if score>bestScore then bestTab,bestScore=tab,score end
        end
    end
    return bestTab or self.globalOtherTab or self.otherTab
end
function GBS:BuildMovePlan(items)
    local moves={}; local counts={}
    for _,it in ipairs(items) do
        local target=self:DetermineTargetTab(it)
        if not target then Log("No target for "..(it.name or ("item "..tostring(it.itemID))),1,0.5,0.5)
        elseif target~=it.tab then table.insert(moves,{fromTab=it.tab,fromSlot=it.slot,toTab=target,item=it}); counts[target]=(counts[target] or 0)+1 end
    end
    return moves,counts
end
-- ============================================================
-- High-level Sort Flow
-- ============================================================
function GBS:StartSort()
    if self.isRunning or self.routing or self.activeMove then Chat("Already running. Wait or /reload.",1,0.8,0.2); return end
    if not (self.Bank and self.Bank:IsOpen()) then Chat("Open the guild bank first.",1,0.4,0.4); return end
    if SafeGetCursorInfo() then Chat("Clear the cursor before sorting.",1,0.4,0.4); return end
    self:CheckOtherTab()
    if not self.globalOtherTab then
        if not next(self.tabNames or {}) then Chat("Open Guild Bank first.",1,0.4,0.4); return end
        Log("No fallback tab set - unassigned items will be skipped. Assign a Fallback (Other) tab.",1,0.8,0.2)
    end
    self.scanData=nil; self.workRouteDone=0
    self:DoSort(false)
end
function GBS:DoSort(afterPrestack)
    self.isRunning=true; self.cancelRequested=false
    UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    if self.logFrame and not afterPrestack then self.logFrame:Clear() end
    Log(afterPrestack and "=== Rescanning after pre-stacking ===" or "=== Guild Bank Enhanced scan started (no moves yet) ===",0.6,1,0.6)
    if self.globalOtherTab then Log(string.format("Fallback: Tab %d (%s)", self.globalOtherTab, self.tabNames[self.globalOtherTab] or "?"),0.8,0.8,0.8) end
    for tab=1,NUM_TABS do if self.tabKeywords[tab] then Log(string.format("  Tab %d (%s): %s", tab, self.tabNames[tab], table.concat(GBS.Assign:Describe(tab),", ")),0.7,0.7,0.7) end end
    self:ScanAllTabs(function(scanData)
        if not scanData then self:Stop("Scan failed."); return end
        if self.cancelRequested then self:Stop("Cancelled."); return end
        local items=scanData.items; Log(string.format("Scan complete: %d items.", #items),0.6,1,0.6)
        local moves,counts=self:BuildMovePlan(items); Log(string.format("Plan: %d moves needed.", #moves),0.8,0.9,1)
        for tab,c in pairs(counts) do Log(string.format("  -> Tab %d (%s): +%d", tab, self.tabNames[tab] or "?", c),0.8,0.8,0.8) end
        local shortage=false
        if not afterPrestack then
            for tab,c in pairs(counts) do
                local free=98-(scanData.tabsScanned[tab] or 0)
                if c>free then shortage=true; Log(string.format("Tab %d has %d incoming stacks and %d currently empty slots; pre-stacking before routing.",tab,c,free),1,0.8,0.3) end
            end
        end
        Log("Scan and routing plan complete.",0.6,1,0.6); self:Stop("Scan finished.")
        if shortage then self:StartArrange(false,true) else self:StartRouting() end
    end)
end
function GBS:Cancel()
    if self.arrange then self:StopArrange("Cancelled; inspect cursor and slots."); return end
    if self.routing then self:StopRouting("Cancelled; inspect both tabs and the cursor."); return end
    if self.activeMove then self.StopMove("Cancelled. Inspect the cursor and bank slots."); return end
    self.cancelRequested=true
    if SafeGetCursorInfo()=="item" then Log("Warning: cursor has an item. Click to place it.",1,0.8,0.2) end
    self:Stop("Cancelled.")
end

-- Guarded single-stack transfer, used by the routing pipeline.
local moveDriver=CreateFrame("Frame","GBSMoveDriver",UIParent)
moveDriver:Hide()
local function MoveLog(msg)
    Log("MOVE: "..msg,0.85,0.85,1)
end
local function FinishMove(msg,observed)
    local hadCursor=SafeGetCursorInfo()
    moveDriver:SetScript("OnUpdate",nil); moveDriver:Hide()
    GBS.activeMove=nil; GBS.isRunning=false; GBS.cancelRequested=false
    GBS.scanData=nil -- any attempted or cancelled move requires a fresh scan
    UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    if msg then MoveLog(msg) end
    if hadCursor then MoveLog("Something is on your cursor. Place it manually; the addon will not clear or move it.") end
    if GBS.routing and GBS.RouteItemComplete then GBS:RouteItemComplete(observed==true) end
end
GBS.StopMove=FinishMove
local function CanMoveBetween(src,dst)
    local _,_,sourceView,_,withdrawals,remaining=GetGuildBankTabInfo(src)
    local _,_,destView,canDeposit=GetGuildBankTabInfo(dst)
    local left=type(remaining)=="number" and remaining or withdrawals
    if not sourceView or sourceView==0 or not destView or destView==0 or not canDeposit or canDeposit==0 then return false end
    if type(left)~="number" or left==0 then return false end
    return true
end
local function EmptyUnlocked(tab,slot)
    local tex,_,locked=GetGuildBankItemInfo(tab,slot)
    return not tex and not locked and not GetGuildBankItemLink(tab,slot)
end
local function DestinationUnchanged(t)
    if not t.destBefore then return EmptyUnlocked(t.targetTab,t.destSlot) end
    local tex,count,locked=GetGuildBankItemInfo(t.targetTab,t.destSlot)
    local link=GetGuildBankItemLink(t.targetTab,t.destSlot)
    return tex and not locked and link==t.destBefore.link and (count or 1)==t.destBefore.count
end
local function SourceUnchanged(t)
    local tex,count,locked=GetGuildBankItemInfo(t.sourceTab,t.sourceSlot)
    local link=GetGuildBankItemLink(t.sourceTab,t.sourceSlot)
    return tex and not locked and link==t.link and (count or 1)==t.count
end
function GBS:RunMove()
    local t=self.activeMove
    if not t or t.stage~="confirm" then return end
    if not self.Bank:IsOpen() or SafeGetCursorInfo() or not CanMoveBetween(t.sourceTab,t.targetTab) or not SourceUnchanged(t) or not DestinationUnchanged(t) then
        FinishMove("Preflight failed: cursor, permissions, source or destination changed. No move requested."); return
    end
    if type(PickupGuildBankItem)~="function" then FinishMove("Move API unavailable; no move requested."); return end
    t.stage="pickup"; t.elapsed=0; self.isRunning=true
    UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    MoveLog(string.format("Attempting %s x%d: tab %d/%d -> tab %d/%d.",t.itemName,t.count,t.sourceTab,t.sourceSlot,t.targetTab,t.destSlot))
    local ok,err=pcall(PickupGuildBankItem,t.sourceTab,t.sourceSlot)
    if not ok then FinishMove("Pickup error: "..tostring(err)); return end
    moveDriver:SetScript("OnUpdate",function(_,elapsed)
        local current=GBS.activeMove
        if not current or not GBS.isRunning then moveDriver:SetScript("OnUpdate",nil); moveDriver:Hide(); return end
        current.elapsed=current.elapsed+elapsed
        if current.stage=="pickup" then
            local kind,id=GetCursorInfo()
            if not kind and current.elapsed<3 then return end -- slow server: wait without issuing a second pickup
            if kind~="item" or id~=current.itemID then FinishMove("Pickup could not be verified; no destination click was made. Inspect the source and cursor."); return end
            if not GBS.Bank:IsOpen() or not CanMoveBetween(current.sourceTab,current.targetTab) or not DestinationUnchanged(current) then FinishMove("Destination or permissions changed; no destination click was made."); return end
            current.stage="verify"; current.elapsed=0
            local placed,err2=pcall(PickupGuildBankItem,current.targetTab,current.destSlot)
            if not placed then FinishMove("Placement error: "..tostring(err2)); return end
        elseif current.stage=="verify" then
            local kind=SafeGetCursorInfo()
            if kind then
                if kind=="item" and current.elapsed<3 then return end
                FinishMove("Placement is not complete; inspect the cursor and both slots."); return
            end
            if not current.queried then
                if type(QueryGuildBankTab)~="function" then FinishMove("Cannot query result; inspect both tabs and cursor."); return end
                local a=pcall(QueryGuildBankTab,current.sourceTab); local b=pcall(QueryGuildBankTab,current.targetTab)
                if not a or not b then FinishMove("Result query failed; inspect both tabs and cursor."); return end
                current.queried=true; current.queryAt=current.elapsed
                return -- allow a response window before reading client state
            end
            local dest=GetSlotData(current.targetTab,current.destSlot)
            local source=GetGuildBankItemLink(current.sourceTab,current.sourceSlot)
            local _,_,sourceLocked=GetGuildBankItemInfo(current.sourceTab,current.sourceSlot)
            local _,_,destLocked=GetGuildBankItemInfo(current.targetTab,current.destSlot)
            if dest and dest.link==current.link and dest.count==current.count+(current.destBefore and current.destBefore.count or 0) and not source and not sourceLocked and not destLocked then
                UpdateTabCounts(current.sourceTab,current.targetTab)
                FinishMove("Move observed in the client.",true)
            elseif current.elapsed>=5 then
                FinishMove("Move result not confirmed. Inspect the source, destination and cursor; no further move was attempted.")
            end
        end
    end)
    local run=moveDriver:GetScript("OnUpdate")
    moveDriver:SetScript("OnUpdate",function(frame,elapsed)
        local ok,err=pcall(run,frame,elapsed)
        if not ok then FinishMove("Unexpected error; stopped. Inspect cursor and slots: "..tostring(err)) end
    end)
    moveDriver:Show()
end

-- Guarded routing never requests the next move before observing the current one.
local routeDriver=CreateFrame("Frame","GBSRouteDriver",UIParent); routeDriver:Hide()
local function RouteLog(message)
    Log("ROUTING: "..message,0.8,0.9,1)
end
function GBS:StopRouting(reason)
    self.routing=nil; self.scanData=nil
    routeDriver:SetScript("OnUpdate",nil); routeDriver:Hide()
    if self.activeMove then FinishMove(nil) end
    self.isRunning=false; self.cancelRequested=false; UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    self:UpdateProgress()
    if reason then RouteLog(reason) end
    if SafeGetCursorInfo() then RouteLog("Cursor is not empty. Place the item manually before continuing.") end
end
function GBS:FinishRouting()
    local batch=self.routing; if not batch then return end
    local done=batch.done; local skipped,overflow=batch.skipped or 0,batch.overflowed or 0
    self.workRouteDone=done
    self:StopRouting(string.format("Completed %d observed routing moves; %d to overflow, %d left in place.",done,overflow,skipped))
    self:StartArrange(done>0)
end
function GBS:RouteItemComplete(ok)
    local batch=self.routing; if not batch then return end
    if not ok then self:StopRouting("Stopped on an unconfirmed move. No further moves attempted; inspect source, destination and cursor."); return end
    if batch.currentOverflow then batch.overflowed=(batch.overflowed or 0)+1; batch.currentOverflow=nil end
    batch.done=batch.done+1; batch.index=batch.index+1
    if batch.index>#batch.moves then self:FinishRouting()
    else
        self.isRunning=true; self.currentPhase="Routing"; self.doneSteps=batch.index-1; self.totalSteps=#batch.moves; self:UpdateProgress()
        local ok,err=pcall(self.RouteNext,self); if not ok then self:StopRouting("Unexpected error; stopped. "..tostring(err)) end
    end
end
local function TabSpace(tab)
    local lockedEmpty=false
    for slot=1,98 do
        local tex,_,locked=GetGuildBankItemInfo(tab,slot); local link=GetGuildBankItemLink(tab,slot)
        if not tex and not link then if not locked then return true,false else lockedEmpty=true end end
    end
    return false,lockedEmpty
end
local function FindRouteMerge(batch,move,target)
    local source=GetSlotData(move.fromTab,move.fromSlot)
    if not source or not source.maxStack or source.maxStack<=1 then return nil end
    for slot=1,98 do
        local tex,count,locked=GetGuildBankItemInfo(target,slot)
        if tex and not locked and GetGuildBankItemLink(target,slot)==move.item.link and (count or 1)+move.item.count<=source.maxStack then
            local reserved=false
            for i=batch.index,#batch.moves do local pending=batch.moves[i]
                if pending.fromTab==target and pending.fromSlot==slot then reserved=true; break end
            end
            if not reserved then return {slot=slot,link=move.item.link,count=count or 1} end
        end
    end
end
local routeSelector=GuildBankSorterModules.RouteSelector.New({tabSpace=TabSpace,findMerge=FindRouteMerge})

local function ReportUnroutable(batch)
    local relevant={}; for i=batch.index,#batch.moves do relevant[batch.moves[i].toTab]=true end
    if GBS.overflowTab then relevant[GBS.overflowTab]=true end
    if GBS.globalOtherTab then relevant[GBS.globalOtherTab]=true end
    local summary={}; for tab=1,NUM_TABS do if relevant[tab] then summary[#summary+1]=string.format("tab %d %d/98",tab,CountItemsInTab(tab)) end end
    Log("No eligible destination or compatible whole-stack merge in the current client view ("..table.concat(summary,", ").."). Cached counts may be stale.",1,0.8,0.3)
    for i=batch.index,#batch.moves do
        local move=batch.moves[i]
        Log(string.format("No eligible target, overflow or fallback slot: left %s x%d in tab %d slot %d.",move.item.name or tostring(move.item.itemID),move.item.count or 1,move.fromTab,move.fromSlot),1,0.7,0.3)
        batch.skipped=(batch.skipped or 0)+1
    end
    batch.index=#batch.moves+1; GBS:FinishRouting()
end
local function MakeRouteMove(move,choice)
    local item=move.item; local merge=choice.merge
    return {stage="confirm",sourceTab=move.fromTab,sourceSlot=move.fromSlot,targetTab=choice.target,primaryTab=move.toTab,
        link=item.link,itemID=item.itemID,itemName=item.name or ("item "..item.itemID),count=item.count or 1,
        destSlot=merge and merge.slot,destBefore=merge}
end
local function CheckRouteMove(move)
    if not GBS.Bank:IsOpen() or SafeGetCursorInfo() or not CanMoveBetween(move.sourceTab,move.targetTab) or not SourceUnchanged(move) then
        return "Preflight failed: bank, cursor, permissions or source changed; no further move requested."
    end
    local live=GetSlotData(move.sourceTab,move.sourceSlot)
    if not live or not live.itemType or not live.itemSubType or GBS:DetermineTargetTab(live)~=move.primaryTab then
        return "Assignment or item information changed; no further move requested."
    end
    if type(QueryGuildBankTab)~="function" then return "Tab query API unavailable; no further move requested." end
    local source=pcall(QueryGuildBankTab,move.sourceTab); local dest=pcall(QueryGuildBankTab,move.targetTab)
    if not source or not dest then return "Could not query source or destination tab." end
end
local function FindRouteDestination(move)
    if move.destSlot then return DestinationUnchanged(move) end
    for logical=1,98 do
        local slot=GBS:GetPhysicalSlot(logical)
        if EmptyUnlocked(move.targetTab,slot) then move.destSlot=slot; return true end
    end
    return false
end
local function AdvanceRouteAfterQuery(batch,move)
    if not GBS.Bank:IsOpen() or SafeGetCursorInfo() or not CanMoveBetween(move.sourceTab,move.targetTab) or not SourceUnchanged(move) then
        GBS:StopRouting("State changed after the query; no further move requested."); return
    end
    local hadDestination=move.destSlot~=nil
    if not FindRouteDestination(move) then
        if hadDestination then GBS:StopRouting("Merge destination changed after query.")
        else batch.waitPaid=true; GBS:RouteNext() end
        return
    end
    GBS.activeMove=move; GBS:RunMove()
end
local function StartRouteWait(batch,move)
    batch.current=move; batch.wait=0; batch.waitFor=batch.done>0 and not batch.waitPaid and GetMoveDelay() or 0; batch.waitPaid=nil
    local function advance(_,elapsed)
        local current=GBS.routing
        if not current or not current.current then routeDriver:SetScript("OnUpdate",nil); routeDriver:Hide(); return end
        current.wait=current.wait+elapsed
        if current.wait<current.waitFor then return end
        routeDriver:SetScript("OnUpdate",nil); routeDriver:Hide()
        local nextMove=current.current; current.current=nil
        AdvanceRouteAfterQuery(current,nextMove)
    end
    routeDriver:SetScript("OnUpdate",function(frame,elapsed)
        local ok,err=pcall(advance,frame,elapsed)
        if not ok then GBS:StopRouting("Unexpected error; stopped. "..tostring(err)) end
    end)
    routeDriver:Show()
end
function GBS:RouteNext()
    local batch=self.routing; if not batch then return end
    local choice,why=routeSelector:Choose(batch,self.overflowTab,self.globalOtherTab)
    if why then self:StopRouting(why); return end
    if not choice then ReportUnroutable(batch); return end
    batch.moves[batch.index],batch.moves[choice.index]=batch.moves[choice.index],batch.moves[batch.index]
    local selected=batch.moves[batch.index]; local item=selected.item; batch.currentOverflow=choice.overflow
    if choice.overflow then Log(string.format("Target tab %d is full; routing %s to %s tab %d.",selected.toTab,item.name or tostring(item.itemID),choice.secondary and "fallback" or "overflow",choice.target),1,0.8,0.4) end
    local move=MakeRouteMove(selected,choice); local problem=CheckRouteMove(move)
    if problem then self:StopRouting(problem); return end
    self.isRunning=true; self.currentPhase="Routing"; self.doneSteps=batch.index-1; self.totalSteps=#batch.moves; self:UpdateProgress(); UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    StartRouteWait(batch,move)
end
-- Live stack/ordering pass. Ordering plans a chain of final destinations,
-- retaining the displaced stack on the cursor until the chain reaches a hole.
local arrangeDriver=CreateFrame("Frame","GBSArrangeDriver",UIParent); arrangeDriver:Hide()
local function SameSlot(a,b)
    if not a or not b then return not a and not b end
    return a.link==b.link and a.count==b.count
end
local function SlotUnlocked(tab,slot)
    local _,_,locked=GetGuildBankItemInfo(tab,slot); return not locked
end
local function CursorItemFields(link)
    if type(link)~="string" then return nil end
    local payload=link:match("|Hitem:([^|]+)|h") or link:match("^item:(.+)$")
    if not payload then return nil end
    local fields={}
    for value in (payload..":"):gmatch("(.-):") do
        if value~="" and not value:match("^%-?%d+$") then return nil end
        fields[#fields+1]=tonumber(value) or 0
    end
    return fields
end
local function CursorMatchesItem(kind,id,cursorLink,item)
    if not item or kind~="item" or id~=item.itemID then return false end
    if type(cursorLink)=="string" then
        local cursorFields,slotFields=CursorItemFields(cursorLink),CursorItemFields(item.link)
        if cursorFields and slotFields then
            -- Link level is display context, not item identity; preserve all
            -- enchant, gem, random-property and unique/suffix-factor fields.
            for i=1,math.max(8,#cursorFields,#slotFields) do
                if i~=9 and (cursorFields[i] or 0)~=(slotFields[i] or 0) then return false end
            end
        else return false end
    end
    return true
end
local function LogCursorMismatch(cursorLink,slotLink)
    local function safe(link) return tostring(link or "unavailable"):gsub("|","||") end
    Log("Cursor link: "..safe(cursorLink).."; expected link: "..safe(slotLink),1,0.7,0.4)
end
local function OrderingSourceConsistent(tab,slot,original)
    local texture,count,locked=GetGuildBankItemInfo(tab,slot); local link=GetGuildBankItemLink(tab,slot)
    if not texture and not link then return true end
    -- Some clients temporarily suppress the link of the locked pickup slot.
    if locked and not link and (count==nil or count==original.count) then return true end
    return SameSlot(GetSlotData(tab,slot),original)
end
local function ArrangeLess(a,b)
    local sa,sb=Lower(a.itemSubType or ""),Lower(b.itemSubType or "")
    if sa~=sb then if sa=="" then return false elseif sb=="" then return true end; return sa<sb end
    local ca,cb=GetItemCategory(a.name,a.itemSubType,a.itemType),GetItemCategory(b.name,b.itemSubType,b.itemType)
    if ca~=cb then return ca<cb end
    if sa=="cloth" or sa=="metal & stone" then
        local ta,tb=GetClothTier(a.name,a.itemSubType),GetClothTier(b.name,b.itemSubType)
        if ta~=tb then return ta<tb end
    end
    if (a.itemLevel or 0)~=(b.itemLevel or 0) then return (a.itemLevel or 0)<(b.itemLevel or 0) end
    local an,bn=Lower(a.name or ""),Lower(b.name or ""); if an~=bn then return an<bn end
    if a.link~=b.link then return a.link<b.link end
    return a.count>b.count
end
local arrangePlanner=GuildBankSorterModules.SortPlanner.New({
    getSlots=GetTabSlotsData,
    getItemInfo=function(tab,slot) return GetGuildBankItemInfo(tab,slot) end,
    physicalSlot=function(logical) return GBS:GetPhysicalSlot(logical) end,
    compare=ArrangeLess,
    same=SameSlot,
})
local function FindArrangeOp(tab,provided,stackOnly) return arrangePlanner:Find(tab,provided,stackOnly) end
local function EstimateArrange(tab,stackOnly) return arrangePlanner:Estimate(tab,stackOnly) end
function GBS:StopArrange(reason)
    arrangeDriver:SetScript("OnUpdate",nil); arrangeDriver:Hide(); self.arrange=nil
    self.scanData=nil; self:Stop(reason)
    if SafeGetCursorInfo() then Log("Cursor holds an item: place it manually before continuing.",1,0.5,0.3) end
    if self.Bank and self.Bank:IsOpen() then self.Bank:Refresh() end
end
-- Each stage handles one transition; the driver owns timing and error handling.
local arrangeStages={}
arrangeStages.cooldown=function(a)
    if a.elapsed<GetMoveDelay() then return end
    a.stage="query"; a.elapsed=0
end
arrangeStages.query=function(a)
    if a.tab>NUM_TABS or not GBS.tabNumSlots[a.tab] then
        if a.prestack then
            GBS:StopArrange("Pre-stacking complete: "..a.ops.." operations observed.")
            GBS:DoSort(true)
        else GBS:StopArrange("Sort complete: "..a.ops.." stack/order operations observed. Reopen and verify the bank.") end
        return
    end
    if a.displayedTab~=a.tab then GBS.Bank:SelectTab(a.tab,true); a.displayedTab=a.tab end
    if SafeGetCursorInfo() or not CanMoveBetween(a.tab,a.tab) then GBS:StopArrange("Cannot sort tab "..a.tab..": cursor or permissions."); return end
    if type(QueryGuildBankTab)~="function" or not pcall(QueryGuildBankTab,a.tab) then GBS:StopArrange("Tab query failed."); return end
    a.elapsed=0; a.stage="plan"; GBS:UpdateProgress()
end
arrangeStages.plan=function(a)
    local op,why=FindArrangeOp(a.tab,nil,a.prestack)
    if why then GBS:StopArrange(why); return end
    if not op then Log("Tab "..a.tab..(a.prestack and " pre-stacked." or " stacked and ordered."),0.7,0.9,0.7); a.tab=a.tab+1; a.tabOps=0; a.stage="query"; a.elapsed=0; GBS:UpdateProgress(); return end
    if SafeGetCursorInfo() or not CanMoveBetween(a.tab,a.tab) or not SameSlot(GetSlotData(a.tab,op.src),op.source) or not SameSlot(GetSlotData(a.tab,op.dst),op.target) or not SlotUnlocked(a.tab,op.src) or not SlotUnlocked(a.tab,op.dst) or (not op.target and not EmptyUnlocked(a.tab,op.dst)) then GBS:StopArrange("Tab changed or a slot is locked before "..op.kind.."; inspect the log and bank."); return end
    if op.kind=="order" then
        a.op=op; a.orderIndex=1; a.stage="orderPickup"; a.elapsed=0
        local pass,e=pcall(PickupGuildBankItem,a.tab,op.src); if not pass then GBS:StopArrange("Ordering pickup failed: "..tostring(e)) end
        return
    end
    if op.kind=="stack" then
        local total=op.source.count+op.target.count
        op.expectedDest={link=op.target.link,count=math.min(op.max,total)}
        op.expectedSource=total>op.max and {link=op.source.link,count=total-op.max} or nil
    else op.expectedDest=op.source; op.expectedSource=op.target end
    a.op=op; a.stage="pickup"; a.elapsed=0
    local pass,e=pcall(PickupGuildBankItem,a.tab,op.src)
    if not pass then GBS:StopArrange("Pickup failed: "..tostring(e)) end
end
arrangeStages.orderPickup=function(a)
    local op=a.op; local kind,id,link=GetCursorInfo()
    -- On 3.3.5a a guild-bank pickup may leave the original slot
    -- visible and locked until the destination click. An empty
    -- source is not a prerequisite for a verified cursor pickup.
    if (not kind or not OrderingSourceConsistent(a.tab,op.src,op.source)) and a.elapsed<3 then return end
    if not CursorMatchesItem(kind,id,link,op.source) or not OrderingSourceConsistent(a.tab,op.src,op.source) then
        local _,count,locked=GetGuildBankItemInfo(a.tab,op.src)
        if kind=="item" and id==op.source.itemID then LogCursorMismatch(link,op.source.link) end
        GBS:StopArrange(string.format("Ordering pickup not verified on tab %d slot %d (cursor=%s id=%s, source count=%s locked=%s); inspect cursor and source.",a.tab,op.src,tostring(kind),tostring(id),tostring(count),tostring(locked))); return
    end
    a.stage="orderPlace"; a.elapsed=0
end
arrangeStages.orderCooldown=function(a)
    if a.elapsed<GetMoveDelay() then return end
    a.stage="orderPlace"; a.elapsed=0
end
arrangeStages.orderPlace=function(a)
    local op=a.op; local step=op.steps[a.orderIndex]; local kind,id,link=GetCursorInfo()
    if not step or not CursorMatchesItem(kind,id,link,step.after) or not CanMoveBetween(a.tab,a.tab) then
        if step and kind=="item" and id==step.after.itemID then LogCursorMismatch(link,step.after.link) end
        GBS:StopArrange("Ordering cursor or permissions changed; inspect tab and cursor."); return
    end
    -- Do not continue a chain if an already verified placement was
    -- changed by another user, or the source hole was filled.
    for i=1,a.orderIndex-1 do local prior=op.steps[i]
        if not SameSlot(GetSlotData(a.tab,prior.dst),prior.after) or not SlotUnlocked(a.tab,prior.dst) then GBS:StopArrange("An earlier ordering destination changed; inspect tab and cursor."); return end
    end
    if a.orderIndex==1 then
        if not OrderingSourceConsistent(a.tab,op.src,op.source) then GBS:StopArrange("Ordering source changed; inspect tab and cursor."); return end
    elseif step.dst~=op.src and not EmptyUnlocked(a.tab,op.src) then
        GBS:StopArrange("Ordering source hole changed; inspect tab and cursor."); return
    end
    if not SameSlot(GetSlotData(a.tab,step.dst),step.before) or not SlotUnlocked(a.tab,step.dst) or (not step.before and not EmptyUnlocked(a.tab,step.dst)) then
        GBS:StopArrange("Ordering destination changed or locked; inspect tab and cursor."); return
    end
    a.stage="orderVerify"; a.elapsed=0; a.orderQueried=false
    local pass,e=pcall(PickupGuildBankItem,a.tab,step.dst); if not pass then GBS:StopArrange("Ordering placement failed: "..tostring(e)) end
end
arrangeStages.orderVerify=function(a)
    local op=a.op; local step=op.steps[a.orderIndex]
    if not a.orderQueried then
        if type(QueryGuildBankTab)~="function" or not pcall(QueryGuildBankTab,a.tab) then GBS:StopArrange("Ordering result query failed; inspect tab and cursor."); return end
        a.orderQueried=true; return
    end
    local kind,id,link=GetCursorInfo(); local displaced=step.before
    local destOK=SameSlot(GetSlotData(a.tab,step.dst),step.after) and SlotUnlocked(a.tab,step.dst)
    -- Different clients may either keep the displaced stack on the
    -- cursor, or complete a server swap back into the pickup slot.
    -- Only continue after the observed source AND destination match.
    local carried=displaced and CursorMatchesItem(kind,id,link,displaced) and EmptyUnlocked(a.tab,op.src)
    local serverSwap=displaced and a.orderIndex==1 and not kind and SameSlot(GetSlotData(a.tab,op.src),displaced) and SlotUnlocked(a.tab,op.src)
    local finished=not displaced and not kind and (step.dst==op.src or EmptyUnlocked(a.tab,op.src))
    if destOK and (carried or serverSwap or finished) then
        UpdateTabCounts(a.tab); a.ops=a.ops+1; a.tabOps=a.tabOps+1; GBS.doneSteps=a.ops
        if a.ops>a.estimate then a.estimate=a.ops; GBS.totalSteps=a.estimate end
        GBS:UpdateProgress(); Log(string.format("order tab %d: -> %d (%s x%d)%s",a.tab,step.dst,step.after.name or step.after.itemID,step.after.count,serverSwap and " [server swap; replanning]" or ""),0.8,0.8,0.8)
        if carried then
            if not op.steps[a.orderIndex+1] then GBS:StopArrange("Ordering chain ended with an item on the cursor; inspect tab."); return end
            a.orderIndex=a.orderIndex+1; a.stage="orderCooldown"; a.elapsed=0
        else
            if finished and op.steps[a.orderIndex+1] then GBS:StopArrange("Ordering cursor emptied before the end of the chain; inspect tab."); return end
            a.op=nil; a.orderIndex=nil; a.stage="cooldown"; a.elapsed=0
        end
    elseif a.elapsed>=5 then
        local _,sourceCount,sourceLocked=GetGuildBankItemInfo(a.tab,op.src)
        local _,destCount,destLocked=GetGuildBankItemInfo(a.tab,step.dst)
        if displaced and kind=="item" and id==displaced.itemID and not CursorMatchesItem(kind,id,link,displaced) then LogCursorMismatch(link,displaced.link) end
        GBS:StopArrange(string.format("Ordering placement not observed on tab %d (source %d count=%s locked=%s, destination %d count=%s locked=%s, cursor=%s id=%s); inspect tab and cursor.",a.tab,op.src,tostring(sourceCount),tostring(sourceLocked),step.dst,tostring(destCount),tostring(destLocked),tostring(kind),tostring(id)))
    end
end
arrangeStages.pickup=function(a)
    local op=a.op; local kind,id=GetCursorInfo()
    if not kind and a.elapsed<3 then return end
    if kind~="item" or id~=op.source.itemID or not SameSlot(GetSlotData(a.tab,op.dst),op.target) or not SlotUnlocked(a.tab,op.dst) or not CanMoveBetween(a.tab,a.tab) then GBS:StopArrange("Pickup or destination changed; inspect cursor and tab."); return end
    a.stage="place"; a.elapsed=0
    local pass,e=pcall(PickupGuildBankItem,a.tab,op.dst); if not pass then GBS:StopArrange("Placement failed: "..tostring(e)) end
end
arrangeStages.place=function(a)
    local op=a.op; local kind,id=GetCursorInfo()
    if kind then
        -- Wait for the placement to be visible before returning an overflow or swap.
        if not SameSlot(GetSlotData(a.tab,op.dst),op.expectedDest) then
            if a.elapsed<5 then return end
            GBS:StopArrange("Placement not observed; inspect cursor and slots."); return
        end
        local expected=op.expectedSource
        local expectedID=expected and ParseItemIDFromLink(expected.link)
        if kind~="item" or not expected or id~=expectedID then GBS:StopArrange("Unexpected cursor after placement; inspect cursor and slots."); return end
        local pass,e=pcall(PickupGuildBankItem,a.tab,op.src); if not pass then GBS:StopArrange("Return-to-source failed: "..tostring(e)); return end
        a.stage="return"; a.elapsed=0
    else a.stage="verifyQuery"; a.elapsed=0 end
end
arrangeStages["return"]=function(a)
    if SafeGetCursorInfo() then if a.elapsed<3 then return end; GBS:StopArrange("Return-to-source not complete; inspect cursor and slots."); return end
    a.stage="verifyQuery"; a.elapsed=0
end
arrangeStages.verifyQuery=function(a)
    if not pcall(QueryGuildBankTab,a.tab) then GBS:StopArrange("Result query failed; inspect tab."); return end
    a.stage="verify"; a.elapsed=0
end
arrangeStages.verify=function(a)
    local op=a.op
    if SafeGetCursorInfo() then GBS:StopArrange("Cursor not empty after operation."); return end
    if SameSlot(GetSlotData(a.tab,op.src),op.expectedSource) and SameSlot(GetSlotData(a.tab,op.dst),op.expectedDest) and SlotUnlocked(a.tab,op.src) and SlotUnlocked(a.tab,op.dst) then
        UpdateTabCounts(a.tab); a.ops=a.ops+1; a.tabOps=a.tabOps+1; GBS.doneSteps=a.ops; if a.ops>a.estimate then a.estimate=a.ops; GBS.totalSteps=a.estimate end; GBS:UpdateProgress(); Log(string.format("%s tab %d: %d -> %d (%s x%d)",op.kind,a.tab,op.src,op.dst,op.source.name or op.source.itemID,op.source.count),0.8,0.8,0.8)
        a.op=nil; a.stage="cooldown"; a.elapsed=0
    elseif a.elapsed>=5 then GBS:StopArrange("Result not observed; inspect the slots and cursor.") end
end
function GBS:StartArrange(waitFirst,prestack)
    local estimates={}; local total=0; local complete=true; local tabCount=0
    for tab=1,NUM_TABS do if self.tabNumSlots[tab] then
        tabCount=tabCount+1; local stacks,orders=EstimateArrange(tab,prestack); if stacks then estimates[tab]={stack=stacks,order=orders}; total=total+stacks+orders else complete=false end
    end end
    self.arrange={prestack=prestack,tab=1,stage=waitFirst and "cooldown" or "query",elapsed=0,ops=0,estimates=estimates,estimate=total,estimateComplete=complete,tabCount=tabCount,tabOps=0}
    self.isRunning=true; self.currentPhase=prestack and "Pre-stacking" or "Stacking and ordering"; self.doneSteps=0; self.totalSteps=total
    UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end; self:UpdateProgress()
    Log(prestack and "Starting pre-routing stack pass." or "Starting stack and in-tab order pass.",0.6,1,0.6)
    arrangeDriver:SetScript("OnUpdate",function(_,dt)
        local ok,err=pcall(function()
            local a=GBS.arrange; if not a or not GBS.isRunning then return end
            if not GBS.Bank:IsOpen() then GBS:StopArrange("Bank closed during sorting."); return end
            a.elapsed=a.elapsed+dt
            local stage=arrangeStages[a.stage]
            if not stage then error("Unknown arrange stage: "..tostring(a.stage)) end
            stage(a)
        end)
        if not ok then GBS:StopArrange("Sorting error: "..tostring(err).."; inspect cursor and slots.") end
    end)
    arrangeDriver:Show()
end

function GBS:StartRouting()
    if self.routing or self.activeMove or self.isRunning then Chat("Finish or cancel the current operation first.",1,0.6,0.2); return end
    if not self.Bank or not self.Bank:IsOpen() or SafeGetCursorInfo() then Chat("Open the bank and clear the cursor before sorting.",1,0.6,0.2); return end
    if not self.scanData or not self.scanData.items then Log("A current bank scan is required.",1,0.6,0.2); return end
    self:CheckOtherTab()
    local proposed={}
    for _,move in ipairs(self:BuildMovePlan(self.scanData.items)) do
        if move.item and move.item.link and move.item.itemID then proposed[#proposed+1]=move end
    end
    if #proposed==0 then self.workRouteDone=0; self:StartArrange(); return end
    self.routing={moves=proposed,index=1,done=0}
    RouteLog("Starting "..#proposed.." real cross-tab moves.")
    local ok,err=pcall(self.RouteNext,self); if not ok then self:StopRouting("Unexpected error; stopped. "..tostring(err)) end
end

-- ============================================================
-- Skin (WoW 3.3.5a-safe, no SetBackdrop on frames that lack it)
-- ============================================================
SkinGuildBank = function()
    if not GuildBankFrame or GuildBankFrame._gbsSkinned then return end
    pcall(function()
        local function HideRegion(obj)
            if obj and obj.Hide then pcall(function() obj:Hide() end) end
            if obj and obj.SetAlpha then pcall(function() obj:SetAlpha(0) end) end
        end
        local f=GuildBankFrame
        -- Hide Blizzard art (red velvet, borders) - background texture behind vault
        for _,name in ipairs({"GuildBankFrameBackground","GuildBankFrameTopLeft","GuildBankFrameTopRight","GuildBankFrameBottomLeft","GuildBankFrameBottomRight","GuildBankFrameTopBorder","GuildBankFrameBottomBorder","GuildBankFrameLeftBorder","GuildBankFrameRightBorder","GuildBankFrameTitleBg","GuildBankFramePortrait"}) do
            HideRegion(_G[name])
        end
        if not f._gbsBg then
            local bg=CreateFrame("Frame",nil,f); bg:SetFrameLevel(f:GetFrameLevel()-1); bg:SetAllPoints(f)
            bg:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
            bg:SetBackdropColor(0.07,0.07,0.07,0.96); bg:SetBackdropBorderColor(0,0,0,1)
            local inset=CreateFrame("Frame",nil,bg); inset:SetPoint("TOPLEFT",bg,"TOPLEFT",1,-1); inset:SetPoint("BOTTOMRIGHT",bg,"BOTTOMRIGHT",-1,1)
            inset:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=0,right=0,top=0,bottom=0}})
            inset:SetBackdropColor(0,0,0,0); inset:SetBackdropBorderColor(0.22,0.22,0.22,1); f._gbsBg=bg
        end
        for i=1,6 do
            local bt=_G["GuildBankTab"..i.."Button"] or _G["GuildBankFrameTab"..i]
            if bt and not bt._gbsSkinned then
                bt._gbsSkinned=true
                pcall(function()
                    local nt=bt:GetNormalTexture(); if nt then nt:SetAlpha(0) end
                    local pt=bt:GetPushedTexture(); if pt then pt:SetAlpha(0) end
                    local ht=bt:GetHighlightTexture(); if ht then ht:SetAlpha(0) end
                end)
                if bt.SetBackdrop then
                    bt:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=0,right=0,top=0,bottom=0}})
                    bt:SetBackdropColor(0.13,0.13,0.13,1); bt:SetBackdropBorderColor(0.22,0.22,0.22,1)
                end
                local fs=bt:GetFontString(); if fs then fs:SetFont(GBS_FONT,GBS_FONT_SIZE,"") end
            end
        end
        if GuildBankFrame and not f._gbsSlotHooked then
            f._gbsSlotHooked=true
            local function SkinSlots()
                pcall(function()
                    for col=1,14 do for row=1,7 do
                        local btn=_G["GuildBankColumn"..col.."Button"..row] or _G["GuildBankTab"..(GuildBankFrame.selectedTab or 1).."Button"..((col-1)*7+row)]
                        if btn and not btn._gbsStyled then
                            local ic=btn.icon or _G[btn:GetName().."IconTexture"]; if ic then ic:SetTexCoord(0.08,0.92,0.08,0.92) end
                        end
                    end end
                end)
            end
            if GuildBankFrame.HookScript then pcall(function() GuildBankFrame:HookScript("OnShow", SkinSlots) end) end
        end
        f._gbsSkinned=true
    end)
end
GBS.SkinGuildBank=SkinGuildBank

-- ============================================================
-- Panel (single-responsibility builders)
-- ============================================================
local PANEL_W, PANEL_H = 470, 540

-- A mouse-enabled overlay remains hoverable even when a WoW button is disabled.
local function AddSortBlocker(btn)
    local overlay=CreateFrame("Frame",nil,btn:GetParent())
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel()+1)
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sort unavailable",1,0.82,0)
        if not GBS.globalOtherTab then
            GameTooltip:AddLine("Optional: assign a Fallback tab for unmatched items.",1,1,1,true)
        end
        if GBS.isRunning then
            GameTooltip:AddLine("A scan is currently running.",1,1,1,true)
        end
        GameTooltip:AddLine("Wait for the active operation to finish.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave",function() GameTooltip:Hide() end)
    btn.sortBlocker=overlay
end

UpdateSortControls=function()
    local btn=GBS.Bank and GBS.Bank.frame and GBS.Bank.frame.sortBtn
    if not btn then return end
    local blocked=GBS.isRunning
    if blocked then btn:Disable(); if btn.sortBlocker then btn.sortBlocker:Show() end
    else btn:Enable(); if btn.sortBlocker then btn.sortBlocker:Hide() end end
end
GBS.UpdateSortControls=UpdateSortControls

local function BuildDelays(f,buttonWidth)
    local function SettingsButton(parent,text)
        local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
        StyleButton(b,false); b:SetText(text)
        local fs=b:GetFontString(); if fs then fs:SetFont(GBS_FONT,GBS_FONT_SIZE,""); fs:SetTextColor(1,1,1,1) end
        b:HookScript("OnEnable",function(s) local text=s:GetFontString(); if text then text:SetTextColor(1,1,1,1) end end)
        return b
    end
    f.delayPopups={}
    local function MakeDelay(name,label,getVal,setVal,x)
        local trigger=SettingsButton(f,""); trigger:SetSize(buttonWidth,22); trigger:SetPoint("LEFT",f,"LEFT",x,0)
        local popup=CreateFrame("Frame",nil,UIParent); popup:SetSize(250,76); popup:SetPoint("BOTTOM",trigger,"TOP",0,4); popup:SetFrameStrata("DIALOG"); popup:SetFrameLevel(55); StyleBackdrop(popup,1); popup:Hide(); f.delayPopups[#f.delayPopups+1]=popup
        local caption=CreateGBSFontString(popup,"OVERLAY"); caption:SetPoint("TOP",popup,"TOP",0,-8)
        local track=CreateFrame("Frame",nil,popup); track:SetSize(170,8); track:SetPoint("CENTER",popup,"CENTER",0,-7); StyleInset(track)
        local slider=CreateFrame("Slider",name,popup); slider:SetSize(170,18); slider:SetPoint("CENTER",track,"CENTER",0,0); slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(0,1); slider:SetValueStep(0.05)
        slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8"); local thumb=slider:GetThumbTexture(); if thumb then thumb:SetSize(6,16); thumb:SetVertexColor(0.9,0.9,0.9,1) end
        local adjusting=false
        local function set(v)
            v=math.max(0,math.min(1,math.floor((tonumber(v) or 0)*20+0.5)/20))
            setVal(v); local text=string.format("%s: %.2fs",label,v); trigger:SetText(text); caption:SetText(text)
            adjusting=true; slider:SetValue(v); adjusting=false
        end
        slider:SetScript("OnValueChanged",function(_,v) if not adjusting then set(v) end end); set(getVal())
        local function adjust(delta) set(getVal()+delta*0.05) end
        local minus=CreateFrame("Button",nil,popup,"UIPanelButtonTemplate"); minus:SetSize(22,22); minus:SetPoint("RIGHT",track,"LEFT",-5,0); minus:SetText("-"); StyleButton(minus,false); minus:SetScript("OnClick",function() adjust(-1) end)
        local plus=CreateFrame("Button",nil,popup,"UIPanelButtonTemplate"); plus:SetSize(22,22); plus:SetPoint("LEFT",track,"RIGHT",5,0); plus:SetText("+"); StyleButton(plus,false); plus:SetScript("OnClick",function() adjust(1) end)
        trigger:EnableMouseWheel(true); trigger:SetScript("OnMouseWheel",function(_,d) adjust(d>0 and 1 or -1) end)
        slider:EnableMouseWheel(true); slider:SetScript("OnMouseWheel",function(_,d) adjust(d>0 and 1 or -1) end)
        trigger:SetScript("OnClick",function() if GBS.isRunning then return end; local was=popup:IsVisible(); for _,p in ipairs(f.delayPopups) do p:Hide() end; if not was then popup:Show() end end)
        trigger:SetScript("OnEnter",function(self) self:SetBackdropColor(0.18,0.18,0.18,1); GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine(label.." delay",1,0.82,0); GameTooltip:AddLine(label=="MOVE" and "Time between completed routing, stacking, ordering and split operations." or "Time allowed after selecting each tab during a scan.",1,1,1,true); GameTooltip:AddLine("0 to 1 second in 0.05s steps. Click or use the mouse wheel.",0.8,0.8,0.8,true); GameTooltip:Show() end)
        trigger:SetScript("OnLeave",function(self) self:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); GameTooltip:Hide() end)
        return slider,trigger,popup,minus,plus
    end
    f.moveSlider,f.moveTrigger,f.movePopup,f.moveMinus,f.movePlus=MakeDelay("GBSMoveDelaySlider","MOVE",function() return GetMoveDelay() end,function(v) GBSCharDB.moveDelay=v end,0)
    f.scanSlider,f.scanTrigger,f.scanPopup,f.scanMinus,f.scanPlus=MakeDelay("GBSScanDelaySlider","SCAN",function() return GetScanDelay() end,function(v) GBSCharDB.scanDelay=v end,buttonWidth+4)
    local ddBtn=SettingsButton(f,"DOWN > RIGHT"); ddBtn:SetSize(buttonWidth,22); ddBtn:SetPoint("LEFT",f,"LEFT",2*(buttonWidth+4),0)
    local function UpdateDirText() local d=GBSCharDB.sortDir or "col"; for _,o in ipairs(GBS.SortDirections or {}) do if o.id==d then ddBtn:SetText(o.label); return end end; ddBtn:SetText("DOWN > RIGHT") end
    UpdateDirText(); f.sortDirBtn=ddBtn; f.UpdateDirText=UpdateDirText; _G.GBSUpdateDirText=UpdateDirText
    ddBtn:SetScript("OnClick",function()
        for _,p in ipairs(f.delayPopups) do p:Hide() end
        if not GBS.SortDirMenu then
            local m=CreateFrame("Frame","GBSSortDirMenu",UIParent); m:SetSize(160,90); m:SetFrameStrata("DIALOG"); m:SetFrameLevel(50); StyleBackdrop(m,1); m:Hide(); GBS.SortDirMenu=m
            local y=-8
            for _,opt in ipairs(GBS.SortDirections) do
                local b=CreateFrame("Button",nil,m,"UIPanelButtonTemplate"); b:SetSize(144,18); b:SetPoint("TOPLEFT",m,"TOPLEFT",8,y); b:SetText(opt.label); StyleButton(b,false)
                b:SetScript("OnClick",function() GBSCharDB.sortDir=opt.id; UpdateDirText(); m:Hide() end)
                b:SetScript("OnEnter",function(s) GameTooltip:SetOwner(s,"ANCHOR_RIGHT"); GameTooltip:AddLine(opt.label,1,1,1); GameTooltip:AddLine(opt.desc,0.7,0.7,0.7,true); GameTooltip:Show() end); b:SetScript("OnLeave",function() GameTooltip:Hide() end)
                y=y-20
            end
            m:SetHeight(-y+8)
        end
        if GBS.SortDirMenu:IsVisible() then GBS.SortDirMenu:Hide() else GBS.SortDirMenu:ClearAllPoints(); GBS.SortDirMenu:SetPoint("TOPRIGHT",ddBtn,"BOTTOMRIGHT",0,-2); GBS.SortDirMenu:Show() end
    end)
    ddBtn:SetScript("OnEnter",function(s) s:SetBackdropColor(0.18,0.18,0.18,1); GameTooltip:SetOwner(s,"ANCHOR_TOP"); GameTooltip:AddLine("Sort direction",1,1,1); GameTooltip:AddLine("Controls the traversal order used to fill empty slots and arrange stacks inside each tab. It does not change which tab an item is assigned to.",0.8,0.8,0.8,true); GameTooltip:Show() end); ddBtn:SetScript("OnLeave",function(s) s:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); GameTooltip:Hide() end)
end


local function EnsureTabNames()
    if next(GBS.tabNames) then return end
    for i=1,NUM_TABS do
        local ok,name=pcall(function() if GetGuildBankTabInfo then return select(1, GetGuildBankTabInfo(i)) end end)
        if ok and name and name~="" then GBS.tabNames[i]=name; GBS.tabNumSlots[i]=98 else GBS.tabNames[i]="Tab "..i; GBS.tabNumSlots[i]=98 end
    end
end

-- Fit all assignment and tab-name text in the available column without
-- hiding the rest behind an ellipsis. Explicit breaks make row heights
-- deterministic even on clients whose GetStringHeight ignores wrapping.
local rowWrapProbe
local function WrapRowText(text,width)
    if not rowWrapProbe then rowWrapProbe=CreateGBSFontString(UIParent,"OVERLAY"); rowWrapProbe:Hide() end
    local lines,current={},""
    local function fits(value) rowWrapProbe:SetText(value); return (rowWrapProbe:GetStringWidth() or 0)<=width end
    local function flush()
        if current~="" then lines[#lines+1]=Trim(current); current="" end
    end
    for word in tostring(text or ""):gmatch("%S+") do
        local candidate=current=="" and word or current.." "..word
        if fits(candidate) then current=candidate
        else
            flush()
            if fits(word) then current=word
            else
                -- Split only at UTF-8 codepoint boundaries, never inside a byte sequence.
                for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                    if current~="" and not fits(current..char) then flush() end
                    current=current..char
                end
            end
        end
    end
    flush(); if #lines==0 then lines[1]="" end
    return table.concat(lines,"\n"),#lines
end

local function RowFits(text,width)
    if not rowWrapProbe then rowWrapProbe=CreateGBSFontString(UIParent,"OVERLAY"); rowWrapProbe:Hide() end
    rowWrapProbe:SetText(text)
    return (rowWrapProbe:GetStringWidth() or 0)<=width
end
local function SingleLineText(text,width)
    text=tostring(text or "")
    if RowFits(text,width) then return text end
    local value=""
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if not RowFits(value..char.."...",width) then break end
        value=value..char
    end
    return value.."..."
end
local function CompactAssignments(kws,width)
    local prefix=""
    for i,kw in ipairs(kws) do
        local nextText=prefix=="" and kw or prefix..", "..kw
        local remaining=#kws-i
        local suffix=remaining>0 and (" +"..remaining) or ""
        if not RowFits(nextText..suffix,width) then
            if prefix=="" then return SingleLineText(kw,width) end
            return prefix.." +"..(#kws-i+1)
        end
        prefix=nextText
    end
    return prefix
end

UpdateBankPanelTabs = function()
    if not GBS.bankPanel or not GBS.bankPanel.tabRows then return end
    GBS:CheckOtherTab()
        for tab=1,NUM_TABS do
        local row=GBS.bankPanel.tabRows[tab]; local name=GBS.tabNames[tab]; local numSlots=GBS.tabNumSlots[tab]
        if name and numSlots and numSlots>0 then
            row.nameFS:SetTextColor(0.92,0.92,0.92,1)
            row.nameFS:SetText(SingleLineText(name,120))
            local used=CountItemsInTab(tab)
            row.countFS:SetText(string.format("%d/98", used)); row.countFS:SetTextColor(0.50,0.50,0.50,1)
            local kws=GBS.tabKeywords[tab] or GBS.categoryOtherKeywords[tab]
            local tag=""; if GBS.globalOtherTab==tab then tag="  |cffff55ff Other|r" elseif GBS.categoryOtherKeywords and GBS.categoryOtherKeywords[tab] then tag="  |cffffe066 Cat Other|r" end
            if kws and #kws>0 then
                row.kwFS:SetText(CompactAssignments(kws,PANEL_W-40-204)); row.kwFS:SetTextColor(1,0.84,0.3,1)
            else
                if GBS.globalOtherTab==tab then row.kwFS:SetText("Fallback (Other)"); row.kwFS:SetTextColor(1,0.55,0.9,1) else row.kwFS:SetText("unassigned"); row.kwFS:SetTextColor(0.75,0.75,0.75,1) end
            end
            if tab%2==1 then row.bg:SetBackdropColor(0.13,0.13,0.13,1) else row.bg:SetBackdropColor(0.10,0.10,0.10,1) end
            row.bg:SetBackdropBorderColor(0.20,0.20,0.20,0.45); row:Show()
        else
            row.nameFS:SetText("- empty -"); row.nameFS:SetTextColor(0.32,0.32,0.32,1); row.countFS:SetText(""); row.kwFS:SetText("not purchased"); row.kwFS:SetTextColor(0.6,0.6,0.6,1)
            row.bg:SetBackdropColor(0.07,0.07,0.07,0.55); row.bg:SetBackdropBorderColor(0.12,0.12,0.12,0.6)
            row:Show()
        end
    end
    local panel=GBS.bankPanel
    if panel.warningFS then panel.warningFS:Hide() end
    if UpdateSortControls then UpdateSortControls() end
end

CreateBankPanel=function() end
local function ToggleBankPanel()
    if not GBS.Bank or not GBS.Bank:IsOpen() then Chat("Open the guild bank first.",1,0.7,0.3); return end
    GBSCharDB.bankSections=GBSCharDB.bankSections or {log=true}
    GBSCharDB.bankSections.log=false
    if GBS.Bank.frame.LayoutAttached then GBS.Bank.frame.LayoutAttached() end
end
GBS.ToggleBankPanel=ToggleBankPanel

-- ============================================================
-- Assign Editor (class: GBS.AssignEditor)
-- ============================================================
GBS.AssignEditor = { frame=nil }
function GBS.AssignEditor:Create()
    if self.frame then return self.frame end
    local ef=CreateGBSFrameBase("GBSAssignFrame",320,300,65)
    ef:SetMovable(false); ef:SetClampedToScreen(false); ef:SetScript("OnDragStart",nil); ef:SetScript("OnDragStop",nil)
    ef:SetPoint("CENTER",UIParent,"CENTER",0,0); ef:Hide(); self.frame=ef; GBS.assignFrame=ef
    local title=CreateGBSFontString(ef.titleBar,"OVERLAY")
    title:SetPoint("LEFT",ef.titleBar,"LEFT",8,0); title:SetFont(GBS_FONT,GBS_FONT_SIZE,""); ef.titleFS=title
    local hint=CreateGBSFontString(ef,"OVERLAY")
    hint:SetPoint("TOPLEFT",ef,"TOPLEFT",12,-28); hint:SetText("Choose types for this tab, or mark it as the fallback."); ef.hint=hint
    ef.checks={}; ef.sections={}; ef.collapsed={}; ef.embedded=false; ef.embeddedHeight=264

    -- Backdrop and check mark are regions on the checkbutton itself. There is
    -- no child background frame to intercept mouse events or obscure the mark.
    local function NewCheck(parent,keyword,onChange)
        local cb=CreateFrame("CheckButton",nil,parent)
        cb:SetSize(16,16); cb:EnableMouse(true); cb:RegisterForClicks("LeftButtonUp")
        StyleBackdrop(cb,1); cb:SetBackdropColor(0.09,0.09,0.09,1)
        local mark=cb:CreateTexture(nil,"OVERLAY")
        mark:SetTexture("Interface\\Buttons\\WHITE8x8"); mark:SetVertexColor(E.accent[1],E.accent[2],E.accent[3],1)
        mark:SetPoint("TOPLEFT",cb,"TOPLEFT",3,-3); mark:SetPoint("BOTTOMRIGHT",cb,"BOTTOMRIGHT",-3,3); mark:Hide()
        cb.chk=mark; cb.keyword=keyword
        cb.Sync=function() if cb:GetChecked() then mark:Show() else mark:Hide() end end
        cb:SetScript("OnClick",function() cb.Sync(); if onChange then onChange(cb) end end)
        return cb
    end
    local other=NewCheck(ef,nil)
    other:SetPoint("TOPLEFT",ef,"TOPLEFT",12,-49); ef.otherCB=other
    other:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Fallback tab",1,0.82,0); GameTooltip:AddLine("Receives unassigned items. It may also receive items when their assigned tab is full and overflow is unavailable or full.",1,1,1,true); GameTooltip:Show() end)
    other:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local otherText=CreateGBSFontString(ef,"OVERLAY")
    otherText:SetPoint("LEFT",other,"RIGHT",6,0); otherText:SetText("Fallback")
    local otherLabel=CreateFrame("Button",nil,ef); otherLabel:SetPoint("LEFT",other,"RIGHT",2,0); otherLabel:SetSize(82,18)
    otherLabel:SetScript("OnClick",function() other:Click() end)
    local overflow=NewCheck(ef,nil); overflow:SetPoint("TOPLEFT",ef,"TOPLEFT",140,-49); ef.overflowCB=overflow
    local overflowText=CreateGBSFontString(ef,"OVERLAY"); overflowText:SetPoint("LEFT",overflow,"RIGHT",6,0); overflowText:SetText("Overflow")
    local overflowLabel=CreateFrame("Button",nil,ef); overflowLabel:SetPoint("LEFT",overflow,"RIGHT",2,0); overflowLabel:SetSize(82,18); overflowLabel:SetScript("OnClick",function() overflow:Click() end)
    overflow:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Overflow tab",1,0.82,0); GameTooltip:AddLine("Receives items whose assigned tab is full. A distinct fallback is used if this tab fills, or when no overflow is assigned.",1,1,1,true); GameTooltip:Show() end)
    overflow:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local scroll=CreateFrame("ScrollFrame","GBSAssignScroll",ef,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",ef,"TOPLEFT",10,-72); scroll:SetSize(304,190); scroll:SetFrameLevel(ef:GetFrameLevel()+2)
    local inner=CreateFrame("Frame",nil,scroll); inner:SetSize(304,170); inner:SetFrameLevel(scroll:GetFrameLevel()+1); scroll:SetScrollChild(inner)
    ef.scroll=scroll; ef.inner=inner; SkinScroll(scroll)
    local scrollBar=_G[scroll:GetName().."ScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints(); scrollBar:SetPoint("TOPLEFT",scroll,"TOPRIGHT",3,-1)
        scrollBar:SetPoint("BOTTOMLEFT",scroll,"BOTTOMRIGHT",3,1)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(self,delta)
        local value=math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*32))
        self:SetVerticalScroll(value)
    end)

    local function MakeButton(text,x,primary)
        local b=CreateFrame("Button",nil,ef,"UIPanelButtonTemplate"); b:SetSize(76,22)
        b:SetPoint("BOTTOMRIGHT",ef,"BOTTOMRIGHT",x,10); b:SetText(text); StyleButton(b,primary); return b
    end
    local save=MakeButton("Save",-10,true); ef.saveBtn=save
    local cancel=MakeButton("Cancel",-92,false); ef.cancelBtn=cancel; cancel:SetScript("OnClick",function() ef:Hide() end)
    local clear=MakeButton("Clear",-174,false); ef.clearBtn=clear
    local rebuild
    local function Changed(cb)
        if cb:GetChecked() then other:SetChecked(false); other.Sync() end
        if rebuild then rebuild() end
    end
    local function LabelFor(cb,label)
        local fs=CreateGBSFontString(inner,"OVERLAY")
        fs:SetPoint("LEFT",cb,"RIGHT",5,0); fs:SetWidth(118); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false); fs:SetText(label)
        local button=CreateFrame("Button",nil,inner); button:SetPoint("LEFT",cb,"RIGHT",2,0); button:SetSize(118,18)
        button:SetScript("OnClick",function() cb:Click() end)
        return fs,button
    end
    for idx,cat in ipairs(CATEGORIES) do
        local sec={cat=cat,subChecks={},subLabels={}}; ef.sections[idx]=sec
        local cb=NewCheck(inner,TypeKey(cat.name),Changed); sec.anyCB=cb; table.insert(ef.checks,cb)
        local header=CreateFrame("Button",nil,inner); header:SetSize(126,20); StyleBackdrop(header,1); header:SetBackdropColor(0.14,0.14,0.14,1); header:EnableMouse(true)
        local label=CreateGBSFontString(header,"OVERLAY"); label:SetPoint("LEFT",header,"LEFT",6,0); label:SetWidth(92); label:SetJustifyH("LEFT"); label:SetWordWrap(false); label:SetText(cat.name)
        local arrow=CreateGBSFontString(header,"OVERLAY"); arrow:SetPoint("RIGHT",header,"RIGHT",-6,0); sec.arrow=arrow; sec.header=header
        local badge=CreateGBSFontString(header,"OVERLAY"); badge:SetPoint("RIGHT",arrow,"LEFT",-4,0); badge:SetTextColor(0.45,0.9,0.65); badge:SetText(""); sec.badge=badge
        local key=Lower(cat.name)
        header:EnableMouse(#cat.subs>0)
        header:SetScript("OnClick",function() if #cat.subs>0 then ef.collapsed[key]=not ef.collapsed[key]; rebuild() end end)
        for _,sub in ipairs(cat.subs) do
            local subcb=NewCheck(inner,SubKey(cat.name,sub),Changed); table.insert(ef.checks,subcb); table.insert(sec.subChecks,subcb)
            local lab,button=LabelFor(subcb,sub); table.insert(sec.subLabels,{lab=lab,button=button})
        end
    end
    rebuild=function()
        local ys={0,0}; local colW=152
        for idx,sec in ipairs(ef.sections) do
            local col=(idx-1)%2+1; local x=(col-1)*colW; local y=ys[col]
            sec.anyCB:ClearAllPoints(); sec.anyCB:SetPoint("TOPLEFT",inner,"TOPLEFT",x+2,-y-2)
            sec.header:ClearAllPoints(); sec.header:SetPoint("TOPLEFT",inner,"TOPLEFT",x+24,-y)
            local collapsed=ef.collapsed[Lower(sec.cat.name)]~=false
            if #sec.subChecks>0 then sec.arrow:SetText(collapsed and "+" or "-"); sec.arrow:Show() else sec.arrow:SetText(""); sec.arrow:Hide() end
            local selected=0; for _,cb in ipairs(sec.subChecks) do if cb:GetChecked() then selected=selected+1 end end
            sec.badge:SetText(selected>0 and tostring(selected) or "")
            sec.anyCB:Show(); sec.header:Show(); y=y+23
            for j,cb in ipairs(sec.subChecks) do
                local label=sec.subLabels[j]
                if not collapsed then
                    cb:ClearAllPoints(); cb:SetPoint("TOPLEFT",inner,"TOPLEFT",x+14,-y-1)
                    cb:Show(); label.lab:Show(); label.button:Show(); y=y+19
                else cb:Hide(); label.lab:Hide(); label.button:Hide() end
            end
            ys[col]=y+2
        end
        local contentH=math.max(ys[1],ys[2])+4
        inner:SetHeight(contentH)
        local frameH=ef.embedded and (ef.embeddedHeight or 264) or math.max(250,math.min(520,contentH+112))
        ef:SetHeight(frameH); local scrollH=ef.embedded and math.max(30,frameH-36) or frameH-112; scroll:SetHeight(scrollH)
        local range=scroll:GetVerticalScrollRange()
        if scroll:GetVerticalScroll()>range then scroll:SetVerticalScroll(range) end
        local bar=_G[scroll:GetName().."ScrollBar"]
        if bar then if contentH>scrollH then bar:Show() else bar:Hide(); scroll:SetVerticalScroll(0) end end
    end
    ef.RebuildAssignLayout=rebuild
    clear:SetScript("OnClick",function()
        for _,cb in ipairs(ef.checks) do cb:SetChecked(false); cb.Sync() end
        other:SetChecked(false); other.Sync(); overflow:SetChecked(false); overflow.Sync(); rebuild()
    end)
    ef.GetSelection=function()
        local selected,seen={},{}
        local isOther=other:GetChecked()
        if not isOther then
            for _,cb in ipairs(ef.checks) do
                if cb:GetChecked() and not seen[cb.keyword] then selected[#selected+1]=cb.keyword; seen[cb.keyword]=true end
            end
        end
        return selected,isOther,overflow:GetChecked() and true or false
    end
    save:SetScript("OnClick",function()
        local selected,isOther,isOverflow=ef.GetSelection(); GBS.Assign:Set(ef._tabIdx,selected,isOther,isOverflow); ef:Hide(); UpdateBankPanelTabs()
    end)
    rebuild(); return ef
end
function GBS.OpenAssignEditor(tabIdx,embedded)
    if not embedded then if GBS.Bank then GBS.Bank:OpenTabConfig(tabIdx) end; return end
    if GBS.Bank and GBS.Bank.moneyBox then GBS.Bank.moneyBox:Hide() end
    if not embedded and GBS.Bank and GBS.Bank.tabConfig then GBS.Bank.tabConfig:Hide() end
    if not tabIdx or not GBS.tabNames[tabIdx] then Chat("Open a Guild Bank tab first.",1,0.4,0.4); return end
    local ef=GBS.AssignEditor:Create(); ef._tabIdx=tabIdx
    ef.titleFS:SetText("|cffffd100Assign Tab "..tabIdx.."|r  "..(GBS.tabNames[tabIdx] or ""))
    local saved=GBS.Assign:Get(tabIdx); local set={}
    if saved then for _,kw in ipairs(saved) do set[Lower(kw)]=true end end
    ef.otherCB:SetChecked(GBS.Assign:IsOther(tabIdx)); ef.otherCB.Sync()
    ef.overflowCB:SetChecked(GBS.Assign:IsOverflow(tabIdx)); ef.overflowCB.Sync()
    for _,cb in ipairs(ef.checks) do cb:SetChecked(set[Lower(cb.keyword)] and true or false); cb.Sync() end
    for _,sec in ipairs(ef.sections) do
        local key=Lower(sec.cat.name)
        ef.collapsed[key]=true
        for _,cb in ipairs(sec.subChecks) do if cb:GetChecked() then ef.collapsed[key]=false; break end end
    end
    if embedded then
        local cf=GBS.Bank.tabConfig
        ef.embedded=true; ef:SetParent(cf); ef:ClearAllPoints(); ef:SetPoint("TOPLEFT",cf,"TOPLEFT",10,-65)
        ef:SetFrameLevel(cf:GetFrameLevel()+2)
        local function Relayer(parent)
            for _,child in ipairs({parent:GetChildren()}) do child:SetFrameLevel(parent:GetFrameLevel()+1); Relayer(child) end
        end
        Relayer(ef); ef.titleBar:Hide(); ef.hint:Hide(); ef.saveBtn:Hide(); ef.cancelBtn:Hide()
        ef.otherCB:ClearAllPoints(); ef.otherCB:SetPoint("TOPLEFT",ef,"TOPLEFT",5,-4)
        ef.overflowCB:ClearAllPoints(); ef.overflowCB:SetPoint("TOPLEFT",ef,"TOPLEFT",105,-4)
        ef.scroll:ClearAllPoints(); ef.scroll:SetPoint("TOPLEFT",ef,"TOPLEFT",5,-32)
        ef.clearBtn:ClearAllPoints(); ef.clearBtn:SetPoint("TOPLEFT",ef,"TOPLEFT",205,-2); ef.clearBtn:SetSize(100,20)
    end
    ef.RebuildAssignLayout(); ef.scroll:SetVerticalScroll(0); ef:Show()
end

-- ============================================================

-- ============================================================
-- Guild bank
GBS.Bank = { frame=nil, currentTab=1, slotButtons={}, tabButtons={}, bagHooked=false }
local qualityRetry=CreateFrame("Frame","GBSQualityRetry",UIParent); qualityRetry:Hide()
local qualityRetryActive=false
local function StopQualityRetry()
    qualityRetryActive=false; qualityRetry:SetScript("OnUpdate",nil); qualityRetry:Hide()
end
local function ScheduleQualityRetry()
    if qualityRetryActive then return end
    qualityRetryActive=true; local elapsedTotal,attempts=0,0
    qualityRetry:SetScript("OnUpdate",function(_,elapsed)
        if not GBS.Bank:IsOpen() then StopQualityRetry(); return end
        elapsedTotal=elapsedTotal+elapsed; if elapsedTotal<1 then return end
        elapsedTotal=0; attempts=attempts+1; GBS.Bank:RefreshSlots()
        if not GBS.Bank.qualityPending or attempts>=8 then StopQualityRetry() end
    end)
    qualityRetry:Show()
end
local function SetItemBorder(button,r,g,b,a)
    for _,edge in ipairs(button.qualityEdges) do edge:SetVertexColor(r,g,b,a or 1) end
end
local QUALITY_COLORS={
    [0]={0.62,0.62,0.62}, [1]={1,1,1}, [2]={0.12,1,0}, [3]={0,0.44,0.87},
    [4]={0.64,0.21,0.93}, [5]={1,0.5,0}, [6]={0.9,0.8,0.5}, [7]={0,0.8,1}
}

local GRID_W, GRID_H = BANK_COLS*SLOT_SIZE + (BANK_COLS-1)*SLOT_GAP, BANK_ROWS*SLOT_SIZE + (BANK_ROWS-1)*SLOT_GAP
function GBS.Bank:IsOpen() return self.frame and self.frame:IsVisible() end
-- Use the 3.3.5 native stack splitter and restore its original strata afterwards.
-- The custom bank is DIALOG, whereas the stock splitter is HIGH on this client.
local function IsOurSplitOwner(owner)
    if not owner or not GBS.Bank then return false end
    for _,btn in ipairs(GBS.Bank.slotButtons) do if btn==owner then return true end end
    return false
end
local function CloseOurSplit()
    if StackSplitFrame and IsOurSplitOwner(StackSplitFrame.owner) then StackSplitFrame:Hide() end
end
local function OpenOurSplit(btn,tab,slot,link,count)
    if type(OpenStackSplitFrame)~="function" or type(SplitGuildBankItem)~="function" or not StackSplitFrame then
        Chat("Stack splitting is unavailable on this client.",1,0.6,0.2); return
    end
    btn._splitTab=tab; btn._splitSlot=slot; btn._splitLink=link; btn._splitCount=count
    btn.SplitStack=function(owner,amount)
        local n=tonumber(amount)
        if not n or n~=math.floor(n) or n<1 or n>owner._splitCount then return end
        if GBS.isRunning or GBS.activeMove or not GBS.Bank:IsOpen() or GBS.Bank.currentTab~=owner._splitTab or SafeGetCursorInfo() then
            Chat("Split cancelled: the bank, tab or cursor changed.",1,0.6,0.2); return
        end
        local tex,liveCount,locked=GetGuildBankItemInfo(owner._splitTab,owner._splitSlot)
        local liveLink=GetGuildBankItemLink(owner._splitTab,owner._splitSlot)
        if not tex or locked or liveCount~=owner._splitCount or liveLink~=owner._splitLink then
            Chat("Split cancelled: the source stack changed or is locked.",1,0.6,0.2); return
        end
        GBS.scanData=nil
        local ok,err=pcall(SplitGuildBankItem,owner._splitTab,owner._splitSlot,n)
        if not ok then Chat("Split failed: "..tostring(err),1,0.4,0.3) end
    end
    if StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
    if not StackSplitFrame._gbsSplitHook then
        StackSplitFrame:HookScript("OnHide",function(frame)
            local saved=frame._gbsSavedLayer
            if saved then frame._gbsSavedLayer=nil; frame:SetFrameStrata(saved.strata); frame:SetFrameLevel(saved.level) end
        end)
        StackSplitFrame._gbsSplitHook=true
    end
    StackSplitFrame._gbsSavedLayer={strata=StackSplitFrame:GetFrameStrata(),level=StackSplitFrame:GetFrameLevel()}
    StackSplitFrame:SetFrameStrata("DIALOG"); StackSplitFrame:SetFrameLevel(90)
    local ok,err=pcall(OpenStackSplitFrame,count,btn,"BOTTOMLEFT","TOPLEFT")
    if not ok then
        local saved=StackSplitFrame._gbsSavedLayer; StackSplitFrame._gbsSavedLayer=nil
        if saved then StackSplitFrame:SetFrameStrata(saved.strata); StackSplitFrame:SetFrameLevel(saved.level) end
        Chat("Could not open the split dialog: "..tostring(err),1,0.4,0.3)
    end
end

function GBS.Bank:BuildAttachedSections(f)
    GBSCharDB.bankSections=GBSCharDB.bankSections or {log=true}
    local state=GBSCharDB.bankSections; if state.log==nil then state.log=true end
    f.extraSections={}
    local logHeader=CreateFrame("Button",nil,f); logHeader:SetSize(GRID_W,20); StyleBackdrop(logHeader,1); logHeader:SetBackdropColor(0.14,0.14,0.14,1); f.logHeader=logHeader
    local label=CreateGBSFontString(logHeader,"OVERLAY"); label:SetPoint("LEFT",logHeader,"LEFT",8,0); label:SetText("LOG")
    local arrow=CreateGBSFontString(logHeader,"OVERLAY"); arrow:SetPoint("RIGHT",logHeader,"RIGHT",-8,0); logHeader.arrow=arrow
    f.ToggleSection=function(key)
        if GBS.isRunning then return end
        local left,top=f:GetLeft(),f:GetTop()
        local rootLeft,rootTop=UIParent:GetLeft(),UIParent:GetTop()
        if left and top and rootLeft and rootTop then
            local scale=f:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local x,y=left*scale-rootLeft,top*scale-rootTop
            f:SetClampedToScreen(false); f:ClearAllPoints(); f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x,y)
            GBSCharDB.bankPos={point="TOPLEFT",x=x,y=y}
        end
        state[key]=not state[key]; f.LayoutAttached()
        if not state[key] and key~="log" then f.RefreshSection(key)
        elseif state[key] and key=="info" and f.activity then f.activity.info.edit:ClearFocus() end
    end
    logHeader:SetScript("OnClick",function() f.ToggleSection("log") end)
    local copy=CreateFrame("Button",nil,logHeader,"UIPanelButtonTemplate"); copy:SetSize(44,18); copy:SetPoint("RIGHT",logHeader,"RIGHT",-24,0); copy:SetText("Copy"); StyleButton(copy,false); f.copyBtn=copy
    local logContent=CreateFrame("Frame",nil,f); logContent:SetSize(GRID_W,206); StyleInset(logContent); f.logContent=logContent
    local scroll=CreateFrame("ScrollFrame","GBSAttachedLogScroll",logContent,"UIPanelScrollFrameTemplate"); scroll:SetSize(GRID_W-24,196); scroll:SetPoint("TOPLEFT",logContent,"TOPLEFT",4,-4); f.logScroll=scroll
    local canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(GRID_W-30,196); scroll:SetScrollChild(canvas)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel",function(self,d) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-d*32))) end); SkinScroll(scroll)
    local raw,rows={},{}; GBS.logRawLines=raw; f.logRows=rows
    local height=4; local followFrames=0
    local function follow()
        -- Scroll range may update on the frame after resizing the child.
        followFrames=3
        if scroll:IsVisible() then scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end
    end
    scroll:SetScript("OnUpdate",function(self)
        if followFrames>0 then self:SetVerticalScroll(self:GetVerticalScrollRange()); followFrames=followFrames-1 end
    end)
    logContent:SetScript("OnShow",follow)
    local function visibleText(text)
        return tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1")
    end
    GBS.logFrame={
        addMessage=function(self,msg,r,g,b)
            raw[#raw+1]=msg
            local row=rows[#raw]
            if not row then row=CreateGBSFontString(canvas,"OVERLAY"); rows[#raw]=row end
            local wrapped,lines=WrapRowText(visibleText(msg),GRID_W-34)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",canvas,"TOPLEFT",2,-height); row:SetWidth(GRID_W-34); row:SetJustifyH("LEFT"); row:SetJustifyV("TOP"); row:SetHeight(10000); row:SetText(wrapped)
            local lineHeight=GBS_FONT_SIZE+2
            -- Explicit wrapping plus an unconstrained font string avoids clients
            -- whose GetStringHeight ignores automatic wrapping.
            if row.GetStringHeight then local measured=row:GetStringHeight(); if measured and measured>0 then lineHeight=math.max(lineHeight,measured/lines) end end
            local h=math.ceil(lineHeight*lines)+2; row:SetHeight(h); row:SetTextColor(r or 1,g or 1,b or 1); row:Show()
            height=height+h; canvas:SetHeight(math.max(196,height+4)); f.logText=row; follow()
        end,
        Clear=function()
            for i=#raw,1,-1 do raw[i]=nil end
            for _,row in ipairs(rows) do row:Hide() end
            height=4; canvas:SetHeight(196); scroll:SetVerticalScroll(0); followFrames=0
        end,
        GetRaw=function() return table.concat(raw,"\n") end,
    }
    local cf=CreateGBSFrameBase("GBSCopyFrame",480,420,75); cf:SetPoint("CENTER",UIParent,"CENTER",0,0); cf:Hide(); GBS.copyFrame=cf
    local title=CreateGBSFontString(cf.titleBar,"OVERLAY"); title:SetPoint("LEFT",cf.titleBar,"LEFT",8,0); title:SetText("|cffffd100Copy log|r")
    local hint=CreateGBSFontString(cf,"OVERLAY"); hint:SetPoint("TOPLEFT",cf,"TOPLEFT",10,-28); hint:SetText("Click the text if needed; Ctrl+A, then Ctrl+C.")
    local es=CreateFrame("ScrollFrame","GBSCopyScroll",cf,"UIPanelScrollFrameTemplate"); es:SetSize(455,340); es:SetPoint("TOPLEFT",cf,"TOPLEFT",10,-48); SkinScroll(es)
    local eb=CreateFrame("EditBox","GBSCopyEditBox",es); eb:SetMultiLine(true); eb:SetFontObject("GBSFont"); eb:SetSize(430,340); eb:SetAutoFocus(false); eb:EnableMouse(true); eb:SetMaxLetters(0); es:SetScrollChild(eb); cf.editBox=eb
    eb:SetScript("OnEscapePressed",function() cf:Hide() end)
    cf:SetScript("OnHide",function() eb:ClearFocus() end)
    GBS.ShowCopyLog=function()
        local text=table.concat(raw,"\n"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
        local lineCount=0; for _,line in ipairs(raw) do lineCount=lineCount+math.max(1,math.ceil(#line/64)) end
        eb:SetHeight(math.max(340,lineCount*18+16)); eb:SetText(text); cf:Show() -- focus only after the entire ancestor chain is visible
        eb:SetFocus(); eb:HighlightText()
    end
    copy:SetScript("OnClick",function() if GBS.isRunning then return end; if cf:IsVisible() then cf:Hide() else GBS.ShowCopyLog() end end)
    f.LayoutAttached=function()
        local y=-365
        logHeader:ClearAllPoints(); logHeader:SetPoint("TOPLEFT",f,"TOPLEFT",6,y); y=y-20
        logHeader.arrow:SetText(state.log and "+" or "-")
        if not state.log then
            logContent:ClearAllPoints(); logContent:SetPoint("TOPLEFT",f,"TOPLEFT",6,y); logContent:Show(); copy:Show(); y=y-206
        else logContent:Hide(); copy:Hide() end
        local allCollapsed=state.log
        for _,section in ipairs(f.extraSections) do
            section.header:ClearAllPoints(); section.header:SetPoint("TOPLEFT",f,"TOPLEFT",6,y); y=y-20
            local collapsed=state[section.key]; section.header.arrow:SetText(collapsed and "+" or "-")
            if collapsed then section.content:Hide()
            else section.content:ClearAllPoints(); section.content:SetPoint("TOPLEFT",f,"TOPLEFT",6,y); section.content:Show(); y=y-section.height; allCollapsed=false end
        end
        f:SetHeight(-y+6)
        f:SetClampedToScreen(allCollapsed)
        if GBS.Bank.LayoutTabConfig then GBS.Bank:LayoutTabConfig() end
        if GBS.Bank.LayoutActivityPanel then GBS.Bank:LayoutActivityPanel() end
        if GBS.Bank.ScheduleBorderSnap then GBS.Bank:ScheduleBorderSnap() end
    end
    f.LayoutAttached()
end

local function ActivityAge(year,month,day,hour)
    local parts={}; local units={{year,"y"},{month,"mo"},{day,"d"},{hour,"h"}}
    for _,unit in ipairs(units) do if type(unit[1])=="number" and unit[1]>0 then parts[#parts+1]=unit[1]..unit[2] end end
    return #parts>0 and (" ("..table.concat(parts," ").." ago)") or ""
end
local function ActivityMoney(amount)
    amount=math.max(0,math.floor(tonumber(amount) or 0))
    return math.floor(amount/10000).."g "..(math.floor(amount/100)%100).."s "..(amount%100).."c"
end
local function ActivityTabName(tab)
    if type(tab)~="number" then return "?" end
    return GBS.tabNames[tab] or ("Tab "..tab)
end
local function ActivityCount(fn,...)
    if type(fn)~="function" then return nil end
    local ok,n=pcall(fn,...)
    if not ok or type(n)~="number" or n~=n or n<0 or n~=math.floor(n) then return nil end
    return math.min(n,1000)
end
local function ItemActivity(tab)
    local n=ActivityCount(GetNumGuildBankTransactions,tab)
    if not n or type(GetGuildBankTransaction)~="function" then return {"Item log unavailable."} end
    local lines={}
    for i=1,n do
        local ok,kind,name,link,count,from,to,year,month,day,hour=pcall(GetGuildBankTransaction,tab,i)
        if ok and kind then
            name=name or "Unknown"; local item=tostring(link or "Unknown item"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1")
            local quantity=type(count)=="number" and count>1 and (" x"..count) or ""
            local action=kind=="deposit" and "deposited" or (kind=="withdraw" or kind=="withdrawal") and "withdrew" or kind=="move" and "moved" or tostring(kind)
            local path=kind=="move" and (" ("..ActivityTabName(from).." -> "..ActivityTabName(to)..")") or ""
            lines[#lines+1]=name.." "..action.." "..item..quantity..path..ActivityAge(year,month,day,hour)
        end
    end
    if #lines==0 then lines[1]="No item transactions in the client cache." end
    return lines
end
local function MoneyActivity()
    local n=ActivityCount(GetNumGuildBankMoneyTransactions)
    if not n or type(GetGuildBankMoneyTransaction)~="function" then return {"Money log unavailable."} end
    local lines={}
    for i=1,n do
        local ok,kind,name,amount,year,month,day,hour=pcall(GetGuildBankMoneyTransaction,i)
        if ok and kind then
            local labels={deposit="deposited",withdraw="withdrew",withdrawal="withdrew",repair="repaired",withdrawForTab="withdrew for a tab",buyTab="purchased a tab",depositSummary="deposited"}
            lines[#lines+1]=(name or "Unknown").." "..(labels[kind] or tostring(kind)).." "..ActivityMoney(amount)..ActivityAge(year,month,day,hour)
        end
    end
    if #lines==0 then lines[1]="No money transactions in the client cache." end
    return lines
end
local function NewActivityList(parent,name,width)
    width=width or GRID_W
    local scroll=CreateFrame("ScrollFrame",name,parent,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",parent,"TOPLEFT",4,-4); scroll:SetSize(width-24,150); SkinScroll(scroll)
    local canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(width-30,150); scroll:SetScrollChild(canvas)
    local rows={}; local contentHeight=0
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel",function(self,d) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-d*32))) end)
    local function resize(height)
        scroll:SetHeight(height); canvas:SetHeight(math.max(height,contentHeight)); scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()))
    end
    local function render(lines)
        local height=3
        for i,line in ipairs(lines) do
            local row=rows[i] or CreateGBSFontString(canvas,"OVERLAY"); rows[i]=row
            local text,count=WrapRowText(line,width-38)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",canvas,"TOPLEFT",3,-height); row:SetWidth(width-38); row:SetJustifyH("LEFT"); row:SetJustifyV("TOP")
            row:SetText(text); row:SetHeight(count*(GBS_FONT_SIZE+2)+2); row:Show(); height=height+row:GetHeight()
        end
        for i=#lines+1,#rows do rows[i]:Hide() end
        contentHeight=height+3; resize(scroll:GetHeight()); scroll:SetVerticalScroll(0)
    end
    return scroll,render,resize
end
function GBS.Bank:BuildActivitySections(f)
    local bank=self; local state=GBSCharDB.bankSections; f.extraSections={}; bank.infoDrafts={}
    if state.itemLog==nil then state.itemLog=false end
    if state.info==nil then state.info=true end
    if state.itemLog and state.info then state.itemLog=false end
    local side=CreateGBSFrameBase("GBSActivityPanel",340,f:GetHeight(),65)
    side:SetParent(f); side:ClearAllPoints(); side:SetPoint("TOPRIGHT",f,"TOPLEFT",-8,0)
    side:SetClampedToScreen(false); side:SetMovable(false); side:SetScript("OnDragStart",nil); side:SetScript("OnDragStop",nil)
    local title=CreateGBSFontString(side.titleBar,"OVERLAY"); title:SetPoint("LEFT",side.titleBar,"LEFT",8,0); title:SetText("|cffffd100Tab Details|r")
    side:Hide(); bank.activityPanel=side
    side.closeBtn:SetScript("OnClick",function() state.activityOpen=false; side:Hide() end)
    local function updateActivityButton()
        local active=side:IsShown(); local button=f.activityBtn
        button:SetText(active and ">" or "<")
        if active then button:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1); button:SetBackdropBorderColor(E.accent[1]*0.7,E.accent[2]*0.7,E.accent[3]*0.7,1)
        else button:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); button:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1) end
    end
    side:HookScript("OnShow",updateActivityButton)
    side:HookScript("OnHide",function() updateActivityButton(); if f.activity then f.activity.info.edit:ClearFocus() end end)
    f.activityBtn:HookScript("OnEnter",updateActivityButton); f.activityBtn:HookScript("OnLeave",updateActivityButton); f.activityBtn:HookScript("OnEnable",updateActivityButton)
    local SIDE_W=320
    local function section(key,title,parent,width,attached)
        if state[key]==nil then state[key]=true end
        local h=CreateFrame("Button",nil,parent); h:SetSize(width,20); StyleBackdrop(h,1); h:SetBackdropColor(0.14,0.14,0.14,1)
        local label=CreateGBSFontString(h,"OVERLAY"); label:SetPoint("LEFT",h,"LEFT",8,0); label:SetText(title)
        local arrow=CreateGBSFontString(h,"OVERLAY"); arrow:SetPoint("RIGHT",h,"RIGHT",-8,0); h.arrow=arrow
        local panel=CreateFrame("Frame",nil,parent); panel:SetSize(width,160); StyleInset(panel); panel:Hide()
        local entry={key=key,header=h,content=panel,height=160}; if attached then f.extraSections[#f.extraSections+1]=entry end
        h:SetScript("OnClick",function() if not GBS.isRunning then if attached then f.ToggleSection(key) else bank:ToggleActivitySection(key) end end end)
        return entry
    end
    local money=section("moneyLog","MONEY LOG",f,GRID_W,true); local _,renderMoney=NewActivityList(money.content,"GBSMoneyLogScroll"); money.render=renderMoney
    local items=section("itemLog","ITEM LOG",side,SIDE_W,false); local _,renderItems,resizeItems=NewActivityList(items.content,"GBSItemLogScroll",SIDE_W); items.render=renderItems; items.resize=resizeItems
    local info=section("info","INFO",side,SIDE_W,false); local panel=info.content
    local scroll=CreateFrame("ScrollFrame","GBSInfoScroll",panel,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",panel,"TOPLEFT",5,-5); scroll:SetSize(SIDE_W-25,112); SkinScroll(scroll)
    local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetFontObject("GBSFont"); edit:SetSize(SIDE_W-44,112); edit:SetAutoFocus(false); edit:SetMaxLetters(500); edit:EnableMouse(true); scroll:SetScrollChild(edit); info.edit=edit; info.scroll=scroll
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel",function(self,d) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-d*32))) end)
    local status=CreateGBSFontString(panel,"OVERLAY"); status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",8,8); status:SetWidth(SIDE_W-16); status:SetJustifyH("LEFT"); status:SetText(""); info.status=status
    local save=CreateFrame("Button",nil,info.header,"UIPanelButtonTemplate"); save:SetSize(44,18); save:SetPoint("RIGHT",info.header,"RIGHT",-24,0); save:SetText("Save"); StyleButton(save,true); save:Hide(); info.save=save
    info.loading=false; info.setting=false
    local function canEdit(tab)
        if type(CanEditGuildTabInfo)~="function" then return false end
        local ok,allowed=pcall(CanEditGuildTabInfo,tab)
        if not ok or not allowed or allowed==0 or type(GetGuildBankTabInfo)~="function" then return false end
        local valid,_,_,view=pcall(GetGuildBankTabInfo,tab)
        return valid and view and view~=0
    end
    local function updateSave()
        local tab=bank.currentTab; local draft=bank.infoDrafts[tab]
        if draft and draft.loaded and draft.dirty then save:Show() else save:Hide() end
        if draft and draft.loaded and not draft.conflict and not GBS.isRunning and canEdit(tab) then save:Enable() else save:Disable() end
    end
    info.UpdateSave=updateSave
    edit:EnableMouse(false)
    edit:SetScript("OnEscapePressed",function() edit:ClearFocus() end)
    local function resizeInfoText()
        local text=edit:GetText() or ""; local lines=0
        for line in (text.."\n"):gmatch("(.-)\n") do local _,n=WrapRowText(line,SIDE_W-54); lines=lines+n end
        edit:SetHeight(math.max(scroll:GetHeight(),lines*(GBS_FONT_SIZE+2)+12))
    end
    info.resize=function(height) scroll:SetHeight(math.max(1,height-30)); resizeInfoText(); scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange())) end
    edit:SetScript("OnTextChanged",function(self,userInput)
        local text=self:GetText() or ""; resizeInfoText()
        if info.setting then return end
        local d=bank.infoDrafts[bank.currentTab]; if not d or not d.loaded then return end
        d.text=text; d.dirty=d.text~=d.base; updateSave()
        if d.dirty then status:SetText("Unsaved changes") else status:SetText("") end
    end)
    save:SetScript("OnClick",function()
        local tab=bank.currentTab; local d=bank.infoDrafts[tab]
        if not bank:IsOpen() or GBS.isRunning or not d or not d.loaded then status:SetText("Wait for tab info to load."); return end
        if not d.dirty then return end
        if d.conflict then status:SetText("Info changed; reopen or review before saving."); return end
        if not canEdit(tab) then status:SetText("You cannot edit this tab's info."); return end
        if type(GetGuildBankText)~="function" or type(SetGuildBankText)~="function" then status:SetText("Tab info is unavailable."); return end
        local ok,latest=pcall(GetGuildBankText,tab)
        if ok and latest==nil then latest="" end
        if not ok or type(latest)~="string" or latest~=d.base then status:SetText("Info changed; reopen or review before saving."); return end
        local sent=pcall(SetGuildBankText,tab,d.text)
        if not sent then status:SetText("Could not send the info update."); return end
        d.sent=d.text; status:SetText("Save requested. Reopen to verify.")
        if type(QueryGuildBankText)=="function" then pcall(QueryGuildBankText,tab) end
    end)
    f.activity={money=money,items=items,info=info}
    local DIVIDER_HEIGHT=6
    local MIN_CONTENT=3*(GBS_FONT_SIZE+2)+30
    local divider=CreateFrame("Button",nil,side); divider:SetSize(SIDE_W,DIVIDER_HEIGHT); divider:EnableMouse(true); StyleBackdrop(divider,1)
    divider:SetBackdropColor(0.22,0.22,0.22,1); divider:Hide(); side.divider=divider
    divider:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Drag to resize Item Log and Info",1,0.82,0); GameTooltip:Show() end)
    divider:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local function stopDrag() divider.dragY=nil; divider:SetScript("OnUpdate",nil) end
    divider:SetScript("OnHide",stopDrag)
    divider:SetScript("OnMouseUp",stopDrag)
    divider:SetScript("OnMouseDown",function(self,button)
        if button~="LeftButton" or GBS.isRunning or type(GetCursorPosition)~="function" then return end
        local _,y=GetCursorPosition(); if type(y)~="number" then return end
        self.dragY=y; self.startHeight=items.content:GetHeight()
        self:SetScript("OnUpdate",function(d)
            if GBS.isRunning or (type(IsMouseButtonDown)=="function" and not IsMouseButtonDown("LeftButton")) then stopDrag(); return end
            local _,current=GetCursorPosition(); if type(current)~="number" then return end
            local scale=side:GetEffectiveScale() or 1; if scale<=0 then return end
            local available=math.max(2,side:GetHeight()-28-10-40-DIVIDER_HEIGHT)
            local minimum=math.min(MIN_CONTENT,available/2)
            local h=math.max(minimum,math.min(available-minimum,d.startHeight+(d.dragY-current)/scale))
            GBSCharDB.activitySplitPercent=100*h/available; bank:LayoutActivityPanel()
        end)
    end)
    function bank:LayoutActivityPanel()
        side:SetHeight(f:GetHeight())
        local both=not state.itemLog and not state.info
        local available=math.max(2,side:GetHeight()-28-10-40-(both and DIVIDER_HEIGHT or 0))
        local ratio=tonumber(GBSCharDB.activitySplitPercent)
        if not ratio or ratio~=ratio then ratio=50 end
        ratio=math.max(0,math.min(100,ratio))/100
        local minimum=math.min(MIN_CONTENT,available/2)
        local itemHeight=both and math.max(minimum,math.min(available-minimum,available*ratio)) or available
        local y=-28
        for _,entry in ipairs({items,info}) do
            entry.header:ClearAllPoints(); entry.header:SetPoint("TOPLEFT",side,"TOPLEFT",10,y); y=y-20
            local collapsed=state[entry.key]; entry.header.arrow:SetText(collapsed and "+" or "-")
            if collapsed then entry.content:Hide()
            else
                local height=both and (entry==items and itemHeight or available-itemHeight) or available
                entry.content:ClearAllPoints(); entry.content:SetPoint("TOPLEFT",side,"TOPLEFT",10,y)
                entry.content:SetHeight(height); entry.resize(entry==items and math.max(1,height-8) or height); entry.content:Show(); y=y-height
            end
            if entry==items and both then
                divider:ClearAllPoints(); divider:SetPoint("TOPLEFT",side,"TOPLEFT",10,y); divider:Show(); y=y-DIVIDER_HEIGHT
            end
        end
        if not both then divider:Hide() end
    end
    function bank:ToggleActivitySection(key)
        if GBS.isRunning then return end
        local other=key=="info" and "itemLog" or "info"
        state[key]=not state[key]
        local openOther=state[key] and state[other]
        if openOther then state[other]=false end
        if state.info then edit:ClearFocus() end
        self:LayoutActivityPanel()
        if not state[key] then f.RefreshSection(key) end
        if openOther then f.RefreshSection(other) end
    end
    function bank:ToggleActivityPanel()
        if GBS.isRunning then return end
        if side:IsShown() then state.activityOpen=false; side:Hide() else
            state.activityOpen=true; self:RestoreActivityPanel()
        end
    end
    function bank:RestoreActivityPanel()
        if not state.activityOpen then return end
        self:LayoutActivityPanel(); side:Show()
        for _,key in ipairs({"itemLog","info"}) do if not state[key] then f.RefreshSection(key) end end
    end
    function f.RefreshSection(key)
        if not bank:IsOpen() or GBS.isRunning then return end
        if key=="moneyLog" then
            renderMoney({"Loading money log..."})
            if type(QueryGuildBankLog)=="function" then pcall(QueryGuildBankLog,(MAX_GUILDBANK_TABS or NUM_TABS)+1) else renderMoney({"Money log unavailable."}) end
        elseif key=="itemLog" then
            renderItems({"Loading item log..."})
            if GBS.tabNames[bank.currentTab] and type(QueryGuildBankLog)=="function" then pcall(QueryGuildBankLog,bank.currentTab) else renderItems({"Item log unavailable."}) end
        elseif key=="info" then
            local tab=bank.currentTab; local draft=bank.infoDrafts[tab]
            edit:ClearFocus()
            info.setting=true; edit:SetText(draft and draft.text or ""); info.setting=false; updateSave()
            if draft and draft.loaded and canEdit(tab) then
                if draft.conflict then save:Disable() else save:Enable() end; edit:EnableMouse(true)
            else save:Disable(); edit:EnableMouse(false) end
            status:SetText(draft and draft.dirty and "Unsaved changes" or "Loading tab info...")
            if GBS.tabNames[tab] and type(QueryGuildBankText)=="function" then pcall(QueryGuildBankText,tab) else status:SetText("Tab info unavailable.") end
        end
    end
    function f.RefreshActivityForTab()
        for _,key in ipairs({"moneyLog","itemLog","info"}) do if not state[key] and (key=="moneyLog" or side:IsVisible()) then f.RefreshSection(key) end end
    end
    function f.ActivityEvent(event,tab)
        if event=="GUILDBANKLOG_UPDATE" then
            if not state.moneyLog then renderMoney(MoneyActivity()) end
            if side:IsVisible() and not state.itemLog and GBS.tabNames[bank.currentTab] then renderItems(ItemActivity(bank.currentTab)) end
        elseif event=="GUILDBANK_UPDATE_TEXT" then
            tab=tonumber(tab); if not tab then return end
            if type(GetGuildBankText)~="function" then return end
            local ok,text=pcall(GetGuildBankText,tab); if not ok then return end; if text==nil then text="" end; if type(text)~="string" then return end
            local d=bank.infoDrafts[tab]
            if not d then d={}; bank.infoDrafts[tab]=d end
            if d.sent and text==d.sent then d.base=text; d.sent=nil; d.dirty=d.text~=text; d.conflict=nil
            elseif not d.dirty then d.base=text; d.text=text
            elseif d.base~=text then d.conflict=true end
            d.loaded=true
            if tab==bank.currentTab then updateSave() end
            if tab==bank.currentTab and side:IsVisible() and not state.info then
                info.setting=true; edit:SetText(d.text or ""); info.setting=false
                if d.conflict then status:SetText("Info changed remotely; review before saving.")
                elseif d.dirty then status:SetText("Unsaved changes") else status:SetText("Client view updated; reopen to verify.") end
                if not GBS.isRunning and canEdit(tab) then if d.conflict then save:Disable() else save:Enable() end; edit:EnableMouse(true)
                else save:Disable(); edit:ClearFocus(); edit:EnableMouse(false) end
            end
        elseif event=="GUILDBANK_TEXT_CHANGED" and not GBS.isRunning and tonumber(tab)==bank.currentTab and side:IsVisible() and not state.info and type(QueryGuildBankText)=="function" then
            pcall(QueryGuildBankText,bank.currentTab)
        end
    end
    save:Disable(); renderMoney({"Open to load money transactions."}); renderItems({"Open to load item transactions."})
    return f.activity
end

function GBS.Bank:BuildProcessingDialog(f)
    -- Shield is confined to the bank, not UIParent; it covers the attached panes too.
    local shield=CreateFrame("Frame",nil,f); shield:SetAllPoints(f); shield:SetFrameLevel(80); shield:EnableMouse(true); shield:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"}); shield:SetBackdropColor(0,0,0,0.18); shield:Hide(); f.processingShield=shield
    local dialog=CreateFrame("Frame",nil,f); dialog:SetSize(340,119); dialog:SetPoint("TOPLEFT",f,"TOPRIGHT",8,0); dialog:SetFrameLevel(85); StyleBackdrop(dialog,1); dialog:EnableMouse(true); dialog:SetClampedToScreen(true); dialog:Hide()
    local title=CreateGBSFontString(dialog,"OVERLAY"); title:SetPoint("TOP",dialog,"TOP",0,-10); title:SetText("|cffffd100Guild bank processing|r")
    local status=CreateGBSFontString(dialog,"OVERLAY"); status:SetPoint("TOP",dialog,"TOP",0,-31); status:SetWidth(320); status:SetJustifyH("CENTER"); status:SetText(""); dialog.status=status
    local detail=CreateGBSFontString(dialog,"OVERLAY"); detail:SetPoint("TOP",dialog,"TOP",0,-50); detail:SetWidth(320); detail:SetJustifyH("CENTER"); detail:SetText(""); dialog.detail=detail
    local bar=StyleThinBar(dialog,300,12); bar:SetPoint("TOP",dialog,"TOP",0,-71); bar:SetMinMaxValues(0,1); bar:SetValue(0); dialog.bar=bar
    local stop=CreateFrame("Button",nil,dialog,"UIPanelButtonTemplate"); stop:SetSize(100,22); stop:SetPoint("BOTTOM",dialog,"BOTTOM",0,7); stop:SetText("STOP"); StyleButton(stop,false); stop:SetBackdropColor(0.5,0.12,0.12,1); stop:SetScript("OnClick",function() GBS:Cancel() end); dialog.stopBtn=stop
    f.processingDialog=dialog; f.wasProcessing=false
end
function GBS.Bank:UpdateProcessing()
    local f=self.frame; if not f or not f.processingShield then return end
    if GBS.isRunning then
        f.wasProcessing=true
        CloseOurSplit()
        if GBS.SortDirMenu then GBS.SortDirMenu:Hide() end
        if f.settings and f.settings.delayPopups then for _,popup in ipairs(f.settings.delayPopups) do popup:Hide() end end
        if self.tabConfig then self.tabConfig:Hide() end
        if f.activity then f.activity.info.edit:ClearFocus(); f.activity.info.edit:EnableMouse(false); f.activity.info.save:Disable() end
        if self.purchaseDialog then self.purchaseDialog:Hide() end
        if self.moneyBox then self.moneyBox:Hide() end
        if GBS.copyFrame then GBS.copyFrame:Hide() end
        local phase=GBS.currentPhase or "Processing"; local done,total=GBS.doneSteps or 0,GBS.totalSteps or 0; local detail=""
        if GBS.arrange then
            local a=GBS.arrange; local e=a.estimates[a.tab]; local tabTotal=e and (e.stack+e.order) or 0
            phase=string.format("%s tab %d: %d/%d estimated",a.prestack and "Pre-stack" or "Sort",a.tab,a.tabOps,tabTotal)
            done=(GBS.workRouteDone or 0)+a.ops; total=(GBS.workRouteDone or 0)+a.estimate
            detail=string.format("Total %d/%d estimated%s | tabs %d/%d",done,total,a.estimateComplete and "" or "+",math.min(a.tab-1,a.tabCount),a.tabCount)
        elseif GBS.routing then
            local a=GBS.routing; phase="Routing "..(a.index-1).."/"..#a.moves
            detail="Stack/order total calculated after routing"
        else phase=phase.." "..done.."/"..total; detail="Work planned after scanning" end
        local bar=f.processingDialog.bar; bar:SetMinMaxValues(0,math.max(1,total)); bar:SetValue(math.min(done,math.max(1,total)))
        f.processingDialog.status:SetText(phase); f.processingDialog.detail:SetText(detail); f.processingShield:Show(); f.processingDialog:Show()
    else
        f.processingShield:Hide(); f.processingDialog:Hide()
        if f.wasProcessing then
            f.wasProcessing=false
            if not self.activityRefreshDriver then self.activityRefreshDriver=CreateFrame("Frame",nil,f) end
            self.activityRefreshDriver:SetScript("OnUpdate",function(driver)
                driver:SetScript("OnUpdate",nil)
                if not GBS.Bank:IsOpen() then return end
                if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange then f.wasProcessing=true; return end
                if f.RefreshActivityForTab then f.RefreshActivityForTab() end
            end)
        end
    end
end

-- Calculate one physical-pixel thickness without modifying the player's UI scale.
local borderSnap=CreateFrame("Frame","GBSBorderSnap",UIParent); borderSnap:Hide()
local function PixelSize(frame)
    local height
    if type(GetPhysicalScreenSize)=="function" then local _,h=GetPhysicalScreenSize(); if type(h)=="number" and h>0 then height=h end end
    if not height and type(GetScreenResolutions)=="function" and type(GetCurrentResolution)=="function" then
        local resolutions={GetScreenResolutions()}; local resolution=resolutions[GetCurrentResolution() or 0]
        if resolution then height=tonumber(resolution:match("%d+%s*[xX]%s*(%d+)")) end
    end
    if not height and type(GetCVar)=="function" then
        local resolution=GetCVar("gxWindowedResolution") or GetCVar("gxResolution")
        if resolution then height=tonumber(resolution:match("%d+%s*[xX]%s*(%d+)")) end
    end
    local scale=frame:GetEffectiveScale() or 1
    if height and height>0 and scale>0 then return 768/height/scale end
    return 1
end
local function AlignBorders(btn)
    local p=PixelSize(btn); local l,r,t,b=btn:GetLeft(),btn:GetRight(),btn:GetTop(),btn:GetBottom()
    local function offset(v) return v and (math.floor(v/p+0.5)*p-v) or 0 end
    local dxL,dxR,dyT,dyB=offset(l),offset(r),offset(t),offset(b)
    local e=btn.qualityEdges
    for _,v in ipairs(e) do v:ClearAllPoints() end
    e[1]:SetPoint("TOPLEFT",btn,"TOPLEFT",dxL,dyT); e[1]:SetPoint("TOPRIGHT",btn,"TOPRIGHT",dxR,dyT); e[1]:SetHeight(p)
    e[2]:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",dxL,dyB); e[2]:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",dxR,dyB); e[2]:SetHeight(p)
    e[3]:SetPoint("TOPLEFT",btn,"TOPLEFT",dxL,dyT); e[3]:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",dxL,dyB); e[3]:SetWidth(p)
    e[4]:SetPoint("TOPRIGHT",btn,"TOPRIGHT",dxR,dyT); e[4]:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",dxR,dyB); e[4]:SetWidth(p)
end
function GBS.Bank:ScheduleBorderSnap()
    if not self:IsOpen() then return end
    borderSnap:SetScript("OnUpdate",function(self)
        self:SetScript("OnUpdate",nil); self:Hide()
        if GBS.Bank:IsOpen() then for _,btn in ipairs(GBS.Bank.slotButtons) do AlignBorders(btn) end end
    end); borderSnap:Show()
end

function GBS.Bank:Create()
    if self.frame then return self.frame end
    local f=CreateFrame("Frame","GBSCustomBank",UIParent)
    f:Hide()
    f:SetSize(GRID_W+12,430)
    if GBSCharDB.bankPos and GBSCharDB.bankPos.point then RestoreFramePos(f,"bankPos") else f:SetPoint("CENTER",UIParent,"CENTER",-238,0) end
    f:SetFrameStrata("DIALOG"); f:SetToplevel(false); f:SetFrameLevel(20)
    pcall(function() StyleBackdrop(f,0.96); f:SetBackdropBorderColor(0,0,0,1) end)
    f:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end); f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local left,top=s:GetLeft(),s:GetTop(); local rootLeft,rootTop=UIParent:GetLeft(),UIParent:GetTop()
        if left and top and rootLeft and rootTop then
            local scale=s:GetEffectiveScale()/UIParent:GetEffectiveScale()
            local x,y=left*scale-rootLeft,top*scale-rootTop
            s:ClearAllPoints(); s:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x,y); GBSCharDB.bankPos={point="TOPLEFT",x=x,y=y}
        end
        if GBS.Bank.ScheduleBorderSnap then GBS.Bank:ScheduleBorderSnap() end
    end)
    f:SetClampedToScreen(true)
    local tb=CreateFrame("Frame",nil,f); tb:SetFrameLevel(f:GetFrameLevel()+1); tb:SetHeight(22); tb:SetPoint("TOPLEFT",f,"TOPLEFT",1,-1); tb:SetPoint("TOPRIGHT",f,"TOPRIGHT",-1,-1)
    tb:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"}); tb:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); tb:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],0); f.titleBar=tb
    local ttl=CreateGBSFontString(tb,"OVERLAY"); ttl:SetPoint("LEFT",tb,"LEFT",8,0); ttl:SetFont(GBS_FONT,GBS_FONT_SIZE,""); ttl:SetText("|cffffd100Guild Bank|r"); f.title=ttl
    local access=CreateGBSFontString(tb,"OVERLAY"); access:SetPoint("LEFT",ttl,"RIGHT",4,0); access:SetPoint("RIGHT",tb,"RIGHT",-26,0); access:SetJustifyH("LEFT"); access:SetWordWrap(false); access:SetTextColor(0.65,0.65,0.65); access:SetText(""); f.accessTitle=access
    local close=CreateTitleClose(f,tb)
    close:SetScript("OnClick", function() f:Hide(); if CloseGuildBankFrame then CloseGuildBankFrame() end end)
    f.close=close
    local tabs=CreateFrame("Frame",nil,f); tabs:SetHeight(46); tabs:SetPoint("TOPLEFT",f,"TOPLEFT",6,-24); tabs:SetPoint("TOPRIGHT",f,"TOPRIGHT",-6,-24); f.tabsBar=tabs
    local tabW = math.floor((GRID_W-8)/3)
    for i=1,NUM_TABS do
        local b=CreateFrame("Button",nil,tabs); b:SetSize(tabW,22); b:SetPoint("TOPLEFT",tabs,"TOPLEFT",((i-1)%3)*(tabW+4),-math.floor((i-1)/3)*24)
        StyleBackdrop(b,1); b:SetBackdropColor(0.13,0.13,0.13,1)
        local icon=b:CreateTexture(nil,"ARTWORK"); icon:SetSize(16,16); icon:SetPoint("LEFT",b,"LEFT",4,0); icon:SetTexCoord(0.08,0.92,0.08,0.92); b.icon=icon
        local tx=CreateGBSFontString(b,"OVERLAY"); tx:SetPoint("LEFT",icon,"RIGHT",4,0); tx:SetPoint("RIGHT",b,"RIGHT",-52,0); tx:SetFont(GBS_FONT,GBS_FONT_SIZE,""); tx:SetJustifyH("LEFT"); tx:SetJustifyV("MIDDLE"); tx:SetWordWrap(false); tx:SetHeight(20); b.text=tx
        local count=CreateGBSFontString(b,"OVERLAY"); count:SetPoint("RIGHT",b,"RIGHT",-3,0); count:SetTextColor(0.65,0.65,0.65); count:SetText("(?/98)"); b.count=count
        b:SetScript("OnClick", function(self, btn)
            if not GBS.tabNames[i] then GBS.Bank:OpenTabPurchase(i)
            elseif btn=="RightButton" then GBS.Bank:OpenTabConfig(i) else GBS.Bank:SelectTab(i) end
        end); b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b:SetScript("OnEnter", function(s) if GBS.Bank.currentTab~=i then s:SetBackdropBorderColor(0.45,0.45,0.45,1) end; local name=GBS.tabNames[i]; GameTooltip:SetOwner(s,"ANCHOR_TOP"); if name then GameTooltip:AddLine(name,1,0.82,0); for _,line in ipairs(GBS.Assign:Describe(i)) do GameTooltip:AddLine(line,0.85,0.85,0.85) end; GameTooltip:AddLine("Left-click: view  |  Right-click: configure tab",0.7,0.7,0.7) else GameTooltip:AddLine("Locked tab "..i,0.7,0.7,0.7); GameTooltip:AddLine("Click to view purchase options.",0.7,0.7,0.7) end; GameTooltip:Show() end)
        b:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(0.22,0.22,0.22,1); GameTooltip:Hide() end)
        self.tabButtons[i]=b
    end
    local grid=CreateFrame("Frame",nil,f); grid:SetPoint("TOPLEFT",f,"TOPLEFT",6,-75); grid:SetSize(GRID_W, GRID_H); grid:SetFrameLevel(f:GetFrameLevel()+2); f.grid=grid
    for i=1,98 do
        local r=math.floor((i-1)/BANK_COLS); local c=(i-1)%BANK_COLS
        local btn=CreateFrame("Button",nil,grid); btn:SetSize(SLOT_SIZE,SLOT_SIZE); btn:SetPoint("TOPLEFT",grid,"TOPLEFT", c*(SLOT_SIZE+SLOT_GAP), -r*(SLOT_SIZE+SLOT_GAP))
        StyleBackdrop(btn,1); btn:SetBackdropColor(0.07,0.07,0.07,1); btn:SetBackdropBorderColor(0.20,0.20,0.20,0.8)
        local icon=btn:CreateTexture(nil,"ARTWORK"); icon:SetPoint("TOPLEFT",btn,"TOPLEFT",2,-2); icon:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-2,2); icon:SetTexCoord(0.08,0.92,0.08,0.92); btn.icon=icon
        -- Explicit overlay edges render above the icon rather than relying on
        -- a backdrop border underneath the artwork.
        btn.qualityEdges={}
        for edge=1,4 do
            local t=btn:CreateTexture(nil,"OVERLAY"); t:SetTexture("Interface\\Buttons\\WHITE8x8")
            if edge==1 then t:SetPoint("TOPLEFT",btn,"TOPLEFT",0,0); t:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,0); t:SetHeight(1)
            elseif edge==2 then t:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",0,0); t:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",0,0); t:SetHeight(1)
            elseif edge==3 then t:SetPoint("TOPLEFT",btn,"TOPLEFT",0,0); t:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",0,0); t:SetWidth(1)
            else t:SetPoint("TOPRIGHT",btn,"TOPRIGHT",0,0); t:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",0,0); t:SetWidth(1) end
            btn.qualityEdges[edge]=t
        end
        local count=CreateGBSFontString(btn,"OVERLAY"); count:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-2,2); count:SetFont(GBS_FONT,GBS_FONT_SIZE,"OUTLINE"); count:SetTextColor(1,1,1,1); count:SetShadowColor(0,0,0,1); count:SetShadowOffset(1,-1); btn.count=count
        local hl=btn:CreateTexture(nil,"HIGHLIGHT"); hl:SetAllPoints(btn); hl:SetTexture("Interface\\Buttons\\WHITE8x8"); hl:SetVertexColor(1,1,1,0.15); hl:SetBlendMode("ADD"); btn.hl=hl
        btn:SetScript("OnEnter", function(self)
            local tab=GBS.Bank.currentTab; if not tab or not GBS.tabNames[tab] then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            local ok=pcall(function() GameTooltip:SetGuildBankItem(tab, i) end)
            if not ok then local link; pcall(function() link=GetGuildBankItemLink(tab,i) end); if link then GameTooltip:SetHyperlink(link) end end
            if GameTooltip:NumLines()==0 then GameTooltip:AddLine("Empty slot",0.6,0.6,0.6) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self, button)
            local tab=GBS.Bank.currentTab
            if not tab or not GBS.tabNames[tab] or GBS.isRunning then return end
            if not GBS.Bank:EnsureManualTab() then return end
            local link=GetGuildBankItemLink and GetGuildBankItemLink(tab,i)
            if link and type(HandleModifiedItemClick)=="function" then
                local ok,handled=pcall(HandleModifiedItemClick,link)
                if ok and handled then return end
            elseif link and type(IsModifiedClick)=="function" and IsModifiedClick("CHATLINK") and type(ChatEdit_InsertLink)=="function" then
                local ok,handled=pcall(ChatEdit_InsertLink,link); if ok and handled then return end
            end
            if type(IsModifiedClick)=="function" and IsModifiedClick("SPLITSTACK") then
                local tex,count,locked=GetGuildBankItemInfo(tab,i)
                if button=="LeftButton" and not SafeGetCursorInfo() and tex and link and count and count>1 and not locked then OpenOurSplit(self,tab,i,link,count) end
                return -- a modified click must never fall through to pickup or autostore
            end
            GBS.scanData=nil -- manual bank interaction invalidates cached scan data
            if button=="RightButton" then
                if not SafeGetCursorInfo() and type(AutoStoreGuildBankItem)=="function" then AutoStoreGuildBankItem(tab,i) end
            else
                SafePickupGuildBankItem(tab,i)
            end
        end)
        btn:RegisterForClicks("LeftButtonUp","RightButtonUp"); btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function(self) if not GBS.isRunning and not GBS.activeMove and GBS.tabNames[GBS.Bank.currentTab] and GBS.Bank:EnsureManualTab() then GBS.scanData=nil; SafePickupGuildBankItem(GBS.Bank.currentTab,i) end end)
        btn:SetScript("OnReceiveDrag", function(self) if not GBS.isRunning and not GBS.activeMove and GBS.tabNames[GBS.Bank.currentTab] and GBS.Bank:EnsureManualTab() then GBS.scanData=nil; SafePickupGuildBankItem(GBS.Bank.currentTab,i) end end)
        self.slotButtons[i]=btn
    end
    local bot=CreateFrame("Frame",nil,f); bot:SetHeight(26); bot:SetPoint("TOPLEFT",f,"TOPLEFT",6,-335); bot:SetPoint("TOPRIGHT",f,"TOPRIGHT",-6,-335); f.botBar=bot
    local sideBtn=CreateFrame("Button",nil,bot,"UIPanelButtonTemplate"); sideBtn:SetSize(22,22); sideBtn:SetPoint("LEFT",bot,"LEFT",0,0); sideBtn:SetText("<"); StyleButton(sideBtn,false); f.activityBtn=sideBtn
    sideBtn:SetScript("OnClick",function() GBS.Bank:ToggleActivityPanel() end)
    sideBtn:HookScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Item log and tab info",1,0.82,0); GameTooltip:Show() end)
    sideBtn:HookScript("OnLeave",function() GameTooltip:Hide() end)
    local sortBtn=CreateFrame("Button",nil,bot,"UIPanelButtonTemplate"); local buttonWidth=(GRID_W-42)/5; sortBtn:SetSize(buttonWidth,22); sortBtn:SetPoint("LEFT",sideBtn,"RIGHT",4,0); sortBtn:SetText("SORT"); StyleButton(sortBtn,true); sortBtn:SetScript("OnClick", function() GBS:StartSort() end); f.sortBtn=sortBtn; AddSortBlocker(sortBtn)
    sortBtn:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Sort guild bank",1,0.82,0); GameTooltip:AddLine("Immediately scans, routes, stacks and orders items.",1,1,1,true); GameTooltip:Show() end)
    sortBtn:SetScript("OnLeave",function() GameTooltip:Hide() end); UpdateSortControls()
    local moneyBG=CreateFrame("Button",nil,bot); moneyBG:SetSize(buttonWidth,22); moneyBG:SetPoint("RIGHT",bot,"RIGHT",0,0); moneyBG:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=0,right=0,top=0,bottom=0}}); moneyBG:SetBackdropColor(0.07,0.07,0.07,1); moneyBG:SetBackdropBorderColor(0.22,0.22,0.22,1)
    local money=CreateGBSFontString(moneyBG,"OVERLAY"); money:SetPoint("LEFT",moneyBG,"LEFT",4,0); money:SetPoint("RIGHT",moneyBG,"RIGHT",-4,0); money:SetWordWrap(false); money:SetFont(GBS_FONT,GBS_FONT_SIZE,""); money:SetJustifyH("CENTER"); money:SetText(""); f.money=money; f.moneyBG=moneyBG
    moneyBG:RegisterForClicks("LeftButtonUp","RightButtonUp")
    moneyBG:SetScript("OnClick",function(_,button)
        if GBS.isRunning then return end
        if button=="LeftButton" then GBS.Bank:OpenMoneyBox("deposit") elseif button=="RightButton" then GBS.Bank:OpenMoneyBox("withdraw") end
    end)
    moneyBG:SetScript("OnEnter",function(self)
        local copper=0; if type(GetGuildBankMoney)=="function" then local ok,v=pcall(GetGuildBankMoney); if ok and type(v)=="number" then copper=math.max(0,math.floor(v)) end end
        local gold=math.floor(copper/10000); local silver=math.floor(copper/100)%100; local rest=copper%100
        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Bank balance",1,0.82,0)
        GameTooltip:AddLine(string.format("|cffffffff%d|r|cffffd100g|r |cffffffff%d|r|cffc7c7c7s|r |cffffffff%d|r|cffcd7f32c|r",gold,silver,rest),1,1,1)
        local limit
        if type(GetGuildBankWithdrawMoney)=="function" then local ok,v=pcall(GetGuildBankWithdrawMoney); if ok and type(v)=="number" then limit=v end end
        local limitText=not limit and "Unknown" or (limit<0 or limit>=4294967295) and "Unlimited" or ActivityMoney(limit)
        GameTooltip:AddLine("Withdrawal remaining: "..limitText,0.8,0.8,0.8)
        GameTooltip:AddLine("Left-click: Deposit",0.8,0.8,0.8); GameTooltip:AddLine("Right-click: Withdraw",0.8,0.8,0.8); GameTooltip:Show()
    end)
    moneyBG:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local settings=CreateFrame("Frame",nil,bot); settings:SetSize(3*buttonWidth+8,22); settings:SetPoint("LEFT",sortBtn,"RIGHT",4,0); f.settings=settings
    BuildDelays(settings,buttonWidth); f.moveSlider=settings.moveSlider; f.scanSlider=settings.scanSlider; f.sortDirBtn=settings.sortDirBtn
    f:SetScript("OnShow", function() GBS.Bank:Refresh(); GBS.Bank:HookBags(); if GBS.Bank.RestoreActivityPanel then GBS.Bank:RestoreActivityPanel() end end)
    f:SetScript("OnHide", function()
        if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange then GBS:Cancel() end
        CloseOurSplit()
        if f.settings and f.settings.delayPopups then for _,popup in ipairs(f.settings.delayPopups) do popup:Hide() end end
        if GBS.copyFrame then GBS.copyFrame:Hide() end; if GBS.SortDirMenu then GBS.SortDirMenu:Hide() end
        if GBS.Bank.activityPanel then GBS.Bank.activityPanel:Hide() end
        GBS.Bank.infoDrafts={}; if f.activity then f.activity.info.UpdateSave() end
    end)
    f:SetScript("OnEvent", function(self, event, ...)
        if not self:IsVisible() then return end
        local native
        if type(GetCurrentGuildBankTab)=="function" then local ok,value=pcall(GetCurrentGuildBankTab); if ok then native=value end end
        if event=="GUILDBANKBAGSLOTS_CHANGED" and not GBS.isRunning and GBS.Bank.currentTab and GBS.tabNames[GBS.Bank.currentTab] and (not native or native==GBS.Bank.currentTab) then
            GBS.Bank.knownCounts=GBS.Bank.knownCounts or {}; GBS.Bank.knownCounts[GBS.Bank.currentTab]=CountItemsInTab(GBS.Bank.currentTab)
        end
        if event=="GUILDBANKLOG_UPDATE" or event=="GUILDBANK_UPDATE_TEXT" or event=="GUILDBANK_TEXT_CHANGED" then
            if self.ActivityEvent then self.ActivityEvent(event,...) end
            return
        end
        if GBS.Bank and GBS.Bank.Refresh then GBS.Bank:Refresh() end
        if not GBS.isRunning and (event=="GUILDBANK_UPDATE_TABS" or (event=="GUILDBANKBAGSLOTS_CHANGED" and native and native~=GBS.Bank.currentTab)) then GBS.Bank:ScheduleSelectionRefresh(false) end
    end)
    f:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED"); f:RegisterEvent("GUILDBANK_ITEM_LOCK_CHANGED"); f:RegisterEvent("GUILDBANK_UPDATE_TABS"); f:RegisterEvent("GUILDBANK_UPDATE_MONEY")
    f:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY"); f:RegisterEvent("GUILD_ROSTER_UPDATE"); f:RegisterEvent("GUILDBANKLOG_UPDATE"); f:RegisterEvent("GUILDBANK_UPDATE_TEXT"); f:RegisterEvent("GUILDBANK_TEXT_CHANGED")
    self.frame=f
    GBS.Bank:BuildAttachedSections(f)
    GBS.Bank:BuildActivitySections(f); f.LayoutAttached()
    GBS.Bank:BuildProcessingDialog(f)
    UpdateSortControls(); return f
end
function GBS.Bank:OpenMoneyBox(mode)
    if self.purchaseDialog then self.purchaseDialog:Hide() end
    if GBS.assignFrame then GBS.assignFrame:Hide() end
    if self.tabConfig then self.tabConfig:Hide() end
    if not self.moneyBox then
        local box=CreateGBSFrameBase("GBSMoneyBox",264,174,95)
        RestoreFramePos(box,"moneyPos","CENTER",0,60)
        local title=CreateGBSFontString(box.titleBar,"OVERLAY")
        title:SetPoint("LEFT",box.titleBar,"LEFT",8,0); title:SetFont(GBS_FONT,GBS_FONT_SIZE,""); box.title=title
        local labels={"Gold","Silver","Copper"}; local widths={76,76,76}; local xs={10,94,178}
        box.inputs={}
        for i=1,3 do
            local lbl=CreateGBSFontString(box,"OVERLAY")
            lbl:SetPoint("TOPLEFT",box,"TOPLEFT",xs[i],-31); lbl:SetText(labels[i])
            local eb=CreateGBSInput(box,widths[i],22)
             eb:SetPoint("TOPLEFT",box,"TOPLEFT",xs[i],-46); eb:SetAutoFocus(false); eb:SetNumeric(true)
            eb:SetMaxLetters(i==1 and 9 or 2); eb:SetScript("OnEscapePressed",function() box:Hide() end)
            box.inputs[i]=eb
        end
        local avail=CreateGBSFontString(box,"OVERLAY")
        avail:SetPoint("TOPLEFT",box,"TOPLEFT",16,-76); avail:SetPoint("RIGHT",box,"RIGHT",-16,0); avail:SetJustifyH("LEFT"); box.avail=avail
        local limitFS=CreateGBSFontString(box,"OVERLAY"); limitFS:SetPoint("TOPLEFT",box,"TOPLEFT",16,-96); limitFS:SetWidth(236); limitFS:SetJustifyH("LEFT"); box.limit=limitFS
        local err=CreateGBSFontString(box,"OVERLAY")
        err:SetPoint("TOPLEFT",box,"TOPLEFT",16,-119); err:SetPoint("RIGHT",box,"RIGHT",-16,0); err:SetJustifyH("LEFT"); err:SetTextColor(1,0.35,0.3); box.error=err
        local ok=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); ok:SetSize(76,22); ok:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-98,10); ok:SetText("Confirm"); StyleButton(ok,true); box.ok=ok
        local cancel=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); cancel:SetSize(76,22); cancel:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-12,10); cancel:SetText("Cancel"); StyleButton(cancel,false); cancel:SetScript("OnClick",function() box:Hide() end)
        box.ShowError=function(text)
            box:SetHeight(box.mode=="deposit" and 146 or 165); box.error:SetText(text)
        end
        ok:SetScript("OnClick",function()
            local vals={}
            for i=1,3 do
                local txt=Trim(box.inputs[i]:GetText() or "")
                if txt~="" and not txt:match("^%d+$") then box.ShowError("Use whole numbers only."); return end
                vals[i]=tonumber(txt) or 0
            end
            if vals[2]>99 or vals[3]>99 then box.ShowError("Silver and copper must be 0 to 99."); return end
            local amount=vals[1]*10000+vals[2]*100+vals[3]
            if amount<=0 or amount>2147483647 then box.ShowError("Enter a valid amount greater than zero."); return end
            local available=box.mode=="deposit" and (GetMoney and GetMoney() or 0) or (GetGuildBankMoney and GetGuildBankMoney() or 0)
            if amount>available then box.ShowError("Amount exceeds available funds."); return end
            if box.mode=="withdraw" and GetGuildBankWithdrawMoney then
                local limit=GetGuildBankWithdrawMoney()
                if limit and limit>=0 and amount>limit then box.ShowError("Amount exceeds your withdrawal limit."); return end
            end
            local fn=box.mode=="deposit" and DepositGuildBankMoney or WithdrawGuildBankMoney
            if type(fn)~="function" then box.ShowError("Money operation is unavailable."); return end
            local success,errMsg=pcall(fn,amount)
            if not success then box.ShowError("Transaction failed; see chat."); Chat(tostring(errMsg),1,0.4,0.4); return end
            box:Hide()
        end)
        if UISpecialFrames then tinsert(UISpecialFrames,"GBSMoneyBox") end
        box:Hide(); self.moneyBox=box
    end
    local box=self.moneyBox; box.mode=mode
    box.title:SetText(mode=="deposit" and "|cffffd100Deposit Money|r" or "|cffffd100Withdraw Money|r")
    local balance=mode=="deposit" and (GetMoney and GetMoney() or 0) or (GetGuildBankMoney and GetGuildBankMoney() or 0)
    local text=GetCoinTextureString and GetCoinTextureString(balance) or tostring(balance)
    box.avail:SetText((mode=="deposit" and "Your balance: " or "Bank balance: ")..text)
    if mode=="withdraw" then
        local limit=GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
        local amount=type(limit)=="number" and ((limit<0) and "Unlimited" or (GetCoinTextureString and GetCoinTextureString(limit) or tostring(limit))) or "Unknown"
        box.limit:SetText("Withdraw limit: "..amount)
    else box.limit:SetText("") end
    box.error:SetText(""); for _,eb in ipairs(box.inputs) do eb:SetText("") end
    box:SetHeight(mode=="deposit" and 128 or 147)
    box.error:ClearAllPoints(); box.error:SetPoint("TOPLEFT",box,"TOPLEFT",16,mode=="deposit" and -93 or -114); box.error:SetPoint("RIGHT",box,"RIGHT",-16,0)
    box:Show(); box.inputs[1]:SetFocus()
end

-- Wrath's guild bank icon chooser uses the item-icon index, not the newer
-- table-returning 4.3+ API or a filename accepted by later clients.
local function GuildIconName(icon)
    if type(icon)~="string" then return nil end
    local name=icon:gsub("/","\\"):match("([^\\]+)$")
    if name and name~="" then return string.upper(name) end
end
local function GetGuildIconCatalog()
    local out={}
    if type(GetNumMacroItemIcons)~="function" or type(GetMacroItemIconInfo)~="function" then return out,false end
    local ok,count=pcall(GetNumMacroItemIcons)
    if not ok or type(count)~="number" then return out,false end
    for index=1,count do
        local valid,texture=pcall(GetMacroItemIconInfo,index)
        local name=valid and GuildIconName(texture)
        if name then out[#out+1]={name=name,index=index,texture=texture} end
    end
    return out,#out>0
end
local function FindGuildIconIndex(texture,catalog)
    local name=GuildIconName(texture)
    if not name then return nil end
    for _,entry in ipairs(catalog) do if entry.name==name then return entry.index end end
    return nil
end
local function PurchaseInfo()
    if type(GetNumGuildBankTabs)~="function" or type(GetGuildBankTabCost)~="function" then return nil,nil end
    local ok,count=pcall(GetNumGuildBankTabs); local costOK,cost=pcall(GetGuildBankTabCost)
    if not ok or type(count)~="number" or count~=count or count<0 or count>NUM_TABS or count~=math.floor(count) then return nil,nil end
    if count==NUM_TABS then return count,nil end
    if not costOK or type(cost)~="number" or cost~=cost or cost<0 or cost==math.huge or cost~=math.floor(cost) then return count,nil end
    return count,cost
end
local function CanBuyTab(count,cost)
    if not GBS.Bank:IsOpen() or GBS.isRunning then return "Open the bank and stop sorting first." end
    if SafeGetCursorInfo() then return "Place the item on your cursor before purchasing." end
    if GBS.Bank.purchasePending or GBS.Bank.purchaseUnconfirmed then return "A purchase is pending or unconfirmed. Reopen the bank to check." end
    if type(IsGuildLeader)~="function" or not IsGuildLeader() then return "Only the guild leader can purchase a tab." end
    if type(BuyGuildBankTab)~="function" then return "Tab purchasing is unavailable on this client." end
    if not count or not cost then return "Tab price is unavailable. Reopen the bank and try again." end
    if type(GetMoney)~="function" or type(GetGuildBankMoney)~="function" then return "Unable to check available funds." end
    local a,personal=pcall(GetMoney); local b,guild=pcall(GetGuildBankMoney)
    if not a or not b or type(personal)~="number" or type(guild)~="number" then return "Unable to check available funds." end
    if personal+guild<cost then return "Insufficient available gold." end
end
local function FormatTabPrice(copper)
    local gold=math.floor(copper/10000); local silver=math.floor(copper/100)%100; local rest=copper%100
    local parts={}
    if gold>0 then parts[#parts+1]=gold.."g" end
    if silver>0 then parts[#parts+1]=silver.."s" end
    if rest>0 or #parts==0 then parts[#parts+1]=rest.."c" end
    return table.concat(parts," ")
end
function GBS.Bank:OpenTabPurchase(tab)
    if not self:IsOpen() or GBS.isRunning then return end
    if self.tabConfig then self.tabConfig:Hide() end
    if self.moneyBox then self.moneyBox:Hide() end
    if not self.purchaseDialog then
        local box=CreateGBSFrameBase("GBSTabPurchase",340,210,75)
        box:SetParent(self.frame); box:ClearAllPoints(); box:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",8,0)
        box:SetClampedToScreen(false); box:SetMovable(false); box:SetScript("OnDragStart",nil); box:SetScript("OnDragStop",nil)
        local title=CreateGBSFontString(box.titleBar,"OVERLAY"); title:SetPoint("LEFT",box.titleBar,"LEFT",8,0); title:SetText("|cffffd100Purchase guild bank tab|r")
        local info=CreateGBSFontString(box,"OVERLAY"); info:SetPoint("TOPLEFT",box,"TOPLEFT",14,-34); info:SetWidth(310); info:SetJustifyH("LEFT"); box.info=info
        local note=CreateGBSFontString(box,"OVERLAY"); note:SetPoint("TOPLEFT",box,"TOPLEFT",14,-65); note:SetWidth(310); note:SetJustifyH("LEFT"); note:SetText("Funds may come from your character or the guild bank. After purchase, the bank closes; reopen it. Unsaved tab info is discarded.")
        local status=CreateGBSFontString(box,"OVERLAY"); status:SetPoint("TOPLEFT",box,"TOPLEFT",14,-140); status:SetWidth(310); status:SetJustifyH("LEFT"); status:SetTextColor(1,0.55,0.35); box.status=status
        local confirm=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); confirm:SetSize(95,22); confirm:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-112,10); confirm:SetText("Purchase"); StyleButton(confirm,true); box.confirm=confirm
        local cancel=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); cancel:SetSize(90,22); cancel:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-12,10); cancel:SetText("Cancel"); StyleButton(cancel,false); cancel:SetScript("OnClick",function() box:Hide() end)
        confirm:SetScript("OnClick",function()
            local count,cost=PurchaseInfo(); local why=CanBuyTab(count,cost)
            if why then box.status:SetText(why); return end
            if count~=box.expectedCount or cost~=box.expectedCost then
                box.status:SetText("Tab or price changed. Close and reopen this dialog."); return
            end
            GBS.Bank.purchasePending={count=count,elapsed=0}; confirm:Disable(); box.status:SetText("Waiting for the bank to update...")
            local ok=pcall(BuyGuildBankTab)
            if not ok then GBS.Bank.purchasePending=nil; GBS.Bank.purchaseUnconfirmed=true; box.status:SetText("Purchase not confirmed. Reopen the bank to check.") end
        end)
        local watcher=CreateFrame("Frame",nil,self.frame); self.purchaseWatcher=watcher; watcher:SetScript("OnUpdate",function(_,dt)
            local pending=GBS.Bank.purchasePending; if not pending then return end
            pending.elapsed=pending.elapsed+dt
            local count=PurchaseInfo()
            if pending.purchased or (count and count>pending.count) then
                if SafeGetCursorInfo() then
                    if not pending.purchased then Chat("Tab purchased. Place the cursor item to close and reopen the bank.",1,0.8,0.2) end
                    pending.purchased=true; box.status:SetText("Place the cursor item before the bank closes."); return
                end
                if type(CloseGuildBankFrame)~="function" then
                    GBS.Bank.purchasePending=nil; GBS.Bank.purchaseUnconfirmed=true; box.status:SetText("Please close and reopen the bank."); Chat("Tab purchased. Please close and reopen the bank.",1,0.8,0.2); return
                end
                local ok=pcall(CloseGuildBankFrame)
                if not ok then
                    GBS.Bank.purchasePending=nil; GBS.Bank.purchaseUnconfirmed=true; box.status:SetText("Please close and reopen the bank."); Chat("Tab purchased. Please close and reopen the bank.",1,0.8,0.2); return
                end
                GBS.Bank.purchasePending=nil; Chat("Tab purchased. Please reopen the guild bank.",0.8,1,0.8); GBS.Bank:Hide(); return
            end
            if pending.elapsed>=8 then
                GBS.Bank.purchasePending=nil; GBS.Bank.purchaseUnconfirmed=true
                box.status:SetText("Not confirmed. Reopen the bank to check before retrying.")
            end
        end)
        box:Hide(); self.purchaseDialog=box
    end
    local box=self.purchaseDialog; local count,cost=PurchaseInfo()
    box.expectedCount=count; box.expectedCost=cost; box.status:SetText("")
    if not count or tab~=count+1 then
        box.info:SetText("Tabs must be purchased in order. Select the next locked tab."); box.confirm:Disable()
    elseif not cost then box.info:SetText("Price unavailable."); box.confirm:Disable()
    else
        box.info:SetText("Purchase tab "..tab.." for "..FormatTabPrice(cost).."?")
        local why=CanBuyTab(count,cost)
        if why then box.status:SetText(why); box.confirm:Disable() else box.confirm:Enable() end
    end
    box:Show()
end

function GBS.Bank:LayoutTabConfig()
    local cf=self.tabConfig
    if not cf or not self.frame then return end
    local height=self.frame:GetHeight(); cf:SetHeight(height)
    local ef=GBS.AssignEditor.frame
    if ef and ef.embedded and ef:GetParent()==cf then
        local message=cf.status and cf.status:GetText()
        ef.embeddedHeight=math.max(80,height-65-((message and message~="") and 24 or 10))
        ef.RebuildAssignLayout()
    end
end
function GBS.Bank:OpenTabConfig(tab)
    if GBS.isRunning or not GBS.tabNames[tab] then return end
    if self.purchaseDialog then self.purchaseDialog:Hide() end
    if GBS.assignFrame then GBS.assignFrame:Hide() end
    if self.moneyBox then self.moneyBox:Hide() end
    if not self.tabConfig then
        local cf=CreateGBSFrameBase("GBSTabConfig",340,390,65)
        cf:SetParent(self.frame); cf:ClearAllPoints(); cf:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",8,0)
        cf:SetClampedToScreen(false); cf:SetMovable(false); cf:SetScript("OnDragStart",nil); cf:SetScript("OnDragStop",nil)
        local title=CreateGBSFontString(cf.titleBar,"OVERLAY"); title:SetPoint("LEFT",cf.titleBar,"LEFT",8,0); title:SetFont(GBS_FONT,GBS_FONT_SIZE,""); cf.title=title
        local nameLabel=CreateGBSFontString(cf,"OVERLAY"); nameLabel:SetPoint("TOPLEFT",cf,"TOPLEFT",10,-37); nameLabel:SetText("Name")
        local eb=CreateGBSInput(cf,95,22); eb:SetPoint("TOPLEFT",cf,"TOPLEFT",49,-32); eb:SetAutoFocus(false); eb:SetMaxLetters(16); eb:SetScript("OnEscapePressed",function() cf:Hide() end); cf.eb=eb
        local iconBtn=CreateFrame("Button",nil,cf); iconBtn:SetSize(26,26); iconBtn:SetPoint("TOPLEFT",cf,"TOPLEFT",150,-30); StyleBackdrop(iconBtn,1)
        local icon=iconBtn:CreateTexture(nil,"ARTWORK"); icon:SetPoint("TOPLEFT",iconBtn,"TOPLEFT",2,-2); icon:SetPoint("BOTTOMRIGHT",iconBtn,"BOTTOMRIGHT",-2,2); iconBtn.icon=icon; cf.iconBtn=iconBtn
        iconBtn:SetScript("OnClick",function() GBS.Bank:OpenIconPicker() end)
        iconBtn:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Choose icon",1,1,1); GameTooltip:Show() end)
        iconBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
        local status=CreateGBSFontString(cf,"OVERLAY"); status:SetPoint("BOTTOMLEFT",cf,"BOTTOMLEFT",12,12); status:SetWidth(316); status:SetJustifyH("LEFT"); status:SetTextColor(1,0.4,0.3); cf.status=status
        cf.SetStatus=function(text) status:SetText(text); GBS.Bank:LayoutTabConfig() end
        local save=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); save:SetSize(69,22); save:SetPoint("TOPLEFT",cf,"TOPLEFT",182,-32); save:SetText("Save"); StyleButton(save,true); cf.save=save
        local cancel=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); cancel:SetSize(69,22); cancel:SetPoint("TOPLEFT",cf,"TOPLEFT",257,-32); cancel:SetText("Cancel"); StyleButton(cancel,false); cancel:SetScript("OnClick",function() cf:Hide() end); cf.cancel=cancel
        cf:HookScript("OnHide",function() cf.pending=nil; if cf.picker then cf.picker:Hide() end; if GBS.assignFrame then GBS.assignFrame:Hide() end end)
        if UISpecialFrames then tinsert(UISpecialFrames,"GBSTabConfig") end
        cf:Hide(); self.tabConfig=cf
        local function CommitAssignments()
            local ef=GBS.AssignEditor.frame
            if ef and ef._tabIdx==cf.tab then local values,other,overflow=ef.GetSelection(); GBS.Assign:Set(cf.tab,values,other,overflow) end
            GBS:CheckOtherTab(); if GBS.Bank then GBS.Bank:Refresh() end
        end
        save:SetScript("OnClick",function()
            local name=Trim(cf.eb:GetText() or ""); local iconIndex=cf._iconIndex
            if name=="" then cf.SetStatus("Enter a tab name."); return end
            local currentName,currentIcon=GetTabInfo(cf.tab)
            if name==currentName and (not iconIndex or GuildIconName(currentIcon)==GuildIconName(GetMacroItemIconInfo(iconIndex))) then
                CommitAssignments(); cf:Hide(); Log("Tab assignments saved.",0.6,1,0.6); return
            end
            if not iconIndex then cf.SetStatus("Select an icon before saving."); return end
            if type(CanEditGuildBankTabInfo)=="function" and not CanEditGuildBankTabInfo() then cf.SetStatus("You do not have permission to edit tabs."); return end
            if type(SetGuildBankTabInfo)~="function" then cf.SetStatus("Tab editing is unavailable."); return end
            local ok,err=pcall(SetGuildBankTabInfo,cf.tab,name,iconIndex)
            if not ok then cf.SetStatus("Save failed; see chat."); Chat(tostring(err),1,0.4,0.4); return end
            cf.pending={name=name,tab=cf.tab,iconName=GuildIconName(GetMacroItemIconInfo(iconIndex)),elapsed=0,queried=false}
            cf.SetStatus("Checking tab name...")
        end)
        cf:SetScript("OnUpdate",function(self,elapsed)
            local pending=self.pending; if not pending then return end
            pending.elapsed=pending.elapsed+elapsed
            if pending.elapsed>=0.5 and not pending.queried then
                pending.queried=true
                if type(QueryGuildBankTab)=="function" then pcall(QueryGuildBankTab,pending.tab) end
            end
            if pending.elapsed>=1 then
                local observed,observedIcon=GetTabInfo(pending.tab)
                if observed==pending.name and pending.iconName and GuildIconName(observedIcon)==pending.iconName then
                    self.pending=nil; CommitAssignments(); self:Hide(); GBS.Bank:Refresh()
                    Chat("Tab details appear updated. Reopen the bank to confirm they persisted.",0.8,0.8,0.8)
                    return
                end
            end
            if pending.elapsed>=4 then
                self.pending=nil
                self.SetStatus("Change not confirmed; see chat."); Chat("Tab change not confirmed. The client or server may have rejected the name or icon.",1,0.6,0.2)
            end
        end)
    end
    local cf=self.tabConfig; cf.tab=tab; cf.pending=nil
    self:LayoutTabConfig()
    local name,icon=GetTabInfo(tab); cf.eb:SetText(name or "")
    cf.catalog,cf.catalogAvailable=GetGuildIconCatalog()
    cf._iconIndex=FindGuildIconIndex(icon,cf.catalog)
    cf.iconBtn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    cf.SetStatus("")
    cf.title:SetText("|cffffd100Configure Tab "..tab.."|r"); cf:Show(); GBS.OpenAssignEditor(tab,true); self:LayoutTabConfig(); cf.eb:SetFocus(); cf.eb:HighlightText()
end
function GBS.Bank:OpenIconPicker()
    local cf=self.tabConfig; if not cf then return end
    if cf.picker and cf.picker:IsVisible() then cf.picker:Hide(); return end
    if not cf.picker then
        local p=CreateGBSFrameBase("GBSIconPicker",360,298,85)
        p:SetPoint("CENTER",UIParent,"CENTER",160,0); p:Hide(); cf.picker=p
        local title=CreateGBSFontString(p.titleBar,"OVERLAY"); title:SetPoint("LEFT",p.titleBar,"LEFT",8,0); title:SetFont(GBS_FONT,GBS_FONT_SIZE,""); title:SetText("|cffffd100Choose an Icon|r")
        local search=CreateGBSInput(p,250,22); search:SetPoint("TOPLEFT",p,"TOPLEFT",18,-32); search:SetAutoFocus(false); search:SetScript("OnEscapePressed",function() p:Hide() end); p.search=search
        local count=CreateGBSFontString(p,"OVERLAY"); count:SetPoint("TOPLEFT",p,"TOPLEFT",16,-59); count:SetText(""); p.count=count
        local slider=CreateFrame("Slider",nil,p); slider:SetPoint("TOPRIGHT",p,"TOPRIGHT",-12,-82); slider:SetSize(14,174); slider:SetOrientation("VERTICAL"); slider:SetMinMaxValues(0,0); slider:SetValueStep(1)
        slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob"); slider:EnableMouse(true); p.slider=slider
        local track=CreateFrame("Frame",nil,p); track:SetPoint("TOPLEFT",slider,"TOPLEFT",0,0); track:SetPoint("BOTTOMRIGHT",slider,"BOTTOMRIGHT",0,0); track:SetFrameLevel(p:GetFrameLevel()); StyleInset(track)
        local grid=CreateFrame("Frame",nil,p); grid:SetPoint("TOPLEFT",p,"TOPLEFT",12,-79); grid:SetSize(320,180); grid:EnableMouseWheel(true); p.grid=grid; p.buttons={}
        local function Update()
            local row=math.floor((slider:GetValue() or 0)+0.5)
            for i,b in ipairs(p.buttons) do
                local entry=p.filtered[row*8+i]
                if entry then b.iconName=entry.name; b.iconIndex=entry.index; b.icon:SetTexture(entry.texture); b:Show() else b.iconName=nil; b.iconIndex=nil; b:Hide() end
            end
            if not p.catalogAvailable then count:SetText("Icon catalogue unavailable on this client.") else count:SetText(string.format("%d icons - scroll to browse",#p.filtered)) end
        end
        for i=1,40 do
            local b=CreateFrame("Button",nil,grid); b:SetSize(32,32); b:SetPoint("TOPLEFT",grid,"TOPLEFT",((i-1)%8)*39,-math.floor((i-1)/8)*36); StyleBackdrop(b,1)
            b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",2,-2); b.icon:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-2,2)
            b:SetScript("OnClick",function(self) if self.iconIndex then cf._iconIndex=self.iconIndex; cf.iconBtn.icon:SetTexture("Interface\\Icons\\"..self.iconName); cf.SetStatus(""); p:Hide() end end)
            b:SetScript("OnEnter",function(self) if self.iconName then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(self.iconName,1,1,1); GameTooltip:Show() end end)
            b:SetScript("OnLeave",function() GameTooltip:Hide() end); p.buttons[i]=b
        end
        p.Filter=function()
            local q=Lower(Trim(search:GetText() or "")); p.filtered={}
            for _,entry in ipairs(p.all or {}) do if q=="" or string.find(Lower(entry.name),q,1,true) then p.filtered[#p.filtered+1]=entry end end
            local maxRow=math.max(0,math.ceil(#p.filtered/8)-5); slider:SetMinMaxValues(0,maxRow); slider:SetValue(0); Update()
        end
        slider:SetScript("OnValueChanged",function() Update() end)
        grid:SetScript("OnMouseWheel",function(_,delta) local _,max=slider:GetMinMaxValues(); slider:SetValue(math.max(0,math.min(max,(slider:GetValue() or 0)-delta))) end)
        p:EnableMouseWheel(true); p:SetScript("OnMouseWheel",function(_,delta) local _,max=slider:GetMinMaxValues(); slider:SetValue(math.max(0,math.min(max,(slider:GetValue() or 0)-delta))) end)
        search:SetScript("OnTextChanged",function() p.Filter() end)
        local close=CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); close:SetSize(76,22); close:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-12,10); close:SetText("Close"); StyleButton(close,false); close:SetScript("OnClick",function() p:Hide() end)
    end
    local p=cf.picker; p.all=cf.catalog; p.catalogAvailable=cf.catalogAvailable; p.filtered={}; p.search:SetText(""); p.Filter(); p:Show(); p.search:SetFocus()
end

function GBS.Bank:HookBags()
    -- The unhidden Blizzard guild bank frame keeps native bag right-click deposit active.
    -- Do not post-hook container clicks: that risks depositing twice or using an item.
end
local function BankNativeTab()
    if type(GetCurrentGuildBankTab)~="function" then return nil end
    local ok,tab=pcall(GetCurrentGuildBankTab); if ok and type(tab)=="number" then return tab end
end
function GBS.Bank:EnsureManualTab()
    local actual=BankNativeTab(); local selected=self.currentTab
    if actual and selected and actual~=selected then
        SafeSelectGuildBankTab(selected); self:RefreshSlots()
        Chat("Bank tab refreshed. Please retry the item action.",1,0.8,0.3)
        return false
    end
    return true
end
function GBS.Bank:ScheduleSelectionRefresh(force)
    if not self.frame or not self:IsOpen() then return end
    if not self.selectionDriver then self.selectionDriver=CreateFrame("Frame",nil,self.frame) end
    self.selectionForce=self.selectionForce or force
    self.selectionDriver:SetScript("OnUpdate",function(driver)
        driver:SetScript("OnUpdate",nil)
        if not GBS.Bank:IsOpen() or GBS.isRunning then GBS.Bank.selectionForce=nil; return end
        local tab=GBS.Bank.currentTab; local native=BankNativeTab(); local forced=GBS.Bank.selectionForce; GBS.Bank.selectionForce=nil
        if GBS.tabNames[tab] and (forced or (native and native~=tab)) then
            SafeSelectGuildBankTab(tab); GBS.Bank.knownCounts[tab]=nil; GBS.Bank:Refresh()
        end
    end)
end
function GBS.Bank:RefreshAccessTitle()
    if not self.frame or not self.frame.accessTitle then return end
    local tab=self.currentTab; local name=GBS.tabNames[tab]
    if not name or type(GetGuildBankTabInfo)~="function" then self.frame.accessTitle:SetText(""); return end
    local ok,_,_,view,deposit,allowed,remaining=pcall(GetGuildBankTabInfo,tab)
    if not ok then self.frame.accessTitle:SetText(" - "..name.." - Unknown access"); return end
    local canView=view and view~=0; local canDeposit=deposit and deposit~=0
    local limit=type(remaining)=="number" and remaining or nil
    local unlimited=limit and (limit<0 or limit>=4294967295)
    local withdrawPermission=type(allowed)=="number" and (allowed~=0) or nil
    if type(allowed)=="number" and allowed==0 then withdrawPermission=false end
    if withdrawPermission==nil and limit~=nil then withdrawPermission=unlimited or limit>0 end
    local access
    if not canView then access="No access"
    elseif withdrawPermission==nil then access=canDeposit and "View / deposit" or "View"
    elseif canDeposit and withdrawPermission then access="Full Access"
    elseif canDeposit then access="Deposit only"
    elseif withdrawPermission then access="Withdraw only"
    else access="View only" end
    local count=not limit and "withdrawals unknown" or unlimited and "unlimited withdrawals" or tostring(limit).." withdrawals remaining"
    self.frame.accessTitle:SetText(" - "..name.." - "..access.." ("..count..")")
end
function GBS.Bank:SelectTab(tab,internal)
    if not internal and GBS.isRunning then return end
    if not GBS.tabNames[tab] then return end
    CloseOurSplit()
    self.currentTab=tab
    if self.frame.activity then self.frame.activity.info.UpdateSave() end
    for i,b in ipairs(self.tabButtons) do
        if i==tab then b:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1); b:SetBackdropBorderColor(E.accent[1]*0.7,E.accent[2]*0.7,E.accent[3]*0.7,1); if b.text then b.text:SetTextColor(1,1,1) end
        else b:SetBackdropColor(0.13,0.13,0.13,1); b:SetBackdropBorderColor(0.22,0.22,0.22,1); if b.text then local shade=GBS.tabNames[i] and 0.9 or 0.5; b.text:SetTextColor(shade,shade,shade) end end
    end
    SafeSelectGuildBankTab(tab); if GBS.bankPanel then UpdateBankPanelTabs() end; self:RefreshSlots(); self:RefreshAccessTitle()
    if not internal and self.frame.RefreshActivityForTab then self.frame.RefreshActivityForTab()
    elseif internal and self.frame.activity then
        local activity=self.frame.activity
        if not GBSCharDB.bankSections.itemLog then activity.items.render({"Item log will refresh after sorting."}) end
        if not GBSCharDB.bankSections.info then activity.info.edit:ClearFocus(); activity.info.edit:EnableMouse(false); activity.info.save:Disable(); activity.info.status:SetText("Info will refresh after sorting.") end
    end
end
function GBS.Bank:RefreshTabs()
    for i=1,NUM_TABS do
        local b=self.tabButtons[i]; local name=GBS.tabNames[i]
        if b then
            if name and name~="" then b:Show(); b.text:SetText(SingleLineText(name,math.floor((GRID_W-8)/3)-78)); local used=self.knownCounts and self.knownCounts[i]; b.count:SetText("("..(used and tostring(used) or "?").."/98)"); if GetGuildBankTabInfo then local ok,_,icon=pcall(GetGuildBankTabInfo,i); if ok and icon then b.icon:SetTexture(icon) else b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end end
            else
                b:Show(); b.text:SetText("Locked "..i); b.count:SetText("")
                b.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); b.icon:SetVertexColor(0.45,0.45,0.45,1)
                b.text:SetTextColor(0.5,0.5,0.5)
            end
            if name then b.icon:SetVertexColor(1,1,1,1); b.text:SetTextColor(0.9,0.9,0.9) end
        end
    end
    if not GBS.tabNames[self.currentTab] then for i=1,NUM_TABS do if GBS.tabNames[i] then self.currentTab=i; break end end end
    for i,b in ipairs(self.tabButtons) do
        if GBS.tabNames[i] and i==self.currentTab then b:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1)
        else b:SetBackdropColor(0.13,0.13,0.13,1) end
    end
end
function GBS.FormatBankBalance(copper)
    copper=math.max(0,math.floor(tonumber(copper) or 0))
    local gold=math.floor(copper/10000); local silver=math.floor(copper/100)%100; local rest=copper%100
    if gold>=10000 then return gold.."g" end
    if gold>0 then return gold.."g"..(silver>0 and (" "..silver.."s") or "") end
    if silver>0 then return silver.."s"..(rest>0 and (" "..rest.."c") or "") end
    return rest.."c"
end
function GBS.Bank:RefreshSlots()
    local tab=self.currentTab; local qualityPending=false
    for i=1,98 do
        local btn=self.slotButtons[i]; if not btn then break end
        local tex,count,locked=nil,0,false
        if GBS.tabNames[tab] and GetGuildBankItemInfo then local ok,a,b,c=pcall(GetGuildBankItemInfo, tab, i); if ok then tex=a; count=b; locked=c end end
        local link=nil; if GBS.tabNames[tab] and GetGuildBankItemLink then pcall(function() link=GetGuildBankItemLink(tab,i) end) end
        if locked then btn:SetAlpha(0.5) else btn:SetAlpha(1) end
        if tex or link then btn.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark"); btn.icon:Show(); if count and count>1 then btn.count:SetText(count) else btn.count:SetText("") end; btn:Show()
            local rarity=nil
            if link and type(GetItemInfo)=="function" then
                local ok,_,_,q=pcall(GetItemInfo,link); if ok and type(q)=="number" then rarity=q end
                if rarity==nil then
                    local id=ParseItemIDFromLink(link)
                    if id then local ok2,_,_,q2=pcall(GetItemInfo,id); if ok2 and type(q2)=="number" then rarity=q2 end end
                    if rarity==nil then qualityPending=true end
                end
            elseif tex and not link then qualityPending=true end
            if rarity==nil and link then
                local col=link:match("|c(%x%x%x%x%x%x%x%x)")
                local hex=col and string.lower(col:sub(3))
                if hex=="9d9d9d" or hex=="666666" then rarity=0 elseif hex=="ffffff" then rarity=1 elseif hex=="1eff00" then rarity=2 elseif hex=="0070dd" then rarity=3 elseif hex=="a335ee" then rarity=4 elseif hex=="ff8000" then rarity=5 elseif hex=="e6cc80" then rarity=6 end
            end
            local rgb=QUALITY_COLORS[rarity]
            if rgb then
                local r,g,b=rgb[1],rgb[2],rgb[3]
                if type(GetItemQualityColor)=="function" then
                    local ok,qr,qg,qb=pcall(GetItemQualityColor,rarity)
                    if ok and type(qr)=="number" and type(qg)=="number" and type(qb)=="number" then r,g,b=qr,qg,qb end
                end
                SetItemBorder(btn,r,g,b,1)
            else SetItemBorder(btn,0.25,0.25,0.25,1) end
        else btn.icon:Hide(); btn.count:SetText(""); btn:Show(); SetItemBorder(btn,0.15,0.15,0.15,0.8) end
    end
    self.qualityPending=qualityPending
    if self.ScheduleBorderSnap then self:ScheduleBorderSnap() end
    if qualityPending and self:IsOpen() then ScheduleQualityRetry() end
    if self.frame and self.frame.money then
        local ok,money=pcall(GetGuildBankMoney); if not ok then money=0 end
        local compact=GBS.FormatBankBalance(money or 0)
        local colored=compact:gsub("(%d+)([gsc])",function(value,unit)
            local color=(unit=="g" and "ffffd100") or (unit=="s" and "ffc7c7c7") or "ffcd7f32"
            return "|cffffffff"..value.."|r|c"..color..unit.."|r"
        end)
        self.frame.money:SetText(colored)
    end
end
function GBS.Bank:Refresh() GBS:CheckOtherTab(); self:RefreshTabs(); self:RefreshSlots(); self:RefreshAccessTitle(); if GBS.bankPanel then UpdateBankPanelTabs() end end
function GBS.Bank:Show() self:Create(); self.frame:Show(); self:Refresh(); if GBS.bankPanel and not GBSCharDB.panelPos then GBS.bankPanel:ClearAllPoints(); GBS.bankPanel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 6, 0) end end
function GBS.Bank:Hide() StopQualityRetry(); if self.frame then self.frame:Hide() end end



-- Slash / Events
-- ============================================================
SLASH_GBS1="/gbsort"; SLASH_GBS2="/gbs"; SLASH_GBS3="/guildbanksort"; SLASH_GBS4="/gbe"; SLASH_GBS5="/guildbankenhanced"
SlashCmdList["GBS"] = function(msg)
    msg=Trim(Lower(msg or ""))
    if msg=="sort" then GBS:StartSort()
    elseif msg=="stop" then if GBS.isRunning then GBS:Cancel() else Chat("Nothing is running.",0.8,0.8,0.8) end
    elseif msg=="" or msg=="panel" or msg=="bankpanel" then ToggleBankPanel()
    else Chat("Commands: /gbs sort, /gbs stop.",0.8,0.9,1) end
end
local function TryCreateBankPanel() if GuildBankFrame and not GBS.bankPanel then CreateBankPanel(); return true elseif GuildBankFrame and GBS.bankPanel then return true end; return false end
GBS.CreateBankPanel=CreateBankPanel; GBS.UpdateBankPanelTabs=UpdateBankPanelTabs; GBS.TryCreateBankPanel=TryCreateBankPanel
GBS.KeywordMatches=KeywordMatches; GBS.KeywordMatchScore=KeywordMatchScore

local hiddenGuildFrameState
local function DisableGuildFrameMouse(frame,state)
    if not frame then return end
    if frame.IsMouseEnabled and frame:IsMouseEnabled() then
        if not state.mouseSeen[frame] then
            state.mouse[#state.mouse+1]=frame; state.mouseSeen[frame]=true
        end
        frame:EnableMouse(false)
    end
    if frame.GetChildren then
        local children={frame:GetChildren()}
        for _,child in ipairs(children) do DisableGuildFrameMouse(child,state) end
    end
end
local function ParkBlizzardGuildFrame()
    local f=GuildBankFrame
    if not f then return end
    if not hiddenGuildFrameState then
        local state={points={},mouse={},mouseSeen={},alpha=f:GetAlpha()}
        if f.IsClampedToScreen then state.clamped=f:IsClampedToScreen() end
        for i=1,f:GetNumPoints() do state.points[i]={f:GetPoint(i)} end
        hiddenGuildFrameState=state
    end
    -- Revisit the tree on the delayed pass too, for children created during opening.
    DisableGuildFrameMouse(f,hiddenGuildFrameState)
    f:SetClampedToScreen(false); f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",-10000,-10000); f:SetAlpha(0)
end
local function RestoreBlizzardGuildFrame()
    local f,state=GuildBankFrame,hiddenGuildFrameState
    if not f or not state then return end
    f:ClearAllPoints()
    for _,point in ipairs(state.points) do f:SetPoint(unpack(point)) end
    if state.clamped~=nil then f:SetClampedToScreen(state.clamped) end
    f:SetAlpha(state.alpha or 1)
    for _,obj in ipairs(state.mouse) do obj:EnableMouse(true) end
    hiddenGuildFrameState=nil
end

local eventFrame=CreateFrame("Frame"); eventFrame:RegisterEvent("PLAYER_LOGIN"); eventFrame:RegisterEvent("ADDON_LOADED"); eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED"); eventFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
eventFrame:SetScript("OnEvent", function(self,event,addonName)
    if event=="PLAYER_LOGIN" then
        if not fontAvailable then Chat("PT Sans Narrow could not be loaded; using the game font. Check the addon Fonts folder and restart the game.",1,0.75,0.25) end

    elseif event=="ADDON_LOADED" then

    elseif event=="GUILDBANKFRAME_OPENED" then
        -- Hiding the Blizzard frame calls CloseGuildBankFrame and kills bank interaction.
        -- Keep it shown for native bag handling, but visually transparent behind our frame.
        ParkBlizzardGuildFrame()
        if GBS.Bank then GBS.Bank.knownCounts={}; GBS.Bank.purchaseUnconfirmed=nil; GBS.Bank.purchasePending=nil end
        local parkDelay=CreateFrame("Frame"); local elapsedPark=0
        parkDelay:SetScript("OnUpdate",function(self,elapsed)
            elapsedPark=elapsedPark+elapsed
            if elapsedPark>=0.1 then self:SetScript("OnUpdate",nil); if hiddenGuildFrameState then ParkBlizzardGuildFrame() end end
        end)
        if GBS.Bank then GBS.Bank:Create(); GBS.Bank:Show() end

        GBS:CheckOtherTab(); if GBS.Bank then GBS.Bank:Refresh(); GBS.Bank:SelectTab(GBS.Bank.currentTab) end
    elseif event=="GUILDBANKFRAME_CLOSED" then
        GBS.scanData=nil
        if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange then GBS:Cancel() end
        RestoreBlizzardGuildFrame()
        if GBS.Bank and GBS.Bank.purchaseDialog then GBS.Bank.purchaseDialog:Hide() end
        if GBS.Bank then GBS.Bank:Hide(); if GBS.Bank.moneyBox then GBS.Bank.moneyBox:Hide() end; if GBS.Bank.tabConfig then GBS.Bank.tabConfig:Hide() end end
        if GBS.assignFrame then GBS.assignFrame:Hide() end
        if GBS.bankPanel then GBS.bankPanel:Hide() end
    end
end)
