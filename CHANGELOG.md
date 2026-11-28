<!-- User-facing release notes only: no file names or code internals. Use Added / Changed / Fixed / Removed. -->

# Changelog

All notable changes to **Vault Manager** will be documented in this file.

## [1.5.0] - Unreleased

### Added
- **Officer Request Workflow:** Approved requests show the buttons *Withdraw*, *Fulfill*, *Complete*, *Return* and *Cancel*. Only the next step can be clicked; finished steps turn green and dim. *Withdraw* takes the items from the right bank tab automatically, *Fulfill* fills the open Mail or Trade window, *Complete* happens automatically when the mail is sent or the trade finishes, and *Return* puts the items or gold back in the Guild Bank and sets the request back to *Approved*.
- **Cancel Your Own Requests:** Members can cancel their own pending or approved requests (and no one else's).
- **Cancel from the Vault:** Your open request can be cancelled directly from the item row in *Vault & Requests*.
- **Request Feedback:** The *Request* button changes to *Requested* right away and shows how many you have requested. A second request for the same item is blocked until the first one is cancelled, and pending requests reserve stock so nobody can request more than the bank holds.
- **Request Size Limit:** One request can hold at most 6 stacks, the most a trade window can hold (for example 6 for gear or 120 for items that stack to 20).
- **Delivery per Member:** *Fulfill* fills one mail (up to 12 attachments, combined Cash on Delivery) or one trade window with all of your prepared orders for that member. After you click *Send*, the next member's mail is filled automatically.
- **Approve + Withdraw and Withdraw All:** Approve and take out a request in one click, or take out every approved request one after another. Each one is checked, and the run stops with a clear message if one fails.
- **No Double Withdrawals:** When an officer starts a withdrawal, the request is reserved for them across the guild, so two officers can never take out the same order.
- **Payment Status:** Delivered requests are paid, awaiting payment or owed. A Cash on Delivery mail stays *awaiting payment* until the money arrives in the officer's mailbox and is then recorded automatically. If the mail comes back unpaid, the request returns to *Prepared* and the charge is reversed. *Complete* asks whether the member has already paid.
- **Member Updates:** Members see a message in Vault Manager when their request is approved, ready, sent, delivered or declined. They also get a whisper on their character or an online alt, which can be turned off in *Settings*.
- **Trade Payment Messages:** After a trade the member is told what was received and what they still owe. When they trade an officer again, older debt is shown, included in the amount to pay and settled automatically.
- **Preferred Delivery:** Members can choose *Mail* or *Trade* in *Settings*. The choice is shown on their requests.
- **Unpaid Trades:** If a member pays less than the price in the trade, the request moves to a new *Unpaid* section and shows the amount still owed. Officers can mark it *Paid* or *Write Off* the debt. Written-off amounts are charged to the guild account (*Member*) and stay visible as unpaid on that member in the *Ledger*.
- **Bank Tab on Requests:** Every item request shows which Guild Bank tab the item is in.
- **Configurable Officer Ranks:** *Settings > Officer Ranks* lets the Guild Master and the guild's officer rank give officer functions (approve, withdraw, Ledger) to additional ranks, for example *Raid Leader* or *Officer Alt*. The choice is shared with all guild members. Only the Guild Master and the officer rank can change this setting and the bank tab rules.
- **Resizable Window:** Drag the corner of the Vault Manager window to make it taller. The height is remembered.
- **Guild Bank Reminder:** Officers get a short reminder of pending, approved and prepared requests when they open the Guild Bank. If auto-open is turned off, a small pop-up with an *Open Requests* button is shown instead.
- **Prepared Requests with Officer Ownership:** Officers can now *Prepare* an approved request, which withdraws the exact items (splitting stacks into free bag slots when needed) or gold from the open Guild Bank and assigns the delivery to that officer. Officers are never asked to deliver another officer's prepared orders.
- **Verified Guild Bank Withdrawals:** *Prepare* only marks a request as prepared (or fulfilled, for your own request) after the items have actually arrived in your bags or the gold in your purse. Failed withdrawals leave the request approved and explain why (daily withdrawal limit, missing permission, missing stock, no free bag slots).
- **Write Off for Departed Officers:** Orders held by an officer who has left the guild can be written off and charged to that officer, or released back to *Approved*.
- **Mail Side Panel:** Opening a mailbox shows your prepared orders with a *Fill Mail* button that fills in recipient, subject, items and Cash on Delivery or gold. It refuses to fill if Send Mail already holds attachments or gold. Sending the mail completes the request automatically.
- **Trade Prompt:** Trading a member with a prepared order offers *Fill Trade*, which places the items or gold in the trade window and whispers the amount due in plain text. Only one gold request can be filled per trade. Completing the trade completes the request automatically.
- **Relog Reminder:** After logging in, officers are reminded about prepared orders that are still waiting for delivery.
- **Auto-Open at Guild Bank:** Vault Manager opens automatically at the Guild Bank (on *Requests* when orders are waiting, otherwise on *Vault & Requests*). This can be turned off in *Settings*.
- **Gold Requests:** Members can request gold from the Guild Bank with an expense category (*Raid*, *Member* or *Tabs*).
- **Guild Expenses:** New *+ Expense* window in the *Ledger* for logging guild expenses and write-offs under the guild account.
- **Guild Bank Tab Purchases:** Buying a new Guild Bank tab is recorded automatically as a guild expense (*Tabs*).
- **Member Payments:** Cash on Delivery and trade payments for requests are credited to the paying member when the order is delivered. When the officer later deposits that gold in the Guild Bank, the deposit is booked as a transfer and does not count as the officer's personal donation.
- **Delete Any Ledger Entry:** Officers can delete any non-derived Ledger entry after confirming. The deletion syncs to all guild members, and deleted bank log entries are not re-imported by later bank scans.
- **Pair / Void Return:** Officers can pair a withdrawn item with its matching return (same member, item and count within 30 days). Both entries are voided and net to 0g, no matter how the auction price changed in between.
- **Expand / Collapse All** in the *Ledger*, a **? Help** window that explains request statuses and officer buttons, and *(Active)* tab rule tooltips for each bank tab.
- **Data Synced / Request Sync** status button in the header that checks online guild members for newer data.
- **Guild-Wide Reset with Guild Master Approval:** *Settings > Reset Guild Data* (or `/vm resetguild`) clears the Ledger, requests and vault data for the whole guild and rebuilds them from the Guild Bank logs on the next scan. Tab rules, officer ranks and alt links are kept. The Guild Master or the officer rank asks for the reset by typing *RESET*. The Guild Master must then approve it by typing *RESET* too; a request waits up to 24 hours. A Guild Master who asks for the reset approves it in the same step.
- `/vm diag` command that shows Guild Bank detection, sync queue and payment status, to help with troubleshooting.

### Changed
- **Price Lock at Approval:** The member price is fixed when a request is approved and used for the Ledger, Cash on Delivery, trade messages and debt alike.
- **Full Names First:** Mail recipients and whispers use the full two-word character name and automatically fall back to the first name if the server does not accept it. The working form is remembered.
- **Zero-Sum Guild Accounting:** On *% of AH* tabs the member is charged the discounted price (rounded to the nearest gold, minimum 1g). The rest is shown on the guild account as a *[SUBSIDY]*, or as a *[SURPLUS]* when the 1g minimum is more than the item is worth.
- **Free-for-All and Direct Withdrawals:** Items taken from Free-for-All tabs, or withdrawn without an approved request, are tracked at 100% of their auction value in the *Ledger* and *Ranking*, so taking an item out and putting it back nets to 0g.
- **Reassign** now works on every non-derived Ledger entry, including item deposits (for example raid loot) moved to the guild account with an expense category.
- **Two-Word Character Names:** Names that appear only partly in the Guild Bank log (first word only) are matched to the full guild roster name everywhere, including class colors and duplicate detection.
- **Live Prices Only:** Ledger and Ranking always value items at the current auction house price, so taking an item out and putting it back always nets to 0g. The *Historical price* and *Historical / Current values* options have been removed.
- **Settings** shows unpurchased Guild Bank tabs in a compact list.
- **Sync Protocol:** The protocol version is now 7. Request and Ledger messages go out before bulk inventory data, the inventory is only re-sent when its contents change (gold-only changes send a small update), and long messages are shortened to fit the chat channel limit instead of being dropped silently.
- **Officer Rank Detection:** Officer permissions are now determined the same way for your own client, other members' messages and tab rule checks.
- **Request Cleanup:** Completed, rejected and written-off requests are removed after 30 days.
- **Monthly Ledger Compaction** is paused for now so that all clients keep identical Ledger data. Old deletion records are still cleaned up after 90 days.

### Fixed
- Fixed Vault Manager failing to start its Guild Bank, sync and delivery features on clients that do not know the old Guild Bank open/close events.
- Vault Manager now detects an open Guild Bank on clients and bag addons that do not report it (no Guild Bank open event, hidden default Guild Bank window). Withdraw, Return and scanning no longer depend on that detection: they are attempted directly and checked afterwards.
- Fixed Vault Manager closing again right after opening automatically at the Guild Bank.
- Fixed *Prepare* doing nothing, and fixed requests being marked as fulfilled without the items or gold actually being withdrawn.
- Fixed a Guild Bank withdrawal by an officer with a different number of items being auto-matched to an approved request.
- Fixed gold deposits and withdrawals only appearing in the *Ledger* after closing and reopening the Guild Bank.
- Fixed deleted Ledger entries coming back after the next bank scan or from other guild members.
- Fixed two identical transactions by the same member within two days being merged into one.
- Fixed a member with no bank data being able to wipe the vault view for the whole guild.
- Fixed any guild member being able to trigger a guild-wide data reset. Resets now need the Guild Master's approval, and members who missed a reset can no longer send old data back.
- Fixed attaching several stacks to Send Mail overwriting the first attachment.
- Fixed members being charged a different price in the Ledger than the amount they were asked to pay.
- Fixed Mail and Trade completing approved requests that were never withdrawn through Vault Manager.
- Fixed a member's own withdrawal being ignored for three days after a request for the same item was delivered to them.
- Fixed items taken out by hand and then completed being charged twice; an item taken out and put back shortly after now cancels out automatically.
- Fixed the *X* in the mail panel releasing an order while the items stayed in the officer's bags.
- Fixed pressing Escape in Vault Manager also opening the game menu.
- Fixed the minimap button sitting inside the minimap. It now sits on the outer edge like other addon buttons and follows the minimap's size and shape.
- Fixed a double click on a request button triggering the next action after the button changed.
- Fixed the relog reminder sometimes not appearing because guild rank information was not loaded yet.

### Removed
- Removed the unused automatic return tracking, which is replaced by *Pair / Void Return*.

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
