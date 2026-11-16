# Guild Bank Enhanced

Organise your guild bank with one click. Guild Bank Enhanced routes items to tabs by type and subtype, combines partial stacks and sorts each tab—all from a consolidated bank interface for World of Warcraft 3.3.5a.

## Features

- **Type and subtype routing:** Assign entire item types or specific subtypes to tabs. For example, send Trade Goods to one tab and Herbs to another; the more specific subtype assignment takes priority.
- **Fallback and overflow:** Optionally collect unassigned items in a fallback tab and send items to an overflow tab when their destination is full. A separate fallback can also receive overflow if needed.
- **Stack and sort:** Combine matching partial stacks up to their normal maximum, then group and order items within each tab in your chosen direction.
- **One configurable view:** See the bank, money log, selected tab’s item log and tab information together—or collapse the sections you don’t need. Less clicking and tab switching than the default interface.
- **Per-character settings:** Save assignments, sort direction and operation delays separately for each character.

## Configuration

Right-click a bank tab to set its item assignments, fallback or overflow role. The bank’s bottom bar provides:

- **Sort direction:** Controls the order in which slots are filled within each tab. The default is Down > Right.
- **Move delay:** Time between completed item operations; defaults to 0.10 seconds.
- **Scan delay:** Time allowed after selecting each tab during a scan; defaults to 0.30 seconds.

Both delays can be adjusted from 0 to 1 second. Sending moves too quickly can trigger server throttling or cause operations to fail, especially with lag. Start cautiously; if you see delays or errors, stop, check the bank and increase the delays before trying again. Server behaviour varies.

## Screenshots

<!-- Add screenshots here. -->

See the [changelog](changelog.md) for release notes.
