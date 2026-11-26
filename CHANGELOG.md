<!-- User-facing release notes only: no file names or code internals. Use Added / Changed / Fixed / Removed. -->

# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## v1.4.4 (2026-11-26)

### New Features
- **Gold Requests for Guild Expenses:** Members and officers can now submit gold requests with an expense reason from the **Requests** tab. Approved gold requests pre-fill *Send Money* in Mail or Trade and are booked directly to the dedicated **GUILD** account instead of the member's personal balance.
- **Dedicated GUILD Account & Reassignment:** Added a system **GUILD** account for guild operations (AH sales, guild purchases, external donations). Officers can reassign `[GOLD IN]`, `[GOLD OUT]`, and item `[OUT]` entries in the **Ledger** to **GUILD** or any member while preserving the original actor. **GUILD** is excluded from **Ranking**.
- **Quantity Dropdown Picker:** Replaced the manual quantity input box in **Vault & Requests** with a scrollable dropdown selector that updates `% of AH` total prices live.
- **Automatic Request Completion:** Approved item and gold requests now auto-complete when fulfilled via Guild Bank withdrawal, Mail, or Trade, recording the delivery method and officer.
- **Rank-Grouped Roster & Foldable Sections:** **Roster & Mains** now groups mains by foldable guild ranks (keeping linked alts nested under their main regardless of alt rank) with an officer **Unlinked Only** filter and collapsed **Legacy Members** section. **Requests** is organized into foldable *Pending*, *Approved*, and collapsed *History* sections with an open-request counter on the tab.

### Improvements & UI Polish
- **1g Member Price Rounding:** `% of AH` item requests and manual assignments now round total prices to the nearest gold (minimum 1g) consistently across Requests, Mail CoD, Ledger, and Ranking.
- **Requests Workflow & Metadata:** Reordered approved request buttons to `Prepare` (blue) → `Complete` (green) → `Cancel` (red), and expanded rows to two lines showing request time, approving officer, and completion/cancellation details.
- **Ledger, Ranking & Settings Cleanup:** Rebuilt the **Ledger** topbar with a search filter, aligned columns, and a collapsed *Legacy Members* group; added color-coded positive/negative `Net Balance` values in **Ranking**; compressed unpurchased bank tabs in **Settings**, fixed button overlap on tab rules, and removed the unused *Rule Signatures* counter.
- **Minimap Button Upgrade:** Switched to a Vault chest icon with an event-driven, color-coded request badge (removed background polling), status tooltip, and right-click shortcut to **Requests**.
- **P2P Sync & Performance:** Added delta-sync with randomized response delay, 255-byte payload protection, ghost-item cleanup on newer bank scans, 30-day pruning of closed requests, 90-day tombstone cleanup, search debouncing, and reduced `GUILD_ROSTER_UPDATE` overhead.

### Bug Fixes
- Fixed non-purchased bank tabs (e.g., Tab 2) temporarily appearing in **Vault & Requests** or affecting **Bank Value**.
- Fixed player names occasionally appearing white instead of class-colored in **Ledger** and **Requests** on first open.
- Fixed an item-matching bug in Mail/Trade auto-fill for items without an `itemID`.
- Fixed the **Show Minimap Button** setting toggle not hiding/showing the button reliably.
- Fixed compressed monthly `SUMMARY` rows displaying as gold entries when expanded in **Ranking**.

## [1.4.3] - 2026-11-25

### Added
- **Crafting Reagents Category:** Added a dedicated *Crafting Reagents* category in *Vault & Requests* for items marked as crafting reagents.
- **Custom UI Scaling & Reset Command:** Replaced the fixed scale buttons in *Settings* with a custom percentage input (50%–200%) and added the `/vm reset` command to restore 100% scale and center the window on screen.
- **Controller & Keyboard Navigation:** Added gamepad and keyboard navigation support for switching tabs, moving through lists, toggling categories, activating buttons, and closing dialogs.

### Changed
- **Ledger Sorting:** Member groups in the *Ledger* tab are now ordered with the most recent donor at the top while keeping individual entries nested under each member.
- **Window Layering:** Raised the Vault Manager window and popups above other addon frames so they stay visible in front of overlays such as quest trackers, and prevented windows from being dragged off-screen.

### Fixed
- Fixed incomplete bank scans overwriting cached guild bank items during peer-to-peer syncing when item data had not finished loading.
- Fixed guild bank log timestamp parsing and duplicate ledger entries when multiple guild members scan the bank, including automatic cleanup of existing duplicates.
- Fixed gold donations and withdrawals failing to sync automatically after bank money log scans or being filtered out by duplicate detection.
- Fixed the header status button occasionally staying stuck on *Scanning...* after a bank scan completed.

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
