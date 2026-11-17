-- Guild Bank Enhanced 1.1.0: modules bundled in TOC order
do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
-- The category and subtype order is the frozen v1 Info codebook.
local categories = {
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
modules.Categories=categories

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local InfoDisplay={}
local categories=modules.Categories

local function directionLabel(id,directions)
    local label=id
    for _,entry in ipairs(directions) do if entry.id==id then label=entry.label end end
    return label
end

local function assignments(lines,parsed)
    local selected={}; for _,key in ipairs(parsed.keywords or {}) do selected[key]=true end
    local found=false
    for _,category in ipairs(categories) do
        local items={}; local parent=string.lower(category.name)
        if selected["type:"..parent] then items[#items+1]="All" end
        for _,subtype in ipairs(category.subs) do
            if selected["sub:"..parent..":"..string.lower(subtype)] then items[#items+1]=subtype end
        end
        if #items>0 then lines[#lines+1]=category.name..": "..table.concat(items,", "); found=true end
    end
    if parsed.other then lines[#lines+1]="Fallback: Yes"; found=true end
    if parsed.overflow then lines[#lines+1]="Overflow: Yes"; found=true end
    if not found then lines[#lines+1]="Assignments: None" end
end

local function savedLine(parsed)
    if not parsed.savedBy or not parsed.savedAt then return "Last saved: Unknown" end
    local when=tostring(parsed.savedAt)
    if type(date)=="function" then
        local ok,value=pcall(date,"%Y-%m-%d %H:%M",parsed.savedAt)
        if ok and type(value)=="string" then when=value end
    end
    return "Last saved: "..parsed.savedBy.." - "..when
end

InfoDisplay.SavedLine=savedLine

function InfoDisplay.Settings(parsed,directions)
    local lines={"GuildBankEnhanced:"}
    if not parsed then lines[#lines+1]="Loading..."; return lines end
    lines[#lines+1]="SortDirection: "..directionLabel(parsed.direction,directions)
    assignments(lines,parsed)
    lines[#lines+1]=savedLine(parsed)
    return lines
end

function InfoDisplay.Lock(shared)
    if not shared or not shared.loaded[1] or (shared.corrupt and shared.corrupt[1]) then return "Lock: Unknown" end
    local lock=shared.tabs[1] and shared.tabs[1].lock
    if not lock then return "Lock: None" end
    local mine=shared.mine and lock.owner==shared.mine.owner and lock.token==shared.mine.token
    return "Locked by "..(mine and "You" or lock.owner)
end

modules.InfoDisplay=InfoDisplay

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local InfoDraft={}

local function clearConflict(draft)
    draft.conflict=nil; draft.latestRaw=nil; draft.latestDescription=nil
end

function InfoDraft.Update(draft,raw,description)
    if draft.reloadAwaiting~=nil and draft.reloadAwaiting==(draft.revision or 0) then
        draft.base=raw; draft.baseDescription=description; draft.text=description; draft.dirty=false
        draft.sent=nil; draft.reloadAwaiting=nil; clearConflict(draft)
    elseif draft.sent and description==draft.sent then
        draft.base=raw; draft.baseDescription=description; draft.sent=nil; draft.dirty=draft.text~=description
        clearConflict(draft)
    elseif not draft.dirty then
        draft.base=raw; draft.baseDescription=description; draft.text=description
        clearConflict(draft)
    elseif draft.baseDescription~=description then
        draft.conflict=true; draft.latestRaw=raw; draft.latestDescription=description
    else
        draft.base=raw; clearConflict(draft)
    end
    draft.loaded=true
end
function InfoDraft.Status(draft,received)
    if draft and draft.conflict then return "Info changed remotely; reload or review your draft." end
    if draft and ((received and draft.reloadAwaiting~=nil) or (not received and draft.reloadAwaiting)) then return "Refreshing tab info..." end
    if draft and draft.saveError then return draft.saveError end
    if received and draft and draft.sent then return "Saving tab info..." end
    if draft and draft.dirty then return "Unsaved changes" end
    if not received and (not draft or not draft.loaded) then return "Loading tab info..." end
    return ""
end

modules.InfoDraft=InfoDraft

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local ItemQuality={}
local byHex={
    ["9d9d9d"]=0,["666666"]=0,["ffffff"]=1,["1eff00"]=2,
    ["0070dd"]=3,["a335ee"]=4,["ff8000"]=5,["e6cc80"]=6,
}
local colors={
    [0]={0.62,0.62,0.62}, [1]={1,1,1}, [2]={0.12,1,0}, [3]={0,0.44,0.87},
    [4]={0.64,0.21,0.93}, [5]={1,0.5,0}, [6]={0.9,0.8,0.5}, [7]={0,0.8,1},
}

function ItemQuality.Resolve(texture,link,parseID,itemInfo)
    local rarity,pending=nil,false
    if link and type(itemInfo)=="function" then
        local ok,_,_,quality=pcall(itemInfo,link)
        if ok and type(quality)=="number" then rarity=quality end
        if rarity==nil then
            local id=parseID(link)
            if id then
                local valid,_,_,fallback=pcall(itemInfo,id)
                if valid and type(fallback)=="number" then rarity=fallback end
            end
            if rarity==nil then pending=true end
        end
    elseif texture and not link then pending=true end
    if rarity==nil and link then
        local color=link:match("|c(%x%x%x%x%x%x%x%x)")
        rarity=color and byHex[string.lower(color:sub(3))] or nil
    end
    return rarity,pending
end

function ItemQuality.Color(rarity,api)
    local rgb=colors[rarity]
    if not rgb then return nil end
    local r,g,b=rgb[1],rgb[2],rgb[3]
    if type(api)=="function" then
        local ok,red,green,blue=pcall(api,rarity)
        if ok and type(red)=="number" and type(green)=="number" and type(blue)=="number" then r,g,b=red,green,blue end
    end
    return r,g,b
end

modules.ItemQuality=ItemQuality

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local Access={}

local function enabled(value)
    return value and value~=0
end

local function withdrawalPermission(allowed,limit)
    if type(allowed)=="number" then return allowed~=0 end
    if limit==nil then return nil end
    return limit<0 or limit>=4294967295 or limit>0
end

local function accessLabel(view,deposit,withdraw)
    if not view then return "No access" end
    if withdraw==nil then return deposit and "View / deposit" or "View" end
    if deposit and withdraw then return "Full Access" end
    if deposit then return "Deposit only" end
    if withdraw then return "Withdraw only" end
    return "View only"
end

function Access.Title(view,deposit,allowed,remaining,selected)
    local v,d=enabled(view),enabled(deposit)
    local limit=type(remaining)=="number" and remaining or nil
    local unlimited=limit and (limit<0 or limit>=4294967295)
    local withdraw=withdrawalPermission(allowed,limit)
    local text=accessLabel(v,d,withdraw)
    if v and withdraw and limit and limit==limit and limit>0 and not unlimited and selected then
        return text.." ("..tostring(limit).." withdrawals)"
    end
    return text
end

local function accessItems(view,deposit,editInfo,withdraw)
    local items={}
    if view and deposit then items[#items+1]="Deposit" end
    if editInfo then items[#items+1]="EditInfo" end
    if withdraw then items[#items+1]="Withdraw" end
    return "Access: "..(#items>0 and table.concat(items,", ") or "None")
end

local function actionItems(sort,routeIn,routeOut,ready,editInfo)
    local items={}
    if sort then items[#items+1]="Sort" end
    if routeIn and routeOut then items[#items+1]="Route*"
    elseif routeIn then items[#items+1]="Route In"
    elseif routeOut then items[#items+1]="Route Out*" end
    if ready and editInfo then items[#items+1]="AssignConfig" end
    return "GBE Actions: "..(#items>0 and table.concat(items,", ") or "None")
end

function Access.Info(view,deposit,editInfo,remaining,selected,ready,routingAllowed)
    local v,d=enabled(view),enabled(deposit)
    local valid=selected and type(remaining)=="number" and remaining==remaining
    local withdraw=v and valid and (remaining<0 or remaining>0)
    local out=ready and v and valid and (remaining<0 or remaining>=1000)
    local into=ready and v and d
    local routeIn,routeOut=into and routingAllowed~=false,out and routingAllowed~=false
    return accessItems(v,d,editInfo,withdraw),actionItems(into,routeIn,routeOut,ready,editInfo),routeOut
end

modules.BankAccess=Access

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local Money={}

local function split(value)
    local copper=math.max(0,math.floor(tonumber(value) or 0))
    return math.floor(copper/10000),math.floor(copper/100)%100,copper%100
end

function Money.Full(value)
    local gold,silver,copper=split(value)
    return gold.."g "..silver.."s "..copper.."c"
end

function Money.Price(value)
    local gold,silver,copper=split(value)
    local parts={}
    if gold>0 then parts[#parts+1]=gold.."g" end
    if silver>0 then parts[#parts+1]=silver.."s" end
    if copper>0 or #parts==0 then parts[#parts+1]=copper.."c" end
    return table.concat(parts," ")
end

function Money.Compact(value)
    local gold,silver,copper=split(value)
    if gold>=10000 then return gold.."g" end
    if gold>0 then return gold.."g"..(silver>0 and (" "..silver.."s") or "") end
    if silver>0 then return silver.."s"..(copper>0 and (" "..copper.."c") or "") end
    return copper.."c"
end

local colors={g="ffffd100",s="ffc7c7c7",c="ffcd7f32"}
function Money.Color(text)
    return (text:gsub("(%d+)([gsc])",function(value,unit)
        return "|cffffffff"..value.."|r|c"..colors[unit]..unit.."|r"
    end))
end

modules.Money=Money

end

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
function Planner:FirstIncorrect(tab,slots,sorted)
    for pos=1,98 do
        local physical=self.api.physicalSlot(pos,tab)
        if not self.api.same(slots[physical],sorted[pos]) then return pos,sorted[pos] end
    end
end
function Planner:FindSource(tab,slots,sorted,first,want)
    for pos=first+1,98 do
        local physical=self.api.physicalSlot(pos,tab)
        if self.api.same(slots[physical],want) and not self.api.same(slots[physical],sorted[pos]) then return physical end
    end
end
function Planner:NextDestination(tab,held,shadow,sorted)
    local emptyChoice
    for pos=1,98 do
        local physical=self.api.physicalSlot(pos,tab); local before=shadow[physical]
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
        local dst=self:NextDestination(tab,held,shadow,sorted)
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
    local first,want=self:FirstIncorrect(tab,slots,sorted)
    if not first then return nil,nil end
    if not want then return nil,"Ordering plan has an unexpected empty destination." end
    local src=self:FindSource(tab,slots,sorted,first,want)
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
        local move=batch.moves[i]
        if not self.api.canRoute or self.api.canRoute(move,move.toTab,batch) then
            local free,locked=self.api.tabSpace(move.toTab)
            local merge=not free and self.api.findMerge(batch,move,move.toTab) or nil
            if free or merge then return {index=i,target=move.toTab,merge=merge} end
            anyLocked=anyLocked or locked
        end
    end
    if anyLocked then return nil,"Target has locked empty slots; inspect tabs and retry." end
end
local function eligible(move,tab,secondary,overflow)
    if tab==move.fromTab or tab==move.toTab then return false end
    if secondary and overflow==move.fromTab then return false end
    return true
end
function Selector:Alternative(batch,candidate,overflow)
    local tab=candidate.tab
    for i=batch.index,#batch.moves do
        local move=batch.moves[i]
        if eligible(move,tab,candidate.secondary,overflow) and (not self.api.canRoute or self.api.canRoute(move,tab,batch)) then
            local free,locked=self.api.tabSpace(tab)
            if locked and not free then return nil,"Overflow/fallback has locked empty slots; inspect tabs and retry." end
            local merge=not free and self.api.findMerge(batch,move,tab) or nil
            if free or merge then return {index=i,target=tab,merge=merge,overflow=true,secondary=candidate.secondary} end
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

do
-- Compact, versioned guild-bank tab metadata. The v1 index order is fixed.
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local SharedInfo={}
local categories=modules.Categories
local directions={"col","row","row_up","row_rev","row_rev_up","col_left","col_up","col_up_left","snake"}
local keyToCode,codeToKey={},{}
for i,cat in ipairs(categories) do
    local parent=string.lower(cat.name); local code=string.format("%x%02x",i,0)
    local key="type:"..parent; keyToCode[key]=code; codeToKey[code]=key
    for j,sub in ipairs(cat.subs) do
        code=string.format("%x%02x",i,j); key="sub:"..parent..":"..string.lower(sub)
        keyToCode[key]=code; codeToKey[code]=key
    end
end
local function parseVersion(version)
    if type(version)~="string" or #version>64 then return nil end
    local major,minor,patch,suffix=version:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major then return nil end
    local parts={}
    if suffix~="" then
        if suffix:sub(1,1)~="-" then return nil end
        suffix=suffix:sub(2); if suffix=="" or suffix:find("[^%w%.%-]") or suffix:sub(1,1)=="." or suffix:sub(-1)=="." or suffix:find("..",1,true) then return nil end
        for piece in suffix:gmatch("[^.]+") do parts[#parts+1]=piece end
    end
    return {major,minor,patch,pre=parts}
end
local function compareNumber(a,b)
    a=a:gsub("^0+",""); b=b:gsub("^0+","")
    if #a~=#b then return #a<#b and -1 or 1 end
    if a==b then return 0 end
    return a<b and -1 or 1
end
function SharedInfo.CompareVersions(a,b)
    local x,y=parseVersion(a),parseVersion(b); if not x or not y then return nil end
    for i=1,3 do local n=compareNumber(x[i],y[i]); if n~=0 then return n end end
    if #x.pre==0 or #y.pre==0 then
        if #x.pre==#y.pre then return 0 end
        return #x.pre==0 and 1 or -1
    end
    for i=1,math.max(#x.pre,#y.pre) do
        local p,q=x.pre[i],y.pre[i]
        if not p then return -1 elseif not q then return 1 end
        local pn,qn=p:match("^%d+$"),q:match("^%d+$")
        if pn and qn then local n=compareNumber(p,q); if n~=0 then return n end
        elseif pn then return -1 elseif qn then return 1
        elseif p~=q then return p<q and -1 or 1 end
    end
    return 0
end
function SharedInfo.ExtractVersion(text)
    if type(text)~="string" then return nil end
    local first=text:find("[GBE:",1,true)
    if not first or text:find("[GBE:",first+1,true) then return nil end
    local value=text:sub(first):match(":V([%w%.%-]+)%]$")
    if value and parseVersion(value) then return value end
end
local function validOwner(name)
    return type(name)=="string" and #name>0 and #name<=40 and not name:find("[,%[%]:|%c]")
end
local function validSettings(settings)
    if type(settings)~="table" or type(settings.keywords)~="table" then return nil,"Invalid assignments." end
    local dir
    for i,value in ipairs(directions) do if value==settings.direction then dir=i end end
    if not dir then return nil,"Invalid sort direction." end
    local codes,seen={},{}
    for _,key in ipairs(settings.keywords) do
        local code=keyToCode[key]
        if not code or seen[code] then return nil,"Unknown or duplicate assignment." end
        seen[code]=true; codes[#codes+1]=code
    end
    if settings.other and #codes>0 then return nil,"Fallback cannot have category assignments." end
    table.sort(codes)
    return tostring(dir),tostring((settings.other and 1 or 0)+(settings.overflow and 2 or 0)),table.concat(codes)
end
function SharedInfo.Compose(description,settings)
    if type(description)~="string" then return nil,"Invalid tab description." end
    if description:find("[GBE:",1,true) then return nil,"Description contains a reserved addon marker." end
    local dir,role,codes=validSettings(settings)
    if not dir then return nil,role end
    local lock=""
    if settings.lock~=nil then
        local l=settings.lock
        if type(l)~="table" or not validOwner(l.owner) or type(l.token)~="string" or not l.token:match("^[%w]+$") or #l.token>32 or type(l.timestamp)~="number" or l.timestamp<0 or l.timestamp%1~=0 then return nil,"Invalid bank lock." end
        lock=":"..l.owner..","..string.format("%.0f",l.timestamp)..","..l.token
    end
    local saved=""
    if settings.savedBy~=nil or settings.savedAt~=nil then
        if not validOwner(settings.savedBy) or type(settings.savedAt)~="number" or settings.savedAt<0 or settings.savedAt%1~=0 then return nil,"Invalid settings author or timestamp." end
        saved=":S"..settings.savedBy..","..string.format("%.0f",settings.savedAt)
    end
    local version=""
    if settings.addonVersion~=nil then
        if not parseVersion(settings.addonVersion) then return nil,"Invalid addon version." end
        version=":V"..settings.addonVersion
    end
    local block="[GBE:"..(version~="" and "2" or "1")..":"..dir..role..":"..codes..lock..saved..version.."]"
    local result=description=="" and block or description.."\n"..block
    if #result>500 then return nil,"Tab info exceeds 500 bytes; shorten the description or assignments." end
    return result
end
function SharedInfo.Parse(text)
    if type(text)~="string" then return nil,"Tab info is unavailable." end
    local first=text:find("[GBE:",1,true)
    if not first then return {description=text,keywords={},direction="col",other=false,overflow=false,managed=false} end
    if text:find("[GBE:",first+1,true) then return nil,"Multiple addon markers in tab info." end
    local description
    if first==1 then description=""
    elseif text:sub(first-1,first-1)=="\n" then description=text:sub(1,first-2)
    else return nil,"Invalid addon marker position." end
    local block=text:sub(first)
    local addonVersion=SharedInfo.ExtractVersion(text)
    if addonVersion then block=block:sub(1,#block-#addonVersion-3).."]" end
    local savedBy,savedStamp=block:match(":S([^,]+),(%d+)%]$")
    if savedBy then
        if not validOwner(savedBy) or not tonumber(savedStamp) then return nil,"Invalid settings author or timestamp." end
        block=block:sub(1,#block-#savedBy-#savedStamp-4).."]"
    end
    local version,dir,role,codes,owner,stamp,token=block:match("^%[GBE:(%d+):(%d)(%d):([%da-f]*):([^,]+),(%d+),([%w]+)%]$")
    if not version then version,dir,role,codes=block:match("^%[GBE:(%d+):(%d)(%d):([%da-f]*)%]$") end
    if (version~="1" and version~="2") or (version=="2" and not addonVersion) or (version=="1" and addonVersion) or not directions[tonumber(dir)] or not role or tonumber(role)>3 or #codes%3~=0 then return nil,"Invalid or unsupported addon data." end
    local keywords,seen={},{}
    for i=1,#codes,3 do
        local code=codes:sub(i,i+2); local key=codeToKey[code]
        if not key or seen[code] then return nil,"Unknown or duplicate addon assignment." end
        seen[code]=true; keywords[#keywords+1]=key
    end
    local flags=tonumber(role); local other=flags%2==1
    if other and #keywords>0 then return nil,"Fallback cannot have category assignments." end
    local lock
    if owner then
        if not validOwner(owner) or #token>32 or not tonumber(stamp) then return nil,"Invalid bank lock." end
        lock={owner=owner,timestamp=tonumber(stamp),token=token}
    end
    return {description=description,keywords=keywords,direction=directions[tonumber(dir)],other=other,overflow=flags>=2,managed=true,lock=lock,savedBy=savedBy,savedAt=savedStamp and tonumber(savedStamp) or nil,addonVersion=addonVersion}
end
-- Retain ordinary description text; the original raw text is backed up before repair.
function SharedInfo.Recover(text)
    if type(text)~="string" then return nil end
    local first=text:find("[GBE:",1,true); if not first then return nil end
    local unsupported=false
    for version in text:gmatch("%[GBE:(%d+):") do if version~="1" then unsupported=true end end
    local description=text:sub(1,first-1)
    local position=first
    while position do
        local close=text:find("]",position+5,true)
        if not close then break end
        local nextMarker=text:find("[GBE:",close+1,true)
        description=description..text:sub(close+1,nextMarker and nextMarker-1 or #text)
        position=nextMarker
    end
    description=description:gsub("\n$","")
    return {description=description,keywords={},direction="col",other=false,overflow=false,managed=false,corrupt=true,unsupported=unsupported}
end
modules.SharedInfo=SharedInfo

end

do
-- Snapshot comparison and advisory lock decisions; no bank writes occur here.
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules
local SharedState={}
local function copySettings(value)
    if type(value)~="table" or type(value.keywords)~="table" or type(value.direction)~="string" then return nil end
    local out={direction=value.direction,other=not not value.other,overflow=not not value.overflow,keywords={}}
    local seen={}
    for _,key in ipairs(value.keywords) do
        if type(key)~="string" or seen[key] then return nil end
        seen[key]=true; out.keywords[#out.keywords+1]=key
    end
    table.sort(out.keywords)
    return out
end
function SharedState.Snapshot(realm,guild,tabs)
    if type(realm)~="string" or realm=="" or type(guild)~="string" or guild=="" or type(tabs)~="table" then return nil,"Guild or realm unavailable." end
    local result={realm=realm,guild=guild,tabs={}}
    for tab,value in pairs(tabs) do
        if type(tab)~="number" or tab<1 or tab>6 or tab%1~=0 then return nil,"Invalid tab number." end
        result.tabs[tab]=copySettings(value)
        if not result.tabs[tab] then return nil,"Invalid tab settings." end
    end
    return result
end
local function keywordChanges(lines,old,new)
    local oldKeys,newKeys={},{}
    for _,key in ipairs(old) do oldKeys[key]=true end
    for _,key in ipairs(new) do newKeys[key]=true end
    for _,key in ipairs(old) do if not newKeys[key] then lines[#lines+1]="Removed: "..key end end
    for _,key in ipairs(new) do if not oldKeys[key] then lines[#lines+1]="Added: "..key end end
end
local function tabChanges(old,new)
    local lines={}
    if not old and new then lines[#lines+1]="Tab added"; return lines end
    if old and not new then lines[#lines+1]="Tab removed or unavailable"; return lines end
    if not old or not new then return lines end
    if old.direction~=new.direction then lines[#lines+1]="Direction: "..old.direction.." -> "..new.direction end
    if old.other~=new.other then lines[#lines+1]="Fallback: "..(old.other and "on" or "off").." -> "..(new.other and "on" or "off") end
    if old.overflow~=new.overflow then lines[#lines+1]="Overflow: "..(old.overflow and "on" or "off").." -> "..(new.overflow and "on" or "off") end
    keywordChanges(lines,old.keywords,new.keywords)
    return lines
end
function SharedState.Diff(snapshot,realm,guild,current)
    if not snapshot then return nil,"No previous snapshot." end
    if snapshot.realm~=realm or snapshot.guild~=guild then return nil,"Snapshot belongs to another guild or realm." end
    local now,err=SharedState.Snapshot(realm,guild,current)
    if not now then return nil,err end
    local old,oldErr=SharedState.Snapshot(snapshot.realm,snapshot.guild,snapshot.tabs)
    if not old then return nil,oldErr end
    local changes={}
    for tab=1,6 do
        local lines=tabChanges(old.tabs[tab],now.tabs[tab])
        if #lines>0 then changes[tab]=lines end
    end
    return changes
end
-- Caller must requery tab 1 before a write and verify the returned value afterward.
-- These checks cannot make the server's whole-text update atomic.
function SharedState.LockDecision(lock,actor,ownerStatus,isLeader,force)
    if type(actor)~="string" or actor=="" then return "blocked","Character identity unavailable." end
    if lock==nil then return "claim" end
    if type(lock)~="table" or type(lock.owner)~="string" or lock.owner=="" or type(lock.token)~="string" or lock.token=="" or type(lock.timestamp)~="number" then return "blocked","Invalid lock data." end
    if force then
        if not isLeader then return "blocked","Only the guild master can force unlock." end
        return "force"
    end
    if lock.owner==actor then return "blocked","This character already has a lock; verify the previous session or ask the guild master." end
    if ownerStatus=="offline" then return "reclaim" end
    if ownerStatus=="online" then return "blocked","Bank is locked by "..lock.owner.."." end
    return "blocked","Lock owner status is unknown."
end
modules.SharedState=SharedState

end

do
local modules=_G.GuildBankSorterModules or {}; _G.GuildBankSorterModules=modules

function modules.AttachSharedReview(S,helpers)
    local GBS=helpers.GBS
    local codec=helpers.codec
    local snapshots=helpers.snapshots
    local display=modules.InfoDisplay
    local tell,clock,copy,sameLock=helpers.tell,helpers.clock,helpers.copy,helpers.sameLock
    local automationActive=helpers.automationActive

    local function createReviewFrame(name,height,level,scrollName,scrollHeight)
        local d=GBS.CreateSyncFrame(name,470,height,level)
        d:SetFrameStrata('FULLSCREEN_DIALOG'); d:SetToplevel(true); d:ClearAllPoints(); d:SetPoint('CENTER',GBS.Bank.frame,'CENTER',0,0); d:Hide()
        local title=GBS.CreateSyncText(d.titleBar,'OVERLAY'); title:SetPoint('LEFT',d.titleBar,'LEFT',8,0); d.title=title
        local scroll=CreateFrame('ScrollFrame',scrollName,d,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',d,'TOPLEFT',14,-35); scroll:SetSize(420,scrollHeight); GBS.SkinScroll(scroll)
        scroll:EnableMouseWheel(true); scroll:SetScript('OnMouseWheel',function(frame,delta) frame:SetVerticalScroll(math.max(0,math.min(frame:GetVerticalScrollRange(),frame:GetVerticalScroll()-delta*32))) end)
        local text=CreateFrame('EditBox',nil,scroll); text:SetMultiLine(true); text:SetFontObject('GBSFont'); text:SetAutoFocus(false); text:EnableMouse(false); text:SetWidth(406); text:SetHeight(scrollHeight); scroll:SetScrollChild(text); d.text=text; d.scroll=scroll
        return d
    end
    local function showReviewText(d,lines,height)
        local total=0; for _,line in ipairs(lines) do local _,count=GBS.WrapSyncText(line,395); total=total+count end
        d.text:SetText(table.concat(lines,'\n')); d.text:SetHeight(math.max(height,total*16+8)); d.scroll:SetVerticalScroll(0); d:Show()
    end
    local function reviewState(state)
        return state=='ready' or state=='readonly' or state=='locked' or state=='corrupt'
    end

    function S:ShowNextReadOnlyReview()
        if not reviewState(self.state) then
            if self.reviewDialog then self.reviewDialog:Hide() end
            return
        end
        if self.reviewDialog and self.reviewDialog:IsShown() then
            local tab=self.reviewDialog.target
            local review=self.readonlyReviews[tab]
            if review then
                if review.raw~=self.reviewDialog.expectedRaw then self:ReviewReadOnly(tab) end
                return
            end
            self.reviewDialog:Hide()
        end
        for tab=1,self.count do
            local review=self.readonlyReviews[tab]
            if review and self:CanViewReviewTab(tab) and self.reviewSnoozed[tab]~=review.raw then self:ReviewReadOnly(tab); return end
        end
    end
    local function createReadOnlyDialog(self)
        local d=createReviewFrame('GBEReadOnlyReview',300,111,'GBEReadOnlyReviewScroll',210)
        local accept=CreateFrame('Button',nil,d,'UIPanelButtonTemplate'); accept:SetSize(150,22); accept:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',14,12); accept:SetText('Use bank settings'); GBS.StyleSyncButton(accept,true); d.acceptBtn=accept
        local skip=CreateFrame('Button',nil,d,'UIPanelButtonTemplate'); skip:SetSize(100,22); skip:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',174,12); skip:SetText('Skip tab'); GBS.StyleSyncButton(skip,false); d.skipBtn=skip
        accept:SetScript('OnClick',function() S:AcceptReadOnly(d.target,d.expectedRaw) end)
        skip:SetScript('OnClick',function() S:SkipReadOnly(d.target,d.expectedRaw) end)
        d.close:SetScript('OnClick',function() S:SkipReadOnly(d.target,d.expectedRaw) end)
        self.reviewDialog=d
    end
    local function readOnlyLines(self,d,review,tab)
        local lines
        if review.reason=='corrupt' then
            d.acceptBtn:Disable(); d.acceptBtn:Hide(); d.skipBtn:SetText('Skip tab')
            lines={'Tab '..tab..' settings are damaged or were edited by hand. Bank settings cannot be read.', '', 'If you choose Skip tab, this tab will be skipped for routing, stacking and sorting until a guild member with permission repairs its settings.', '', 'Routing between other tabs is also paused because this tab’s assignments are unknown.', '', 'Bank settings last saved: Unknown'}
            if tab==1 then lines[#lines+1]=''; lines[#lines+1]='Tab 1 lock cannot be read. All addon sorting and configuration are blocked until it is repaired.' end
        else
            local author=self.tabs[tab] and self.tabs[tab].savedBy
            if type(author)=='string' and author~='' then d.acceptBtn:Enable() else d.acceptBtn:Disable() end
            d.acceptBtn:Show(); d.acceptBtn:SetText('Use bank settings'); d.skipBtn:SetText('Skip tab')
            lines={'Tab '..tab..' settings changed since you last accepted them.', '', display.SavedLine(self.tabs[tab]):gsub('^Last saved:', 'Bank settings last saved:'), ''}
            for _,line in ipairs(review.changes or {}) do lines[#lines+1]=line end
            lines[#lines+1]=''
            if type(author)~='string' or author=='' then
                lines[#lines+1]='The last person to save these settings is unknown. This tab will be skipped until a guild member with permission reviews and saves them, or they match your saved settings again.'
            else
                lines[#lines+1]='Use the bank settings or skip this tab. A skipped tab will not be routed, stacked or sorted.'
            end
        end
        return lines
    end
    function S:ReviewReadOnly(tab)
        local review=self.readonlyReviews and self.readonlyReviews[tab]
        if not review or not self:CanViewReviewTab(tab) or not GBS.Bank or not GBS.Bank:IsOpen() then return end
        if not reviewState(self.state) then return end
        if self.dialog and self.dialog:IsShown() then return end
        if automationActive() then return end
        if not self.reviewDialog then createReadOnlyDialog(self) end
        local d=self.reviewDialog; d.target=tab; d.expectedRaw=review.raw
        d.title:SetText('|cffffd100Review tab '..tab..' settings|r')
        local lines=readOnlyLines(self,d,review,tab)
        showReviewText(d,lines,210)
    end
    function S:SkipReadOnly(tab,expected)
        local review=self.readonlyReviews and self.readonlyReviews[tab]
        if not review or review.raw~=expected then self:ShowNextReadOnlyReview(); return end
        self:SkippedStore(true)[tab]=true
        self.reviewSnoozed[tab]=review.raw
        if self.reviewDialog then self.reviewDialog:Hide() end
        self:UpdateUI(); self:ShowNextReadOnlyReview()
    end
    function S:AcceptReadOnly(tab,expected)
        if self.versionNeeded or not self:CheckCurrentVersion() then return end
        local review=self.readonlyReviews and self.readonlyReviews[tab]
        if not review or review.reason=='corrupt' or review.raw~=expected or not self:CanViewReviewTab(tab) or not self.tabs[tab] or type(self.tabs[tab].savedBy)~='string' or self.tabs[tab].savedBy=='' then return end
        local ok,current=pcall(GetGuildBankText,tab); if ok and current==nil then current='' end
        if not ok or current~=expected then
            tell('Tab '..tab..' changed again; review the latest settings.')
            if self.reviewDialog then self.reviewDialog:Hide() end
            self:Changed(tab); return
        end
        if not self:CurrentSnapshot() then self:SaveSnapshot() end
        if not self:SaveSnapshotTab(tab) then tell('Could not save the accepted settings.'); return end
        local skipped=self:SkippedStore(false); if skipped then skipped[tab]=nil end
        self.readonlyReviews[tab]=nil; self.reviewSnoozed[tab]=nil
        if self.reviewDialog then self.reviewDialog:Hide() end
        self:Evaluate()
    end
    local function button(parent,text,x,width,primary)
        local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); b:SetSize(width,22); b:SetPoint('BOTTOMLEFT',parent,'BOTTOMLEFT',x,12); b:SetText(text); GBS.StyleSyncButton(b,primary); return b
    end
    function S:ReviewTab(tab)
        if self.versionNeeded then tell('Update Guild Bank Enhanced first.'); return end
        if self.organizerReviews and self.organizerReviews[tab] then
            local review=self.organizerReviews[tab]
            self.state=review.reason=='corrupt' and 'corrupt' or 'conflict'
            self:ShowConflict({},tab)
        else self:ReviewReadOnly(tab) end
    end
    function S:SkipOrganizer(tab,expected)
        local review=self.organizerReviews and self.organizerReviews[tab]
        if not review or review.raw~=expected then self:Evaluate(); return end
        self:SkippedStore(true)[tab]=true; self.reviewSnoozed[tab]=review.raw
        if self.dialog then self.dialog:Hide() end
        self:Evaluate()
    end
    function S:AcceptOrganizer(tab,expected)
        if self.versionNeeded or not self:CheckCurrentVersion() then return end
        local review=self.organizerReviews and self.organizerReviews[tab]
        if not review or review.raw~=expected or not self:CanEditReviewTab(tab) then self:Evaluate(); return end
        local ok,current=pcall(GetGuildBankText,tab); if not ok or (current or '')~=expected then self:Changed(tab); return end
        if review.reason=='corrupt' then return end
        if not self:CurrentSnapshot() then self:SaveSnapshot() end
        if not self:SaveSnapshotTab(tab) then tell('Could not save the accepted settings.'); return end
        local skipped=self:SkippedStore(false); if skipped then skipped[tab]=nil end
        self.organizerReviews[tab]=nil; self.reviewSnoozed[tab]=nil
        if self.dialog then self.dialog:Hide() end
        self:Evaluate()
    end
    function S:ApplyOneSaved(tab,expected,reset)
        if self.versionNeeded or not self:CheckCurrentVersion() then return end
        local review=self.organizerReviews and self.organizerReviews[tab]
        if reset and (not review or review.reason~='corrupt') then return end
        local prior=reset and {keywords={},direction='col',other=false,overflow=false} or self:PreviousTabSettings(tab)
        if not review or review.raw~=expected or not prior or not self:CanEditReviewTab(tab) or self.pending or self.closing then self:Evaluate(); return end
        if not (review.reason=='corrupt' and tab==1) and (not self.mine or not self.tabs[1] or not sameLock(self.mine,self.tabs[1].lock)) then
            tell('Cannot apply saved settings until you hold the bank lock.'); return
        end
        local ok,current=pcall(GetGuildBankText,tab); if not ok or (current or '')~=expected then self:Changed(tab); return end
        for other,value in pairs(self.tabs) do
            if other~=tab and ((prior.other and value.other) or (prior.overflow and value.overflow)) then
                tell('Clear the existing Fallback or Overflow on tab '..other..' first.'); return
            end
        end
        local stamp=clock(); if not stamp or not self.actor then tell('Cannot record settings author or time.'); return end
        local v=copy(prior); v.description=self.tabs[tab].description; v.lock=self.tabs[tab].lock; v.savedBy=self.actor; v.savedAt=stamp
        if tab==1 then v.addonVersion=self.tabs[1].addonVersion or GBS.Version end
        if review.reason=='corrupt' and tab==1 then v.lock={owner=self.actor,timestamp=stamp,token=tostring(stamp)..tostring(math.random(100000,999999))} end
        local composed,err=codec.Compose(v.description,v); if not composed then tell(err); return end
        if review.reason=='corrupt' then self:BackupCorrupt(tab,expected) end
        if self.dialog then self.dialog:Hide() end
        self.state='restoring'; self:UpdateUI()
        local function after()
            if tab==1 and review.reason=='corrupt' then self.mine=v.lock end
            if reset then self:SaveSnapshotTab(tab) end
            self:Evaluate()
        end
        local written,why=self:Write(tab,v,after,expected,nil,after)
        if not written and self.state~='error' then self:Fail(why) end
    end
    local function createOrganizerDialog(self)
        local d=createReviewFrame('GBESyncConflict',330,110,'GBESyncDiffScroll',247)
        d.useBankBtn=button(d,'Use bank settings',14,125,true); d.useSavedBtn=button(d,'Apply saved settings',145,140,false); d.resetBtn=button(d,'Reset tab',291,80,false); d.cancelBtn=button(d,'Skip tab',378,78,false)
        d.resetBtn:SetScript('OnClick',function()
            if type(StaticPopup_Show)~='function' then tell('Confirmation UI unavailable.'); return end
            StaticPopup_Show('GBE_RESET_DAMAGED',nil,nil,{tab=d.target,raw=d.expectedRaw})
        end)
        d.useBankBtn:SetScript('OnClick',function() S:AcceptOrganizer(d.target,d.expectedRaw) end)
        d.useSavedBtn:SetScript('OnClick',function() S:ApplyOneSaved(d.target,d.expectedRaw) end)
        d.cancelBtn:SetScript('OnClick',function() S:SkipOrganizer(d.target,d.expectedRaw) end)
        d.close:SetScript('OnClick',function() S:SkipOrganizer(d.target,d.expectedRaw) end)
        self.dialog=d
    end
    local function organizerLines(self,d,review,tab,saved)
        local lines={}
        if review.reason=='corrupt' then
            d.useBankBtn:Hide(); d.resetBtn:Show()
            d.useSavedBtn:ClearAllPoints(); d.useSavedBtn:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',14,12)
            d.resetBtn:ClearAllPoints(); d.resetBtn:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',165,12)
            d.cancelBtn:ClearAllPoints(); d.cancelBtn:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',256,12)
            lines={'Tab '..tab..' bank settings are damaged or were edited by hand and cannot be read.', '', 'WARNING: Resetting makes this tab unassigned. Check its settings before sorting or routing items.', '', 'Skip tab excludes this tab from routing, stacking and sorting until its settings are resolved. Routing between other tabs is also paused while its assignments are unknown.'}
            if tab==1 then lines[#lines+1]='Tab 1 lock cannot be read. All addon sorting and configuration are blocked until it is repaired. Check that nobody else is working before restoring.' end
            lines[#lines+1]=''; lines[#lines+1]='Bank settings last saved: Unknown'
            lines[#lines+1]=saved and 'Saved settings are available on this character.' or 'No saved settings are available on this character.'
            lines[#lines+1]='Reset tab clears its assignments, roles and direction and replaces damaged addon data after confirmation.'
            if saved then
                lines[#lines+1]=''; lines[#lines+1]='Apply saved settings would restore:'
                local settings=display.Settings(saved,GBS.SortDirections)
                for i=2,#settings-1 do lines[#lines+1]='  '..settings[i] end
            end
            if self.tabs[tab].unsupported then lines[#lines+1]='This format cannot be read. Applying saved settings replaces the unreadable addon data; a backup is kept on this character.' end
        else
            d.useBankBtn:Show(); d.resetBtn:Hide()
            d.useSavedBtn:ClearAllPoints(); d.useSavedBtn:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',145,12)
            d.cancelBtn:ClearAllPoints(); d.cancelBtn:SetPoint('BOTTOMLEFT',d,'BOTTOMLEFT',378,12)
            lines={'Tab '..tab..' settings changed. They may have been edited by hand or corrupted.', '', 'WARNING: Using incorrect bank settings may route or sort items incorrectly.', '', 'Skip tab excludes this tab from routing, stacking and sorting until you accept or restore its settings, or they match again.', '', display.SavedLine(self.tabs[tab]):gsub('^Last saved:', 'Bank settings last saved:'), '', 'Apply saved settings would make these changes:'}
            if saved then
                local one=snapshots.Snapshot(self.realm,self.guild,{[tab]=self.tabs[tab]})
                local diff=one and snapshots.Diff(one,self.realm,self.guild,{[tab]=saved})
                for _,line in ipairs(diff and diff[tab] or {}) do lines[#lines+1]='  '..line end
            else lines[#lines+1]='  No saved settings are available.' end
        end
        return lines
    end
    function S:ShowConflict(changes,tab)
        tab=tab or (self.dialog and self.dialog.target)
        if not tab or not self.organizerReviews or not self.organizerReviews[tab] then return end
        if not self.dialog then createOrganizerDialog(self) end
        if self.reviewDialog then self.reviewDialog:Hide() end
        local d=self.dialog; local review=self.organizerReviews[tab]; local saved=self:PreviousTabSettings(tab)
        d.target=tab; d.expectedRaw=review.raw; d.title:SetText('|cffffd100Review tab '..tab..' settings|r')
        local lines=organizerLines(self,d,review,tab,saved)
        showReviewText(d,lines,247); self:UpdateUI()
    end
    function S:ShowConflictAgain()
        for tab=1,self.count or 0 do if self:IsTabExcluded(tab) then self:ReviewTab(tab); return end end
    end
end

end

do

local Money = _G.GuildBankSorterModules.Money
local BankAccess = _G.GuildBankSorterModules.BankAccess
local InfoDisplay = _G.GuildBankSorterModules.InfoDisplay
local InfoDraft = _G.GuildBankSorterModules.InfoDraft
local ItemQuality = _G.GuildBankSorterModules.ItemQuality
local GBS = {}
_G["GuildBankEnhanced"] = GBS
_G["GuildBankSorter"] = GBS

GBSCharDB = GBSCharDB or {}
local function NormaliseDelay(value,default,maximum)
    if type(value)~="number" or value~=value then value=default end
    value=math.max(0,math.min(maximum or 1,value))
    return math.floor(value*20+0.5)/20
end
GBSCharDB.moveDelay=NormaliseDelay(GBSCharDB.moveDelay,0.1)
GBSCharDB.scanDelay=NormaliseDelay(GBSCharDB.scanDelay,0.3)
GBSCharDB.infoDelay=NormaliseDelay(GBSCharDB.infoDelay,0.5,5)

local NUM_TABS = 6
local BANK_COLS, BANK_ROWS, SLOT_SIZE, SLOT_GAP = 14, 7, 34, 3

local function GetMoveDelay() return GBSCharDB.moveDelay or 0.1 end
local function GetScanDelay() return GBSCharDB.scanDelay or 0.3 end
local function GetInfoDelay() return NormaliseDelay(GBSCharDB.infoDelay,0.5,5) end
GBS.GetMoveDelay = GetMoveDelay
GBS.GetScanDelay = GetScanDelay
GBS.GetInfoDelay = GetInfoDelay

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

-- Use the real addon directory when the loader supplies it; do not assume
-- that the user extracted the folder under a particular name.
local addonName = ...
if type(addonName) ~= "string" or addonName == "" then addonName = "GuildBankEnhanced" end
local requestedFont = "Interface\\AddOns\\"..addonName.."\\Fonts\\PTSansNarrow-Bold.ttf"
local GBS_FONT_SIZE=14
local GBS_VERSION="1.1.0"
GBS.Version=GBS_VERSION
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
GBS.CreateSyncFrame=CreateGBSFrameBase
GBS.StyleSyncButton=StyleButton
GBS.CreateSyncText=CreateGBSFontString

local CATEGORIES = _G.GuildBankSorterModules.Categories
GBS.CATEGORIES = CATEGORIES

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
function GBS:GetPhysicalSlot(logical,tab)
    local dir=(tab and self.tabDirections and self.tabDirections[tab]) or "col"; local n=logical-1
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
    -- Blizzard numbers the seven slots down each visual column before moving right.
    return col*BANK_ROWS+row+1
end
function GBS:GetLogicalSlot(phys,tab)
    local dir=(tab and self.tabDirections and self.tabDirections[tab]) or "col"; local row=(phys-1)%BANK_ROWS; local col=math.floor((phys-1)/BANK_ROWS)
    if dir=="col" or dir=="col_left" or dir=="col_up" or dir=="col_up_left" then
        if dir=="col_left" or dir=="col_up_left" then col=BANK_COLS-1-col end
        if dir=="col_up" or dir=="col_up_left" then row=BANK_ROWS-1-row end
        return col*BANK_ROWS+row+1
    end
    if dir=="row_rev" or dir=="row_rev_up" or (dir=="snake" and row%2==1) then col=BANK_COLS-1-col end
    if dir=="row_up" or dir=="row_rev_up" then row=BANK_ROWS-1-row end
    return row*BANK_COLS+col+1
end


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
local function ContainsKeyword(text,keywords)
    for _,keyword in ipairs(keywords) do
        if string.find(text,keyword,1,true) then return true end
    end
    return false
end
local function GetItemCategory(name, subtype, itemType)
    local text=Lower(name or "")
    if ContainsKeyword(text,VENDOR_KEYWORDS) then return 3 end
    if ContainsKeyword(text,CRAFTED_KEYWORDS) then return 2 end
    return 1
end
GBS.GetClothTier=GetClothTier; GBS.GetItemCategory=GetItemCategory; GBS.VENDOR_KEYWORDS=VENDOR_KEYWORDS; GBS.CRAFTED_KEYWORDS=CRAFTED_KEYWORDS; GBS.CLOTH_TIER=CLOTH_TIER

local function GetTabInfo(tab)
    if type(GetGuildBankTabInfo)=="function" then local ok,n,icon,isViewable,canDeposit,numWithdrawals,remaining=pcall(GetGuildBankTabInfo,tab); if ok then return n,icon,isViewable end end
    return nil
end
local function TabAccess(tab)
    if type(GetGuildBankTabInfo)~="function" then return nil end
    local ok,_,_,view,deposit,_,remaining=pcall(GetGuildBankTabInfo,tab)
    if not ok then return nil end
    return view and view~=0, deposit and deposit~=0, remaining
end
local function CanViewTab(tab) local view=TabAccess(tab); return view==true end
local function CanUseAutomation(tab)
    local shared=GBS.Shared
    return not shared or type(shared.IsTabExcluded)~="function" or not shared:IsTabExcluded(tab)
end
local function CanArrangeTab(tab) local view,deposit=TabAccess(tab); return view==true and deposit==true and CanUseAutomation(tab) end
-- Planning may only check tab-specific flags; the remaining count returned for
-- *any* tab can actually be the most recently selected/updated tab's count.
-- A routing batch may use a source count only after its source-specific query.
local function RoutePermission(src,dst,batch,requireSource)
    if not CanUseAutomation(src) then return false,"source tab settings need review" end
    if not CanUseAutomation(dst) then return false,"destination tab settings need review" end
    local sourceView=TabAccess(src)
    local destView,deposit=TabAccess(dst)
    if not sourceView then return false,"source tab is not viewable" end
    if not destView then return false,"destination tab is not viewable" end
    if not deposit then return false,"no deposit permission on destination tab" end
    local budget=batch and batch.remaining and batch.remaining[src]
    if batch and budget==nil then return false,"source allowance unknown" end
    if requireSource then
        local selected
        if type(GetCurrentGuildBankTab)=="function" then local ok,t=pcall(GetCurrentGuildBankTab); if ok then selected=t end end
        if selected~=src then return false,"source tab selection changed" end
    end
    if budget~=nil and budget<1000 then return false,"fewer than 1000 withdrawals remain on source tab" end
    return true
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
function GBS.Assign:Get(tab) return GBS.sharedAssignments and GBS.sharedAssignments[tab] end
function GBS.Assign:IsOther(tab) return GBS.sharedOther==tab end
function GBS.Assign:IsOverflow(tab) return GBS.sharedOverflow==tab end
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
        if GBS.sharedAssignments and GBS.sharedAssignments[tab] then self.tabKeywords[tab]=GBS.sharedAssignments[tab] end
    end
    if self.sharedOther and self.tabNames[self.sharedOther] then self.globalOtherTab=self.sharedOther end
    self.otherTab=self.globalOtherTab
    if self.sharedOverflow and self.tabNames[self.sharedOverflow] then self.overflowTab=self.sharedOverflow end
    if count==0 then self.noTabsReason="Waiting for guild bank tab information." end
    if UpdateSortControls then UpdateSortControls() end
    return self.otherTab
end

-- Queue (OnUpdate, 3.3.5 no C_Timer)
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
function GBS:Stop(msg,continuing)
    if not continuing then self.sortStartTab=nil end
    self.isRunning=false; self.cancelRequested=false; processorFrame:Hide()
    UpdateStopButtons()
    if UpdateSortControls then UpdateSortControls() end
    if msg then Log(msg,0.6,0.8,1) end
    self:UpdateProgress()
end

function GBS:ScanAllTabs(onDone)
    self:CheckOtherTab()
    local tabList={}
    for tab=1,NUM_TABS do if self.tabNumSlots[tab] then
        if not CanUseAutomation(tab) then Log("Skipping tab "..tab..": settings need review.",1,0.8,0.3)
        elseif CanViewTab(tab) then table.insert(tabList,tab) else Log("Skipping tab "..tab..": no view permission.",1,0.8,0.3) end
    end end
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
    if self.Shared and self.Shared.HasUncertainAssignments and self.Shared:HasUncertainAssignments() then return nil end
    local bestTab,bestScore=nil,0
    for tab=1,NUM_TABS do
        for _,key in ipairs(self.tabKeywords[tab] or {}) do
            local score=AssignmentScore(key,item.itemType,item.itemSubType)
            if score>bestScore then bestTab,bestScore=tab,score end
        end
    end
    -- A skipped tab's previous assignments must not silently fall through to another tab.
    if self.Shared and type(self.Shared.PreviousTabSettings)=="function" then
        for tab=1,NUM_TABS do if not CanUseAutomation(tab) then
            local previous=self.Shared:PreviousTabSettings(tab)
            for _,key in ipairs(previous and previous.keywords or {}) do
                local score=AssignmentScore(key,item.itemType,item.itemSubType)
                if score>0 and score>=bestScore then bestTab,bestScore=tab,score end
            end
            if bestScore==0 and previous and previous.other then bestTab=tab end
        end end
    end
    return bestTab or self.globalOtherTab or self.otherTab
end
function GBS:BuildMovePlan(items)
    local moves={}; local counts={}
    for _,it in ipairs(items) do
        local target=self:DetermineTargetTab(it)
        if not target then Log("No target for "..(it.name or ("item "..tostring(it.itemID))),1,0.5,0.5)
        elseif target~=it.tab then
            local permitted,why=RoutePermission(it.tab,target)
            if permitted then table.insert(moves,{fromTab=it.tab,fromSlot=it.slot,toTab=target,item=it}); counts[target]=(counts[target] or 0)+1
            else Log("Routing skipped: tab "..it.tab.." -> tab "..target.." ("..why..").",1,0.8,0.3) end
        end
    end
    return moves,counts
end
function GBS:StartSort()
    if self.isRunning or self.routing or self.activeMove or self.routingPrompt then Chat("Already running. Wait or /reload.",1,0.8,0.2); return end
    if not (self.Bank and self.Bank:IsOpen()) then Chat("Open the guild bank first.",1,0.4,0.4); return end
    if SafeGetCursorInfo() then Chat("Clear the cursor before sorting.",1,0.4,0.4); return end
    local reason=not self.Shared and "Shared settings unavailable." or (self.Shared and self.Shared:Reason()); if reason then Chat(reason,1,0.4,0.4); return end
    self:CheckOtherTab()
    if not self.globalOtherTab then
        if not next(self.tabNames or {}) then Chat("Open Guild Bank first.",1,0.4,0.4); return end
        Log("No fallback tab set - unassigned items will be skipped. Assign a Fallback (Other) tab.",1,0.8,0.2)
    end
    self.scanData=nil; self.workRouteDone=0
    self.sortStartTab=self.Bank.currentTab
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
        Log("Scan and routing plan complete.",0.6,1,0.6); self:Stop("Scan finished.",true)
        if shortage then self:StartArrange(false,true) else self:StartRouting() end
    end)
end
function GBS:Cancel()
    if self.routingPrompt then
        if self.routing then self:StopRouting("Sort cancelled before routing.")
        else self.routingPrompt=nil; if self.Bank and self.Bank.routeWarning then self.Bank.routeWarning.callback=nil; self.Bank.routeWarning:Hide() end; self.scanData=nil; self:Stop("Sort cancelled before routing.") end
        return
    end
    if self.arrange then self:StopArrange("Cancelled; inspect cursor and slots."); return end
    if self.routing then self:StopRouting("Cancelled; inspect both tabs and the cursor."); return end
    if self.activeMove then self.StopMove("Cancelled. Inspect the cursor and bank slots."); return end
    self.cancelRequested=true
    if SafeGetCursorInfo()=="item" then Log("Warning: cursor has an item. Click to place it.",1,0.8,0.2) end
    self:Stop("Cancelled.")
end

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
    if not GBS.Shared or GBS.Shared:Reason() or not GBS.Shared:CheckCurrentVersion() then return false end
    if src==dst then return CanArrangeTab(src) end
    return RoutePermission(src,dst,GBS.routing,true)
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
function GBS:StopRouting(reason,continuing)
    if not continuing then self.sortStartTab=nil end
    self.routingPrompt=nil
    if self.Bank and self.Bank.routeWarning then self.Bank.routeWarning.callback=nil; self.Bank.routeWarning:Hide() end
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
    for tab=1,NUM_TABS do
        local budget=batch.remaining and batch.remaining[tab]
        if budget~=nil then
            RouteLog("Tab "..tab.." estimated remaining after routing: "..(budget==math.huge and "unlimited" or tostring(budget)).." (not re-queried).")
        end
    end
    self.workRouteDone=done
    self:StopRouting(string.format("Completed %d observed routing moves; %d to overflow, %d left in place.",done,overflow,skipped),true)
    self:StartArrange(done>0)
end
function GBS:RouteItemComplete(ok)
    local batch=self.routing; if not batch then return end
    if not ok then self:StopRouting("Stopped on an unconfirmed move. No further moves attempted; inspect source, destination and cursor."); return end
    if batch.currentOverflow then batch.overflowed=(batch.overflowed or 0)+1; batch.currentOverflow=nil end
    local source=batch.currentSource; batch.currentSource=nil
    if source and batch.remaining and batch.remaining[source] and batch.remaining[source]~=math.huge then batch.remaining[source]=math.max(0,batch.remaining[source]-1) end
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
local routeSelector=GuildBankSorterModules.RouteSelector.New({tabSpace=TabSpace,findMerge=FindRouteMerge,canRoute=function(move,target,batch)
    local uncertainAlternative=target~=move.toTab and GBS.Shared and GBS.Shared.HasExcludedRouteRoles and GBS.Shared:HasExcludedRouteRoles()
    return not uncertainAlternative and CanUseAutomation(move.toTab) and RoutePermission(move.fromTab,target,batch)
end})

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
    if not GBS.Bank:IsOpen() or SafeGetCursorInfo() or not GBS.Shared or GBS.Shared:Reason() or not RoutePermission(move.sourceTab,move.targetTab,GBS.routing) or not SourceUnchanged(move) then
        return "Preflight failed: bank, cursor, permissions or source changed; no further move requested."
    end
    local live=GetSlotData(move.sourceTab,move.sourceSlot)
    if not live or not live.itemType or not live.itemSubType or GBS:DetermineTargetTab(live)~=move.primaryTab then
        return "Assignment or item information changed; no further move requested."
    end
    if type(QueryGuildBankTab)~="function" then return "Tab query API unavailable; no further move requested." end
    if not pcall(QueryGuildBankTab,move.targetTab) then return "Could not query destination tab." end
end
local function FindRouteDestination(move)
    if move.destSlot then return DestinationUnchanged(move) end
    for logical=1,98 do
        local slot=GBS:GetPhysicalSlot(logical,move.targetTab)
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
-- Sample each candidate source once at the start of routing. Bank events have
-- no request id, so a response can still be ambiguous if other addons or very
-- late packets interfere. Never use a count obtained while another tab is
-- selected. Unknown values skip that source; the budget only decreases.
local function StartAllowanceScan(batch)
    local sources,seen={},{}
    for _,move in ipairs(batch.moves) do if not seen[move.fromTab] then seen[move.fromTab]=true; sources[#sources+1]=move.fromTab end end
    table.sort(sources)
    batch.remaining={}; batch.allowanceScan={sources=sources,index=1,phase="settle",quiet=0,elapsed=0}
    GBS.isRunning=true; GBS.currentPhase="Checking source allowances"; GBS:UpdateProgress(); UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
    local function advance(_,dt)
        local current=GBS.routing; local scan=current and current.allowanceScan
        if not scan then routeDriver:SetScript("OnUpdate",nil); routeDriver:Hide(); return end
        if not GBS.Bank:IsOpen() or SafeGetCursorInfo() or not GBS.Shared or GBS.Shared:Reason() then GBS:StopRouting("Allowance scan stopped: bank, lock or cursor changed."); return end
        scan.elapsed=scan.elapsed+dt; scan.quiet=scan.quiet+dt
        local tab=scan.sources[scan.index]
        if not tab then
            current.allowanceScan=nil; routeDriver:SetScript("OnUpdate",nil); routeDriver:Hide(); GBS:AllowanceScanComplete(current); return
        end
        if scan.phase=="settle" then
            if scan.quiet<1 then return end
            if type(SetCurrentGuildBankTab)~="function" or type(GetCurrentGuildBankTab)~="function" or type(QueryGuildBankTab)~="function" then GBS:StopRouting("Source allowance API unavailable; no pickup made."); return end
            scan.phase="waiting"; scan.elapsed=0; scan.quiet=0; scan.seen=nil
            GBS.Bank:SelectTab(tab,true,true)
            local ok,selected=pcall(GetCurrentGuildBankTab)
            if not ok or selected~=tab then GBS:StopRouting("Could not select source tab "..tab.."; no pickup made."); return end
            if not pcall(QueryGuildBankTab,tab) then GBS:StopRouting("Source allowance query failed; no pickup made."); return end
            return
        end
        if scan.elapsed>=8 then
            RouteLog("Tab "..tab.." allowance update timed out; routes from this tab will be skipped.")
        elseif not scan.seen or scan.quiet<0.5 then return
        else
            local ok,selected=pcall(GetCurrentGuildBankTab)
            if not ok or selected~=tab then GBS:StopRouting("Source tab selection changed during allowance scan; no pickup made."); return end
            local _,_,remaining=TabAccess(tab)
            if type(remaining)=="number" and remaining==remaining then
                local budget=(remaining<0 or remaining>=4294967295) and math.huge or remaining
                current.remaining[tab]=budget
                RouteLog("Tab "..tab.." initial selected allowance: "..(budget==math.huge and "unlimited" or tostring(budget)).."; tracked locally during routing.")
            else RouteLog("Tab "..tab.." allowance unknown; routes from this tab will be skipped.") end
        end
        scan.index=scan.index+1; scan.phase="settle"; scan.elapsed=0; scan.quiet=0; scan.seen=nil
    end
    routeDriver:SetScript("OnUpdate",function(frame,dt)
        local ok,err=pcall(advance,frame,dt)
        if not ok then GBS:StopRouting("Unexpected allowance scan error; stopped. "..tostring(err)) end
    end)
    routeDriver:Show()
end
local function StartRouteWait(batch,move)
    batch.current=move; batch.wait=0; batch.waitFor=batch.done>0 and not batch.waitPaid and GetMoveDelay() or 0; batch.waitPaid=nil
    -- Changing the selected source for pickup does not request another
    -- allowance sample. Existing destination/result queries still verify slots.
    GBS.Bank:SelectTab(move.sourceTab,true,true)
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
    local i=batch.index
    while i<=#batch.moves do
        local move=batch.moves[i]; local allowed,reason=RoutePermission(move.fromTab,move.toTab,batch)
        if not allowed then
            RouteLog("Skipped tab "..move.fromTab.." -> tab "..move.toTab..": "..reason..".")
            batch.skipped=(batch.skipped or 0)+1; table.remove(batch.moves,i)
        else i=i+1 end
    end
    if batch.index>#batch.moves then self:FinishRouting(); return end
    local choice,why=routeSelector:Choose(batch,self.overflowTab,self.globalOtherTab)
    if why then self:StopRouting(why); return end
    if not choice then ReportUnroutable(batch); return end
    batch.moves[batch.index],batch.moves[choice.index]=batch.moves[choice.index],batch.moves[batch.index]
    local selected=batch.moves[batch.index]; local item=selected.item; batch.currentOverflow=choice.overflow
    if choice.overflow then Log(string.format("Target tab %d is full; routing %s to %s tab %d.",selected.toTab,item.name or tostring(item.itemID),choice.secondary and "fallback" or "overflow",choice.target),1,0.8,0.4) end
    batch.currentSource=selected.fromTab
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
local function CompareCursorFields(cursorFields,slotFields)
    if not cursorFields or not slotFields then return false,false end
    local missingSuffix=false
    for i=1,math.max(8,#cursorFields,#slotFields) do
        local cursorValue,slotValue=cursorFields[i] or 0,slotFields[i] or 0
        if i~=9 and cursorValue~=slotValue then
            if i==7 and cursorValue==0 and slotValue~=0 then missingSuffix=true else return false,false end
        end
    end
    return true,missingSuffix
end
local function OrderingSourceSnapshot(tab,slot,item,requireLock)
    if not tab or not slot or not item then return false end
    local texture,count,locked=GetGuildBankItemInfo(tab,slot)
    return texture and count==item.count and GetGuildBankItemLink(tab,slot)==item.link
        and (not requireLock or (locked and locked~=0))
end
local function CursorMatchesItem(kind,id,cursorLink,item,tab,slot)
    if not item or kind~="item" or id~=item.itemID then return false end
    if type(cursorLink)=="string" then
        local match,missingSuffix=CompareCursorFields(CursorItemFields(cursorLink),CursorItemFields(item.link))
        if not match then return false end
        -- Some 3.3.5 clients omit a random suffix on the cursor. Only accept
        -- it while the original, unchanged source is visibly locked.
        if missingSuffix and not OrderingSourceSnapshot(tab,slot,item,true) then return false end
    end
    return true
end
local function WaitingForSourceLock(kind,id,cursorLink,item,tab,slot)
    if not item or kind~="item" or id~=item.itemID then return false end
    local match,missing=CompareCursorFields(CursorItemFields(cursorLink),CursorItemFields(item.link))
    return match and missing and OrderingSourceSnapshot(tab,slot,item,false)
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
    physicalSlot=function(logical,tab) return GBS:GetPhysicalSlot(logical,tab) end,
    compare=ArrangeLess,
    same=SameSlot,
})
local function FindArrangeOp(tab,provided,stackOnly) return arrangePlanner:Find(tab,provided,stackOnly) end
local function EstimateArrange(tab,stackOnly) return arrangePlanner:Estimate(tab,stackOnly) end
function GBS:StopArrange(reason,continuing,completed)
    local returnTab=completed and self.sortStartTab
    arrangeDriver:SetScript("OnUpdate",nil); arrangeDriver:Hide(); self.arrange=nil
    self.scanData=nil; self:Stop(reason,continuing)
    local cursor=SafeGetCursorInfo()
    if cursor then Log("Cursor holds an item: place it manually before continuing.",1,0.5,0.3) end
    if self.Bank and self.Bank:IsOpen() then
        if returnTab and self.tabNames[returnTab] and not cursor then self.Bank:SelectTab(returnTab) end
        self.Bank:Refresh()
    end
end
local arrangeStages={}
arrangeStages.cooldown=function(a)
    if a.elapsed<GetMoveDelay() then return end
    a.stage="query"; a.elapsed=0
end
arrangeStages.query=function(a)
    if a.tab>NUM_TABS or not GBS.tabNumSlots[a.tab] then
        if a.prestack then
            GBS:StopArrange("Pre-stacking complete: "..a.ops.." operations observed.",true)
            GBS:DoSort(true)
        else GBS:StopArrange("Sort complete: "..a.ops.." stack/order operations observed. Reopen and verify the bank.",false,true) end
        return
    end
    if not CanUseAutomation(a.tab) then Log("Skipping tab "..a.tab..": settings need review.",1,0.8,0.3); a.tab=a.tab+1; a.tabOps=0; a.elapsed=0; GBS:UpdateProgress(); return end
    if not CanViewTab(a.tab) then Log("Skipping tab "..a.tab..": no view permission.",1,0.8,0.3); a.tab=a.tab+1; a.tabOps=0; a.elapsed=0; GBS:UpdateProgress(); return end
    if not CanArrangeTab(a.tab) then Log("Skipping tab "..a.tab..": no deposit permission for stacking or ordering.",1,0.8,0.3); a.tab=a.tab+1; a.tabOps=0; a.elapsed=0; GBS:UpdateProgress(); return end
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
    if (not kind or not OrderingSourceConsistent(a.tab,op.src,op.source) or (not CursorMatchesItem(kind,id,link,op.source,a.tab,op.src) and WaitingForSourceLock(kind,id,link,op.source,a.tab,op.src))) and a.elapsed<3 then return end
    if not CursorMatchesItem(kind,id,link,op.source,a.tab,op.src) or not OrderingSourceConsistent(a.tab,op.src,op.source) then
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
    local sourceSlot=a.orderIndex==1 and op.src or nil
    if step and sourceSlot and not CursorMatchesItem(kind,id,link,step.after,a.tab,sourceSlot) and WaitingForSourceLock(kind,id,link,step.after,a.tab,sourceSlot) and a.elapsed<3 then return end
    if not step or not CursorMatchesItem(kind,id,link,step.after,a.tab,sourceSlot) or not CanMoveBetween(a.tab,a.tab) then
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
        if not CanMoveBetween(a.tab,a.tab) then GBS:StopArrange("Tab permissions or settings changed; inspect the cursor and tab."); return end
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
    for tab=1,NUM_TABS do if self.tabNumSlots[tab] and CanArrangeTab(tab) then
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

-- Decide whether the withdrawal warning is needed only after sampling all
-- candidate source allowances. An unknown or exhausted source cannot route.
function GBS:AllowanceScanComplete(batch)
    if self.routing~=batch then return end
    local eligible,hasFinite=0,false
    for _,move in ipairs(batch.moves) do
        local allowed=RoutePermission(move.fromTab,move.toTab,batch)
        if allowed then
            eligible=eligible+1
            if batch.remaining[move.fromTab]~=math.huge then hasFinite=true end
        end
    end
    if hasFinite then
        self.isRunning=false; self.routingPrompt=true; UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
        self.Bank:ConfirmRouting(eligible,function(accept)
            if GBS.routing~=batch or not GBS.routingPrompt then return end
            GBS.routingPrompt=nil
            if not accept then GBS:StopRouting("Sort cancelled before routing."); return end
            local reason=not GBS.Shared and "Shared settings unavailable." or (GBS.Shared and GBS.Shared:Reason())
            if reason or not GBS.Bank:IsOpen() or SafeGetCursorInfo() then GBS:StopRouting("Routing cancelled: "..(reason or "bank closed or cursor not empty").."."); return end
            GBS.isRunning=true; UpdateStopButtons(); if UpdateSortControls then UpdateSortControls() end
            local ok,err=pcall(GBS.RouteNext,GBS); if not ok then GBS:StopRouting("Unexpected error; stopped. "..tostring(err)) end
        end)
        return
    end
    if eligible>0 then RouteLog("All eligible source allowances are unlimited; no withdrawal warning needed.") end
    self:RouteNext()
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
    RouteLog("Considering "..#proposed.." cross-tab moves; checking each source allowance once before routing.")
    local ok,err=pcall(StartAllowanceScan,self.routing); if not ok then self:StopRouting("Unexpected error; stopped. "..tostring(err)) end
end

SkinGuildBank = function()
    if not GuildBankFrame or GuildBankFrame._gbsSkinned then return end
    pcall(function()
        local function HideRegion(obj)
            if obj and obj.Hide then pcall(function() obj:Hide() end) end
            if obj and obj.SetAlpha then pcall(function() obj:SetAlpha(0) end) end
        end
        local f=GuildBankFrame
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

local PANEL_W, PANEL_H = 470, 540

-- A mouse-enabled overlay remains hoverable even when a WoW button is disabled.
local function AddSortBlocker(btn,title,extraReason,allowUnlock)
    local overlay=CreateFrame("Frame",nil,btn:GetParent())
    overlay:SetAllPoints(btn)
    overlay:SetFrameLevel(btn:GetFrameLevel()+1)
    overlay:EnableMouse(true)
    overlay:Hide()
    overlay:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine(title or "Sort unavailable",1,0.82,0)
        local reason=GBS.Shared and GBS.Shared:Reason() or (not GBS.Shared and "Shared settings unavailable.")
        if reason then GameTooltip:AddLine(reason,1,1,1,true); if GBS.Shared and (GBS.Shared.state=="locked" or (GBS.Shared.state=="corrupt" and GBS.Shared:ForeignLock())) then GameTooltip:AddLine(allowUnlock and "Guild master: right-click Sort to force unlock." or "Guild master: /gbe unlock to force unlock.",0.8,0.8,0.8,true) elseif GBS.Shared and GBS.Shared.state=="conflict" then GameTooltip:AddLine("Use /gbe sync to review the differences.",0.8,0.8,0.8,true) end end
        if extraReason and not reason then local detail=extraReason(); if detail then GameTooltip:AddLine(detail,1,1,1,true) end end
        if GBS.routingPrompt then GameTooltip:AddLine("Respond to the routing withdrawal warning first.",1,1,1,true) end
        if GBS.isRunning then
            GameTooltip:AddLine("A scan is currently running.",1,1,1,true)
        end
        if GBS.isRunning then GameTooltip:AddLine("Wait for the active operation to finish.",0.8,0.8,0.8,true) end
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave",function() GameTooltip:Hide() end)
    if allowUnlock then
        overlay:SetScript("OnMouseUp",function(_,button)
            if button=="RightButton" then GBS.Bank:RequestSortForceUnlock() end
        end)
    end
    btn.sortBlocker=overlay
end

UpdateSortControls=function()
    local btn=GBS.Bank and GBS.Bank.frame and GBS.Bank.frame.sortBtn
    if not btn then return end
    local blocked=GBS.isRunning or GBS.routingPrompt or not GBS.Shared or GBS.Shared:Reason()~=nil
    if blocked then btn:Disable(); if btn.sortBlocker then btn.sortBlocker:Show() end
    else btn:Enable(); if btn.sortBlocker then btn.sortBlocker:Hide() end end
    if GBS.Bank and GBS.Bank.UpdateTabConfigSave then GBS.Bank:UpdateTabConfigSave() end
end
GBS.UpdateSortControls=UpdateSortControls

local function BuildDelays(f,buttonWidth,buttonHeight,gap)
    local function SettingsButton(parent,text)
        local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
        StyleButton(b,false); b:SetText(text)
        local fs=b:GetFontString(); if fs then fs:SetFont(GBS_FONT,GBS_FONT_SIZE,""); fs:SetTextColor(1,1,1,1) end
        b:HookScript("OnEnable",function(s) local text=s:GetFontString(); if text then text:SetTextColor(1,1,1,1) end end)
        return b
    end
    f.delayPopups={}
    local function MakeDelay(name,label,getVal,setVal,x,maximum)
        maximum=maximum or 1
        local trigger=SettingsButton(f,""); trigger:SetSize(buttonWidth,buttonHeight); trigger:SetPoint("TOPLEFT",f,"TOPLEFT",x,0)
        local popup=CreateFrame("Frame",nil,UIParent); popup:SetSize(250,76); popup:SetPoint("BOTTOM",trigger,"TOP",0,4); popup:SetFrameStrata("DIALOG"); popup:SetFrameLevel(55); StyleBackdrop(popup,1); popup:Hide(); f.delayPopups[#f.delayPopups+1]=popup
        local caption=CreateGBSFontString(popup,"OVERLAY"); caption:SetPoint("TOP",popup,"TOP",0,-8)
        local track=CreateFrame("Frame",nil,popup); track:SetSize(170,8); track:SetPoint("CENTER",popup,"CENTER",0,-7); StyleInset(track)
        local slider=CreateFrame("Slider",name,popup); slider:SetSize(170,18); slider:SetPoint("CENTER",track,"CENTER",0,0); slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(0,maximum); slider:SetValueStep(0.05)
        slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8"); local thumb=slider:GetThumbTexture(); if thumb then thumb:SetSize(6,16); thumb:SetVertexColor(0.9,0.9,0.9,1) end
        local adjusting=false
        local function set(v)
            v=math.max(0,math.min(maximum,math.floor((tonumber(v) or 0)*20+0.5)/20))
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
        trigger:SetScript("OnEnter",function(self) self:SetBackdropColor(0.18,0.18,0.18,1); GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine(label.." delay",1,0.82,0); GameTooltip:AddLine(label=="MOVE" and "Time between completed routing, stacking, ordering and split operations." or label=="SCAN" and "Time allowed after selecting each tab during a scan." or "Minimum time between guild bank Info updates, including lock and settings writes. Lower values can trigger server flood protection.",1,1,1,true); GameTooltip:AddLine("0 to "..maximum.." second"..(maximum==1 and "" or "s").." in 0.05s steps. Click or use the mouse wheel.",0.8,0.8,0.8,true); GameTooltip:Show() end)
        trigger:SetScript("OnLeave",function(self) self:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1); GameTooltip:Hide() end)
        return slider,trigger,popup,minus,plus
    end
    f.moveSlider,f.moveTrigger,f.movePopup,f.moveMinus,f.movePlus=MakeDelay("GBSMoveDelaySlider","MOVE",function() return GetMoveDelay() end,function(v) GBSCharDB.moveDelay=v end,0)
    f.scanSlider,f.scanTrigger,f.scanPopup,f.scanMinus,f.scanPlus=MakeDelay("GBSScanDelaySlider","SCAN",function() return GetScanDelay() end,function(v) GBSCharDB.scanDelay=v end,buttonWidth+gap)
    f.infoSlider,f.infoTrigger,f.infoPopup,f.infoMinus,f.infoPlus=MakeDelay("GBSInfoDelaySlider","INFO",function() return GetInfoDelay() end,function(v) GBSCharDB.infoDelay=v end,2*(buttonWidth+gap),5)

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
local function RowFits(text,width)
    if not rowWrapProbe then rowWrapProbe=CreateGBSFontString(UIParent,"OVERLAY"); rowWrapProbe:Hide() end
    rowWrapProbe:SetText(text)
    return (rowWrapProbe:GetStringWidth() or 0)<=width
end
local function WrapRowText(text,width)
    if not rowWrapProbe then rowWrapProbe=CreateGBSFontString(UIParent,"OVERLAY"); rowWrapProbe:Hide() end
    local lines,current={},""
    local function fits(value) return RowFits(value,width) end
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
GBS.WrapSyncText=WrapRowText

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
    ef.checks={}; ef.sections={}; ef.collapsed={}; ef.embedded=false; ef.embeddedHeight=264; ef.readOnly=false

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
    ef.otherLabel=otherLabel; otherLabel:SetScript("OnClick",function() if not ef.readOnly then other:Click() end end)
    local overflow=NewCheck(ef,nil); overflow:SetPoint("TOPLEFT",ef,"TOPLEFT",140,-49); ef.overflowCB=overflow
    local overflowText=CreateGBSFontString(ef,"OVERLAY"); overflowText:SetPoint("LEFT",overflow,"RIGHT",6,0); overflowText:SetText("Overflow")
    local overflowLabel=CreateFrame("Button",nil,ef); overflowLabel:SetPoint("LEFT",overflow,"RIGHT",2,0); overflowLabel:SetSize(82,18); ef.overflowLabel=overflowLabel; overflowLabel:SetScript("OnClick",function() if not ef.readOnly then overflow:Click() end end)
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
        button:SetScript("OnClick",function() if not ef.readOnly then cb:Click() end end)
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
        if ef.readOnly then return end
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
        local selected,isOther,isOverflow=ef.GetSelection(); local ok,err=GBS.Shared:SaveTab(ef._tabIdx,selected,isOther,isOverflow,"col",function() ef:Hide(); UpdateBankPanelTabs() end); if not ok then Chat(err,1,0.4,0.4) end
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
        ef.embedded=true; ef:SetParent(cf); ef:ClearAllPoints(); ef:SetPoint("TOPLEFT",cf,"TOPLEFT",10,-91)
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


GBS.Bank = { frame=nil, currentTab=1, slotButtons={}, tabButtons={}, bagHooked=false }
function GBS.Bank:CanForceUnlockFromSort()
    local shared=GBS.Shared
    if not self:IsOpen() or not shared or (shared.state~="locked" and shared.state~="corrupt") or shared.closing or shared.pending then return false end
    if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange or GBS.routingPrompt then return false end
    if not shared:ForeignLock() or not shared:CanWriteLockTab() or type(IsGuildLeader)~="function" then return false end
    local ok,leader=pcall(IsGuildLeader)
    return ok and leader and leader~=0 or false
end
function GBS.Bank:RequestSortForceUnlock()
    if not self:CanForceUnlockFromSort() then return end
    if type(StaticPopup_Show)~="function" then Chat("Confirmation UI unavailable.",1,0.4,0.4); return end
    local lock=GBS.Shared.tabs[1].lock
    StaticPopup_Show("GBE_FORCE_UNLOCK",nil,nil,{sortUnlock=true,owner=lock.owner,token=lock.token})
end
function GBS.Bank:IsProcessing()
    return not not (GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange or GBS.routingPrompt or GBS.sortStartTab)
end
function GBS.Bank:ConfirmRouting(count,callback)
    if not self.routeWarning then
        local box=CreateGBSFrameBase("GBSRouteWarning",390,160,110)
        box:SetFrameStrata("FULLSCREEN_DIALOG"); box:SetToplevel(true)
        local title=CreateGBSFontString(box.titleBar,"OVERLAY"); title:SetPoint("LEFT",box.titleBar,"LEFT",8,0); title:SetText("|cffffd100Routing uses withdrawals|r")
        local text=CreateGBSFontString(box,"OVERLAY"); text:SetPoint("TOPLEFT",box,"TOPLEFT",14,-36); text:SetWidth(362); text:SetJustifyH("LEFT"); text:SetWordWrap(true); box.text=text
        local yes=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); yes:SetSize(105,22); yes:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-124,12); yes:SetText("Continue"); StyleButton(yes,true)
        local no=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); no:SetSize(100,22); no:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-14,12); no:SetText("Cancel sort"); StyleButton(no,false)
        box.yes=yes; box.no=no
        local function finish(accept)
            local done=box.callback; box.callback=nil; box:Hide(); if done then done(accept) end
        end
        yes:SetScript("OnClick",function() finish(true) end); no:SetScript("OnClick",function() finish(false) end)
        box.close:SetScript("OnClick",function() finish(false) end)
        box:Hide(); self.routeWarning=box
    end
    local box=self.routeWarning; box.callback=callback; box:ClearAllPoints(); box:SetPoint("CENTER",self.frame,"CENTER",0,0)
    box.text:SetText(count.." potential cross-tab move"..(count==1 and "" or "s")..". Routing may reduce your withdrawal allowance. Fewer than 1000 remaining prevents routing out. Stacking and ordering require deposit permission.")
    box:Show()
end

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
local function ReverseActivityLines(lines)
    for i=1,math.floor(#lines/2) do
        local j=#lines-i+1; lines[i],lines[j]=lines[j],lines[i]
    end
    return lines
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
    return ReverseActivityLines(lines)
end
local function MoneyActivity()
    local n=ActivityCount(GetNumGuildBankMoneyTransactions)
    if not n or type(GetGuildBankMoneyTransaction)~="function" then return {"Money log unavailable."} end
    local lines={}
    for i=1,n do
        local ok,kind,name,amount,year,month,day,hour=pcall(GetGuildBankMoneyTransaction,i)
        if ok and kind then
            local labels={deposit="deposited",withdraw="withdrew",withdrawal="withdrew",repair="repaired",withdrawForTab="withdrew for a tab",buyTab="purchased a tab",depositSummary="deposited"}
            lines[#lines+1]=(name or "Unknown").." "..(labels[kind] or tostring(kind)).." "..Money.Full(amount)..ActivityAge(year,month,day,hour)
        end
    end
    if #lines==0 then lines[1]="No money transactions in the client cache." end
    return ReverseActivityLines(lines)
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
        if active then button:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1)
        else button:SetBackdropColor(E.bg2[1],E.bg2[2],E.bg2[3],1) end
        button:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1)
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
    local scroll=CreateFrame("ScrollFrame","GBSInfoScroll",panel,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",panel,"TOPLEFT",4,-4); scroll:SetSize(SIDE_W-24,112); SkinScroll(scroll)
    local canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(SIDE_W-44,112); scroll:SetScrollChild(canvas); info.canvas=canvas
    local editArea=CreateFrame("Frame",nil,canvas); editArea:SetSize(SIDE_W-44,GBS_FONT_SIZE+2); editArea:SetPoint("TOPLEFT",canvas,"TOPLEFT",0,0); info.editArea=editArea
    local edit=CreateFrame("EditBox",nil,canvas); edit:SetMultiLine(true); edit:SetFontObject("GBSFont"); edit:SetTextInsets(0,0,0,0); edit:SetJustifyV("TOP"); edit:SetSize(SIDE_W-44,GBS_FONT_SIZE+2); edit:SetPoint("TOPLEFT",editArea,"TOPLEFT",0,0); edit:SetPoint("BOTTOMRIGHT",editArea,"BOTTOMRIGHT",0,0); edit:SetAutoFocus(false); edit:SetMaxLetters(500); edit:EnableMouse(true); info.edit=edit; info.scroll=scroll
    local managed=CreateGBSFontString(canvas,"OVERLAY"); managed:SetPoint("TOPLEFT",editArea,"BOTTOMLEFT",0,-(GBS_FONT_SIZE+2)); managed:SetWidth(SIDE_W-44); managed:SetWordWrap(true); managed:SetJustifyH("LEFT"); managed:SetJustifyV("TOP"); managed:SetTextColor(0.55,0.55,0.55); managed:SetText("GuildBankEnhanced:\nLoading..."); info.managed=managed
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel",function(self,d) self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-d*32))) end)
    local status=CreateGBSFontString(panel,"OVERLAY"); status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",8,8); status:SetWidth(SIDE_W-16); status:SetJustifyH("LEFT"); status:SetText(""); info.status=status
    info.SetStatus=function(text)
        status:SetText(text or "")
        if info.resize then info.resize(panel:GetHeight()) end
    end
    local save=CreateFrame("Button",nil,info.header,"UIPanelButtonTemplate"); save:SetSize(44,18); save:SetPoint("RIGHT",info.header,"RIGHT",-24,0); save:SetText("Save"); StyleButton(save,true); save:Hide(); info.save=save
    local reload=CreateFrame("Button",nil,info.header,"UIPanelButtonTemplate"); reload:SetSize(52,18); reload:SetPoint("RIGHT",save,"LEFT",-4,0); reload:SetText("Reload"); StyleButton(reload,false); reload:Hide(); info.reload=reload
    reload:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Reload tab info",1,0.82,0); GameTooltip:AddLine("Discard this unsaved draft and load the latest bank description.",1,1,1,true); GameTooltip:Show() end)
    reload:SetScript("OnLeave",function() GameTooltip:Hide() end)
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
        if draft and draft.loaded and draft.conflict then reload:Show() else reload:Hide() end
        if draft and draft.loaded and not draft.conflict and not draft.reloadAwaiting and not GBS.isRunning and canEdit(tab) then save:Enable() else save:Disable() end
        if draft and draft.reloadAwaiting then reload:Disable() else reload:Enable() end
    end
    info.UpdateSave=updateSave
    function info.WriteFailed(tab,message)
        local d=bank.infoDrafts[tab]
        if not d or not d.sent then return end
        d.sent=nil; d.saveError=message
        if tab==bank.currentTab then info.SetStatus(message); updateSave() end
    end
    edit:EnableMouse(false)
    edit:SetScript("OnEscapePressed",function() edit:ClearFocus() end)
    local function countInfoLines(text,width)
        local lines=0
        for line in ((text or "").."\n"):gmatch("(.-)\n") do local _,n=WrapRowText(line,width); lines=lines+n end
        return math.max(1,lines)
    end
    local resizingInfo=false
    local function resizeInfoText()
        if resizingInfo then return end
        resizingInfo=true
        local width=SIDE_W-54; local lineHeight=GBS_FONT_SIZE+2
        local editHeight=countInfoLines(edit:GetText() or "",width)*lineHeight
        local managedHeight=countInfoLines(managed:GetText() or "",width)*lineHeight+4
        editArea:SetHeight(editHeight); edit:SetHeight(editHeight); managed:SetHeight(managedHeight)
        local actual=edit:GetHeight() or 0
        if actual>editHeight then editArea:SetHeight(actual) end
        canvas:SetHeight(math.max(scroll:GetHeight(),editArea:GetHeight()+lineHeight+managedHeight+8))
        resizingInfo=false
    end
    edit:HookScript("OnSizeChanged",function()
        if not resizingInfo then
            local actual=edit:GetHeight() or 0
            if actual>editArea:GetHeight() then editArea:SetHeight(actual) end
            canvas:SetHeight(math.max(scroll:GetHeight(),editArea:GetHeight()+(GBS_FONT_SIZE+2)+(managed:GetHeight() or 0)+8))
        end
    end)
    local function showManaged(parsed)
        local lines=InfoDisplay.Settings(parsed,GBS.SortDirections)
        local shared=GBS.Shared
        lines[#lines+1]=""; lines[#lines+1]=InfoDisplay.Lock(shared)
        local tab=bank.currentTab
        local ok,_,_,view,deposit,allowed,remaining
        if type(GetGuildBankTabInfo)=="function" then ok,_,_,view,deposit,allowed,remaining=pcall(GetGuildBankTabInfo,tab) end
        if not ok then lines[#lines+1]="Access: unknown"
        else
            local editInfo=canEdit(tab)
            local native
            if type(GetCurrentGuildBankTab)=="function" then local valid,value=pcall(GetCurrentGuildBankTab); if valid then native=value end end
            local ready=shared and not shared:Reason() and CanUseAutomation(tab)
            local access,actions,routeOut=BankAccess.Info(view,deposit,editInfo,remaining,native==tab,ready,not (shared and shared:HasUncertainAssignments()))
            lines[#lines+1]=access; lines[#lines+1]=actions
            if routeOut then lines[#lines+1]="* Destination requires deposit access." end
        end
        managed:SetText(table.concat(lines,"\n")); resizeInfoText()
    end
    info.ShowManaged=showManaged
    info.resize=function(height)
        local message=status:GetText() or ""
        local bottom=8 -- same four-pixel top and bottom inset as Item Log
        if message~="" then bottom=math.max(bottom,16+countInfoLines(message,SIDE_W-16)*(GBS_FONT_SIZE+2)) end
        scroll:SetHeight(math.max(1,height-bottom)); resizeInfoText()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()))
    end
    edit:SetScript("OnTextChanged",function(self,userInput)
        local text=self:GetText() or ""; resizeInfoText()
        if info.setting then return end
        local d=bank.infoDrafts[bank.currentTab]; if not d or not d.loaded then return end
        d.revision=(d.revision or 0)+1; d.reloadAwaiting=nil; d.saveError=nil; d.text=text
        if d.conflict and d.latestDescription~=nil and text==d.latestDescription then
            d.base=d.latestRaw; d.baseDescription=d.latestDescription; d.conflict=nil; d.latestRaw=nil; d.latestDescription=nil
        end
        d.dirty=d.text~=d.baseDescription; updateSave()
        if d.conflict then info.SetStatus("Info changed remotely; reload or review your draft.")
        elseif d.dirty then info.SetStatus("Unsaved changes") else info.SetStatus("") end
    end)
    save:SetScript("OnClick",function()
        local tab=bank.currentTab; local d=bank.infoDrafts[tab]
        if not bank:IsOpen() or GBS.isRunning or not d or not d.loaded then info.SetStatus("Wait for tab info to load."); return end
        if not d.dirty then return end
        if d.conflict then info.SetStatus("Info changed remotely; reload or review your draft."); return end
        if not canEdit(tab) then info.SetStatus("You cannot edit this tab's info."); return end
        local reason=not GBS.Shared and "Shared settings unavailable." or (GBS.Shared and GBS.Shared:Reason())
        if reason then info.SetStatus(reason); return end
        local ok,latest=pcall(GetGuildBankText,tab)
        if ok and latest==nil then latest="" end
        if not ok or type(latest)~="string" then info.SetStatus("Tab info is unavailable."); return end
        if latest~=d.base then
            info.SetStatus("Refreshing tab info before saving...")
            if type(QueryGuildBankText)=="function" then pcall(QueryGuildBankText,tab) end
            return
        end
        d.saveError=nil; d.sent=d.text
        local sent,err=GBS.Shared:SaveDescription(tab,d.text)
        if not sent then d.sent=nil; info.SetStatus(err); return end
        info.SetStatus("Saving tab info...")
    end)
    reload:SetScript("OnClick",function()
        local tab=bank.currentTab; local draft=bank.infoDrafts[tab]
        if not draft or not draft.conflict or draft.reloadAwaiting then return end
        if not info.reloadDialog then
            local box=CreateGBSFrameBase("GBEInfoReloadConfirm",330,112,110)
            box:SetFrameStrata("FULLSCREEN_DIALOG"); box:SetToplevel(true); box:ClearAllPoints(); box:SetPoint("CENTER",bank.frame,"CENTER",0,0); box:Hide(); info.reloadDialog=box
            local title=CreateGBSFontString(box.titleBar,"OVERLAY"); title:SetPoint("LEFT",box.titleBar,"LEFT",8,0); title:SetText("|cffffd100Reload tab info|r")
            local text=CreateGBSFontString(box,"OVERLAY"); text:SetPoint("TOPLEFT",box,"TOPLEFT",12,-34); text:SetWidth(306); text:SetJustifyH("LEFT"); text:SetText("Discard your unsaved description and load the latest bank info?")
            local yes=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); yes:SetSize(90,22); yes:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-108,10); yes:SetText("Reload"); StyleButton(yes,true); box.confirm=yes
            local no=CreateFrame("Button",nil,box,"UIPanelButtonTemplate"); no:SetSize(90,22); no:SetPoint("BOTTOMRIGHT",box,"BOTTOMRIGHT",-10,10); no:SetText("Cancel"); StyleButton(no,false); no:SetScript("OnClick",function() box:Hide() end); box.cancel=no
            yes:SetScript("OnClick",function()
                local target,expected,revision=box.target,box.draft,box.revision; box:Hide()
                if not bank:IsOpen() or bank.infoDrafts[target]~=expected or (expected.revision or 0)~=revision then
                    if bank.currentTab==target then info.SetStatus("Draft changed; review it before reloading.") end; return
                end
                if type(QueryGuildBankText)~="function" then if bank.currentTab==target then info.SetStatus("Tab info is unavailable.") end; return end
                expected.reloadAwaiting=revision; expected.reloadElapsed=0
                if not pcall(QueryGuildBankText,target) then expected.reloadAwaiting=nil; if bank.currentTab==target then info.SetStatus("Could not refresh tab info.") end; return end
                if bank.currentTab==target then info.SetStatus("Refreshing tab info..."); updateSave() end
            end)
        end
        local box=info.reloadDialog; box.target=tab; box.draft=draft; box.revision=draft.revision or 0; box:Show()
    end)
    reload:SetScript("OnUpdate",function(_,elapsed)
        local tab=bank.currentTab; local d=bank.infoDrafts[tab]
        if not d or d.reloadAwaiting==nil then return end
        d.reloadElapsed=(d.reloadElapsed or 0)+elapsed
        if d.reloadElapsed>=8 then d.reloadAwaiting=nil; info.SetStatus("Refresh timed out; your draft was kept."); updateSave() end
    end)
    f.activity={money=money,items=items,info=info}
    local DIVIDER_HEIGHT=6
    local MIN_CONTENT=3*(GBS_FONT_SIZE+2)+32
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
            info.setting=true; edit:SetText(draft and draft.text or ""); info.setting=false; showManaged(GBS.Shared and GBS.Shared.tabs[tab]); updateSave()
            if draft and draft.loaded and canEdit(tab) and not GBS.isRunning then edit:EnableMouse(true)
            else edit:EnableMouse(false) end
            info.SetStatus(InfoDraft.Status(draft,false))
            if GBS.tabNames[tab] and type(QueryGuildBankText)=="function" then pcall(QueryGuildBankText,tab) else info.SetStatus("Tab info unavailable.") end
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
            local parsed,parseErr=GuildBankSorterModules.SharedInfo.Parse(text)
            if not parsed and GBS.Shared and GBS.Shared.corrupt and GBS.Shared.corrupt[tab] and GBS.Shared.raw[tab]==text then parsed=GBS.Shared.tabs[tab] end
            if not parsed then if tab==bank.currentTab then info.SetStatus(parseErr); edit:EnableMouse(false); save:Disable() end; return end
            local d=bank.infoDrafts[tab]
            if not d then d={}; bank.infoDrafts[tab]=d end
            InfoDraft.Update(d,text,parsed.description)
            if tab==bank.currentTab then showManaged(parsed) end
            if tab==bank.currentTab then updateSave() end
            if tab==bank.currentTab and side:IsVisible() and not state.info then
                info.setting=true; edit:SetText(d.text or ""); info.setting=false
                info.SetStatus(InfoDraft.Status(d,true))
                if not GBS.isRunning and canEdit(tab) then edit:EnableMouse(true)
                else edit:ClearFocus(); edit:EnableMouse(false) end
            end
        elseif event=="GUILDBANK_TEXT_CHANGED" and not GBS.Shared and not GBS.isRunning and tonumber(tab)==bank.currentTab and side:IsVisible() and not state.info and type(QueryGuildBankText)=="function" then
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
    -- Do not repeatedly read tab information on every progress tick. Refresh
    -- the title only when the overall sort/routing state changes.
    local active=self:IsProcessing()
    if f.titleOperationActive~=active then
        f.titleOperationActive=active
        if self.RefreshAccessTitle then self:RefreshAccessTitle() end
    end
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

-- The native panel closes the bank on hide; intercept Escape before that happens.
function GBS.Bank:EscapeGameHandlers()
    for _,name in ipairs({"StaticPopup_EscapePressed","CloseMenus","CloseCalendarMenus","SpellStopCasting","SpellStopTargeting"}) do
        local handler=_G[name]
        if type(handler)=="function" then
            local ok,handled=pcall(handler)
            if ok and handled then return true end
        end
    end
    return false
end
function GBS.Bank:DismissEscapeWindow()
    if StackSplitFrame and StackSplitFrame.IsShown and StackSplitFrame:IsShown() then StackSplitFrame:Hide(); return true end
    local info=self.frame and self.frame.activity and self.frame.activity.info
    if info and info.reloadDialog and info.reloadDialog:IsShown() then info.reloadDialog:Hide(); return true end
    if self.routeWarning and self.routeWarning:IsShown() then
        if self.routeWarning.no then self.routeWarning.no:Click() end
        return true
    end
    if GBS.Shared and GBS.Shared.versionDialog and GBS.Shared.versionDialog:IsShown() then GBS.Shared.versionDialog:Hide(); return true end
    if GBS.Shared and GBS.Shared.reviewDialog and GBS.Shared.reviewDialog:IsShown() then local d=GBS.Shared.reviewDialog; GBS.Shared:SkipReadOnly(d.target,d.expectedRaw); return true end
    if GBS.Shared and GBS.Shared.dialog and GBS.Shared.dialog:IsShown() then local d=GBS.Shared.dialog; GBS.Shared:SkipOrganizer(d.target,d.expectedRaw); return true end
    if self.tabConfig and self.tabConfig.picker and self.tabConfig.picker:IsShown() then self.tabConfig.picker:Hide(); return true end
    for _,window in ipairs({self.purchaseDialog or false,self.moneyBox or false,GBS.copyFrame or false,self.tabConfig or false}) do
        if window and window.IsShown and window:IsShown() then window:Hide(); return true end
    end
    if info and info.edit and info.edit.HasFocus and info.edit:HasFocus() then info.edit:ClearFocus(); return true end
    return false
end
function GBS.Bank:EscapePressed()
    if not self:IsOpen() or self:EscapeGameHandlers() or self:DismissEscapeWindow() then return end
    self:RequestClose()
end
function GBS.Bank:EnableEscapeHandling()
    if self.escapeUnavailable then return end
    if type(SetOverrideBindingClick)~="function" or type(ClearOverrideBindings)~="function" or type(RegisterStateDriver)~="function" then
        self.escapeUnavailable=true; Chat("Escape cannot safely wait for lock release here; use the bank's X button.",1,0.7,0.3); return
    end
    if type(GetBindingAction)=="function" then
        local ok,action=pcall(GetBindingAction,"ESCAPE",true)
        if not ok or action~="TOGGLEGAMEMENU" then
            Chat("Escape has a custom binding; use the bank's X button to close safely.",1,0.7,0.3); return
        end
    end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then
        Chat("In combat, use the bank's X button to release the lock before closing.",1,0.7,0.3); return
    end
    if not self.escapeOwner then
        local ok,owner=pcall(CreateFrame,"Frame","GBEEscapeBindingOwner",UIParent,"SecureHandlerStateTemplate")
        if not ok or not owner or type(owner.SetFrameRef)~="function" or type(owner.SetAttribute)~="function" then
            self.escapeUnavailable=true; Chat("Escape cannot safely wait for lock release here; use the bank's X button.",1,0.7,0.3); return
        end
        local button=CreateFrame("Button","GBEEscapeClose",UIParent)
        button:SetSize(1,1); button:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",-100,-100); button:EnableMouse(false)
        button:RegisterForClicks("LeftButtonUp"); button:SetScript("OnClick",function() GBS.Bank:EscapePressed() end)
        local setup=pcall(function()
            owner:SetFrameRef("bank",self.frame)
            owner:SetAttribute("_onstate-gbeescape",[[
                self:ClearBindings()
                local bank=self:GetFrameRef("bank")
                if newstate=="safe" and bank and bank:IsShown() then
                    self:SetBindingClick(false,"ESCAPE","GBEEscapeClose","LeftButton")
                end
            ]])
            RegisterStateDriver(owner,"gbeescape","[combat] combat; safe")
        end)
        if not setup then pcall(ClearOverrideBindings,owner); self.escapeUnavailable=true; Chat("Escape cannot safely wait for lock release here; use the bank's X button.",1,0.7,0.3); return end
        self.escapeOwner=owner; self.escapeButton=button
    end
    local ok=pcall(SetOverrideBindingClick,self.escapeOwner,false,"ESCAPE","GBEEscapeClose","LeftButton")
    if not ok then Chat("Escape interception failed; use the bank's X button to close.",1,0.7,0.3) end
end
function GBS.Bank:DisableEscapeHandling()
    if not self.escapeOwner or type(ClearOverrideBindings)~="function" then return end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then return end -- secure state driver clears in combat
    local ok=pcall(ClearOverrideBindings,self.escapeOwner)
    if not ok then Chat("Could not restore Escape binding; try /reload after combat.",1,0.7,0.3) end
end

function GBS.Bank:RequestClose(afterClose)
    if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange or GBS.routingPrompt then GBS:Cancel() end
    local function finish()
        local ok=type(CloseGuildBankFrame)=="function" and pcall(CloseGuildBankFrame)
        if ok then if self.frame then self.frame:Hide() end
        else Chat("Could not close the bank; please close and reopen it manually.",1,0.7,0.3) end
        if afterClose then afterClose(ok) end
    end
    if GBS.Shared then
        if not GBS.Shared.closing and (GBS.Shared.mine or GBS.Shared.pending) then Chat("Finishing bank updates and releasing the lock before closing...",0.8,0.8,0.8) end
        GBS.Shared:RequestClose(finish)
    else finish() end
end
function GBS.Bank:HandleActivityEvent(frame,event,...)
    local accepted=true
    if GBS.Shared then
        if event=="GUILDBANK_UPDATE_TEXT" then accepted=GBS.Shared:Receive(...)
        elseif event=="GUILDBANK_TEXT_CHANGED" then GBS.Shared:Changed(...) end
    end
    if accepted~=false and frame.ActivityEvent then frame.ActivityEvent(event,...) end
end
function GBS.Bank:ObserveAllowanceEvent(event)
    local scan=GBS.routing and GBS.routing.allowanceScan
    if not scan or (event~="GUILDBANKBAGSLOTS_CHANGED" and event~="GUILDBANK_UPDATE_TABS") then return end
    scan.quiet=0
    if scan.phase=="waiting" and event=="GUILDBANKBAGSLOTS_CHANGED" then scan.seen=true end
end
function GBS.Bank:ObserveSlotCount(event,native)
    if event=="GUILDBANKBAGSLOTS_CHANGED" and not GBS.isRunning and self.currentTab and GBS.tabNames[self.currentTab] and (not native or native==self.currentTab) then
        self.knownCounts=self.knownCounts or {}; self.knownCounts[self.currentTab]=CountItemsInTab(self.currentTab)
    end
end
function GBS.Bank:RefreshAfterBankEvent(frame,event,native)
    if event=="GUILD_ROSTER_UPDATE" and GBS.Shared then GBS.Shared:Roster() elseif event=="WHO_LIST_UPDATE" and GBS.Shared then GBS.Shared:Who() end
    if GBS.Shared and (event=="GUILD_ROSTER_UPDATE" or event=="GUILDBANK_UPDATE_TABS") then GBS.Shared:RefreshPermissions() end
    if self.Refresh then self:Refresh() end
    if not GBS.isRunning and frame.activity and frame.activity.info and frame.activity.info.ShowManaged then frame.activity.info.ShowManaged(GBS.Shared and GBS.Shared.tabs[self.currentTab]) end
    if not GBS.isRunning and (event=="GUILDBANK_UPDATE_TABS" or (event=="GUILDBANKBAGSLOTS_CHANGED" and native and native~=self.currentTab)) then self:ScheduleSelectionRefresh(false) end
end
function GBS.Bank:HandleBankEvent(frame,event,...)
    if not frame:IsVisible() then return end
    self:ObserveAllowanceEvent(event)
    local native
    if type(GetCurrentGuildBankTab)=="function" then local ok,value=pcall(GetCurrentGuildBankTab); if ok then native=value end end
    self:ObserveSlotCount(event,native)
    if event=="GUILDBANKLOG_UPDATE" or event=="GUILDBANK_UPDATE_TEXT" or event=="GUILDBANK_TEXT_CHANGED" then
        self:HandleActivityEvent(frame,event,...); return
    end
    self:RefreshAfterBankEvent(frame,event,native)
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
    local access=CreateGBSFontString(tb,"OVERLAY"); access:SetPoint("LEFT",ttl,"RIGHT",4,0); access:SetPoint("RIGHT",tb,"RIGHT",-26,0); access:SetJustifyH("RIGHT"); access:SetWordWrap(false); access:SetTextColor(0.65,0.65,0.65); access:SetText(""); f.accessTitle=access
    local close=CreateTitleClose(f,tb)
    close:SetScript("OnClick", function() GBS.Bank:RequestClose() end)
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
            elseif btn=="RightButton" then GBS.Bank:OpenTabConfig(i)
            elseif CanViewTab(i) then GBS.Bank:SelectTab(i) end
        end); b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b:SetScript("OnEnter",function(s)
            local name=GBS.tabNames[i]; local viewable=name and CanViewTab(i)
            GBS.Bank:StyleTabButton(s,i,true)
            GameTooltip:SetOwner(s,"ANCHOR_TOP")
            if name then
                GameTooltip:AddLine(name,1,0.82,0)
                for _,line in ipairs(GBS.Assign:Describe(i)) do GameTooltip:AddLine(line,0.85,0.85,0.85) end
                if not CanUseAutomation(i) then GameTooltip:AddLine("Excluded from sorting and routing. Right-click to review.",1,0.7,0.3,true) end
                if viewable then GameTooltip:AddLine("Left-click: view  |  Right-click: configure tab",0.7,0.7,0.7)
                else GameTooltip:AddLine("No view permission. Right-click: inspect configuration.",0.7,0.7,0.7) end
            else GameTooltip:AddLine("Locked tab "..i,0.7,0.7,0.7); GameTooltip:AddLine("Click to view purchase options.",0.7,0.7,0.7) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(s) GBS.Bank:StyleTabButton(s,i,false); GameTooltip:Hide() end)
        self.tabButtons[i]=b
    end
    local grid=CreateFrame("Frame",nil,f); grid:SetPoint("TOPLEFT",f,"TOPLEFT",6,-75); grid:SetSize(GRID_W, GRID_H); grid:SetFrameLevel(f:GetFrameLevel()+2); f.grid=grid
    for i=1,98 do
        local r=(i-1)%BANK_ROWS; local c=math.floor((i-1)/BANK_ROWS)
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
            local tab=GBS.Bank.currentTab; if not tab or not GBS.tabNames[tab] or not CanViewTab(tab) then return end
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
    -- One row geometry for every control: five equal panels plus one square,
    -- separated by five identical gaps. All share the same top baseline.
    local rowHeight,rowGap=22,4
    local buttonWidth=(GRID_W-rowHeight-5*rowGap)/5
    local rowTop=-(26-rowHeight)/2
    local sideBtn=CreateFrame("Button",nil,bot,"UIPanelButtonTemplate"); sideBtn:SetSize(rowHeight,rowHeight); sideBtn:SetPoint("TOPLEFT",bot,"TOPLEFT",0,rowTop); sideBtn:SetText("<"); StyleButton(sideBtn,false); f.activityBtn=sideBtn
    sideBtn:SetScript("OnClick",function() GBS.Bank:ToggleActivityPanel() end)
    sideBtn:HookScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Item log and tab info",1,0.82,0); GameTooltip:Show() end)
    sideBtn:HookScript("OnLeave",function() GameTooltip:Hide() end)
    local sortBtn=CreateFrame("Button",nil,bot,"UIPanelButtonTemplate"); sortBtn:SetSize(buttonWidth,rowHeight); sortBtn:SetPoint("TOPLEFT",bot,"TOPLEFT",rowHeight+rowGap,rowTop); sortBtn:SetText("SORT"); StyleButton(sortBtn,true)
    sortBtn:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1)
    sortBtn:HookScript("OnEnable",function(s) s:SetBackdropBorderColor(E.border[1],E.border[2],E.border[3],1) end)
    sortBtn:SetScript("OnClick", function() GBS:StartSort() end); f.sortBtn=sortBtn; AddSortBlocker(sortBtn,nil,nil,true)
    sortBtn:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Sort guild bank",1,0.82,0); GameTooltip:AddLine("Immediately scans, routes, stacks and orders items.",1,1,1,true); GameTooltip:AddLine("Guild master: right-click Sort to force unlock when another player holds the lock.",0.8,0.8,0.8,true); GameTooltip:Show() end)
    sortBtn:SetScript("OnLeave",function() GameTooltip:Hide() end); UpdateSortControls()
    local moneyBG=CreateFrame("Button",nil,bot); moneyBG:SetSize(buttonWidth,rowHeight); moneyBG:SetPoint("TOPLEFT",bot,"TOPLEFT",rowHeight+rowGap+4*(buttonWidth+rowGap),rowTop); StyleBackdrop(moneyBG,1); moneyBG:SetBackdropColor(0.07,0.07,0.07,1)
    local money=CreateGBSFontString(moneyBG,"OVERLAY"); money:SetPoint("LEFT",moneyBG,"LEFT",4,0); money:SetPoint("RIGHT",moneyBG,"RIGHT",-4,0); money:SetWordWrap(false); money:SetFont(GBS_FONT,GBS_FONT_SIZE,""); money:SetJustifyH("CENTER"); money:SetText(""); f.money=money; f.moneyBG=moneyBG
    moneyBG:RegisterForClicks("LeftButtonUp","RightButtonUp")
    moneyBG:SetScript("OnClick",function(_,button)
        if GBS.isRunning then return end
        if button=="LeftButton" then GBS.Bank:OpenMoneyBox("deposit") elseif button=="RightButton" then GBS.Bank:OpenMoneyBox("withdraw") end
    end)
    moneyBG:SetScript("OnEnter",function(self)
        local copper=0; if type(GetGuildBankMoney)=="function" then local ok,v=pcall(GetGuildBankMoney); if ok and type(v)=="number" then copper=math.max(0,math.floor(v)) end end
        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Bank balance",1,0.82,0)
        GameTooltip:AddLine(Money.Color(Money.Full(copper)),1,1,1)
        local limit
        if type(GetGuildBankWithdrawMoney)=="function" then local ok,v=pcall(GetGuildBankWithdrawMoney); if ok and type(v)=="number" then limit=v end end
        local limitText=not limit and "Unknown" or (limit<0 or limit>=4294967295) and "Unlimited" or Money.Full(limit)
        GameTooltip:AddLine("Withdrawal remaining: "..limitText,0.8,0.8,0.8)
        GameTooltip:AddLine("Left-click: Deposit",0.8,0.8,0.8); GameTooltip:AddLine("Right-click: Withdraw",0.8,0.8,0.8); GameTooltip:Show()
    end)
    moneyBG:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local settings=CreateFrame("Frame",nil,bot); settings:SetSize(3*buttonWidth+2*rowGap,rowHeight); settings:SetPoint("TOPLEFT",bot,"TOPLEFT",rowHeight+rowGap+buttonWidth+rowGap,rowTop); f.settings=settings
    BuildDelays(settings,buttonWidth,rowHeight,rowGap); f.moveSlider=settings.moveSlider; f.scanSlider=settings.scanSlider; f.infoSlider=settings.infoSlider
    f:SetScript("OnShow", function() GBS.Bank:Refresh(); GBS.Bank:HookBags(); if GBS.Bank.RestoreActivityPanel then GBS.Bank:RestoreActivityPanel() end end)
    f:SetScript("OnHide", function()
        GBS.Bank:DisableEscapeHandling()
        GBS.Bank:EmergencyRelease()
        if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange or GBS.routingPrompt then GBS:Cancel() end
        CloseOurSplit()
        if f.settings and f.settings.delayPopups then for _,popup in ipairs(f.settings.delayPopups) do popup:Hide() end end
        if GBS.copyFrame then GBS.copyFrame:Hide() end; if GBS.SortDirMenu then GBS.SortDirMenu:Hide() end
        if GBS.Shared and GBS.Shared.reviewDialog then GBS.Shared.reviewDialog:Hide() end
        if f.activity and f.activity.info.reloadDialog then f.activity.info.reloadDialog:Hide() end
        if GBS.Bank.activityPanel then GBS.Bank.activityPanel:Hide() end
        GBS.Bank.infoDrafts={}; if f.activity then f.activity.info.UpdateSave() end
    end)
    f:SetScript("OnEvent",function(frame,event,...) GBS.Bank:HandleBankEvent(frame,event,...) end)
    f:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED"); f:RegisterEvent("GUILDBANK_ITEM_LOCK_CHANGED"); f:RegisterEvent("GUILDBANK_UPDATE_TABS"); f:RegisterEvent("GUILDBANK_UPDATE_MONEY")
    f:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY"); f:RegisterEvent("GUILD_ROSTER_UPDATE"); f:RegisterEvent("WHO_LIST_UPDATE"); f:RegisterEvent("GUILDBANKLOG_UPDATE"); f:RegisterEvent("GUILDBANK_UPDATE_TEXT"); f:RegisterEvent("GUILDBANK_TEXT_CHANGED")
    self.frame=f
    GBS.Bank:BuildAttachedSections(f)
    GBS.Bank:BuildActivitySections(f); f.LayoutAttached()
    GBS.Bank:BuildProcessingDialog(f)
    UpdateSortControls(); return f
end
function GBS.Bank:CreateMoneyBox()
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
    return self.moneyBox
end
function GBS.Bank:OpenMoneyBox(mode)
    if self.purchaseDialog then self.purchaseDialog:Hide() end
    if GBS.assignFrame then GBS.assignFrame:Hide() end
    if self.tabConfig then self.tabConfig:Hide() end
    if not self.moneyBox then self:CreateMoneyBox() end
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
                GBS.Bank.purchasePending=nil
                GBS.Bank:RequestClose(function(ok)
                    if ok then Chat("Tab purchased. Please reopen the guild bank.",0.8,1,0.8)
                    else GBS.Bank.purchaseUnconfirmed=true; box.status:SetText("Please close and reopen the bank.") end
                end); return
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
        box.info:SetText("Purchase tab "..tab.." for "..Money.Price(cost).."?")
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
        ef.embeddedHeight=math.max(80,height-91-((message and message~="") and 24 or 10))
        ef.RebuildAssignLayout()
    end
end
local function ConfigSelectionKey(values,other,overflow,direction)
    local sorted={}; for _,value in ipairs(values or {}) do sorted[#sorted+1]=value end; table.sort(sorted)
    return table.concat(sorted,"\n").."|"..tostring(not not other).."|"..tostring(not not overflow).."|"..tostring(direction or "col")
end
function GBS.Bank:SyncTabConfigDraft(cf,editor)
    if cf:IsVisible() and cf.syncedSelection and editor and editor._tabIdx==cf.tab and editor.GetSelection then
        local bankKey=ConfigSelectionKey(GBS.Assign:Get(cf.tab),GBS.Assign:IsOther(cf.tab),GBS.Assign:IsOverflow(cf.tab),(GBS.tabDirections and GBS.tabDirections[cf.tab]) or "col")
        if bankKey~=cf.syncedSelection then
            local values,other,overflow=editor.GetSelection()
            if ConfigSelectionKey(values,other,overflow,cf.dirValue)==cf.syncedSelection then
                cf.dirValue=(GBS.tabDirections and GBS.tabDirections[cf.tab]) or "col"
                for _,opt in ipairs(GBS.SortDirections) do if opt.id==cf.dirValue then cf.direction:SetText(opt.label) end end
                GBS.OpenAssignEditor(cf.tab,true); cf.syncedSelection=bankKey
                if cf.syncNotice then cf.syncNotice=nil; cf.SetStatus("") end
            elseif not cf.syncNotice and (cf.status:GetText() or "")=="" then
                cf.syncNotice=true; cf.SetStatus("Shared settings changed; review your draft.")
            end
        end
    end
end
function GBS.Bank:SetTabConfigReadOnly(cf,editor,readonly)
    if editor and editor._tabIdx==cf.tab then
        editor.readOnly=readonly
        local function setEditable(control)
            if not control then return end
            if readonly then control:Disable() else control:Enable() end
        end
        for _,check in ipairs(editor.checks) do setEditable(check) end
        setEditable(editor.otherCB); setEditable(editor.overflowCB); setEditable(editor.otherLabel); setEditable(editor.overflowLabel); setEditable(editor.clearBtn)
        for _,sec in ipairs(editor.sections) do for _,label in ipairs(sec.subLabels) do setEditable(label.button) end end
        setEditable(cf.direction); setEditable(cf.iconBtn)
        cf.eb:EnableMouse(not readonly); if readonly then cf.eb:ClearFocus() end
    end
end
function GBS.Bank:UpdateTabConfigSave()
    local cf=self.tabConfig; if not cf or not cf.save then return end
    local editor=GBS.AssignEditor and GBS.AssignEditor.frame
    self:SyncTabConfigDraft(cf,editor)
    local readonly=GBS.Shared and (GBS.Shared:IsTabExcluded(cf.tab) or (GBS.Shared.corrupt and GBS.Shared.corrupt[1]) or not GBS.Shared:CanWriteLockTab() or not GBS.Shared:CanWriteTab(cf.tab)) or false
    cf.readOnly=readonly
    if cf.reviewBtn then if GBS.Shared and GBS.Shared:IsTabExcluded(cf.tab) then cf.reviewBtn:Show() else cf.reviewBtn:Hide() end end
    self:SetTabConfigReadOnly(cf,editor,readonly)
    local reason=not GBS.Shared and "Shared settings unavailable." or (GBS.Shared and GBS.Shared:Reason())
    local blocked=GBS.isRunning or GBS.routingPrompt or reason~=nil or readonly or cf.pending~=nil
    if blocked then cf.save:Disable(); if cf.save.sortBlocker then cf.save.sortBlocker:Show() end
    else cf.save:Enable(); if cf.save.sortBlocker then cf.save.sortBlocker:Hide() end end
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
        iconBtn:SetScript("OnClick",function() if not cf.readOnly then GBS.Bank:OpenIconPicker() end end)
        iconBtn:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Choose icon",1,1,1); GameTooltip:Show() end)
        iconBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
        local status=CreateGBSFontString(cf,"OVERLAY"); status:SetPoint("BOTTOMLEFT",cf,"BOTTOMLEFT",12,12); status:SetWidth(316); status:SetJustifyH("LEFT"); status:SetTextColor(1,0.4,0.3); cf.status=status
        cf.SetStatus=function(text) status:SetText(text); GBS.Bank:LayoutTabConfig() end
        local save=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); save:SetSize(69,22); save:SetPoint("TOPLEFT",cf,"TOPLEFT",182,-32); save:SetText("Save"); StyleButton(save,true); cf.save=save; AddSortBlocker(save,"Save unavailable",function() if cf.pending then return "Checking the tab name and icon." end; if GBS.Shared and GBS.Shared:IsTabExcluded(cf.tab) then return "Review the tab settings first." end; if GBS.Shared and not GBS.Shared:CanWriteTab(cf.tab) then return "Update tab text permission is required for this tab." end end); cf.saveBlocker=save.sortBlocker
        local cancel=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); cancel:SetSize(69,22); cancel:SetPoint("TOPLEFT",cf,"TOPLEFT",257,-32); cancel:SetText("Cancel"); StyleButton(cancel,false); cancel:SetScript("OnClick",function() cf:Hide() end); cf.cancel=cancel
        local dir=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); dir:SetSize(160,22); dir:SetPoint("TOPLEFT",cf,"TOPLEFT",12,-60); StyleButton(dir,false); cf.direction=dir
        dir:SetScript("OnClick",function()
            if cf.readOnly then return end
            for i,opt in ipairs(GBS.SortDirections) do if opt.id==cf.dirValue then local n=GBS.SortDirections[i%#GBS.SortDirections+1]; cf.dirValue=n.id; dir:SetText(n.label); return end end
        end)
        dir:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Sort direction for this tab",1,0.82,0); GameTooltip:AddLine("Click to cycle through directions.",1,1,1); GameTooltip:Show() end)
        dir:SetScript("OnLeave",function() GameTooltip:Hide() end)
        local review=CreateFrame("Button",nil,cf,"UIPanelButtonTemplate"); review:SetSize(144,22); review:SetPoint("TOPLEFT",cf,"TOPLEFT",182,-60); review:SetText("Review settings"); StyleButton(review,false); review:Hide(); cf.reviewBtn=review
        review:SetScript("OnClick",function() if GBS.Shared then GBS.Shared:ReviewTab(cf.tab) end end)
        cf:HookScript("OnHide",function() cf.pending=nil; if cf.picker then cf.picker:Hide() end; if GBS.assignFrame then GBS.assignFrame:Hide() end end)
        if UISpecialFrames then tinsert(UISpecialFrames,"GBSTabConfig") end
        cf:Hide(); self.tabConfig=cf
        local function CommitAssignments()
            local ef=GBS.AssignEditor.frame
            if not ef or ef._tabIdx~=cf.tab then cf.SetStatus("Tab editor unavailable."); return end
            local values,other,overflow=ef.GetSelection()
            local ok,err=GBS.Shared:SaveTab(cf.tab,values,other,overflow,cf.dirValue,function()
                cf:Hide(); GBS:CheckOtherTab(); GBS.Bank:Refresh(); Log("Tab settings saved.",0.6,1,0.6)
            end)
            if not ok then if GBS.Shared:Reason() then cf.SetStatus(""); GBS.Bank:UpdateTabConfigSave() else cf.SetStatus(err) end else cf.SetStatus("Saving shared settings...") end
        end
        save:SetScript("OnClick",function()
            local reason=not GBS.Shared and "Shared settings unavailable." or (GBS.Shared and GBS.Shared:Reason()); if reason or GBS.isRunning or GBS.routingPrompt or cf.pending or GBS.Shared:IsTabExcluded(cf.tab) or not GBS.Shared:CanWriteTab(cf.tab) then GBS.Bank:UpdateTabConfigSave(); return end
            local name=Trim(cf.eb:GetText() or ""); local iconIndex=cf._iconIndex
            if name=="" then cf.SetStatus("Enter a tab name."); return end
            local currentName,currentIcon=GetTabInfo(cf.tab)
            if name==currentName and (not iconIndex or GuildIconName(currentIcon)==GuildIconName(GetMacroItemIconInfo(iconIndex))) then
                CommitAssignments(); return
            end
            if not iconIndex then cf.SetStatus("Select an icon before saving."); return end
            if type(CanEditGuildBankTabInfo)=="function" and not CanEditGuildBankTabInfo() then cf.SetStatus("You do not have permission to edit tabs."); return end
            if type(SetGuildBankTabInfo)~="function" then cf.SetStatus("Tab editing is unavailable."); return end
            local ok,err=pcall(SetGuildBankTabInfo,cf.tab,name,iconIndex)
            if not ok then cf.SetStatus("Save failed; see chat."); Chat(tostring(err),1,0.4,0.4); return end
            cf.pending={name=name,tab=cf.tab,iconName=GuildIconName(GetMacroItemIconInfo(iconIndex)),elapsed=0,queried=false}
            GBS.Bank:UpdateTabConfigSave(); cf.SetStatus("Checking tab name...")
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
                    self.pending=nil; GBS.Bank:UpdateTabConfigSave(); CommitAssignments(); GBS.Bank:Refresh()
                    Chat("Tab details appear updated. Reopen the bank to confirm they persisted.",0.8,0.8,0.8)
                    return
                end
            end
            if pending.elapsed>=4 then
                self.pending=nil; GBS.Bank:UpdateTabConfigSave()
                self.SetStatus("Change not confirmed; see chat."); Chat("Tab change not confirmed. The client or server may have rejected the name or icon.",1,0.6,0.2)
            end
        end)
    end
    local cf=self.tabConfig; cf.tab=tab; cf.pending=nil
    cf.dirValue=(GBS.tabDirections and GBS.tabDirections[tab]) or "col"
    for _,opt in ipairs(GBS.SortDirections) do if opt.id==cf.dirValue then cf.direction:SetText(opt.label) end end
    self:LayoutTabConfig()
    local name,icon=GetTabInfo(tab); cf.eb:SetText(name or "")
    cf.catalog,cf.catalogAvailable=GetGuildIconCatalog()
    cf._iconIndex=FindGuildIconIndex(icon,cf.catalog)
    cf.iconBtn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    cf.SetStatus("")
    cf.title:SetText("|cffffd100Configure Tab "..tab.."|r"); cf:Show(); GBS.OpenAssignEditor(tab,true); cf.syncNotice=nil; cf.syncedSelection=ConfigSelectionKey(GBS.Assign:Get(tab),GBS.Assign:IsOther(tab),GBS.Assign:IsOverflow(tab),cf.dirValue); self:LayoutTabConfig(); self:UpdateTabConfigSave(); if not cf.readOnly then cf.eb:SetFocus(); cf.eb:HighlightText() end
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
    if not selected or not CanViewTab(selected) then return false end
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
    if self:IsProcessing() then self.frame.accessTitle:SetText("Processing..."); return end
    local tab=self.currentTab; local name=GBS.tabNames[tab]
    if not name or type(GetGuildBankTabInfo)~="function" then self.frame.accessTitle:SetText(""); return end
    local ok,_,_,view,deposit,allowed,remaining=pcall(GetGuildBankTabInfo,tab)
    if not ok then self.frame.accessTitle:SetText("Unknown access"); return end
    self.frame.accessTitle:SetText(BankAccess.Title(view,deposit,allowed,remaining,BankNativeTab()==tab))
end
function GBS.Bank:StyleTabButton(button,index,hover)
    local viewable=GBS.tabNames[index] and CanViewTab(index)
    local selected=viewable and self.currentTab==index
    local excluded=GBS.tabNames[index] and not CanUseAutomation(index)
    if excluded then
        if selected then button:SetBackdropColor(0.70,0.38,0.10,1)
        elseif viewable then button:SetBackdropColor(0.58,0.30,0.08,1) else button:SetBackdropColor(0.13,0.13,0.13,1) end
        if hover or selected then button:SetBackdropBorderColor(1,0.72,0.30,1) else button:SetBackdropBorderColor(0.92,0.53,0.16,1) end
    elseif selected then
        button:SetBackdropColor(E.accent[1],E.accent[2],E.accent[3],1)
        button:SetBackdropBorderColor(E.accent[1]*0.7,E.accent[2]*0.7,E.accent[3]*0.7,1)
    else
        button:SetBackdropColor(0.13,0.13,0.13,1)
        if hover and viewable then button:SetBackdropBorderColor(0.45,0.45,0.45,1) else button:SetBackdropBorderColor(0.22,0.22,0.22,1) end
    end
end
function GBS.Bank:SelectTab(tab,internal,noQuery)
    if not internal and GBS.isRunning then return end
    if not GBS.tabNames[tab] or not CanViewTab(tab) then return end
    CloseOurSplit()
    self.currentTab=tab
    if self.frame.activity then self.frame.activity.info.UpdateSave() end
    for i,b in ipairs(self.tabButtons) do
        local viewable=GBS.tabNames[i] and CanViewTab(i)
        self:StyleTabButton(b,i,false)
        if b.text then local shade=viewable and (i==tab and 1 or 0.9) or 0.45; b.text:SetTextColor(shade,shade,shade) end
        if b.icon then local shade=viewable and 1 or 0.4; b.icon:SetVertexColor(shade,shade,shade,1); if type(b.icon.SetDesaturated)=="function" then pcall(b.icon.SetDesaturated,b.icon,not viewable) end end
    end
    if noQuery then if type(SetCurrentGuildBankTab)=="function" then pcall(SetCurrentGuildBankTab,tab) end else SafeSelectGuildBankTab(tab) end
    if GBS.bankPanel then UpdateBankPanelTabs() end; self:RefreshSlots(); self:RefreshAccessTitle()
    if not internal and self.frame.RefreshActivityForTab then self.frame.RefreshActivityForTab()
    elseif internal and self.frame.activity then
        local activity=self.frame.activity
        if not GBSCharDB.bankSections.itemLog then activity.items.render({"Item log will refresh after sorting."}) end
        if not GBSCharDB.bankSections.info then activity.info.edit:ClearFocus(); activity.info.edit:EnableMouse(false); activity.info.save:Disable(); activity.info.SetStatus("Info will refresh after sorting.") end
    end
end
function GBS.Bank:RefreshTabButton(button,index)
    local name=GBS.tabNames[index]
    if not name or name=="" then
        button:Show(); button.text:SetText("Locked "..index); button.count:SetText("")
        button.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up"); button.icon:SetVertexColor(0.45,0.45,0.45,1)
        if type(button.icon.SetDesaturated)=="function" then pcall(button.icon.SetDesaturated,button.icon,true) end
        button.text:SetTextColor(0.5,0.5,0.5)
        return
    end
    local viewable=CanViewTab(index)
    button:Show(); button.text:SetText(SingleLineText(name,math.floor((GRID_W-8)/3)-78))
    local used=self.knownCounts and self.knownCounts[index]
    button.count:SetText(viewable and ("("..(used and tostring(used) or "?").."/98)") or "")
    if GetGuildBankTabInfo then
        local ok,_,icon=pcall(GetGuildBankTabInfo,index)
        if ok and icon then button.icon:SetTexture(icon) else button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    end
    local shade=viewable and 1 or 0.4; button.icon:SetVertexColor(shade,shade,shade,1)
    if type(button.icon.SetDesaturated)=="function" then pcall(button.icon.SetDesaturated,button.icon,not viewable) end
    shade=viewable and 0.9 or 0.45; button.text:SetTextColor(shade,shade,shade)
    button.count:SetTextColor(viewable and 0.65 or 0.4,viewable and 0.65 or 0.4,viewable and 0.65 or 0.4)
end
function GBS.Bank:RefreshTabs()
    for i=1,NUM_TABS do
        local button=self.tabButtons[i]
        if button then self:RefreshTabButton(button,i) end
    end
    -- Switch away from a tab whose view permission was revoked, without
    -- disrupting a live sort. Keep grey tabs right-clickable for inspection.
    if not GBS.isRunning and (not GBS.tabNames[self.currentTab] or not CanViewTab(self.currentTab)) then
        for i=1,NUM_TABS do
            if GBS.tabNames[i] and CanViewTab(i) then
                if self.frame and self:IsOpen() and self.currentTab~=i then self:SelectTab(i)
                else self.currentTab=i end
                break
            end
        end
    end
    for i,b in ipairs(self.tabButtons) do
        self:StyleTabButton(b,i,false)
    end
end
GBS.FormatBankBalance=Money.Compact
function GBS.Bank:ApplyItemQuality(button,rarity)
    local r,g,b=ItemQuality.Color(rarity,GetItemQualityColor)
    if r then SetItemBorder(button,r,g,b,1) else SetItemBorder(button,0.25,0.25,0.25,1) end
end
function GBS.Bank:RefreshSlot(button,tab,slot,viewable)
    local texture,count,locked=nil,0,false
    if viewable and GBS.tabNames[tab] and GetGuildBankItemInfo then
        local ok,a,b,c=pcall(GetGuildBankItemInfo,tab,slot)
        if ok then texture,count,locked=a,b,c end
    end
    local link=nil
    if viewable and GBS.tabNames[tab] and GetGuildBankItemLink then pcall(function() link=GetGuildBankItemLink(tab,slot) end) end
    button:SetAlpha(locked and 0.5 or 1)
    if not texture and not link then
        button.icon:Hide(); button.count:SetText(""); button:Show(); SetItemBorder(button,0.15,0.15,0.15,0.8)
        return false
    end
    button.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark"); button.icon:Show()
    button.count:SetText(count and count>1 and count or ""); button:Show()
    local rarity,pending=ItemQuality.Resolve(texture,link,ParseItemIDFromLink,GetItemInfo)
    self:ApplyItemQuality(button,rarity)
    return pending
end
function GBS.Bank:RefreshSlots()
    local tab=self.currentTab; local viewable=tab and CanViewTab(tab); local qualityPending=false
    for i=1,98 do
        local button=self.slotButtons[i]; if not button then break end
        qualityPending=self:RefreshSlot(button,tab,i,viewable) or qualityPending
    end
    self.qualityPending=qualityPending
    if self.ScheduleBorderSnap then self:ScheduleBorderSnap() end
    if qualityPending and self:IsOpen() then ScheduleQualityRetry() end
    if self.frame and self.frame.money then
        local ok,money=pcall(GetGuildBankMoney); if not ok then money=0 end
        self.frame.money:SetText(Money.Color(Money.Compact(money or 0)))
    end
end
function GBS.Bank:Refresh() GBS:CheckOtherTab(); self:RefreshTabs(); self:RefreshSlots(); self:RefreshAccessTitle(); if GBS.bankPanel then UpdateBankPanelTabs() end end
function GBS.Bank:Show() self:Create(); self.frame:Show(); self:Refresh(); if GBS.bankPanel and not GBSCharDB.panelPos then GBS.bankPanel:ClearAllPoints(); GBS.bankPanel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 6, 0) end end
function GBS.Bank:Hide() StopQualityRetry(); if self.frame then self.frame:Hide() end end


if StaticPopupDialogs then
    StaticPopupDialogs.GBE_RESET_DAMAGED={text="Reset the damaged tab's addon settings? Assignments, roles and direction will be cleared. If tab 1 is damaged, check that nobody else is working in the bank.",button1="Reset tab",button2="Cancel",OnAccept=function(_,data)
        if GBS.Shared and data then GBS.Shared:ApplyOneSaved(data.tab,data.raw,true) end
    end,timeout=0,whileDead=true,hideOnEscape=true}
    StaticPopupDialogs.GBE_FORCE_UNLOCK={text="Force unlock the guild bank? Another member may still be sorting.",button1="Force unlock",button2="Cancel",OnAccept=function(_,data)
        local shared=GBS.Shared
        if not shared then return end
        if data and data.sortUnlock then
            local lock=shared.tabs[1] and shared.tabs[1].lock
            if not GBS.Bank:CanForceUnlockFromSort() or not lock or lock.owner~=data.owner or lock.token~=data.token then
                Chat("The lock or permissions changed; force unlock was cancelled.",1,0.7,0.3); return
            end
        end
        shared:ForceUnlock()
    end,timeout=0,whileDead=true,hideOnEscape=true}
end
SLASH_GBS1="/gbsort"; SLASH_GBS2="/gbs"; SLASH_GBS3="/guildbanksort"; SLASH_GBS4="/gbe"; SLASH_GBS5="/guildbankenhanced"
SlashCmdList["GBS"] = function(msg)
    msg=Trim(Lower(msg or ""))
    if msg=="sort" then GBS:StartSort()
    elseif msg=="sync" then if GBS.Shared then GBS.Shared:ShowConflictAgain() end
    elseif msg=="unlock" then if StaticPopup_Show then StaticPopup_Show("GBE_FORCE_UNLOCK") else Chat("Confirmation UI unavailable.",1,0.4,0.4) end
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

function GBS.Bank:EmergencyRelease()
    local shared=GBS.Shared
    if not shared or not shared.mine or shared.forcedReleaseAttempted then return end
    local ok,why=shared:Release()
    Chat(ok and "Lock release requested but not confirmed; check it when reopening." or ("Lock release not confirmed: "..(why or "unknown error")),1,0.7,0.3)
end
function GBS.Bank:OnNativeOpen()
    -- The Blizzard frame must stay shown for native bank interaction.
    ParkBlizzardGuildFrame()
    self.knownCounts={}; self.purchaseUnconfirmed=nil; self.purchasePending=nil
    local parkDelay=CreateFrame("Frame"); local elapsedPark=0
    parkDelay:SetScript("OnUpdate",function(frame,elapsed)
        elapsedPark=elapsedPark+elapsed
        if elapsedPark>=0.1 then frame:SetScript("OnUpdate",nil); if hiddenGuildFrameState then ParkBlizzardGuildFrame() end end
    end)
    self:Create(); self:Show(); self:EnableEscapeHandling()
    GBS:CheckOtherTab(); self:Refresh(); self:SelectTab(self.currentTab)
    if GBS.Shared then GBS.Shared:Begin() end
end
function GBS.Bank:OnNativeClose()
    local shared=GBS.Shared
    if shared then
        self:EmergencyRelease()
        shared:CancelOwnerCheck(); shared.closing=nil; shared.closeCallback=nil; shared.state="closed"; shared.pending=nil; shared.mine=nil; shared.recent={}
        if shared.dialog then shared.dialog:Hide() end; if shared.reviewDialog then shared.reviewDialog:Hide() end; if shared.versionDialog then shared.versionDialog:Hide() end
    end
    GBS.scanData=nil
    if GBS.isRunning or GBS.routing or GBS.activeMove or GBS.arrange or GBS.routingPrompt then GBS:Cancel() end
    RestoreBlizzardGuildFrame()
    if self.purchaseDialog then self.purchaseDialog:Hide() end
    self:Hide(); if self.moneyBox then self.moneyBox:Hide() end; if self.tabConfig then self.tabConfig:Hide() end
    if GBS.assignFrame then GBS.assignFrame:Hide() end
    if GBS.bankPanel then GBS.bankPanel:Hide() end
end
local eventFrame=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","ADDON_LOADED","GUILDBANKFRAME_OPENED","GUILDBANKFRAME_CLOSED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_LOGIN" then
        if not fontAvailable then Chat("PT Sans Narrow could not be loaded; using the game font. Check the addon Fonts folder and restart the game.",1,0.75,0.25) end
    elseif event=="GUILDBANKFRAME_OPENED" then GBS.Bank:OnNativeOpen()
    elseif event=="GUILDBANKFRAME_CLOSED" then GBS.Bank:OnNativeClose()
    elseif event=="PLAYER_REGEN_DISABLED" then
        if GBS.Bank:IsOpen() then Chat("In combat, use the bank's X button to release the lock before closing.",1,0.7,0.3) end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if GBS.Bank:IsOpen() and not GBS.Bank.escapeOwner then GBS.Bank:EnableEscapeHandling() end
    end
end)

end

do
-- Guild-shared tab settings and an advisory bank lock.
local GBS=_G.GuildBankEnhanced
local codec=GuildBankSorterModules.SharedInfo
local snapshots=GuildBankSorterModules.SharedState
local modules=GuildBankSorterModules
local S={raw={},tabs={},loaded={},state='closed'}; GBS.Shared=S
local function tell(text) DEFAULT_CHAT_FRAME:AddMessage('[GBE] '..text,1,0.75,0.3) end
local function isTrue(v) return v and v~=0 end
local function automationActive()
    return GBS.isRunning or GBS.routing or GBS.arrange or GBS.activeMove or GBS.routingPrompt
end
local function writeAccess(tab)
    if type(CanEditGuildTabInfo)~='function' or type(GetGuildBankTabInfo)~='function' then return nil end
    local ok,permission=pcall(CanEditGuildTabInfo,tab)
    local ok2,name,_,view=pcall(GetGuildBankTabInfo,tab)
    if not ok or not ok2 or not name or name=='' then return nil end
    return not not (isTrue(permission) and isTrue(view))
end
local function canWrite(tab) return writeAccess(tab)==true end
local function me() return type(UnitName)=='function' and UnitName('player') or nil end
local function clock() if type(time)=='function' then local ok,n=pcall(time); if ok and type(n)=='number' then return math.floor(n) end end return nil end
local function copy(v)
    local out={description=v.description,keywords={},direction=v.direction,other=v.other,overflow=v.overflow,lock=v.lock,savedBy=v.savedBy,savedAt=v.savedAt,addonVersion=v.addonVersion}
    for i,k in ipairs(v.keywords or {}) do out.keywords[i]=k end
    return out
end
local function sameLock(a,b) return a and b and a.owner==b.owner and a.token==b.token end
local function ownName(owner,actor,realm)
    if type(owner)~='string' or type(actor)~='string' or type(realm)~='string' then return false end
    local function split(name)
        local character,server=name:match('^([^%-]+)%-(.+)$')
        if not character then return string.lower(name),nil end
        return string.lower(character),string.lower(server:gsub('%s+',''))
    end
    local a,ar=split(actor); local b,br=split(owner)
    local current=string.lower(realm:gsub('%s+',''))
    if ar and ar~=current or br and br~=current then return false end
    return a==b
end
function S:CanWriteLockTab() return canWrite(1) end
function S:CanWriteTab(tab) return canWrite(tab) end
function S:UpdateReviewControls()
    if self.dialog and self.dialog.useSavedBtn then
        local tab=self.dialog.target; local review=tab and self.organizerReviews and self.organizerReviews[tab]
        local saved=tab and self:PreviousTabSettings(tab)
        local canRestore=review and saved and self:CanEditReviewTab(tab) and not self.pending and not self.closing
        if canRestore and review.reason=='corrupt' then
            canRestore=tab==1 or (self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock))
        elseif canRestore then
            canRestore=self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock)
        end
        if canRestore then self.dialog.useSavedBtn:Enable() else self.dialog.useSavedBtn:Disable() end
        local canBank=review and self:CanEditReviewTab(tab) and not self.pending and not self.closing
        if canBank and review.reason=='corrupt' then canBank=false end
        if canBank then self.dialog.useBankBtn:Enable() else self.dialog.useBankBtn:Disable() end
        if self.dialog.resetBtn then
            local canReset=review and review.reason=='corrupt' and not self.versionNeeded and self:CanEditReviewTab(tab) and not self.pending and not self.closing and (tab==1 or (self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock)))
            if canReset then self.dialog.resetBtn:Enable() else self.dialog.resetBtn:Disable() end
        end
    end
end
function S:UpdateUI()
    self:UpdateReviewControls()
    if GBS.UpdateSortControls then GBS.UpdateSortControls() end
    if GBS.Bank and GBS.Bank.RefreshTabs then GBS.Bank:RefreshTabs() end
    if GBS.Bank and GBS.Bank.UpdateTabConfigSave then GBS.Bank:UpdateTabConfigSave() end
    if GBS.Bank and GBS.Bank.frame and GBS.Bank.frame.activity and GBS.Bank.frame.activity.info.ShowManaged then
        GBS.Bank.frame.activity.info.ShowManaged(self.tabs[GBS.Bank.currentTab])
    end
    if self.onUpdate then self.onUpdate() end
end
function S:Reason()
    if self.versionNeeded then return 'Update Guild Bank Enhanced to '..self.versionNeeded..' or newer before sorting or configuring.' end
    if self.closing then return 'Finishing bank updates before closing.' end
    if self.state=='ready' and self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock) and canWrite(1) and not self.pending then return nil end
    local lock=self.tabs[1] and self.tabs[1].lock
    if lock and not sameLock(lock,self.mine) then
        if ownName(lock.owner,self.actor,self.realm) then
            if not canWrite(1) then return 'Tab 1 Info permission is required to acquire the bank lock.' end
            return self.error or 'Verifying your bank lock.'
        end
        local now=clock(); local age=now and math.max(0,math.floor((now-lock.timestamp)/60))
        return 'Locked by '..lock.owner..(age and (' ('..age..' min ago; client clocks may differ).') or '.')
    end
    if not canWrite(1) then return 'Tab 1 Info permission is required to acquire the bank lock.' end
    return self.error or (self.state=='corrupt' and 'Review the damaged tab settings first.') or (self.state=='conflict' and 'Resolve shared settings differences first.') or 'Loading or verifying shared bank settings.'
end
function S:Fail(message)
    self:CancelOwnerCheck(self.restoreWhoNextFrame)
    local tab=self.pending and self.pending.tab
    if tab and GBS.Bank and GBS.Bank.frame and GBS.Bank.frame.activity and GBS.Bank.frame.activity.info.WriteFailed then
        GBS.Bank.frame.activity.info.WriteFailed(tab,message)
    end
    if self.closing then self.closeError=message end
    self.state='error'; self.error=message; self.pending=nil
    if automationActive() then GBS:Cancel() end
    tell(message); self:UpdateUI()
end
function S:Begin()
    self:CancelOwnerCheck()
    self.closing=nil; self.closeError=nil; self.closeCallback=nil; self.forcedReleaseAttempted=nil
    self.openLockObserved=nil; self.openLock=nil; self.permissionKey=nil; self.highestObservedVersion=nil; self.versionNeeded=nil; self.versionWarned=nil
    self.raw={}; self.tabs={}; self.loaded={}; self.corrupt={}; self.readonlyReviews={}; self.organizerReviews={}; self.reviewSnoozed={}; self.recent={}; self.pending=nil; self.mine=nil; self.error=nil; self.state='loading'; self.elapsed=0; self.conflictShown=nil
    GBS.sharedAssignments={}; GBS.tabDirections={}; GBS.sharedOther=nil; GBS.sharedOverflow=nil
    self.realm=type(GetRealmName)=='function' and GetRealmName() or nil
    self.guild=type(GetGuildInfo)=='function' and GetGuildInfo('player') or nil
    self.actor=me(); self.count=type(GetNumGuildBankTabs)=='function' and GetNumGuildBankTabs() or 0
    if not self.realm or self.realm=='' or not self.guild or self.guild=='' or not self.actor or self.actor=='' or not self.count or self.count<1 or type(QueryGuildBankText)~='function' or type(GetGuildBankText)~='function' then self:Fail('Cannot load guild, realm, character or bank info.'); return end
    self.count=math.min(6,self.count)
    for tab=1,self.count do pcall(QueryGuildBankText,tab) end
    self:UpdateUI()
end
function S:Snapshot()
    local t={}; local old=self:CurrentSnapshot()
    for i=1,self.count do
        if not self.tabs[i] then return nil end
        if (not self.corrupt or not self.corrupt[i]) and not self:IsTabExcluded(i) and self:CanViewReviewTab(i) and writeAccess(i)~=nil then t[i]=self.tabs[i]
        elseif old and old.tabs then t[i]=old.tabs[i] end
    end
    local snapshot=snapshots.Snapshot(self.realm,self.guild,t)
    if snapshot then snapshot.bankConfigured=(old and old.bankConfigured) or self:HasConfiguredSettings() end
    return snapshot
end
function S:SaveSnapshot()
    local snapshot=self:Snapshot(); if not snapshot then return end
    GBSCharDB.guildSnapshots=GBSCharDB.guildSnapshots or {}
    GBSCharDB.guildSnapshots[self.realm]=GBSCharDB.guildSnapshots[self.realm] or {}
    GBSCharDB.guildSnapshots[self.realm][self.guild]=snapshot
end
function S:SaveSnapshotTab(tab)
    local old=self:CurrentSnapshot()
    if not old or not old.tabs then return nil end
    local merged={}; for i,v in pairs(old.tabs) do merged[i]=v end
    merged[tab]=self.tabs[tab]
    local value=snapshots.Snapshot(self.realm,self.guild,merged)
    if not value then return nil end
    value.bankConfigured=old.bankConfigured or self:HasConfiguredSettings()
    GBSCharDB.guildSnapshots[self.realm][self.guild]=value
    return true
end
function S:CurrentSnapshot()
    local realms=GBSCharDB.guildSnapshots
    return realms and realms[self.realm] and realms[self.realm][self.guild]
end
local function guildStore(self,key,create)
    local all=GBSCharDB[key]
    if not all and create then all={}; GBSCharDB[key]=all end
    if not all then return nil end
    if not all[self.realm] and create then all[self.realm]={} end
    local realm=all[self.realm]; if not realm then return nil end
    if not realm[self.guild] and create then realm[self.guild]={} end
    return realm[self.guild]
end
function S:PendingStore(create)
    return guildStore(self,'pendingGuildSettings',create)
end
function S:BackupCorrupt(tab,text)
    guildStore(self,'corruptInfoBackups',true)[tab]=text
end
function S:RememberPending(tab,value)
    local store=self:PendingStore(true); store[tab]=copy(value)
end
function S:ForgetPending(tab,value)
    local store=self:PendingStore(false); local pending=store and store[tab]
    if pending and pending.savedBy==value.savedBy and pending.savedAt==value.savedAt then store[tab]=nil end
end
function S:ReconcilePending()
    local store=self:PendingStore(false); if not store then return end
    for tab,intent in pairs(store) do
        local observed=self.tabs[tab]
        if observed and not self:IsTabExcluded(tab) and type(intent)=='table' and observed.savedBy==intent.savedBy and observed.savedAt==intent.savedAt and intent.savedBy and intent.savedAt then
            local candidate=snapshots.Snapshot(self.realm,self.guild,{[tab]=intent})
            local differences=candidate and snapshots.Diff(candidate,self.realm,self.guild,{[tab]=observed})
            if differences and not next(differences) then
                if not self:CurrentSnapshot() then self:SaveSnapshot() end
                if self:SaveSnapshotTab(tab) then store[tab]=nil end
            end
        end
    end
end
function S:ApplyToEngine()
    GBS.sharedAssignments={}; GBS.tabDirections={}; GBS.sharedOther=nil; GBS.sharedOverflow=nil
    for i=1,self.count do
        local v=self.tabs[i]
        GBS.sharedAssignments[i]=v.keywords; GBS.tabDirections[i]=v.direction
        if v.other then if GBS.sharedOther then return nil,'More than one Fallback tab is configured.' end; GBS.sharedOther=i end
        if v.overflow then if GBS.sharedOverflow then return nil,'More than one Overflow tab is configured.' end; GBS.sharedOverflow=i end
    end
    if GBS.CheckOtherTab then GBS:CheckOtherTab() end
    return true
end
function S:HasConfiguredSettings()
    for i=1,self.count do
        local v=self.tabs[i]
        if v and (v.savedBy or v.other or v.overflow or v.direction~='col' or #(v.keywords or {})>0) then return true end
    end
    return false
end
local function snapshotConfigured(snapshot)
    if not snapshot or type(snapshot.tabs)~='table' then return false end
    for _,v in pairs(snapshot.tabs) do
        if type(v)~='table' or type(v.keywords)~='table' or type(v.direction)~='string' then return true end
        if v.other or v.overflow or (v.direction and v.direction~='col') or #(v.keywords or {})>0 then return true end
    end
    return false
end
function S:ForeignLock()
    local lock=self.tabs[1] and self.tabs[1].lock
    return lock and not sameLock(lock,self.mine) and not ownName(lock.owner,self.actor,self.realm)
end
function S:ReadState()
    if self:ForeignLock() then return 'locked' end
    if self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock) and canWrite(1) then return 'ready' end
    return 'readonly'
end
function S:CanViewReviewTab(tab)
    if type(GetGuildBankTabInfo)~='function' then return false end
    local ok,_,_,view=pcall(GetGuildBankTabInfo,tab)
    return ok and not not isTrue(view)
end
function S:CanEditReviewTab(tab)
    return canWrite(1) and canWrite(tab)
end
function S:SkippedStore(create)
    return guildStore(self,'skippedGuildTabs',create)
end
function S:IsTabExcluded(tab)
    local skipped=self:SkippedStore(false)
    return (self.readonlyReviews and self.readonlyReviews[tab]~=nil) or (self.organizerReviews and self.organizerReviews[tab]~=nil) or (skipped and skipped[tab]~=nil) or false
end
function S:HasUncertainAssignments()
    for tab=1,self.count or 0 do
        if self:IsTabExcluded(tab) and (self.corrupt[tab] or not self.tabs[tab] or not self:CanViewReviewTab(tab) or not self:PreviousTabSettings(tab)) then return true end
    end
    return false
end
function S:PreviousTabSettings(tab)
    local old=self:CurrentSnapshot()
    return old and old.tabs and old.tabs[tab]
end
function S:HasExcludedRouteRoles()
    for tab=1,self.count or 0 do if self:IsTabExcluded(tab) then
        local old,current=self:PreviousTabSettings(tab),self.tabs[tab]
        if (old and (old.other or old.overflow)) or (current and (current.other or current.overflow)) then return true end
    end end
    return false
end
local function readOnlyReviewReason(self,tab,value,view,previous,skipped)
    local reason,changes
    if value and view then
        if self.corrupt[tab] then reason='corrupt'
        elseif previous then
            local one,why=snapshots.Snapshot(self.realm,self.guild,{[tab]=previous})
            if not one then return nil,nil,why end
            local diff,err=snapshots.Diff(one,self.realm,self.guild,{[tab]=value})
            if not diff then return nil,nil,err end
            changes=diff[tab]; if changes then reason='changed' end
        elseif skipped and skipped[tab] then
            reason='changed'; changes={'No saved settings are available for comparison.'}
        end
    end
    return reason,changes
end
function S:DetectReadOnlyReviews()
    local old=self:CurrentSnapshot(); local skipped=self:SkippedStore(false)
    for tab=1,self.count do
        local previous=old and old.tabs and old.tabs[tab]
        local value=self.tabs[tab]
        local view=self:CanViewReviewTab(tab); local editable=self:CanEditReviewTab(tab)
        local reason,changes,err=readOnlyReviewReason(self,tab,value,view,previous,skipped)
        if err then return nil,err end
        if reason and not editable then
            local existing=self.readonlyReviews[tab]
            if not existing or existing.raw~=self.raw[tab] or existing.reason~=reason then
                self.reviewSnoozed[tab]=nil
                if automationActive() then GBS:Cancel() end
            end
            self.readonlyReviews[tab]={reason=reason,raw=self.raw[tab],changes=changes}
        else
            self.readonlyReviews[tab]=nil
        end
        if view and not reason and skipped and skipped[tab] then skipped[tab]=nil; self.reviewSnoozed[tab]=nil end
    end
    return true
end
function S:PermissionKey()
    local values={}
    for tab=1,self.count do local access=writeAccess(tab); values[tab]=access==nil and '?' or access and '1' or '0' end
    return table.concat(values)
end
function S:RefreshPermissions()
    if type(self.count)~='number' or self.pending or self.closing then return end
    if automationActive() then return end
    if self.state~='ready' and self.state~='readonly' and self.state~='locked' and self.state~='conflict' and self.state~='corrupt' then return end
    local key=self:PermissionKey(); if key==self.permissionKey then return end
    if canWrite(1) and not self.mine and self.state=='readonly' then self:Acquire() else self:Evaluate() end
end
function S:HasUnresolvedCorruption()
    for tab in pairs(self.corrupt or {}) do
        if tab==1 or canWrite(tab) then return true end
    end
    return false
end
-- Read-only tabs follow the bank; corrupt data never replaces a good local snapshot.
function S:SyncReadOnlyTabs()
    local old=self:CurrentSnapshot(); if not old then return nil end
    local merged,err=snapshots.Snapshot(old.realm,old.guild,old.tabs)
    if not merged or old.realm~=self.realm or old.guild~=self.guild then return nil,err or 'Snapshot belongs to another guild or realm.' end
    for tab=1,self.count do
        if writeAccess(tab)==false and not self.corrupt[tab] and not self:IsTabExcluded(tab) and self:CanViewReviewTab(tab) then
            local one,why=snapshots.Snapshot(self.realm,self.guild,{[tab]=self.tabs[tab]})
            if not one then return nil,why end
            merged.tabs[tab]=one.tabs[tab]
        end
    end
    merged.bankConfigured=old.bankConfigured
    GBSCharDB.guildSnapshots[self.realm][self.guild]=merged
    return merged
end
function S:CanRestoreTab(tab)
    return not self.corrupt[tab] and canWrite(tab)
end
-- Compare only settings that this character could actually restore.
function S:RestoreComparison(saved)
    local target,err=snapshots.Snapshot(saved.realm,saved.guild,saved.tabs)
    if not target or saved.realm~=self.realm or saved.guild~=self.guild then return nil,nil,err or 'Snapshot belongs to another guild or realm.' end
    local current={}; local lockedOther,lockedOverflow=false,false
    for tab=1,self.count do
        local observed=self.tabs[tab]
        if not self:CanRestoreTab(tab) then
            if not self.corrupt[tab] then target.tabs[tab]=observed end
            current[tab]=target.tabs[tab]
            if observed.other then lockedOther=true end
            if observed.overflow then lockedOverflow=true end
        else
            if not target.tabs[tab] then target.tabs[tab]=observed end
            current[tab]=observed
        end
    end
    for tab in pairs(target.tabs) do if tab>self.count then target.tabs[tab]=nil end end
    for tab=1,self.count do
        local value=target.tabs[tab]
        if value and self:CanRestoreTab(tab) then
            if lockedOther then value.other=false end
            if lockedOverflow then value.overflow=false end
        end
    end
    local changes,why=snapshots.Diff(target,self.realm,self.guild,current)
    if not changes then return nil,nil,why end
    for tab in pairs(changes) do if not self:CanRestoreTab(tab) then changes[tab]=nil end end
    return target,changes
end
function S:ShowVersionWarning()
    if not self.versionNeeded or self.versionWarned==self.versionNeeded or not GBS.Bank or not GBS.Bank:IsOpen() then return end
    if not self.versionDialog then
        local d=GBS.CreateSyncFrame('GBEVersionWarning',420,175,115)
        d:SetFrameStrata('FULLSCREEN_DIALOG'); d:SetToplevel(true); d:ClearAllPoints(); d:SetPoint('CENTER',GBS.Bank.frame,'CENTER',0,0)
        local title=GBS.CreateSyncText(d.titleBar,'OVERLAY'); title:SetPoint('LEFT',d.titleBar,'LEFT',8,0); title:SetText('|cffffd100Update Guild Bank Enhanced|r')
        local text=GBS.CreateSyncText(d,'OVERLAY'); text:SetPoint('TOPLEFT',d,'TOPLEFT',14,-38); text:SetWidth(392); text:SetJustifyH('LEFT'); text:SetWordWrap(true); d.text=text
        local ok=CreateFrame('Button',nil,d,'UIPanelButtonTemplate'); ok:SetSize(90,22); ok:SetPoint('BOTTOMRIGHT',d,'BOTTOMRIGHT',-14,12); ok:SetText('OK'); GBS.StyleSyncButton(ok,true); ok:SetScript('OnClick',function() d:Hide() end)
        self.versionDialog=d
    end
    self.versionWarned=self.versionNeeded
    self.versionDialog.text:SetText('This bank uses version '..self.versionNeeded..'. Your version is '..tostring(GBS.Version)..'. Update the addon before sorting or changing settings. You can still use the bank within your normal permissions.')
    self.versionDialog:Show()
end
function S:CheckVersionText(text)
    local observed=codec.ExtractVersion(text)
    if observed and (not self.highestObservedVersion or codec.CompareVersions(observed,self.highestObservedVersion)>0) then self.highestObservedVersion=observed end
    local version=self.highestObservedVersion
    local cmp=version and codec.CompareVersions(GBS.Version,version)
    if version and (not cmp or cmp<0) then
        self.versionNeeded=version; self.error='Update Guild Bank Enhanced to '..version..' or newer.'; self.state='outdated'; self.pending=nil
        self:CancelOwnerCheck()
        if automationActive() then GBS:Cancel() end
        if self.dialog then self.dialog:Hide() end; if self.reviewDialog then self.reviewDialog:Hide() end
        self:UpdateUI(); self:ShowVersionWarning(); return false
    end
    return true
end
function S:CheckCurrentVersion()
    if type(GetGuildBankText)~='function' then return false end
    local ok,text=pcall(GetGuildBankText,1)
    if not ok or (text~=nil and type(text)~='string') then return false end
    return self:CheckVersionText(text or '')
end
function S:EnsureBankVersion()
    if self.corrupt[1] or not canWrite(1) or not self.mine or not self.tabs[1] or not sameLock(self.mine,self.tabs[1].lock) then return false end
    local bank=self.tabs[1].addonVersion
    local comparison=bank and codec.CompareVersions(GBS.Version,bank)
    if bank and comparison and comparison<=0 then return false end
    local value=copy(self.tabs[1]); value.addonVersion=GBS.Version; self.state='versioning'
    local ok,err=self:Write(1,value,function() self:Evaluate() end,self.raw[1])
    if not ok and self.state~='error' then self:Fail(err) end
    return true
end
function S:CollectOrganizerReviews(changes)
    local skipped=self:SkippedStore(false); local first
    if canWrite(1) then
        for tab=1,self.count do
            if self:CanEditReviewTab(tab) then
                local reason
                if self.corrupt[tab] then reason='corrupt'
                elseif changes[tab] and not self.corrupt[tab] then reason='changed' end
                if reason then
                    self.organizerReviews[tab]={reason=reason,raw=self.raw[tab],changes=changes[tab]}
                    if (not (skipped and skipped[tab]) or self.reviewSnoozed[tab]~=self.raw[tab]) and not first then first=tab end
                end
            end
        end
    end
    return first
end
function S:Evaluate()
    if not self:CheckVersionText(self.raw[1]) then return end
    if not self.pending and not self.closing and self:EnsureBankVersion() then return end
    self.permissionKey=self:PermissionKey()
    local ok,err=self:ApplyToEngine(); if not ok then self:Fail(err); return end
    self.organizerReviews={}
    local reviewed,why=self:DetectReadOnlyReviews(); if not reviewed then self:Fail(why); return end
    self:ReconcilePending()
    local old,why=self:SyncReadOnlyTabs()
    if why then self:Fail(why); return end
    local configured=self:HasConfiguredSettings()
    local pending=self:PendingStore(false); local hasPending=pending and next(pending)~=nil
    if old and not old.bankConfigured and (not configured or (not snapshotConfigured(old) and not hasPending)) then
        self:SaveSnapshot(); old=self:CurrentSnapshot()
    end
    local changes={}
    if old then
        local _,found,err=self:RestoreComparison(old)
        if not found then self:Fail(err); return end
        changes=found
    end
    local first=self:CollectOrganizerReviews(changes)
    if not old then self:SaveSnapshot() end
    if first then
        self.state=self.organizerReviews[first].reason=='corrupt' and 'corrupt' or 'conflict'
        self.error=nil; self:UpdateUI(); self:ShowConflict(changes,first); return
    end
    if self.corrupt[1] and canWrite(1) then
        self.state='corrupt'; self.error='Tab 1 settings are damaged; the bank lock is unknown.'
        if self.dialog then self.dialog:Hide() end
        self:UpdateUI(); self:ShowNextReadOnlyReview(); return
    end
    self:SaveSnapshot()
    if self.dialog then self.dialog:Hide() end
    self.state=self:ReadState(); self.error=nil; self:UpdateUI(); self:ShowNextReadOnlyReview()
end
function S:SkipRestoreIfReadOnly(p)
    if p.onReadOnly and canWrite(1) and not canWrite(p.tab) then
        self.pending=nil; p.onReadOnly(); return true
    end
    return false
end
function S:RestoreRoleConflict(tab,value)
    for other,current in pairs(self.tabs) do
        if other~=tab and ((value.other and current.other) or (value.overflow and current.overflow)) then return true end
    end
    return false
end
function S:StartPreflight()
    local p=self.pending
    if not p or p.stage~='waiting' then return end
    if self.state=='closed' or not GBS.Bank or not GBS.Bank:IsOpen() or not canWrite(1) then
        self:Fail('Cannot edit tab '..p.tab..' info or hold the bank lock; reopen and retry.'); return
    end
    if self:SkipRestoreIfReadOnly(p) then return end
    if not canWrite(p.tab) then self:Fail('Cannot edit tab '..p.tab..' info or hold the bank lock; reopen and retry.'); return end
    if p.onReadOnly and self:RestoreRoleConflict(p.tab,p.value) then self:Fail('Fallback or Overflow changed during restore; reopen and review.'); return end
    -- Requery only after the cooldown so the preflight is fresh when we write.
    p.stage='preflight'; p.elapsed=0
    if type(QueryGuildBankText)~='function' or not pcall(QueryGuildBankText,p.tab) then self:Fail('Could not query tab info.') end
end
function S:Write(tab,value,done,expected,trackSettings,onReadOnly)
    if self.versionNeeded or not self:CheckCurrentVersion() then return nil,'Update Guild Bank Enhanced or verify tab 1 Info first.' end
    if self.pending then return nil,'Another tab info update is in progress.' end
    if not self.raw[tab] or not canWrite(tab) or type(SetGuildBankText)~='function' then return nil,'Cannot edit tab '..tab..' info.' end
    if expected and expected~=self.raw[tab] then return nil,'Tab '..tab..' changed before restore; reopen and retry.' end
    local text,err=codec.Compose(value.description,value); if not text then return nil,err end
    self.pending={tab=tab,base=self.raw[tab],value=value,text=text,stage='waiting',done=done,elapsed=0,trackSettings=trackSettings,onReadOnly=onReadOnly}
    self:UpdateUI()
    if not self.lastWriteElapsed or self.lastWriteElapsed>=(GBS.GetInfoDelay and GBS.GetInfoDelay() or 0.5) then self:StartPreflight() end
    if self.state=='error' then return nil,self.error end
    return true
end
function S:ReceivePreflight(tab,text,pending)
    if not self:CheckCurrentVersion() then
        if not self.versionNeeded then self:Fail('Could not verify tab 1 version before saving.') end
        return false
    end
    if text~=pending.base or not canWrite(1) then
        self:Fail('Tab '..tab..' info or edit permission changed before saving; reopen and retry.'); return false
    end
    if self:SkipRestoreIfReadOnly(pending) then return false end
    if not canWrite(tab) or (pending.onReadOnly and self:RestoreRoleConflict(tab,pending.value)) then
        self:Fail('Tab '..tab..' info or edit permission changed before saving; reopen and retry.'); return false
    end
    if self.corrupt and self.corrupt[tab] then self:BackupCorrupt(tab,text) end
    pending.stage='confirm'; pending.elapsed=0; pending.retry=0.5
    local sent=pcall(SetGuildBankText,tab,pending.text)
    if sent then self.lastWriteElapsed=0; self.writeCooldownFresh=true end
    if not sent then self:Fail('Could not send tab '..tab..' info.'); return false end
    if pending.trackSettings then self:RememberPending(tab,pending.value) end
    pcall(QueryGuildBankText,tab); return false
end
function S:ReceiveLockChange(tab,value)
    if not self.mine or tab~=1 or sameLock(self.mine,value.lock) then return true end
    if value.lock and ownName(value.lock.owner,self.actor,self.realm) and not self.pending then
        if automationActive() then GBS:Cancel() end
        self.mine=value.lock; self:Evaluate(); return true
    end
    self.mine=nil; self:Fail('The bank lock changed. Sorting stopped; inspect the bank.'); return false
end
function S:EvaluateReceivedState()
    if self.state=='loading' and not self.pending then
        for i=1,self.count do if not self.loaded[i] then self:UpdateUI(); return end end
        if self.mine and self.tabs[1] and sameLock(self.mine,self.tabs[1].lock) then self:Evaluate() else self:Acquire() end
    elseif (self.state=='ready' or self.state=='readonly' or self.state=='locked' or self.state=='corrupt') and not self.pending then
        if self:HasUnresolvedCorruption() or not canWrite(1) then self:Evaluate()
        elseif self.state=='corrupt' then
            if self.mine then self:Evaluate() else self:Acquire() end
        else
            local changes=snapshots.Diff(self:CurrentSnapshot(),self.realm,self.guild,self.tabs)
            if changes and next(changes) then self:Evaluate() end
        end
    end
    self:UpdateUI()
end
function S:ReadObservedText(tab)
    local ok,text=pcall(GetGuildBankText,tab)
    if not ok or (text~=nil and type(text)~='string') then self:Fail('Could not read tab '..tab..' info.'); return nil end
    return text or ''
end
function S:IgnoreStaleResponse(tab,text,pending)
    if pending and pending.tab==tab and pending.stage=='confirm' and text~=pending.text then
        pending.lastObserved=text; return true
    end
    local recent=self.recent and self.recent[tab]
    if recent and text==recent.base and text~=recent.text then recent.needsQuery=true; return true end
    return false
end
function S:ConfirmObservedWrite(tab,pending)
    self.recent=self.recent or {}; self.recent[tab]={base=pending.base,text=pending.text,elapsed=0,retry=0.5}
    self.pending=nil; if pending.done then pending.done() end
    return self.state~='closed' and GBS.Bank and GBS.Bank:IsOpen()
end
function S:Receive(tab)
    -- Early Info events can arrive before Begin initializes the session.
    if self.state=='closed' or type(self.count)~='number' then return false end
    tab=tonumber(tab); if not tab or tab<1 or tab>self.count then return false end
    local text=self:ReadObservedText(tab); if text==nil then return false end
    if tab==1 and not self:CheckVersionText(text) then return false end
    local pending=self.pending
    if pending and pending.tab==tab and pending.stage=='preflight' then return self:ReceivePreflight(tab,text,pending) end
    if self:IgnoreStaleResponse(tab,text,pending) then return false end
    local value,err=codec.Parse(text)
    if not value then
        value=codec.Recover(text)
        if not value then self:Fail('Tab '..tab..': '..err); return false end
        self.corrupt=self.corrupt or {}
        self.corrupt[tab]=true
        if tab==1 then self.mine=nil; self:CancelOwnerCheck() end
        if automationActive() then GBS:Cancel() end
    elseif self.corrupt then self.corrupt[tab]=nil end
    if tab==1 and self.state=='loading' and not self.openLockObserved then
        self.openLockObserved=true; self.openLock=value.lock
    end
    self.raw[tab]=text; self.tabs[tab]=value; self.loaded[tab]=true
    if pending and pending.tab==tab and pending.stage=='confirm' then
        if not self:ConfirmObservedWrite(tab,pending) then return true end
    elseif not self:ReceiveLockChange(tab,value) then return false end
    self:EvaluateReceivedState(); return true
end
function S:Acquire(replace)
    if self.pending or not self.tabs[1] then return end
    if not self:CheckVersionText(self.raw[1]) then return end
    if self.corrupt and self.corrupt[1] then self:Evaluate(); return end
    local old=self.tabs[1].lock
    if old and not replace then
        if ownName(old.owner,self.actor,self.realm) then
            self.mine=old; self:Evaluate(); return
        end
        self.state='locked'; self.error=nil; if canWrite(1) then self:CheckOwner() end; self:Evaluate(); return
    end
    if not canWrite(1) then self:Evaluate(); return end
    local now=clock(); if not now then self:Fail('Cannot determine the lock timestamp.'); return end
    local v=copy(self.tabs[1]); local token=tostring(now)..tostring(math.random(100000,999999))
    v.lock={owner=self.actor,timestamp=now,token=token}; v.addonVersion=GBS.Version; self.state='claiming'
    local ok,err=self:Write(1,v,function() self.mine=v.lock; self:Evaluate() end)
    if not ok then self:Fail(err) end
end
-- Suppress only Blizzard's Who update while this query is outstanding.
function S:RestoreWhoFrame()
    local frame=self.whoFrame; self.whoFrame=nil; self.restoreWhoNextFrame=nil
    if frame then pcall(frame.RegisterEvent,frame,'WHO_LIST_UPDATE') end
end
function S:CancelOwnerCheck(deferRestore)
    self.whoWaiting=nil; self.rosterWaiting=nil
    if self.whoRouted then
        self.whoRouted=nil
        if type(SetWhoToUI)=='function' then pcall(SetWhoToUI,0) end
    end
    if deferRestore and self.whoFrame then self.restoreWhoNextFrame=true else self:RestoreWhoFrame() end
    if self.hadRosterSetting and type(SetGuildRosterShowOffline)=='function' then pcall(SetGuildRosterShowOffline,self.wasShowOffline) end
    self.hadRosterSetting=nil; self.wasShowOffline=nil
end
function S:StartQuietWho(owner)
    local frame=FriendsFrame
    if not frame or type(frame.IsEventRegistered)~='function' or type(frame.UnregisterEvent)~='function' or type(frame.RegisterEvent)~='function' or type(SendWho)~='function' or type(SetWhoToUI)~='function' then return false end
    if type(frame.IsVisible)=='function' then local ok,visible=pcall(frame.IsVisible,frame); if not ok or (visible and visible~=0) then return false end end
    local ok,registered=pcall(frame.IsEventRegistered,frame,'WHO_LIST_UPDATE')
    if not ok or not registered or registered==0 then return false end
    self.whoFrame=frame
    local removed=pcall(frame.UnregisterEvent,frame,'WHO_LIST_UPDATE')
    if not removed then self:RestoreWhoFrame(); return false end
    local verified,stillRegistered=pcall(frame.IsEventRegistered,frame,'WHO_LIST_UPDATE')
    if not verified or (stillRegistered and stillRegistered~=0) then self:RestoreWhoFrame(); return false end
    if not self.whoHookTried and type(hooksecurefunc)=='function' then
        self.whoHookTried=true
        pcall(hooksecurefunc,'SendWho',function() if S.whoWaiting and not S.sendingOwnWho then S.whoCompeting=true end end)
    end
    self.whoWaiting=true; self.whoElapsed=0; self.whoRouted=true; self.whoCompeting=nil
    local routed=pcall(SetWhoToUI,1)
    if not routed then self:CancelOwnerCheck(); return false end
    self.sendingOwnWho=true; local sent=pcall(SendWho,'n-"'..owner..'"'); self.sendingOwnWho=nil
    if not sent then self:CancelOwnerCheck(); return false end
    return true
end
function S:CheckOwner()
    local lock=self.tabs[1] and self.tabs[1].lock; if not lock then return end
    if self.restoreWhoNextFrame or (self.whoWaiting and self.ownerCheck==lock.owner) then return end
    local previous=self.whoWaiting
    self:CancelOwnerCheck()
    self.ownerCheck=lock.owner; self.rosterWaiting=true; self.rosterOffline=nil; self.whoOffline=nil
    if type(GetGuildRosterShowOffline)=='function' and type(SetGuildRosterShowOffline)=='function' then
        self.hadRosterSetting=true; self.wasShowOffline=GetGuildRosterShowOffline(); pcall(SetGuildRosterShowOffline,1)
    end
    if type(GuildRoster)=='function' then pcall(GuildRoster) end
    if not previous then self:StartQuietWho(lock.owner) end
end
function S:MaybeReclaim()
    local lock=self.tabs[1] and self.tabs[1].lock
    if self.state=='locked' and lock and lock.owner==self.ownerCheck and self.rosterOffline and self.whoOffline then self:Acquire(true) end
end
function S:Roster()
    if not self.rosterWaiting then return end
    local owner=self.ownerCheck; local lock=self.tabs[1] and self.tabs[1].lock
    self.rosterWaiting=nil
    if self.hadRosterSetting and type(SetGuildRosterShowOffline)=='function' then pcall(SetGuildRosterShowOffline,self.wasShowOffline) end
    self.wasShowOffline=nil; self.hadRosterSetting=nil
    if not lock or lock.owner~=owner or type(GetNumGuildMembers)~='function' or type(GetGuildRosterInfo)~='function' then return end
    local count=GetNumGuildMembers() or 0
    for i=1,count do
        local name,_,_,_,_,_,_,_,online=GetGuildRosterInfo(i)
        if type(name)=='string' and string.lower(name)==string.lower(owner) then
            self.rosterOffline=(online==false or online==nil or online==0); self:MaybeReclaim(); return
        end
    end
end
function S:Who()
    if not self.whoWaiting then return end
    self.whoWaiting=nil; if self.whoRouted and type(SetWhoToUI)=='function' then pcall(SetWhoToUI,0) end; self.whoRouted=nil
    if self.whoFrame then self.restoreWhoNextFrame=true end
    if self.whoCompeting then self.whoCompeting=nil; return end
    if type(GetNumWhoResults)~='function' or type(GetWhoInfo)~='function' then return end
    local ok,count,total=pcall(GetNumWhoResults)
    if not ok or type(count)~='number' or (type(total)=='number' and total>count) then return end
    for i=1,count do
        local got,name=pcall(GetWhoInfo,i)
        if not got or type(name)~='string' then return end
        if string.lower(name)==string.lower(self.ownerCheck or '') then return end
    end
    if count==0 then self.whoOffline=true; self:MaybeReclaim() end
end
function S:ForceUnlock()
    if self.versionNeeded or not self:CheckCurrentVersion() then tell('Update Guild Bank Enhanced or verify tab 1 Info first.'); return end
    if self.state=='closed' or not GBS.Bank or not GBS.Bank:IsOpen() then tell('Open the guild bank first.'); return end
    if type(IsGuildLeader)~='function' or not isTrue(IsGuildLeader()) then tell('Only the guild master can force unlock.'); return end
    if not self.tabs[1] or not self.tabs[1].lock then tell('No lock to clear.'); return end
    self:Acquire(true)
end
function S:SaveTab(tab,keywords,other,overflow,direction,callback)
    if self:IsTabExcluded(tab) then return nil,'Review the tab settings first.' end
    local reason=self:Reason(); if reason then return nil,reason end
    for i=1,self.count do if i~=tab and ((other and self.tabs[i].other) or (overflow and self.tabs[i].overflow)) then return nil,'Clear the existing Fallback or Overflow on tab '..i..' first.' end end
    local stamp=clock(); if not stamp or not self.actor then return nil,'Cannot record settings author or time.' end
    local v=copy(self.tabs[tab]); v.keywords=keywords; v.other=other; v.overflow=overflow; v.direction=direction; v.savedBy=self.actor; v.savedAt=stamp
    return self:Write(tab,v,function() if not self:SaveSnapshotTab(tab) then self:Fail('Could not update the local snapshot.'); return end; self:ForgetPending(tab,v); self:Evaluate(); if callback then callback() end end,nil,true)
end
function S:SaveDescription(tab,description,callback)
    local reason=self:Reason(); if reason then return nil,reason end
    if not self.tabs[tab] then return nil,'Tab info is not loaded.' end
    local v=copy(self.tabs[tab]); v.description=description
    return self:Write(tab,v,function() self:Evaluate(); if callback then callback() end end)
end
function S:Changed(tab)
    if self.state=='closed' or type(self.count)~='number' then return end
    tab=tonumber(tab); if not tab or tab<1 or tab>self.count then return end
    if automationActive() then GBS:Cancel() end
    if not self.pending and (self.state=='ready' or self.state=='locked' or self.state=='readonly' or self.state=='conflict' or self.state=='corrupt') then self.state='loading'; self.elapsed=0; self.loaded[tab]=nil end
    self:UpdateUI()
    if type(QueryGuildBankText)=='function' then pcall(QueryGuildBankText,tab) end
end
function S:Release()
    if self.forcedReleaseAttempted then return nil,'Lock release was already attempted.' end
    self.forcedReleaseAttempted=true
    if not self.mine then return true end
    if not self.tabs[1] or not sameLock(self.mine,self.tabs[1].lock) or self.pending or not canWrite(1) or type(SetGuildBankText)~='function' then return nil,'The lock could not be safely released.' end
    local ok,latest=pcall(GetGuildBankText,1); if not ok or latest~=self.raw[1] then return nil,'Tab 1 changed before lock release.' end
    local v=copy(self.tabs[1]); v.lock=nil; local text,err=codec.Compose(v.description,v)
    if not text then return nil,err end
    local sent=pcall(SetGuildBankText,1,text); if not sent then return nil,'Could not send lock release.' end
    self.lastWriteElapsed=0; self.writeCooldownFresh=true
    self.mine=nil; return true
end
function S:FinishClose(warning)
    local callback=self.closeCallback; self.closeCallback=nil; self.closing=nil; self.closeError=nil
    if warning then self.forcedReleaseAttempted=true; tell('Lock release not confirmed: '..warning..' Check the lock when reopening the bank.') end
    if callback then callback() end
end
function S:AdvanceClose()
    if not self.closing then return end
    if self.closeError then self:FinishClose(self.closeError); return end
    if self.pending then return end
    if not self.mine then self:FinishClose(); return end
    if not self.tabs[1] or not sameLock(self.mine,self.tabs[1].lock) then self:FinishClose('lock ownership changed'); return end
    local v=copy(self.tabs[1]); v.lock=nil
    local releaseText,composeError=codec.Compose(v.description,v)
    if not releaseText then self:FinishClose(composeError); return end
    local recent=self.recent and self.recent[1]
    if recent and releaseText==recent.base and releaseText~=recent.text then return end
    local ok,err=self:Write(1,v,function() self.mine=nil; self:FinishClose() end)
    if not ok then self:FinishClose(err or 'release could not be sent') end
end
function S:RequestClose(callback)
    if self.closing then return end
    self.closing=true; self.closeCallback=callback; self.closeError=nil; self:UpdateUI(); self:AdvanceClose()
end
function S:AdvanceWriteTimer(elapsed)
    local pending=self.pending
    local waited=pending and pending.stage=='waiting'
    if waited and (not self.lastWriteElapsed or self.lastWriteElapsed>=(GBS.GetInfoDelay and GBS.GetInfoDelay() or 0.5)) then self:StartPreflight() end
    pending=self.pending
    if not pending or waited or pending.stage=='waiting' then return end
    pending.elapsed=pending.elapsed+elapsed
    if pending.elapsed>8 then
        self:Fail('Tab '..pending.tab..' update was not confirmed within 8 seconds; reopen and verify.')
    elseif pending.stage=='confirm' then
        pending.retry=(pending.retry or 0)-elapsed
        if pending.retry<=0 then pending.retry=0.5; if type(QueryGuildBankText)=='function' then pcall(QueryGuildBankText,pending.tab) end end
    end
end
function S:AdvanceRecentTimers(elapsed)
    for tab,recent in pairs(self.recent or {}) do
        recent.elapsed=recent.elapsed+elapsed; recent.retry=recent.retry-elapsed
        if recent.elapsed>=3 then
            self.recent[tab]=nil
            if recent.needsQuery and type(QueryGuildBankText)=='function' then pcall(QueryGuildBankText,tab) end
        elseif recent.needsQuery and recent.retry<=0 then
            recent.retry=0.5; if type(QueryGuildBankText)=='function' then pcall(QueryGuildBankText,tab) end
        end
    end
end
function S:Tick(elapsed)
    if self.restoreWhoNextFrame then self:RestoreWhoFrame() end
    if self.whoWaiting then self.whoElapsed=(self.whoElapsed or 0)+elapsed; if self.whoElapsed>8 then self:CancelOwnerCheck() end end
    -- Do not count time preceding a write performed between frames.
    if self.writeCooldownFresh then self.writeCooldownFresh=nil
    elseif self.lastWriteElapsed then self.lastWriteElapsed=self.lastWriteElapsed+elapsed end
    self:AdvanceWriteTimer(elapsed)
    self:AdvanceRecentTimers(elapsed)
    if self.closing then self:AdvanceClose() end
    if self.state=='loading' then self.elapsed=(self.elapsed or 0)+elapsed; if self.elapsed>12 then self:Fail('Tab info did not load; reopen the bank.') end end
end
local timer=CreateFrame('Frame'); S.timer=timer
timer:SetScript('OnUpdate',function(_,elapsed) S:Tick(elapsed) end)

modules.AttachSharedReview(S,{GBS=GBS,codec=codec,snapshots=snapshots,tell=tell,clock=clock,copy=copy,sameLock=sameLock,automationActive=automationActive})

end
