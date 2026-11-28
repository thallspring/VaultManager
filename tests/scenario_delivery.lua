-- Delivery & payment chain: price lock, claims, batch withdraw, per-member mail/trade, CoD tracking,
-- trade debt whispers, manual complete, quick-return auto-pair, reconciliation, name fallback
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local function check(label, cond) say(cond and "  OK  " or "  FAIL", label) end
local VM = M.load(arg[1], { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Delivery.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
M.roster[2][9] = true -- Mango online
M.bank.open = true
M.bank.tabs[1][4] = { id = 14047, count = 20 }
M.fire("GUILDBANKBAGSLOTS_CHANGED"); M.advance(3)
VM:SetTabRule(1, "PERCENT", 50)
local function recv(msg, sender) M.fire("CHAT_MSG_ADDON", "VMGR_V1", msg .. "|Test Guild", "GUILD", sender) end
local function lastWhisper() return M.whispers[#M.whispers] end
local function anyWhisper(pat) for _, w in ipairs(M.whispers) do if w.msg:find(pat) then return w end end end

-- Member requests 20 + 20 runecloth (two requests), preferred delivery: trade
recv("REQ|R1|Mango|14047|20|1|PENDING|1764299000|1764299000|||1|PERCENT|50|Runecloth||0|0|1|0||||0||TRADE", "Mango")
recv("REQ|R2|Mango|14047|20|1|PENDING|1764299001|1764299001|||1|PERCENT|50|Runecloth||0|0|1|0||||0||TRADE", "Mango")
check("delivery pref synced", VM.db.requests.R1.deliveryPref == "TRADE")

-- 1) Price lock at approve
VM.Fulfillment:ApproveRequest("R1"); VM.Fulfillment:ApproveRequest("R2")
check("price locked at approval", VM.db.requests.R1.priceAtRequest == 400 and VM.db.requests.R1.quotedTotalPrice == 10000)
check("approve whisper to online member", anyWhisper("approved") ~= nil)

-- 2) Claim race: another officer claims R2 in the same second with a lower name
local saved = VM.db.requests.R2
recv(string.format("REQ|R2|Mango|14047|20|1|APPROVED|1764299001|%d|Aaron||1|PERCENT|50|Runecloth||%d|0|10000|0|||%s|%d|", saved.updatedAt + 5, saved.approvedAt, "Aaron", time() + 0), "Raidboss")
VM:SetOfficerRank(2, true)
recv(string.format("REQ|R2|Mango|14047|20|1|APPROVED|1764299001|%d|Aaron||1|PERCENT|50|Runecloth||%d|0|10000|0|||%s|%d|", saved.updatedAt + 5, saved.approvedAt, "Aaron", time()), "Raidboss")
check("claimed by other officer", VM.Fulfillment:GetActiveClaim(VM.db.requests.R2) == "Aaron")
VM.Fulfillment:PrepareRequest("R2"); M.advance(2)
check("cannot withdraw a request claimed by someone else", VM.db.requests.R2.status == "APPROVED")
-- claim expires / released
VM.db.requests.R2.preparedBy = ""; VM.db.requests.R2.preparedAt = 0

-- 3) Withdraw all approved
VM.Delivery:WithdrawAllApproved(); M.advance(20)
check("withdraw all -> both PREPARED", VM.db.requests.R1.status == "PREPARED" and VM.db.requests.R2.status == "PREPARED")
check("ready whisper mentions trade", anyWhisper("Open a trade") ~= nil)

-- 4) Trade: fill all, member pays 15g of 20g -> owes 5g, gets told
M.doTrade("Mango"); M.advance(0.5)
VM.Fulfillment:PopulateTradeAll("Mango"); M.advance(2)
local nItems = 0 for _ in pairs(M.trade.items) do nItems = nItems + 1 end
check("fill all placed both stacks", nItems == 2)
check("trade summary whisper with total", anyWhisper("Please enter 2g") ~= nil)
M.finishTrade(10000); M.advance(1)
check("both requests fulfilled by trade", VM.db.requests.R1.status == "FULFILLED" and VM.db.requests.R2.status == "FULFILLED")
local outstanding = VM.Fulfillment:GetOutstandingFor("Mango")
check("owes 1g after short payment", outstanding == 10000)
check("member told what they still owe", anyWhisper("still owe 1g") ~= nil)

