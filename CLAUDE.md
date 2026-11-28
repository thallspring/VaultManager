\# Vault Manager — Project Documentation \& Handover (v1.5.0-wip)



\## 1. Project Overview \& Intent

\*\*Vault Manager\*\* is a standalone World of Warcraft guild bank management, request fulfillment, and accounting addon written in pure \*\*Lua 5.1\*\* (no external libraries such as Ace3).



\* \*\*Target Environment:\*\* WoW Forever (a custom Classic Era 1.15.x / Interface `16001` server).

\* \*\*Distribution:\*\* Published on CurseForge. \*\*Hardcoding guild names, character names, or server-specific member data is strictly prohibited.\*\* Everything must work generically for any guild.

\* \*\*Current Release State:\*\* `VaultManager.toc` is intentionally held at `Version: 1.4.3` to prevent triggering a CurseForge release while `v1.5.0` is under active development and in-game testing.

\* \*\*Core Goal:\*\* Give guild members live visibility into Guild Bank inventory and pricing rules, let them submit item and gold requests, give officers a streamlined withdrawal/delivery workflow (Guild Bank → Mail/Trade), and maintain a zero-sum, P2P-synchronized guild ledger and contribution leaderboard.



\---



\## 2. Repository Structure \& Module Responsibilities

All files load in order via `VaultManager.toc` into the shared addon namespace `VM` (`\_G.VaultManager`).



| File | Responsibility |

| :--- | :--- |

| `Core.lua` | Addon bootstrap, `VaultManagerDB` guild-bucket context switching, officer/rank checks, two-word character name resolution (`ResolveNameKey`, `GetMainFor`), class color resolution (`RAID\_CLASS\_COLORS` + fallback), price addon lookups (TSM, Auctionator, Aux, Auctioneer, vendor fallback), money formatting (`FormatMoney`, `FormatMoneyShort`, `FormatMoneyPlain`), tab rules + tamper signatures, `/vm` slash commands. Protocol constant: `VM.VERSION = 7`, prefix `VMGR\_V1`. |

| `Minimap.lua` | Circular minimap button with open-request count badge (color-coded by role/state) and status tooltip. Single source of truth for visibility is `VM.db.minimap.hide`. |

| `Comms.lua` | Throttled P2P synchronization over `GUILD` addon channel (`0.35s` queue, 255-byte payload limit with automatic `itemLink` stripping and `note`/`reason` truncation). Handles `HELLO` (randomized delay on login/reload; 15-min cooldown on zone loading screens), `INV\_META`/`INV\_TAB`/`INV\_ITEM`, `REQ`, `RULE`, `MAIN`, `TX`, `EPOCH`. Provides sync-button status (`GetSyncButtonStatus`, `RequestManualSync`). |

| `Ledger.lua` | Transaction recording (`REQUEST`, `GOLD\_REQUEST`, `WRITE\_OFF`, `GUILD\_EXPENSE`, `TAB\_PURCHASE`, `RETURN`, `BANK\_LOG`, `BANK\_MONEY\_LOG`, `MANUAL`, `MANUAL\_GOLD`, `MANUAL\_ASSIGN`), zero-sum dynamic `GUILD` subsidy/surplus calculation, `GUILD` expense categories (`RAID`, `MEMBER`, `TABS`), `ReassignTransaction`, `DeleteTransaction`, 60-day monthly compaction, and 48h bank-log deduplication. |

| `Ranking.lua` | Contribution leaderboard aggregating Ledger data per main character (excluding `GUILD` and `UNATTRIBUTED`), supporting live vs. locked pricing, period filters (`ALL`, `CURRENT`, `PREVIOUS`), Free-for-All toggle, officer hiding, and legacy member filtering. |

| `BankScanner.lua` | Scans Guild Bank tabs, item logs, and money logs. Tracks open bank state (`Scanner.isBankOpen` / `IsBankOpen()`), detects tab purchases, deduplicates officer request withdrawals against `PREPARED`/`FULFILLED` requests, auto-attributes recent trade payments, and broadcasts inventory updates. |

| `Fulfillment.lua` | Request lifecycle (`PENDING` → `APPROVED` → `PREPARED` → `FULFILLED` / `REJECTED` / `WRITTEN\_OFF`). Handles Guild Bank auto-withdrawal on `Prepare`, Mail/Trade bag attachment + stack splitting, `SendMail` hook + `TRADE\_ACCEPT\_UPDATE`/`UI\_INFO\_MESSAGE` auto-completion, plain-text Trade whisper, Guild Bank auto-open trigger, and 5s post-login relog reminder for unfulfilled `PREPARED` orders. |

