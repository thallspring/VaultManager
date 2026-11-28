-- Admin ranks (0 Guild Master, 1 officer rank) alone may change configuration; delegated ranks may not
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local function check(label, cond) say(cond and "  OK  " or "  FAIL", label) end
table.insert(M.roster, { "Boss Master", "Guild Master", 0, 60, "Warrior", "", "", "", true, 0, "WARRIOR" })
local VM = M.load(arg[1], { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
local function recv(msg, sender) M.fire("CHAT_MSG_ADDON", "VMGR_V1", msg .. "|Test Guild", "GUILD", sender) end

check("officer rank (1) is admin", VM:IsAdmin())
VM:SetOfficerRank(2, true)
check("admin delegates Raid Leader", VM:IsOfficerName("Raidboss Lead") and not VM:IsAdminName("Raidboss Lead"))
VM:SetOfficerRank(1, false)
check("admin rank cannot be removed", VM:IsOfficerRank(1))

-- A delegated officer (Raid Leader) tries to add the Member rank via sync -> rejected
recv("ORANKS|2,3|1764399999|Raidboss Lead", "Raidboss")
check("ORANKS from delegated rank rejected", not VM:IsOfficerRank(3))
-- A tab rule from a delegated rank is rejected
local sig = VM:ComputeRuleSignature("Test Guild", 1, { mode = "FREE", percent = 50, updatedBy = "Raidboss Lead", updatedAt = 1764399999 })
recv("RULE|1|FREE|50|1764399999|Raidboss Lead|" .. sig, "Raidboss")
check("RULE from delegated rank rejected", VM.db.tabRules[1] == nil or VM.db.tabRules[1].updatedBy ~= "Raidboss Lead")

-- Guild-wide valuation: default "at time of entry"; admin switches to live and it syncs
check("default valuation is at time of entry", VM:GetValuationMode() == "locked")
local tx = VM.Ledger:RecordDeposit("Mango", 14047, M.items[14047].link, 20, "BANK_LOG")
tx.unitPriceAtTime = 999
check("stored value used for display", VM.Ledger:GetTransactionValue(tx) == 999 * 20)
VM:SetValuationMode("live"); M.advance(5)
local sentVal = false for _, m in ipairs(M.sent) do if m:find("^VALMODE|live|") then sentVal = true end end
check("admin switch to live is broadcast", sentVal and VM:GetValuationMode() == "live")
check("live value used after switch", VM.Ledger:GetTransactionValue(tx) == 400 * 20)
recv("VALMODE|locked|1764399999|Raidboss Lead", "Raidboss")
check("valuation change from delegated rank rejected", VM:GetValuationMode() == "live")
recv("VALMODE|locked|1764399999|Boss Master", "Boss")
check("valuation change from admin accepted", VM:GetValuationMode() == "locked")

-- Local client running as the delegated Raid Leader
M.playerRank = 2; M.playerName = "Raidboss"
check("delegated rank is officer", VM:IsOfficer())
check("delegated rank is not admin", not VM:IsAdmin())
VM:SetOfficerRank(3, true)
check("delegated rank cannot change officer ranks", not VM:IsOfficerRank(3))
VM:SetTabRule(1, "PERCENT", 50)
check("delegated rank cannot change tab rules", VM.db.tabRules[1] == nil or VM.db.tabRules[1].mode ~= "PERCENT")
VM:SetValuationMode("live")
check("delegated rank cannot change valuation", VM:GetValuationMode() == "locked")

-- Plain member
M.playerRank = 3; M.playerName = "Mango"
check("member is not officer", not VM:IsOfficer())
VM.UI:Toggle(); VM.UI:SelectTab(6); M.advance(1)
M.dumpErrors("final")