-- 5) Next trade without orders: prompt shows debt; paying 5g settles it
M.doTrade("Mango"); M.advance(0.5)
VM.Delivery:WhisperDebtReminder("Mango")
check("debt reminder whisper", anyWhisper("Reminder: you still owe 1g") ~= nil)
M.finishTrade(10000); M.advance(1)
check("old debt settled by later trade", VM.Fulfillment:GetOutstandingFor("Mango") == 0)
check("paid-in-full whisper", anyWhisper("everything is paid") ~= nil)

-- 6) Manual complete: not paid -> owes; paid -> nothing owed
recv("REQ|R3|Mango|19146|1|1|PENDING|1764299002|1764299002|||1|PERCENT|50|Devout Belt||0|0|1|0||||0|", "Mango")
VM.Fulfillment:ApproveRequest("R3")
VM.Fulfillment:CompleteManually("R3", false)
check("manual complete not paid -> owes", VM.Fulfillment:GetOwedAmount(VM.db.requests.R3) > 0 and VM.Fulfillment:GetPaymentState(VM.db.requests.R3) == "OWES")
VM.Fulfillment:MarkDebtPaid("R3")
check("marked paid", VM.Fulfillment:GetOwedAmount(VM.db.requests.R3) == 0)

-- 7) Mail with CoD -> awaiting payment -> CoD money arrives in mailbox -> paid
M.bags[0][10] = { id = 14047, count = 20 }
recv("REQ|R4|Mango|14047|20|1|PENDING|1764299003|1764299003|||1|PERCENT|50|Runecloth||0|0|1|0||||0|", "Mango")
VM.Fulfillment:ApproveRequest("R4")
local r4 = VM.db.requests.R4; r4.status = "PREPARED"; r4.preparedBy = VM:GetPlayerName()
M.fire("MAIL_SHOW"); MailFrame:Show()
VM.Fulfillment:PopulateMailFor("Mango"); M.advance(2)
check("mail recipient uses full roster name", SendMailNameEditBox:GetText() == "Mango Tidecaller")
check("CoD filled", GetSendMailCOD() == 10000)
_G.SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), ""); M.advance(2)
check("mail completed request", VM.db.requests.R4.status == "FULFILLED" and VM.db.requests.R4.completedMethod == "MAIL")
check("awaiting CoD payment", VM.Fulfillment:GetPaymentState(VM.db.requests.R4) == "AWAITING_COD")
table.insert(M.inbox, { sender = "Mango Tidecaller", subject = "COD Payment: " .. M.lastMail.subject, money = 10000 })
M.fire("MAIL_INBOX_UPDATE"); M.advance(0.5)
check("CoD payment detected -> paid", VM.Fulfillment:GetOwedAmount(VM.db.requests.R4) == 0)
M.inbox = {}

-- 8) Mail with CoD returned unpaid -> back to PREPARED, charge reversed
M.bags[0][11] = { id = 14047, count = 20 }
recv("REQ|R5|Mango|14047|20|1|PENDING|1764299004|1764299004|||1|PERCENT|50|Runecloth||0|0|1|0||||0|", "Mango")
VM.Fulfillment:ApproveRequest("R5")
local r5 = VM.db.requests.R5; r5.status = "PREPARED"; r5.preparedBy = VM:GetPlayerName()
VM.Fulfillment:PopulateMailFor("Mango"); M.advance(2)
_G.SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), ""); M.advance(2)
check("R5 awaiting CoD", VM.Fulfillment:GetPaymentState(VM.db.requests.R5) == "AWAITING_COD")
table.insert(M.inbox, { sender = "Mango Tidecaller", subject = M.lastMail.subject, money = 0, hasItem = true, wasReturned = true })
M.fire("MAIL_INBOX_UPDATE"); M.advance(0.5)
check("returned CoD -> PREPARED again", VM.db.requests.R5.status == "PREPARED")
local charged = false for _, tx in pairs(VM.db.ledger) do if tx.fulfillmentId == "R5" and tx.source == "REQUEST" and not tx.deleted then charged = true end end
check("charge reversed (REQUEST tx tombstoned)", not charged)
check("member told CoD came back", anyWhisper("came back unpaid") ~= nil)
M.inbox = {}