| `UI.lua` | Full custom dark-themed 6-tab UI (`Vault \& Requests`, `Requests`, `Ledger`, `Ranking`, `Roster \& Mains`, `Settings`) plus modals (`Gold Request`, `Guild Expense`, `Assign`, `Export`, `Requests Help`, `RosterPicker`, `QtyPicker`, `Bank Value`) and floating delivery panels (`Mail` queue panel, `Trade` prompt, `Relog` reminder). |



\---



\## 3. Server Quirks \& Domain Rules (Must Be Preserved)



\### 3.1 Two-Word Character Names

On WoW Forever, characters often have two-word names (e.g. `Sukker Numse`, `Mango Tidecaller`).

\* Guild Roster (`GetGuildRosterInfo`) stores the full two-word name.

\* Guild Bank transaction logs sometimes record only the first word (`Sukker`, `Mango`).

\* `Core.lua` handles this generically via `VM:ResolveNameKey()` (exact match → case-insensitive exact → unambiguous first-word prefix match) and canonicalization in `VM:GetMainFor()`.



\### 3.2 Zero-Sum Accounting Model (v1.5.0)

The ledger is designed so member balances + `GUILD` account net out against actual Guild Bank value:

\* \*\*Tab Rule `PERCENT` (e.g. 50% of AH, rounded to nearest gold, min 1g):\*\*

&#x20; \* Member is charged `chargedTotalPrice` on `OUT`; paying via Mail CoD / Trade nets the member to `0g`.

&#x20; \* Remainder (`fullAH - chargedTotalPrice`) is \*\*derived dynamically\*\* in `Ledger:GetAggregatedByMain()` onto `GUILD` under category `MEMBER`: positive delta = `OUT` (`\[SUBSIDY]`), negative delta (when 1g minimum exceeds AH value) = `IN` (`\[SURPLUS]`). Never stored as duplicate P2P transactions (except rolled into `SUM\_GUILD\_ym` when a member's old transactions are actually compacted).

\* \*\*Tab Rule `FREE` (Free-for-All):\*\*

&#x20; \* Member pays `0g` in Mail/Trade (`CalculateMemberTotalPrice` returns `0`), \*\*but is debited 100% AH value in Ledger \& Ranking\*\*. No `GUILD` subsidy is created.

\* \*\*Direct Withdrawals (non-FFA tab without an `APPROVED` request):\*\*

&#x20; \* Logged as `OUT` at 100% AH value (`source = "BANK\_LOG"`, `priceMode = "DIRECT"`) so withdrawing and redepositing nets to `0g` (assuming identical valuation).

\* \*\*`GUILD` Expense Categories:\*\* `RAID`, `MEMBER`, `TABS`. Applied to `GOLD\_REQUEST`, `GUILD\_EXPENSE`, `TAB\_PURCHASE`, and any `Reassign` to `GUILD` (including item `IN` deposits such as raid loot/Onyxia scales deposited by a raider).

\* \*\*Departed Officer `Write Off`:\*\* If an officer holding a `PREPARED` order leaves the guild (`VM:IsLegacyMember(req.preparedBy)`), another officer can confirm `Write Off`, charging 100% AH value / gold to the departed officer (`source = "WRITE\_OFF"`).



\### 3.3 Request Ownership \& Security Constraints

\* Officers are never prompted to deliver another officer's `PREPARED` orders (`preparedBy` ownership).

\* Addons must \*\*never\*\* auto-click `Send Mail` or `Accept Trade`. `Fill Mail` / `Fill Trade` only populate the window; the officer manually verifies and clicks Send/Trade.

\* Whispers must use plain text (`VM:FormatMoneyPlain`, no `|cff` or texture escape codes). Allowed whispers (user decision, v1.5.0): the trade summary when the officer clicks `Fill Trade`, the payment result after a trade (incl. amount still owed), debt reminders, and status updates (approved/ready/sent/delivered/declined/CoD returned) to the member or an online alt (`Settings > Whisper members about request status`).

\* P2P sync must avoid broadcast storms in 50-player guilds (randomized delays, peer-suppression window, 15-min cooldown on zone loading screens).



