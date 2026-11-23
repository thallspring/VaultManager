# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## [1.1.5] - 2026-11-23

### Fixed & Added
- **Gold Withdrawal Tracking:** Added support for parsing direct member gold withdrawals (`withdraw`) in the Guild Bank Money Log scanner while explicitly ignoring guild repairs (`repair`) and tab purchases (`buyTab`).
- **Ledger & Ranking Integration:** Recorded member gold withdrawals as `[GOLD OUT]` transactions attributed to members (and their Mains), aggregated `totalGoldOut` in ledger calculations, and rendered them cleanly in the Ledger UI.

## [1.1.4] - 2026-11-23

### Fixed
- **0g Unattributed Entries:** Prevented creation of zero-amount or negative unattributed gold ledger entries, and added automatic startup purging of existing 0g entries from SavedVariables.
- **Async Guild Bank Log Scanning:** Explicitly queried guild bank money logs (`MAX_GUILDBANK_TABS + 1`) and tab logs on `GUILDBANKFRAME_OPENED`, using a debounced `GUILDBANKLOG_UPDATE` handler to ensure scan summaries execute only after server log data arrives.
- **Money Log Transaction Parsing:** Filtered out guild repairs (`repair`), tab purchases (`buyTab`), withdrawals (`withdraw`), and zero/negative transfers so only valid member gold deposits are recorded in the ledger.

## [1.1.3] - 2026-11-23

### Fixed
- **Guild Bank & Tab Caching:** Prevented asynchronous guild bank scans from overwriting valid cached inventory data with empty tables when opening the bank before server packet data arrives.
- **Transaction Deduplication:** Implemented robust deterministic transaction log deduplication using processed entry signatures (`processedBankLogs`) to eliminate duplicate ledger entries on repeated scans.
- **Officer & Version Validation:** Enhanced officer rank safety with dynamic guild roster fallback (`IsOfficerName`), and added a one-time session notification when a peer is running a newer addon version.
- **Localization:** Translated all comments and output messages strictly to English across all addon modules.

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