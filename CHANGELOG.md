# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## [1.1.0] - 2026-11-22

### Added
- **Packaging & Metadata:** Added `.pkgmeta` for automated CurseForge packaging and updated `VaultManager.toc` interface compatibility (`16001`, `11509`, `20506`).
- **Load Order Hardening:** Adjusted TOC load order so `Minimap.lua` initializes prior to `UI.lua`.

### Fixed
- **Guild Bank Scanning:** Fixed item parsing and stack counting when `GetGuildBankItemLink` returns plain bracketed item names without `item:ID` prefixes, and eliminated empty-slot ghost rows.
- **Server Disconnect Prevention:** Prevented client disconnects (`WOW51900319`) caused by querying invalid item IDs (`item:0:...`) on guild bank open and scan.
- **Ledger & Ranking Attribution:** Fixed item and gold transaction log parsing (`ScanLogs`, `ScanMoneyLogs`, `RecordDeposit`, `RecordGoldDeposit`) so deposits and withdrawals are recorded without duplicates and properly aggregated across linked main/alt characters.
- **Export Modal & UI Nil-Guards:** Fixed an `attempt to index field 'scroll' (a nil value)` error when opening the Markdown/CSV export modal in the Ranking tab, and added defensive nil-guards across all UI tabs and widgets.

## [1.0.0] - 2026-11-22

### Added
- Initial release of **Vault Manager** with guild bank inventory scanning, item request queue, donation ledger, main/alt ranking, and guild P2P synchronization.