\---



\## 4. Intended In-Game Workflows



1\. \*\*Member Request:\*\* Opens `/vm` (or minimap icon) → browses `Vault \& Requests` → selects quantity → clicks `Request` (or `+ Request Gold` in `Requests` tab with category `Raid`/`Member`/`Tabs`).

2\. \*\*Officer at Guild Bank:\*\*

&#x20;  \* Opens Guild Bank → VM should automatically open (to `Requests` if open orders exist, otherwise `Vault \& Requests`, controlled by `autoOpenAtBank` in Settings).

&#x20;  \* Officer clicks `Approve` (`PENDING` → `APPROVED`, soft-locks Vault stock).

&#x20;  \* Officer clicks `Prepare` → VM withdraws exact item count (splitting stacks if needed into empty general bag slots) or exact gold amount from the open Guild Bank → status becomes `PREPARED` with `preparedBy = officer` (or `FULFILLED` if officer withdrew their own request).

3\. \*\*Officer at Mailbox:\*\* Opens Mailbox → side panel lists officer's own `PREPARED` orders → clicking `Fill Mail` populates recipient, subject, CoD/Send Money, and items → officer clicks `Send` → `MAIL\_SEND\_SUCCESS` auto-completes the request.

4\. \*\*Officer in Trade:\*\* Opens Trade with a member matching a `PREPARED` order → prompt asks `"<Name> has a prepared request in your inventory. Fulfill now?"` → clicking `Fill Trade` places items/gold in Trade window and whispers payment instructions → trade completion auto-completes request and records received gold in `VM.pendingTradePayments` for bank deposit auto-attribution.

5\. \*\*Relog Reminder:\*\* 5 seconds after login, if the officer still has `PREPARED` orders assigned to them, a reminder popup opens.



\---



\## 5. Development History \& Process Context

\* Versions `1.1.0`–`1.4.3` were built and published on CurseForge.

\* `v1.5.0` refactoring was implemented across all 8 `.lua` files via GitHub web commits (in full-file passes).

\* Current build loads with \*\*zero Lua errors\*\*, and basic request tracking, class colors, and UI layout work, \*\*but live in-game testing revealed critical functional failures\*\* listed below.



\---



\## 6. Known Bugs, In-Game Test Findings \& New Requirements (Audit Priority)



\### Issue A (CRITICAL): VM Does Not Auto-Open at Guild Bank

\* \*\*Observed in game:\*\* Opening the Guild Bank does not open `VaultManagerMainFrame`, even after delaying `OnGuildBankOpened()` by `0.25s`.

\* \*\*Diagnostic data collected with Guild Bank open:\*\*

&#x20; \* `GuildBankFrame \~= nil` → `true`

&#x20; \* `GuildBankFrame:IsVisible()` → `false` (likely a bag/bank addon replaces or hides the default `GuildBankFrame`, or client uses modern interaction events)

&#x20; \* `VaultManager:IsOfficer()` → `true`

&#x20; \* `GetGuildBankWithdrawMoney()` → `450000` (45g)

&#x20; \* `PickupGuildBankItem`, `SplitGuildBankItem`, `AutoStoreGuildBankItem`, `WithdrawGuildBankMoney` → all `true`

&#x20; \* `enableChatNotifications` → `true`

\* \*\*Suspected causes to investigate:\*\*

&#x20; 1. Classic Era 1.15.x client backbone (`Interface: 16001`) may fire `PLAYER\_INTERACTION\_MANAGER\_FRAME\_SHOW` / `PLAYER\_INTERACTION\_MANAGER\_FRAME\_HIDE` (`Enum.PlayerInteractionType.GuildBanker == 10`) instead of, or differently from, `GUILDBANKFRAME\_OPENED` / `GUILDBANKFRAME\_CLOSED`.

&#x20; 2. Interaction with `UISpecialFrames` / `ShowUIPanel` / third-party bag addons (e.g. Bagnon, ElvUI, ArkInventory) closing or obscuring `VaultManagerMainFrame`.



\### Issue B (CRITICAL): `Prepare` Moves Neither Items Nor Gold, Yet Immediately Marked Self-Request as `FULFILLED`

\* \*\*Observed in game:\*\* Clicking `Prepare` did not move items or gold out of the Guild Bank, yet immediately marked the officer's own request as `FULFILLED`.

