local M = dofile((arg[0]:match("^(.*[/\\])") or "") .. "wowmock.lua")
local VM = M.load(arg[1], { "Core.lua", "BankScanner.lua", "Comms.lua", "Ledger.lua", "Fulfillment.lua", "Ranking.lua", "Minimap.lua", "UI.lua" })
M.fire("ADDON_LOADED", "VaultManager"); M.fire("PLAYER_LOGIN"); M.fire("PLAYER_ENTERING_WORLD", true, false); M.advance(6)
M.bank.open = true
M.fire("GUILDBANKBAGSLOTS_CHANGED"); M.advance(0.4)
local f = _G.VaultManagerMainFrame
io.write("auto-opened: ", tostring(f:IsShown()), "\n")
f:Hide()   -- e.g. CloseSpecialWindows from the bank UI
M.advance(0.3)
io.write("re-shown after foreign hide: ", tostring(f:IsShown()), "\n")
VM.UI:Toggle()  -- player closes deliberately
M.advance(0.5)
io.write("stays closed after user close: ", tostring(not f:IsShown()), "\n")
-- reminder when auto-open disabled
VM.db.uiPrefs.autoOpenAtBank = false
VM.Fulfillment:CreateRequest(1, 14047, 20)
VM.BankScanner:SetBankOpen(false, "test"); M.advance(1)
M.fire("GUILDBANKLOG_UPDATE"); M.advance(1)
io.write("reminder shown: ", tostring(_G.VaultManagerBankReminder and _G.VaultManagerBankReminder:IsShown()), " main shown: ", tostring(f:IsShown()), "\n")
M.dumpErrors()

-- Bag addon replaces the default frame: GuildBankFrame shows, is hidden at once, VM must still open
VM.db.uiPrefs.autoOpenAtBank = true
VM.BankScanner:SetBankOpen(false, "test"); M.advance(1)
f:Hide(); VM.UI.userClosedAt = 0
GuildBankFrame:Hide()
GuildBankFrame:Show()      -- OnShow -> session opens
GuildBankFrame:Hide()      -- bag addon hides the default frame immediately
M.advance(4)
io.write("bag addon case: session kept: ", tostring(VM.BankScanner:IsBankOpen()), " VM opened: ", tostring(f:IsShown()), "\n")
-- Something closes the window 1s after auto-open (CloseSpecialWindows) -> re-shown
f:Hide(); M.advance(1)
io.write("re-shown after late foreign hide: ", tostring(f:IsShown()), "\n")
M.dumpErrors()
