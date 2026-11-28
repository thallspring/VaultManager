-- Guild-wide reset: admin request -> Guild Master approval -> peers adopt; forged/old-epoch data rejected
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local function check(label, cond) say(cond and "  OK  " or "  FAIL", label) end
table.insert(M.roster, { "Boss Master", "Guild Master", 0, 60, "Warrior", "", "", "", true, 0, "WARRIOR" })
local VM = M.load(arg[1], { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Delivery.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
M.bank.open = true; M.fire("GUILDBANKBAGSLOTS_CHANGED"); M.advance(3)
local function recv(msg, sender) M.fire("CHAT_MSG_ADDON", "VMGR_V1", msg .. "|Test Guild", "GUILD", sender) end
local function sentMatching(pat) for _, m in ipairs(M.sent) do if m:find(pat) then return m end end end
VM:SetTabRule(1, "PERCENT", 50)
VM.Ledger:RecordGoldDeposit("Mango", 50000, "MANUAL_GOLD")
recv("REQ|R1|Mango|14047|20|1|PENDING|1764299000|1764299000|||1|PERCENT|50|Runecloth||0|0|1|0||||0|", "Mango")
local function ledgerCount() local n = 0 for _ in pairs(VM.db.ledger) do n = n + 1 end return n end
check("data present before reset", ledgerCount() > 0 and VM.db.requests.R1 ~= nil)

-- 1) A member forges a reset -> ignored
recv("EPOCH|99|Boss Master|1764300000", "Mango")
recv("HELLO|7|50|0|0|0|0|0|1.4.3", "Mango")
check("forged EPOCH / HELLO from member ignored", VM.db.dbEpoch == 1 and ledgerCount() > 0)

-- 2) Officer (rank 1, not GM) requests -> nothing deleted yet, request broadcast
VM:RequestGuildReset(); M.advance(2)
check("officer request does not delete anything", ledgerCount() > 0 and VM.db.dbEpoch == 1)
check("reset request broadcast", sentMatching("^RESETREQ|") ~= nil)
local pending = VM:GetPendingReset()

-- 3) The Guild Master's client receives it, gets the approval popup and approves
M.playerRank = 0; M.playerName = "Boss"
M.lastPopup = nil
VM.db.pendingReset = nil
recv(string.format("RESETREQ|%s|%s|%d", pending.id, pending.by, pending.at), "Thallock")
check("GM gets approval popup", M.lastPopup and M.lastPopup.which == "VAULTMANAGER_RESET_APPROVE")
VM:ApproveGuildReset(pending.id); M.advance(2)
check("GM reset wipes data, keeps tab rules", ledgerCount() == 0 and next(VM.db.requests) == nil and VM.db.tabRules[1] and VM.db.tabRules[1].mode == "PERCENT")
check("epoch bumped and announced with GM approval", VM.db.dbEpoch == 2 and sentMatching("^EPOCH|2|Boss Master|") ~= nil)

-- 4) A member client (still epoch 1) receives the EPOCH from an admin -> adopts
M.playerRank = 3; M.playerName = "Mango"
VM.db.dbEpoch = 1; VM.Ledger:RecordGoldDeposit("Mango", 1234, "MANUAL_GOLD")
recv("EPOCH|2|Boss Master|1764300000", "Boss")
check("member adopts GM-approved reset", VM.db.dbEpoch == 2 and ledgerCount() == 0)

-- 5) A peer that missed the reset (epoch 1) cannot push old data back
recv("HELLO|7|1|0|0|0|0|1764300000|1.4.3", "Raidboss")
recv("TX|OLD_1|IN|Raidboss Lead|0|1|90000|0|1764200000|Raidboss|BANK_MONEY_LOG|Gold Deposit|GOLD|0|1764200000|||||||0|", "Raidboss")
check("old-epoch peer data ignored", VM.db.ledger.OLD_1 == nil)

-- 6) Decline path
M.playerRank = 1; M.playerName = "Thallock"
VM:RequestGuildReset(); local p2 = VM:GetPendingReset()
M.playerRank = 0; M.playerName = "Boss"
VM:DeclineGuildReset(p2.id); M.advance(1)
check("GM decline clears request and is broadcast", VM:GetPendingReset() == nil and sentMatching("^RESETDECLINE|") ~= nil)

VM.UI:Toggle(); VM.UI:SelectTab(6); M.advance(1)
M.dumpErrors("final")
