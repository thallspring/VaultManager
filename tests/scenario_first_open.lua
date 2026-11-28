-- First bank visit after login: a quiet money update arrives before the player is at the bank;
-- the first real opening must still auto-open Vault Manager
local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local function say(...) io.write(table.concat({...}, " "), "\n") end
local function check(label, cond) say(cond and "  OK  " or "  FAIL", label) end
local VM = M.load(arg[1], { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Delivery.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
GuildBankFrame:Hide()
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
local f = _G.VaultManagerMainFrame

M.fire("GUILDBANK_UPDATE_MONEY"); M.fire("GUILDBANK_UPDATE_WITHDRAWMONEY"); M.advance(1)
check("quiet money update away from the bank does not start a session", not VM.BankScanner:IsBankOpen())

-- First real visit (bag addon hides the default frame right away)
M.bank.open = true
GuildBankFrame:Show(); GuildBankFrame:Hide()
M.fire("GUILDBANKBAGSLOTS_CHANGED")
M.advance(4)
check("first bank visit after login auto-opens VM", f:IsShown())

-- Session already open from slot events, then the bank window appears: still exactly one auto-open
VM.UI:Toggle(); M.advance(0.5)          -- player closes VM
VM.BankScanner:SetBankOpen(false, "test"); M.advance(1)
VM.UI.userClosedAt = 0
M.fire("GUILDBANKLOG_UPDATE"); M.advance(4)   -- session opens (auto-open #1)
VM.UI:Toggle(); M.advance(0.5)                -- player closes it again
GuildBankFrame:Show(); M.advance(4)           -- frame shows in the same session
check("no second pop-up in the same session after the player closed it", not f:IsShown())
M.dumpErrors()
