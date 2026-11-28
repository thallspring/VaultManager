local root = arg[1]
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local files = { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Ranking.lua", "Minimap.lua", "UI.lua" }
local VM = M.load(root, files)
M.dumpErrors("load")
M.fire("ADDON_LOADED", "VaultManager")
M.fire("PLAYER_LOGIN")
M.fire("PLAYER_ENTERING_WORLD", true, false)
M.advance(6)
M.dumpErrors("login")
say("isUnguilded=", tostring(VM.isUnguilded), "officer=", tostring(VM:IsOfficer()), "player=", VM:GetPlayerName())

-- open guild bank: client fires only slot/log events
M.bank.open = true
M.fire("GUILDBANKBAGSLOTS_CHANGED")
M.fire("GUILDBANKLOG_UPDATE")
M.advance(3)
M.dumpErrors("bank open")
local mf = _G.VaultManagerMainFrame
say("bankOpen=", tostring(VM.BankScanner:IsBankOpen()), "mainFrameShown=", tostring(mf and mf:IsShown()))
local n = 0 for _ in pairs(VM.db.inventory.tabs[1].items) do n = n + 1 end
say("inventory items tab1=", n)

-- member-like request flow for own request (officer requests belt)
local req = VM.Fulfillment:CreateRequest(1, 19146, 1)
say("req1=", tostring(req and req.id))
local req2 = VM.Fulfillment:CreateRequest(1, 19146, 1)
say("dup req2 blocked=", tostring(req2 == nil))
VM.Fulfillment:ApproveRequest(req.id)
M.advance(25)  -- idle at the bank
M.dumpErrors("idle")
say("after idle bankOpen=", tostring(VM.BankScanner:IsBankOpen()))
VM.Fulfillment:PrepareRequest(req.id)
M.advance(6)
M.dumpErrors("prepare")
say("req status=", req.status, VM.db.requests[req.id].status, "bag0slot1=", tostring(M.bags[0][1] and M.bags[0][1].id))
for _, p in ipairs(M.prints) do say("  PRINT:", p) end
M.prints = {}
local cnt = 0 for id, tx in pairs(VM.db.ledger) do cnt = cnt + 1 say("  TX", tx.type, tx.source, tx.player, tostring(tx.rawSender), tx.itemName, tostring(tx.deleted)) end

-- gold withdrawal manually
_G.WithdrawGuildBankMoney(20000)
M.advance(4)
M.dumpErrors("gold")
for id, tx in pairs(VM.db.ledger) do if tx.itemLink == "GOLD" then say("  GOLDTX", tx.type, tx.source, tx.player, tx.unitPriceAtTime) end end
for _, p in ipairs(M.prints) do say("  PRINT:", p) end