\* \*\*Root cause \& investigation targets:\*\*

&#x20; 1. `Fulfillment:ExecuteBankWithdrawSteps()` and `PrepareRequest()` (gold branch) \*\*unconditionally call `FinalizePreparedState(req, true)` without verifying\*\* that items actually arrived in the player's bags or that player money increased.

&#x20; 2. For self-requests (`IsSameRecipient(req.requester, me)`), `FinalizePreparedState()` immediately calls `CompleteRequest(..., method = "BANK")`, falsely fulfilling the order even when the withdrawal failed.

&#x20; 3. Investigate \*\*why the withdrawal API calls failed silently\*\* on this client:

&#x20;    \* `PickupGuildBankItem` + `PickupContainerItem` vs. `AutoStoreGuildBankItem` (hardware event / protected-action / taint / cursor state / `ClearCursor()` timing).

&#x20;    \* Tab loading state when `SetCurrentGuildBankTab` + `QueryGuildBankTab` is called programmatically.

&#x20;    \* Whether `WithdrawGuildBankMoney()` requires a direct hardware click without intermediate timer/wrapper or fails due to `IsBankOpen` / interaction type.

&#x20; 4. Because no order stayed in `PREPARED`, the Mailbox panel also could not be triggered/tested end-to-end. Verify Mail panel \& `PopulateMail` against both default `MailFrame` and common mail addons.



\### Issue C (HIGH): Live Gold Withdrawals Only Register After Closing \& Reopening Guild Bank

\* \*\*Observed in game:\*\* Manual gold withdrawal from the Guild Bank did not show up in the Ledger until closing and reopening the Guild Bank.

\* \*\*Investigation targets:\*\*

&#x20; \* Verify which `QueryGuildBankLog(tabIndex)` argument queries the money log on Classic 1.15.x (`MAX\_GUILDBANK\_TABS + 1` = 9 vs. 7 vs. `GetNumGuildBankTabs() + 1`).

&#x20; \* Verify whether `GUILDBANKLOG\_UPDATE` is being swallowed by `ignoreLogEventsUntil` or whether `ScanMoneyLogs()` runs \*before\* the server responds to `QueryMoneyLogThrottled()`.



\### Issue D (NEW REQUIREMENT): Officer Ledger Deletion \& Price Drift on Withdraw/Return

\* \*\*Problem described by user:\*\*

&#x20; 1. If a player withdraws an item today and returns the exact same item a week later, and the AH price changed in the meantime, the player gets credited/debited the price difference (especially under historical/locked prices or when `OUT` had a locked `chargedTotalPrice`).

&#x20; 2. When testing or when items move back and forth repeatedly, officers currently \*\*cannot delete non-manual Ledger entries\*\* (`Ledger:DeleteTransaction` restricts deletion to `tx.isManual == true`).

\* \*\*Required capabilities:\*\*

&#x20; 1. Allow officers to \*\*delete/void any Ledger transaction\*\* (not only `isManual`), with a confirmation dialog, setting `tx.deleted = true` and `tx.updatedAt = time()`, and broadcasting the tombstone via `Comms:BroadcastTransaction(tx)` so it stays deleted across all guild clients.

&#x20; 2. Guard `BankScanner:ScanLogs()` / `ScanMoneyLogs()` so deleted bank-log transactions within the 72h bank log window are \*\*not immediately re-imported\*\* on the next bank scan (important edge case: currently `existingCounts` skips `exTx.deleted == true`!).

&#x20; 3. Design a clean way to handle \*\*item returns across price changes\*\* (e.g., officer "Void / Pair Return" action or matching return deposit against an open withdrawal so both transactions net to `0g` regardless of AH price drift).



\---



\## 7. Audit Checklist for Claude Code

Before making edits, perform a full read-only review of all 8 `.lua` files and report:

1\. Exact root causes for Issues A, B, C, and D (with file paths and line numbers).

2\. Any Classic Era 1.15.x / custom-server API incompatibilities (events, container APIs, Guild Bank APIs, protected functions, `C\_Timer`, `SendMail`, `TradeFrame`).

3\. Any P2P sync / deduplication / tombstone bugs (especially re-import of deleted bank-log entries and `Comms.lua` 255-byte limits on `REQ` v7 / `TX` v7).

4\. Any accounting edge cases where Ledger totals could drift from zero-sum or diverge from Ranking.

