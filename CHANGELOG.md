# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## [1.2.1] - 2026-11-24

### Fixed & Enhanced
- **Infinite Scan Loop & Chat Spam Prevention:** Implemented `isScanning` and `ignoreEventsUntil` guards in `BankScanner.lua` to prevent server responses to internal queries from triggering cascading scan loops. Suppressed repeated chat spam during background slot and log updates, printing "Scan complete" only upon initial bank open or manual "Force Scan" while keeping the header status button locked cleanly on green "Scan Complete".
- **Ranking Period Dropdown Menu:** Replaced the click-to-cycle ranking period button with a modern custom dropdown menu (`VaultManagerRankingPeriodPicker`) providing direct one-click selection between "All-Time", "Current Month", and "Previous Month".

## [1.2.0] - 2026-11-23

### Added & Enhanced
- **Expandable Nested Ranking Breakdown:** Every player row in the Ranking tab is now expandable (+/- toggle), displaying all transactions with Date, Direction (`[IN]`, `[OUT]`, `[GOLD IN]`, `[GOLD OUT]`), item/gold links, locked price at transaction time, and current AH value.
- **Ranking Terminology & Controls:** Adopted clear "Contributed", "Received", and "Net Balance" columns. Added a "Hide Officers" checkbox toggle and a period filter dropdown ("All-Time", "Current Month", "Previous Month").
- **Officer Payment Tracking & Attribution:**
  - *Trade-to-Bank Auto-Attribution:* Hooked trade money transfers so gold handed to officers during fulfillment auto-attributes to the paying member upon bank deposit.
  - *Manual Gold Reassignment:* Added a "Reassign" button on `[GOLD IN]` entries in the Ledger for officers to attribute deposits to the actual paying member while preserving raw audit trails.
- **Automatic Scanning & Dynamic Status Button:** Full bank scanning runs automatically on bank frame open and slot changes with a 0.6s debounce timer. Added a central status button in the header reflecting scan state ("Scan Complete", "Scanning...", "Force Scan").
- **Multi-Addon AH Pricing & Peer Snapshots:** Unified price lookup across TradeSkillMaster (TSM), Auctionator, Aux, Auctioneer, and vendor fallbacks. Snapshots are synchronized via P2P so peers without AH addons see consistent pricing.
- **Markdown & CSV Data Export:** Enhanced the Export modal to generate copy-ready Markdown tables formatted for Discord pasting as well as CSV.
- **Monthly History Compaction:** Added automated rollup of ledger transactions older than 60 days into monthly summary entries per Main, keeping SavedVariables compact and sync lightweight.
- **Protocol & Version Bump:** Bumped `VM.VERSION` to 4 and updated peer version alerts.

## [1.1.6] - 2026-11-23

### Fixed & Added
- **Lock Automatically Scanned Entries:** Scanned Guild Bank item and money logs are now strictly read-only (`isManual = false`), removing the delete "X" button from the UI and guarding against deletion in `Ledger.lua`. Only manually logged gold entries (`+ Log Gold`) retain deletion controls.
- **Ranking Net Contribution:** Verified and updated donation ranking to calculate net contribution as `(Items Donated + Gold Deposited) - (Items Received + Gold Withdrawn)`. Direct member gold withdrawals (`[GOLD OUT]`) are subtracted from member totals while guild repairs and tab purchases remain completely excluded.

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