-- 9) Mail recipient fallback: full name rejected -> first name
M.mailFailTargets = { ["Mango Tidecaller"] = true }
VM.db.nameFormat = {}
VM.Fulfillment:PopulateMailFor("Mango"); M.advance(2)
_G.SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), ""); M.advance(1)
check("recipient switched to first name after error", SendMailNameEditBox:GetText() == "Mango")
M.mailFailTargets = nil
_G.SendMail(SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), ""); M.advance(2)
check("first-name format remembered", VM.db.nameFormat["Mango Tidecaller"] == "first")
M.mail = { items = {}, money = 0 }

-- 10) Whisper fallback: full name not found -> first name
M.whispers = {}; M.offlineNames = { ["Mango Tidecaller"] = true }; VM.db.nameFormat = {}
VM.Delivery:WhisperMember("Mango", "[Guild Bank] test")
M.advance(1)
check("whisper retried with first name", lastWhisper() and lastWhisper().target == "Mango")
M.offlineNames = {}

-- 11) Quick return auto-pair: Mango withdraws 20 runecloth directly and puts it back
M.logName = "Mango"
table.insert(M.bank.log[1], 1, { type = "withdraw", name = "Mango", link = M.items[14047].link, count = 20 })
VM.BankScanner:SchedulePostWithdrawScan(); M.advance(3)
table.insert(M.bank.log[1], 1, { type = "deposit", name = "Mango", link = M.items[14047].link, count = 20 })
VM.BankScanner:SchedulePostWithdrawScan(); M.advance(3)
local outV, inV = false, false
for _, tx in pairs(VM.db.ledger) do
    if tx.source == "BANK_LOG" and tx.itemID == 14047 and VM:CanonicalActor(tx.player) == "Mango Tidecaller" then
        if tx.type == "OUT" and tx.voided then outV = true end
        if tx.type == "IN" and tx.voided then inV = true end
    end
end
check("quick withdraw+return auto-paired (both voided)", outV and inV)

-- 12) Reconcile: officer takes 7 linen by hand, then completes the APPROVED request manually
M.logName = "Thallock Dotcom"
M.items[2589] = { name = "Linen Cloth", link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r", stack = 20, type = "Trade Goods", sell = 10 }
recv("REQ|R6|Mango|2589|7|1|PENDING|1764299005|1764299005|||1|PERCENT|50|Linen Cloth||0|0|1|0||||0|", "Mango")
VM.Fulfillment:ApproveRequest("R6")
table.insert(M.bank.log[1], 1, { type = "withdraw", name = "Thallock Dotcom", link = M.items[2589].link, count = 7 })
VM.BankScanner:SchedulePostWithdrawScan(); M.advance(3)
local dir for _, tx in pairs(VM.db.ledger) do if tx.source == "BANK_LOG" and tx.type == "OUT" and tx.itemID == 2589 and not tx.deleted then dir = tx end end
check("manual withdrawal first booked on officer", dir ~= nil)
VM.Fulfillment:CompleteManually("R6", true)
check("officer's direct withdrawal reconciled", dir and dir.deleted == true)

-- 13) Auto-complete only for PREPARED by me: giving an item to a member with only an APPROVED request
recv("REQ|R7|Mango|19146|1|1|PENDING|1764299006|1764299006|||1|PERCENT|50|Devout Belt||0|0|1|0||||0|", "Mango")
VM.Fulfillment:ApproveRequest("R7")
local n = VM.Fulfillment:CompleteFromTransfer("Mango", { x = { itemID = 19146, itemName = "devout belt", count = 1 } }, 0, "TRADE")
check("approved (not withdrawn) request not auto-completed", n == 0 and VM.db.requests.R7.status == "APPROVED")

-- 14) Member side notification
M.playerRank = 3; M.playerName = "Mango"
M.prints = {}
recv(string.format("REQ|R7|Mango|19146|1|1|PREPARED|1764299006|%d|Thallock||1|PERCENT|50|Devout Belt||1|0|1|0||Thallock|%d|", time() + 50, time()), "Thallock")
local seen = false for _, p in ipairs(M.prints) do if p:find("has withdrawn") then seen = true end end
check("member notified in addon", seen)

VM.UI:Toggle(); for i = 1, 6 do VM.UI:SelectTab(i) end; M.advance(1)
M.dumpErrors("final")
