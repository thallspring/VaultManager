-- Hostile server: repeated queries are NOT answered (only the real bank open fires events)
local root = arg[1]
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local VM = M.load(root, { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
_G.QueryGuildBankTab = function() end
_G.QueryGuildBankLog = function() end
M.bank.open = true
M.fire("GUILDBANKBAGSLOTS_CHANGED"); M.fire("GUILDBANKLOG_UPDATE")
M.advance(3)
say("open:", tostring(VM.BankScanner:IsBankOpen()), "shown:", tostring(_G.VaultManagerMainFrame:IsShown()))
local req = VM.Fulfillment:CreateRequest(1, 19146, 1); VM.Fulfillment:ApproveRequest(req.id)
M.advance(30)
say("after 30s idle open:", tostring(VM.BankScanner:IsBankOpen()))
VM.Fulfillment:PrepareRequest(req.id); M.advance(6)
say("status:", VM.db.requests[req.id].status)
_G.WithdrawGuildBankMoney(20000); M.advance(4)
local g = 0 for _, tx in pairs(VM.db.ledger) do if tx.itemLink == "GOLD" then g = g + 1 end end
say("gold tx:", g)
M.dumpErrors()
for _, p in ipairs(M.prints) do if p:find("Open the Guild") or p:find("failed") then say("  PRINT:", p) end end
