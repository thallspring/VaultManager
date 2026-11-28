local root = arg[1]
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local function check(label, cond) say(cond and "  OK  " or "  FAIL", label) end
local VM = M.load(root, { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
M.bank.open = true
M.fire("GUILDBANKBAGSLOTS_CHANGED"); M.advance(3)
-- tab rule 50% so payments are due
VM:SetTabRule(1, "PERCENT", 50)

-- 1) Member Mango requests 20 Runecloth via sync
local function recv(msg, sender) M.fire("CHAT_MSG_ADDON", "VMGR_V1", msg .. "|Test Guild", "GUILD", sender) end
recv("REQ|REQ_Mango_1|Mango|14047|20|1|PENDING|1764299000|1764299000|||400|PERCENT|50|Runecloth||0|0|10000|0||||0|", "Mango")
local r = VM.db.requests["REQ_Mango_1"]
check("member request received", r and r.status == "PENDING")
-- member cancel of someone else's request must be rejected
recv("REQ|REQ_Mango_1|Mango|14047|20|1|REJECTED|1764299000|1764299100|||400|PERCENT|50|Runecloth||0|1764299100|10000|0||CANCELLED||0|", "Raidboss")
check("foreign cancel rejected", VM.db.requests["REQ_Mango_1"].status == "PENDING")

-- 2) Officer ranks: Raid Leader (rank 2) becomes officer
check("raid leader not officer by default", not VM:IsOfficerName("Raidboss Lead"))
VM:SetOfficerRank(2, true)
check("raid leader officer after setting", VM:IsOfficerName("Raidboss Lead"))
M.advance(15)
local sentORanks = false for _, m in ipairs(M.sent) do if m:find("^ORANKS|[%d,]*2") then sentORanks = true end end
check("ORANKS broadcast", sentORanks)
for _, m in ipairs(M.sent) do if #m > 255 then say("  OVERSIZE", #m, m:sub(1,40)) end end

-- 3) Approve + Withdraw (bank events not answered any more)
_G.QueryGuildBankTab = function() end; _G.QueryGuildBankLog = function() end
VM.Fulfillment:ApproveRequest("REQ_Mango_1")
VM.Fulfillment:PrepareRequest("REQ_Mango_1"); M.advance(6)
r = VM.db.requests["REQ_Mango_1"]
check("withdraw -> PREPARED", r.status == "PREPARED")
local bagCount = 0 for s, it in pairs(M.bags[0]) do if it.id == 14047 then bagCount = bagCount + it.count end end
check("20 runecloth in bags", bagCount == 20)

-- 4) Return puts it back and releases to APPROVED
VM.Fulfillment:ReturnPreparedRequest("REQ_Mango_1"); M.advance(8)
check("return -> APPROVED", VM.db.requests["REQ_Mango_1"].status == "APPROVED")
bagCount = 0 for s, it in pairs(M.bags[0]) do if it.id == 14047 then bagCount = bagCount + it.count end end
check("bags empty after return", bagCount == 0)

-- 5) Withdraw again, trade with too little gold -> debt
VM.Fulfillment:PrepareRequest("REQ_Mango_1"); M.advance(6)
check("withdraw again -> PREPARED", VM.db.requests["REQ_Mango_1"].status == "PREPARED")
local reqs = { VM.db.requests["REQ_Mango_1"] }
VM.Fulfillment:CompleteRequest("REQ_Mango_1", { method = "TRADE" })
VM.Fulfillment:RecordDeliveryPayments("Mango", 0, "TRADE", reqs)
local owed = VM.Fulfillment:GetOwedAmount(VM.db.requests["REQ_Mango_1"])
say("     owed:", owed)
check("debt recorded", owed > 0)
local unpaid = VM.Ledger:GetUnpaidByMain()
check("ledger unpaid shown for member", unpaid["Mango Tidecaller"] and unpaid["Mango Tidecaller"].outstanding == owed)
VM.Fulfillment:WriteOffDebt("REQ_Mango_1")
check("debt cleared after write off", VM.Fulfillment:GetOwedAmount(VM.db.requests["REQ_Mango_1"]) == 0)
unpaid = VM.Ledger:GetUnpaidByMain()
check("written-off stays visible", unpaid["Mango Tidecaller"] and unpaid["Mango Tidecaller"].writtenOff == owed)
local groups = VM.Ledger:GetAggregatedByMain(false, "ALL")
local guildOut = 0 for _, g in ipairs(groups) do if g.mainName == "GUILD" then for _, tx in ipairs(g.transactions) do if tx.source == "DEBT_WRITEOFF" then guildOut = guildOut + 1 end end end end
check("GUILD (Member) write-off entry", guildOut == 1)

-- 6) Member deposits an item; officer reassigns it
M.logName = "Mango"
M.bags[0][5] = { id = 19146, count = 1 }
_G.PickupContainerItem(0, 5); _G.PickupGuildBankItem(1, 10)
VM.BankScanner:SchedulePostWithdrawScan(); M.advance(4)
local depTx for id, tx in pairs(VM.db.ledger) do if tx.type == "IN" and tx.source == "BANK_LOG" and tx.itemID == 19146 then depTx = tx end end
check("deposit imported", depTx ~= nil)
if depTx then
  VM.Ledger:ReassignTransaction(depTx.id, "GUILD", "RAID")
  check("reassign to GUILD works", depTx.player == "GUILD" and depTx.guildCategory == "RAID")
  -- 7) delete + rescan must not re-import
  VM.Ledger:DeleteTransaction(depTx.id)
  VM.BankScanner:SchedulePostWithdrawScan(); M.advance(4)
  local n = 0 for id, tx in pairs(VM.db.ledger) do if tx.type == "IN" and tx.source == "BANK_LOG" and tx.itemID == 19146 and not tx.deleted then n = n + 1 end end
  check("deleted deposit not re-imported", n == 0)
end

-- 8) Member cancels own request via sync
recv("REQ|REQ_Mango_2|Mango|14047|5|1|PENDING|1764299000|1764299000|||400|PERCENT|50|Runecloth||0|0|10000|0||||0|", "Mango")
recv("REQ|REQ_Mango_2|Mango|14047|5|1|REJECTED|1764299000|1764299200|||400|PERCENT|50|Runecloth||0|1764299200|10000|0||CANCELLED||0|", "Mango")
check("own cancel accepted", VM.db.requests["REQ_Mango_2"].status == "REJECTED" and VM.db.requests["REQ_Mango_2"].completedMethod == "CANCELLED")

-- 9) Stack limit: 6 x 20 = 120
check("max request qty runecloth 120", VM:GetMaxRequestQty(14047) == 120)
check("max request qty belt 6", VM:GetMaxRequestQty(19146) == 6)

-- 10) UI refresh of all tabs without errors
VM.UI:Toggle(); for i = 1, 6 do VM.UI:SelectTab(i) end
M.advance(1)
M.dumpErrors("final")
