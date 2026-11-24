<!-- User-facing release notes only: no file names or code internals. Use Added / Changed / Fixed / Removed. -->

# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## [1.4.2] - 2026-11-24

### Added
- **Categorized Vault View:** Items in *Vault & Requests* are now grouped into collapsible categories (*Gear*, *Consumables*, *Crafting Mats*, *Recipes*, and *Other*), starting collapsed by default and expanding automatically when searching.
- **Manual Item Assignment:** Officers can now assign vault items directly to any guild member (including members without the addon) with automatic rule-based pricing and optional immediate payment logging.
- **Free-for-All Filter:** Added an *Include Free-for-All* toggle on both the *Ledger* and *Ranking* tabs to include or exclude Free-for-All tab activity from transaction lists and member balances.

### Changed
- **Discounted Member Pricing in Ledger:** Withdrawals and deliveries from *% of AH* tabs now record at the discounted member price in the Ledger so member gold payments balance out accurately.
- **Unpurchased Guild Bank Tabs:** Tabs that have not yet been purchased in the guild bank are now disabled and clearly labeled *Not purchased* in *Settings*.

### Fixed
- Fixed unpurchased guild bank tabs falsely triggering rule tamper resets.
- Fixed an issue where items synced from other guild members could fail to categorize properly until cached locally.

## [1.4.0] - 2026-11-24

### Added
- Six-tab navigation layout with dedicated Settings tab for guild bank rules and preferences.
- Automated guild bank tab rule synchronization among officers with anti-tamper signature protection.
- Peer-to-peer addon version handshaking and update alerts in the header.
- Historical vs. live valuation basis toggles and ASCII sort indicators in ranking leaderboards.
- Class colorization for member names across all tabs and status indicators in the header.

### Fixed
- Item tooltip hover errors on WoW 1.60.1 client.

## [1.3.5] - 2026-11-24

### Fixed
- Database splitting issues caused by empty realm strings during early load on WoW 1.60.1.
- Logout and login data loss bugs by preserving guild data without premature purging.

## [1.3.4] - 2026-11-24

### Added
- Global valuation mode toggle with historical price fallbacks.
- Multi-column sorting with persistent preferences.
- Legacy member filter and export options.

## [1.3.3] - 2026-11-24

### Fixed
- UI preferences crash guard and defensive sub-table initialization.
- Top-level slash command registration for /vm.
- Header version display and layout overlap.

## [1.3.2] - 2026-11-24

### Added
- Strict per-guild data isolation and automated migration.
- Guild join and leave detection with automatic cleanup.
- Strict guild verification in peer-to-peer communications.

## [1.3.1] - 2026-11-24

### Added
- Live AH valuation default and price mode selection.
- Clarified locked versus current price labels and color-coded comparison highlighting.
- Dynamic addon version display in the header.

### Fixed
- Guild bank log deduplication using a rolling time window.

## [1.3.0] - 2026-11-24

### Added
- Stable log deduplication and time bucketing.
- Strict price locking against scan overwrites.
- Clock-skew protection and sync provenance tracking.
- Fulfillment confirmation modal and value-neutral bank returns.
- Edge-case hardening for tab viewability, FIFO trade matching, and audit detection.
- Live search, tab filters, tooltip valuation breakdowns, and main/alt ranking grouping.

## [1.2.2] - 2026-11-23

### Added
- Interactive tooltips across Vault, Ledger, and Ranking tabs.
- Persistent item linking on all scanned vault items and transactions.

## [1.2.1] - 2026-11-23

### Added
- Modern custom dropdown menu for ranking period selection.

### Fixed
- Infinite scan loop and chat spam prevention.

## [1.2.0] - 2026-11-23

### Added
- Expandable nested ranking breakdown for player transactions.
- Officer payment tracking with trade-to-bank auto-attribution and manual gold reassignment.
- Automatic scanning with dynamic status button.
- Multi-addon AH pricing support and peer snapshots.
- Markdown and CSV data export options.
- Automated monthly history compaction.

## [1.1.6] - 2026-11-23

### Added
- Net contribution ranking calculations factoring in donations and withdrawals.

### Fixed
- Restricted automatically scanned entries to read-only status.

## [1.1.5] - 2026-11-23

### Added
- Gold withdrawal tracking in guild bank money logs.
- Ledger and ranking integration for direct member gold withdrawals.

## [1.1.4] - 2026-11-23

### Fixed
- Zero-amount unattributed gold entries and automatic startup cleanup.
- Asynchronous guild bank log scanning and transfer parsing.

## [1.1.3] - 2026-11-23

### Fixed
- Prevented guild bank scans from overwriting cached inventory before server data arrives.
- Deterministic transaction log deduplication on repeated scans.
- Officer rank verification fallback and newer version alerts.

## [1.1.0] - 2026-11-22

### Added
- Packaging configuration for automated release distribution.

### Fixed
- Item parsing and stack counting for items lacking full item ID links.
- Disconnect prevention when scanning invalid item links.
- Item and gold transaction log parsing for accurate member attribution.
- Display error when opening data export dialog in the Ranking tab.

## [1.0.0] - 2026-11-22

### Added
- Initial release of Vault Manager with guild bank inventory scanning, item request queue, donation ledger, main/alt ranking, and guild peer-to-peer synchronization.
