# Changelog

## 1.1.0

- Share tab assignments, fallback and overflow roles, and per-tab sort directions through guild bank Info. On upgrading from 1.0.3, previous per-character settings are not imported and must be set on the bank once.
- Review changed settings per tab, with options based on access. Skipped tabs are excluded, marked orange and, if unresolved, presented for review again on the next bank opening. Members without edit access cannot accept changed settings when the last saver is unknown.
- Recover damaged or unsupported tab settings by applying saved settings or confirming a reset. Read-only members must wait for a repair; a damaged tab 1 blocks addon sorting and configuration until repaired.
- Coordinate compatible addon users with an advisory bank lock, confirmation-aware release and offline-owner recovery. Guild masters can confirm a force unlock from Sort or `/gbe unlock`. Record the newest addon version in tab 1 and prompt older participating versions to update; versions predating this check cannot reliably enforce it.
- Respect guild rank permissions for viewing, editing and sorting tabs. Route only to permitted destinations and from sources with at least 1,000 withdrawals remaining or unlimited access; warn before using finite allowances.
- Add a per-character Info delay, pace and confirm shared settings writes, and update only changed tabs when restoring settings.
- Expand tab Info to show shared settings, lock status, access and available actions, with separate description editing and draft conflict protection. Match the standard bank’s slot layout, show processing and access status in the title, and grey out inaccessible tabs.
- Refactor shared logic, settings review and currency formatting to reduce duplication and simplify maintenance.

## 1.0.3

- Display the most recent item and money log transactions first.

## 1.0.2

- Handle ordering equipment when the client omits its random suffix from the cursor link, while checking the locked source slot.

## 1.0.1

- Remember whether the tab details panel is open and allow resizing its sections.
- Improve ordering checks for item links with different display levels.
- Close the bank after a confirmed tab purchase and prompt for reopening.

## 1.0.0

- Initial release.
