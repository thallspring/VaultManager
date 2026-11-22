# Vault Manager — Project Instructions & Architecture

Vault Manager is a World of Warcraft addon designed for guild bank inventory sharing, request queues, peer-to-peer (P2P) synchronization, and main/alt value ledger tracking with Auctionator integration.

---

## 1. Project Overview

- **Addon Name:** Vault Manager (`VaultManager`)
- **Addon Prefix:** `VMGR_V1`
- **SavedVariables:** `VaultManagerDB`
- **Compatibility:** World of Warcraft Classic / TBC / Retail (Interface versions: `11509`, `16001`, `20506`)
- **Key Features:**
  - **Guild Bank Scanning & Inventory:** Automatic and manual scanning of bank tabs, item counts, links, and icons.
  - **P2P Synchronization:** Real-time syncing of inventory, requests, tab rules, main/alt links, and ledger transactions across guild members using addon messages.
  - **Request & Fulfillment Queue:** Members can request items from bank tabs; officers can approve, reject, and fulfill requests with automated Mail (with COD pricing) and Trade auto-filling.
  - **Main/Alt Ledger & Valuation:** Tracks item and gold deposits/withdrawals, aggregates contributions by active main characters, supports historical vs. live Auctionator pricing, and provides donation leaderboards (Total, Pure Gold, Mats + Gear).
  - **Modern UI:** Custom dark-themed interface with 5 tabs, searchable roster pickers, and a minimap button with notification badges.

---

## 2. Module Architecture

The addon follows a modular table structure attached to the addon namespace (`VM = {}`). Files are loaded in the order specified in `VaultManager.toc`:

1. **`Core.lua`**
   - Initializes the addon namespace, default database structure, and SavedVariables (`VaultManagerDB`).
   - Provides character name normalization (`VM:NormalizeName`), officer permission checks (`VM:IsOfficer`), guild roster caching, and main/alt mapping logic (`VM:GetMainFor`, `VM:SetMainCharacter`).
   - Integrates with Auctionator API (`Auctionator.API.v1.GetAuctionPriceByItemID`) for item pricing.
   - Handles addon loading, login events, message prefix registration, and slash commands (`/vm`, `/vaultmanager scan`).

2. **`BankScanner.lua`**
   - Listens to guild bank events (`GUILDBANKFRAME_OPENED`, `GUILDBANKBAGSLOTS_CHANGED`, `GUILDBANKLOG_UPDATE`, `GUILDBANK_UPDATE_MONEY`, `GUILDBANK_UPDATE_TABS`).
   - Scans all guild bank tabs, item stacks, and logs.
   - Records unassigned or attributed item and gold deposits into the ledger and triggers P2P broadcasts.

3. **`Comms.lua`**
   - Manages P2P communication over the `VMGR_V1` addon channel.
   - Implements a throttled outbound message queue (`OnUpdate`, `THROTTLE_INTERVAL = 0.20s`) to avoid disconnects.
   - Handles sync handshakes (`HELLO`) and incremental broadcasts for inventory metadata, tabs, items, requests, tab rules, main/alt links, and ledger transactions.

4. **`Ledger.lua`**
   - Manages financial and item transaction logs (`IN`, `OUT`, `GOLD_IN`).
   - Calculates transaction values using live Auctionator prices or historical prices recorded at transaction time.
   - Aggregates contributions by active main characters and handles legacy member detection.
   - Provides donation ranking modes (`TOTAL`, `GOLD`, `ITEMS`).

5. **`Fulfillment.lua`**
   - Manages the request lifecycle: creation by members, approval/rejection by officers, and completion.
   - Integrates with the mail window (`MAIL_SHOW`, `MAIL_SEND_SUCCESS`) to populate recipient, subject, items, and COD amounts.
   - Integrates with the trade window (`TRADE_SHOW`, `TRADE_ACCEPT_UPDATE`) to auto-populate trade slots.
   - Displays a popup for officers when opening the guild bank with pending/approved orders.

6. **`UI.lua`**
   - Builds the main window (`VaultManagerMainFrame`) with 5 navigation tabs:
     1. *Vault & Requests* (Inventory browser, search, tab switching, request creation).
     2. *Requests* (Order status tracking, officer approval/fulfillment controls).
     3. *Ledger* (Aggregated main ledger, transaction history, gold deposit logging, unassigned deposit assignment).
     4. *Ranking* (Top donors leaderboard by Total, Gold, or Mats+Gear).
     5. *Settings & Mains* (Guild bank tab rules: Free, % of AH, Locked; Alt-to-Main character linking and unlinking).
   - Implements custom UI widgets: modern dark buttons, edit boxes, custom scroll areas, and a searchable roster dropdown picker (`VaultManagerRosterPicker`).

7. **`Minimap.lua`**
   - Creates a minimap button with drag-to-reposition functionality, left/right click toggling, tooltip instructions, and a notification badge displaying the count of pending/approved requests.

---

## 3. Coding Standards & Conventions

- **Namespace Pattern:** All files use local module definitions assigned to the shared addon table:
  ```lua
  local _, VM = ...
  VM.ModuleName = {}
  local ModuleName = VM.ModuleName
  ```
- **UI Styling & Theme:**
  - Strict adherence to the `THEME` table defined in `UI.lua` (consistent dark backgrounds, borders, and accent colors).
  - Use of `BackdropTemplate` and `BackdropTemplateMixin` for all custom frames.
- **Data Integrity & Normalization:**
  - Character names are always normalized via `VM:NormalizeName(name)` (trimming realm names and capitalizing properly).
  - SavedVariables are initialized using deep default copying (`DeepCopyDefaults`).
- **Performance & Networking:**
  - Addon messages must be queued and throttled through `Comms` to prevent chat flood and addon message throttling by the WoW client.
  - Timestamps are used for conflict resolution during peer-to-peer sync.
- **Code Style:**
  - Explicit function definitions, minimal comments focusing on *why*, strict type safety checks, and modular separation of concerns across files.