5\. A concrete, prioritized fix plan (keeping `VaultManager.toc` at `1.4.3` until user confirms in-game tests pass).


---

## 8. Audit Status (fix/v1.5.0-audit, pending in-game verification)

**In-game Step 0 findings (WoW Forever 1.15.x):** opening the Guild Bank fires *no* `GUILDBANKFRAME_OPENED` and *no* `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`; only `GUILDBANKBAGSLOTS_CHANGED` / `GUILDBANKLOG_UPDATE`. `GuildBankFrame` exists but is not visible. `MAX_GUILDBANK_TABS = 8` (money log index 9). Bank logs record full two-word names (`Thallock Dotcom`) while `UnitName("player")` returns only the first word (`Thallock`).

**Implemented:**
* Root cause of A/B/C in the pre-audit build: `RegisterEvent("GUILDBANKFRAME_OPENED")` throws "unknown event" on the 1.15 engine, aborting `Scanner:Init()` and the rest of `PLAYER_LOGIN` init (Comms/Fulfillment/UI:Init). All optional events are now registered via `pcall` (`SafeRegister`).
* Bank session detection: ANY Guild Bank event opens a session (slot/log events may auto-open the window, money/tab events open it quietly); close via `CloseGuildBankFrame` hook, `GuildBankFrame` OnHide, close/interaction events, loading screens or 10 min idle. **No active probing** (this server does not reliably answer repeated queries; a probe-based close blocked Prepare and money logs). Withdraw/Return/Force Scan are always attempted and verified (empty cursor after pickup = bank not reachable). Auto-open is sticky for 2s against `CloseSpecialWindows`; officers get a chat summary and, with auto-open off, a reminder toast. `/vm diag` shows build and detection state.
* Prepare is verified (`BAG_UPDATE` / `PLAYER_MONEY`, 5s timeout, `UI_ERROR_MESSAGE` captured, daily withdrawal limit pre-check). Scanner auto-completion of approved requests requires an exact count.
* Log answers are never dropped (`pendingRescan`, capped chain) and money changes trigger a 2s follow-up money log query.
* Dedup keys use `VM:CanonicalActor()` (roster-resolved two-word names). Tombstones of bank-log sourced entries count as consumed log lines (no re-import) and win against peers' re-imports. `CleanupDuplicates` only tombstones copies from *different* scanners (`dupOf`, local only).
* Officers can delete any non-derived entry (confirm popup). Pair / Void Return (`Ledger:PairTransactions`, synced via TX state flag `2` + `pairId`).
* Member payments (`source = "PAYMENT"`, holder = `tx.officer`) are credited at Mail CoD / Trade delivery; the holder's later bank deposit becomes `source = "TRANSFER"` (`chargedTotalPrice` = transferred part, valued 0).
* Ranks: **admin ranks** = index 0 (Guild Master) and 1 (built-in officer rank), by index never by name (`VM:IsAdminRank/IsAdmin/IsAdminName`); only they may change configuration (officer ranks, tab rules incl. RULE sync/tamper validation, `/vm resetguild`) and they are always officers. Admins can delegate officer functions to extra ranks (`db.officerRanks = { ranks = {[idx]=true}, updatedAt, updatedBy }`, Settings > Officer Ranks, synced via `ORANKS|csv|ts|by`, accepted only from admin senders). `VM:IsOfficerRank()` (admin or delegated) gates officer actions everywhere.
* PENDING requests also reserve stock (`VM:GetReservedCount`). Window height is resizable (`prefs.windowHeight`). `VM.BUILD` marks dev builds (chat on load, header, `/vm diag`).
* Headless simulator: `sh tests/run_all.sh` (Lua 5.1 + `tests/wowmock.lua`) runs login, bank detection, withdraw/return, trade debt, sync and UI refresh scenarios.
* Comms: high/low priority queues, `INV_GOLD`, content-signature inventory broadcasts, TX/REQ byte budget, no fake `lastScan`, officer-only deletes/voids, unified `VM:IsOfficerRank()`.
* Monthly compaction paused (`VM.COMPACTION_ENABLED = false`); 90-day tombstone purge still runs.
* Request workflow (UI `RefreshRequests`): APPROVED → `Withdraw` (PrepareRequest) → `Fulfill` (`Fulfillment:FulfillPrepared`, local `fulfillStarted[reqID]`) → `Complete` (auto on MAIL_SEND_SUCCESS / trade complete, manual fallback after Fulfill) plus `Return` (`ReturnPreparedRequest`: verified deposit back to the request's tab, then release) and `Cancel`. Button states: active / disabled / done (`ApplyButtonState`).
* Members cancel own PENDING/APPROVED requests (`CancelOwnRequest`: status `REJECTED` + `completedMethod = "CANCELLED"`; Comms accepts this from non-officers only for their own request). Duplicate open requests per item/tab are blocked; max 6 stacks per request (`VM:GetMaxRequestQty`).
* Debt: trade payments are split per delivered request (`PAYMENT` with `fulfillmentId`). `Fulfillment:GetOwedAmount` = quoted price − payments − write-offs (TRADE deliveries only). `MarkDebtPaid` records a late PAYMENT; `WriteOffDebt` records `DEBT_WRITEOFF` IN on the member + OUT on GUILD (Member). Requests with debt are not pruned.
* Delivery module (`Delivery.lua`, loaded after Fulfillment): name variants (full roster name first, first-name fallback; `db.nameFormat` remembers per character), online lookup incl. alts, whisper fallback on `ERR_CHAT_PLAYER_NOT_FOUND_S`, mail recipient fallback on "cannot find player", member status messages (`OnRequestUpdated` from Comms), CoD tracking (`db.pendingCod`, settled from `MAIL_INBOX_UPDATE` "COD Payment" mail; returned mail -> `MarkCodReturned`), auto-fill next mail, `WithdrawAllApproved` batch.
* Price is locked at Approve (`priceAtRequest`/`quotedTotalPrice`) and used by `RecordFulfillment`, scanner self-withdrawals, CoD and debt. `RecordFulfillment`/`RecordGoldFulfillment` set `rawSender` = withdrawing officer (`preparedBy` or completer) so bank-log dedupe matches the officer's log line.
* Withdraw claim: `PrepareRequest` broadcasts APPROVED + `preparedBy = me` and waits 1s; same-second ties resolve to the lower name (Comms REQ). Claims expire after 120s. `prepareBusy` covers claim + withdrawal.
* Auto-complete from Mail/Trade only matches PREPARED orders of this officer. Payment states: `GetOwedAmount` covers TRADE always and MAIL/MANUAL completed after `VM.PAYMENT_TRACKING_SINCE`; MAIL = "Awaiting CoD", others = "Owes". Trade money pays delivered requests, then older debts (`GetOutstandingRequests`), then counts as contribution. `CompleteManually(reqID, paid)` via the Complete popup.
* Scanner auto-pairs a deposit with a matching direct/FFA withdrawal by the same actor within 6h (`Ledger:FindQuickReturnMatch`). `CompleteRequest` from APPROVED (no VM withdrawal) tombstones the officer's matching manual OUT within 48h (`ReconcileDirectWithdrawal`).
* Guild-wide reset (two-step): admin `VM:RequestGuildReset()` (typed RESET popup / `/vm resetguild`) -> `RESETREQ|id|by|at` stored as `db.pendingReset` (24h) -> Guild Master (rank 0) approves via popup (typed RESET) -> `VM:ResetGuildData()` bumps `dbEpoch`, `VM:WipeGuildData()` (ledger, requests, inventory, pendingCod; config kept) and sends `EPOCH|n|approvedBy|at`. EPOCH is accepted only from admin senders with a GM `approvedBy`; HELLO never wipes. Admins re-announce EPOCH to lagging peers and re-announce pending requests when the GM says HELLO. Messages from peers on an older epoch are ignored (`peerEpochs`). `RESETDECLINE` from the GM clears the request.
* Compatibility with released 1.4.2/1.4.3 (protocol 6): they adopt ANY higher epoch (EPOCH or HELLO, no checks) and also wipe tab rules + alt links. A GM reset therefore resets them too; `ResetGuildData` picks an epoch above `Comms.maxSeenEpoch` and re-sends RULE/ORANKS/MAIN after 3s so 1.4.x clients get their config back (they accept RULE/MAIN from rank 0/1). A reset started from a 1.4.x client is rejected by 1.5.0 clients (no GM approval). 1.4.x clients ignore unknown messages (RESETREQ, ORANKS, INV_GOLD) and extra fields; they value TRANSFER/voided pairs differently, so their Ledger totals can differ until they update.
