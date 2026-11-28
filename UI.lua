local _, VM = ...
VM.UI = {}
local UI = VM.UI

local mainFrame
local mailPanelFrame
local tradePromptFrame
local relogReminderFrame
local requestsHelpFrame
local rosterPickerFrame
local qtyPickerFrame
local goldReqModalFrame
local guildExpenseModalFrame
local exportModalFrame
local assignModalFrame
local rankingPeriodDropdownFrame
local bankValDropdownFrame

local STATE = {
    currentTab = 1,
    selectedBankTab = 1,
    vaultCategoryExpanded = {},
    selectedVaultQty = {},
    searchQuery = "",
    requestSectionExpanded = {
        PENDING = true,
        APPROVED = true,
        PREPARED = true,
        UNPAID = true,
        HISTORY = false,
    },
    ledgerSearchQuery = "",
    ledgerLegacyExpanded = false,
    expandedMains = {},
    expandedRankingMains = {},
    expandedTreeMains = {},
    rosterRankExpanded = {},
    rosterLegacyExpanded = false,
    rosterUnlinkedOnly = false,
    rosterSearchFilter = "",
    selectedAssignRecipient = "",
    selectedAssignGuildCat = nil,
    selectedAssignItem = nil,
    selectedAssignTab = 1,
    manualLedgerDonor = "",
    manualLedgerGuildCat = nil,
}

local THEME = {
    bg = { 0.07, 0.08, 0.10, 0.96 },
    panel = { 0.10, 0.11, 0.14, 0.95 },
    rowEven = { 0.12, 0.13, 0.17, 0.75 },
    rowOdd = { 0.09, 0.10, 0.13, 0.75 },
    rowLegacy = { 0.08, 0.08, 0.09, 0.85 },
    rowSpecial = { 0.11, 0.14, 0.20, 0.88 },
    rowHover = { 0.18, 0.22, 0.30, 0.90 },
    headerBg = { 0.12, 0.15, 0.22, 0.95 },
    border = { 0.22, 0.25, 0.32, 1.0 },
    accent = { 0.15, 0.65, 0.95, 1.0 },
    green = { 0.25, 0.80, 0.45, 1.0 },
    red = { 0.85, 0.30, 0.30, 1.0 },
    gold = { 0.90, 0.72, 0.20, 1.0 },
    btnBg = { 0.16, 0.18, 0.23, 1.0 },
    btnHover = { 0.22, 0.26, 0.34, 1.0 },
    btnDisabled = { 0.10, 0.11, 0.13, 0.6 },
}

if StaticPopupDialogs then
    StaticPopupDialogs["VAULTMANAGER_WRITEOFF"] = {
        text = "Write off this prepared request?\n\n%s\n\n100%% of the value will be charged to departed officer %s (Legacy Member).",
        button1 = "Write Off",
        button2 = "Cancel",
        OnAccept = function(self, data)
            local d = data or self.data
            if d and d.reqID and VM.Fulfillment and VM.Fulfillment.WriteOffRequest then
                VM.Fulfillment:WriteOffRequest(d.reqID)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

if StaticPopupDialogs then
    StaticPopupDialogs["VAULTMANAGER_DELETE_TX"] = {
        text = "Delete this Ledger entry for all guild members?\n\n%s\n\nThe deletion is synced as a tombstone and the entry will not be re-imported from the Guild Bank log.",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function(self, data)
            local d = data or self.data
            if d and d.txID and VM.Ledger then
                VM.Ledger:DeleteTransaction(d.txID)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    -- Typed confirmation ("RESET") for guild-wide resets
    local function ResetEditBox(dialog)
        return dialog.editBox or dialog.EditBox or (dialog.GetName and _G[(dialog:GetName() or "") .. "EditBox"])
    end
    local function ResetTyped(dialog)
        local eb = ResetEditBox(dialog)
        return eb and strupper(strtrim(eb:GetText() or "")) == "RESET"
    end
    local function ResetOnShow(dialog)
        local eb = ResetEditBox(dialog)
        if eb then eb:SetText("") eb:SetFocus() end
        if dialog.button1 then dialog.button1:Disable() end
    end
    local function ResetOnTextChanged(editBox)
        local dialog = editBox:GetParent()
        if dialog and dialog.button1 then
            if strupper(strtrim(editBox:GetText() or "")) == "RESET" then dialog.button1:Enable() else dialog.button1:Disable() end
        end
    end

    StaticPopupDialogs["VAULTMANAGER_RESET_REQUEST"] = {
        text = "Reset ALL Vault Manager data for the whole guild?\n\nLedger, requests and the vault cache are cleared for every member. Tab rules, officer ranks and alt links are kept. Data is rebuilt from the Guild Bank logs on the next scan.\n\n%s\n\nType RESET to confirm.",
        button1 = "Reset",
        button2 = "Cancel",
        hasEditBox = 1,
        OnShow = ResetOnShow,
        EditBoxOnTextChanged = ResetOnTextChanged,
        OnAccept = function(self)
            if ResetTyped(self) then VM:RequestGuildReset() end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local dialog = editBox:GetParent()
            if dialog and ResetTyped(dialog) then
                VM:RequestGuildReset()
                dialog:Hide()
            end
        end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["VAULTMANAGER_RESET_APPROVE"] = {
        text = "%s asks to reset ALL Vault Manager data for the whole guild.\n\nLedger, requests and the vault cache are cleared for every member (tab rules, officer ranks and alt links are kept). Data is rebuilt from the Guild Bank logs.\n\nType RESET to approve.",
        button1 = "Approve",
        button2 = "Later",
        button3 = "Decline",
        hasEditBox = 1,
        OnShow = ResetOnShow,
        EditBoxOnTextChanged = ResetOnTextChanged,
        OnAccept = function(self, data)
            local d = data or self.data
            if ResetTyped(self) and d then VM:ApproveGuildReset(d.id) end
        end,
        OnAlt = function(self, data)
            local d = data or self.data
            if d then VM:DeclineGuildReset(d.id) end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local dialog = editBox:GetParent()
            local d = dialog and dialog.data
            if dialog and ResetTyped(dialog) and d then
                VM:ApproveGuildReset(d.id)
                dialog:Hide()
            end
        end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["VAULTMANAGER_COMPLETE_MANUAL"] = {
        text = "Mark as delivered?\n\n%s\n\nHas the member already paid %s?",
        button1 = "Paid",
        button2 = "Cancel",
        button3 = "Not Paid",
        OnAccept = function(self, data)
            local d = data or self.data
            if d and d.reqID then VM.Fulfillment:CompleteManually(d.reqID, true) end
        end,
        OnAlt = function(self, data)
            local d = data or self.data
            if d and d.reqID then VM.Fulfillment:CompleteManually(d.reqID, false) end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["VAULTMANAGER_WRITEOFF_DEBT"] = {
        text = "Write off unpaid amount?\n\n%s\n\nThe loss is charged to GUILD (Member) and stays visible as unpaid on %s in the Ledger.",
        button1 = "Write Off",
        button2 = "Cancel",
        OnAccept = function(self, data)
            local d = data or self.data
            if d and d.reqID and VM.Fulfillment then
                VM.Fulfillment:WriteOffDebt(d.reqID)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopupDialogs["VAULTMANAGER_PAIR_TX"] = {
        text = "Pair as return?\n\n%s\n%s\n\nBoth entries are voided and net to 0g regardless of price changes.",
        button1 = "Pair",
        button2 = "Cancel",
        OnAccept = function(self, data)
            local d = data or self.data
            if d and d.a and d.b and VM.Ledger then
                VM.Ledger:PairTransactions(d.a, d.b)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function DescribeTxPlain(tx)
    if not tx then return "?" end
    local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
    local when = date("%d/%m %H:%M", tx.timestamp or 0)
    local who = tx.player or "?"
    if isGold then
        return string.format("%s  %s %s  %s", when, tx.type == "OUT" and "GOLD OUT" or "GOLD IN", VM:FormatMoneyPlain((tx.unitPriceAtTime or 0) * (tx.count or 1)), who)
    end
    return string.format("%s  %s %dx %s  %s", when, tx.type or "?", tx.count or 1, tx.itemName or "Item", who)
end

local function ApplyModernBackdrop(frame, bgColor, borderColor)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local bg = bgColor or THEME.bg
    local bd = borderColor or THEME.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
end

local function SetButtonAccent(btn, accentColor)
    btn.accentColor = accentColor
    local bd = accentColor or THEME.border
    btn:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.85)
end

-- Workflow button states: "active" (clickable), "disabled" (greyed, not clickable),
-- "done" (step completed: green, dimmed, not clickable)
local function ApplyButtonState(btn, state)
    if state == "active" then
        btn:SetModernEnabled(true)
    else
        btn:SetModernEnabled(false)
        if state == "done" then
            btn:SetBackdropColor(0.10, 0.30, 0.16, 0.65)
            btn:SetBackdropBorderColor(THEME.green[1], THEME.green[2], THEME.green[3], 0.55)
            btn.label:SetTextColor(0.45, 0.80, 0.52)
        end
    end
end

-- Tooltip help on any frame
local function AttachHelp(frame, text)
    if not frame or not text then return end
    frame.helpText = text
    frame:HookScript("OnEnter", function(selfFrame)
        GameTooltip:SetOwner(selfFrame, "ANCHOR_TOP")
        GameTooltip:SetText(selfFrame.helpText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateDebouncer(delaySec, callback)
    local f = CreateFrame("Frame")
    f:Hide()
    f.delay = delaySec or 0.15
    f.timeLeft = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.timeLeft = self.timeLeft - elapsed
        if self.timeLeft <= 0 then
            self:Hide()
            if callback then callback() end
        end
    end)
    return function()
        f.timeLeft = f.delay
        f:Show()
    end
end

local function GetUIPrefs()
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local defaults = {
        useHistoricalPrices = false,
        showLockedPrices = false,
        rankingPriceMode = "live",
        hideOfficers = false,
        showLegacyRanking = true,
        hideLegacyLedger = false,
        rankingPeriod = "ALL",
        rankingSortBy = "net",
        rankingSortDir = "desc",
        enableChatNotifications = true,
        notifyNewerVersion = true,
        autoOpenAtBank = true,
    }
    for k, v in pairs(defaults) do
        if VM.db.uiPrefs[k] == nil then
            VM.db.uiPrefs[k] = v
        end
    end
    return VM.db.uiPrefs
end

local function IsBankCurrentlyOpen()
    if VM.BankScanner and VM.BankScanner.IsBankOpen then
        return VM.BankScanner:IsBankOpen()
    end
    return GuildBankFrame and GuildBankFrame:IsVisible() and true or false
end

local function ApplyDefaultWindowPosition()
    if not mainFrame then return end
    local prefs = GetUIPrefs()
    if prefs.windowPos then return end
    mainFrame:ClearAllPoints()
    if IsBankCurrentlyOpen() then
        mainFrame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function ShowItemTooltip(selfFrame, itemLink, itemID, itemName, tx, isHistoricalOverride)
    GameTooltip:SetOwner(selfFrame, "ANCHOR_RIGHT")
    local handled = false

    local numID = tonumber(itemID)
    if numID and numID > 0 then
        if type(GameTooltip.SetItemByID) == "function" then
            pcall(function() GameTooltip:SetItemByID(numID) end)
            handled = true
        else
            local _, realLink = GetItemInfo(numID)
            if realLink then
                GameTooltip:SetHyperlink(realLink)
                handled = true
            else
                pcall(function() GameTooltip:SetHyperlink("item:" .. tostring(numID)) end)
                handled = true
            end
        end
    end

    if not handled and itemLink then
        local linkStr = tostring(itemLink)
        if linkStr:find("|Hitem:") or linkStr:find("^item:%d+") then
            GameTooltip:SetHyperlink(linkStr)
            handled = true
        end
    end

    if not handled then
        local fallbackText = itemName or itemLink
        if fallbackText and fallbackText ~= "" and not tostring(fallbackText):find("^Gold") then
            GameTooltip:SetText(tostring(fallbackText))
        else
            GameTooltip:SetText("Item")
        end
    end

    if tx and tx.itemID and tonumber(tx.itemID) and tonumber(tx.itemID) > 0 then
        local curPrice = VM:GetEffectiveLivePrice(tx.itemID, tx.itemLink, tx.unitPriceAtTime) or 0
        if curPrice > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Current AH Value: %s", VM:FormatMoney(curPrice * (tx.count or 1))), 0.2, 0.8, 0.9)
        end
    end

    GameTooltip:Show()
end

local function HideItemTooltip()
    GameTooltip:Hide()
end

local function CreateModernButton(parent, width, height, text, accentColor)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    ApplyModernBackdrop(btn, THEME.btnBg, THEME.border)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetText(text or "")

    btn.accentColor = accentColor
    if accentColor then
        btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.85)
    end

    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropColor(THEME.btnHover[1], THEME.btnHover[2], THEME.btnHover[3], 1)
            local ac = self.accentColor or THEME.accent
            self:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self:IsEnabled() then
            local bg = self.customBg or THEME.btnBg
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
            local bd = self.accentColor or THEME.border
            self:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.85)
        end
    end)

    btn.SetText = function(self, t) self.label:SetText(t) end
    btn.SetModernEnabled = function(self, enabled)
        if enabled then
            self:Enable()
            local bg = self.customBg or THEME.btnBg
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
            local bd = self.accentColor or THEME.border
            self:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.85)
            self.label:SetTextColor(1, 1, 1)
        else
            self:Disable()
            self:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.6)
            self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.4)
            self.label:SetTextColor(0.45, 0.45, 0.45)
        end
    end

    return btn
end

local function CreateModernEditBox(parent, width, height, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width, height)
    ApplyModernBackdrop(eb, { 0.05, 0.06, 0.08, 1 }, THEME.border)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    end)
    return eb
end

local function CreateModernDropdown(parent, width, height, placeholder)
    local dd = CreateModernButton(parent, width, height, placeholder or "Select...")
    dd.label:ClearAllPoints()
    dd.label:SetPoint("LEFT", 6, 0)
    dd.label:SetPoint("RIGHT", -16, 0)
    dd.label:SetJustifyH("LEFT")

    local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetText("|cff26a6f2v|r")
    return dd
end

local function CreateScrollArea(parent, topOffset, bottomOffset)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, topOffset or 0)
    sf:SetPoint("BOTTOMRIGHT", -24, bottomOffset or 4)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(740, 1)
    sf:SetScrollChild(content)
    sf.content = content
    sf.rows = {}
    return sf
end

local function HideAllPopups()
    if rosterPickerFrame then rosterPickerFrame:Hide() end
    if qtyPickerFrame then qtyPickerFrame:Hide() end
    if goldReqModalFrame then goldReqModalFrame:Hide() end
    if guildExpenseModalFrame then guildExpenseModalFrame:Hide() end
    if requestsHelpFrame then requestsHelpFrame:Hide() end
    if exportModalFrame then exportModalFrame:Hide() end
    if assignModalFrame then assignModalFrame:Hide() end
    if rankingPeriodDropdownFrame then rankingPeriodDropdownFrame:Hide() end
    if bankValDropdownFrame then bankValDropdownFrame:Hide() end
end

function UI:Init()
    self:CreateMainFrame()
    self:CreateMailFulfillmentPanel()
    self:CreateTradeFulfillmentPrompt()
    self:CreateRelogReminderFrame()
    self:CreateRequestsHelpModal()
    self:CreateRosterPickerFrame()
    self:CreateQtyPickerFrame()
    self:CreateGoldRequestModal()
    self:CreateGuildExpenseModal()
    self:CreateExportModal()
    self:CreateAssignModal()
    self:CreateRankingPeriodPickerFrame()
    self:CreateBankValDropdown()
end

function UI:Toggle()
    if not mainFrame then self:CreateMainFrame() end
    if mainFrame:IsShown() then
        UI.userClosedAt = GetTime()
        mainFrame:Hide()
        HideAllPopups()
    else
        if VM.SwitchGuildContext then
            VM:SwitchGuildContext("UI_TOGGLE")
        end
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
            elseif GuildRoster then GuildRoster() end
        end
        if VM.UpdateRosterCache then
            VM:UpdateRosterCache()
        end
        ApplyDefaultWindowPosition()
        mainFrame:Show()
        self:RefreshAll()
    end
end

-- Auto-open at the Guild Bank: keep the window up for a moment in case the bank UI (or a bag addon)
-- closes special windows while it opens; a deliberate close by the player is always respected.
local AUTO_OPEN_STICKY_SEC = 5.0
function UI:MarkAutoOpened()
    self.autoOpenedAt = GetTime()
end

function UI:OpenToRequestsTab(isAuto)
    if not mainFrame then self:CreateMainFrame() end
    if isAuto then self:MarkAutoOpened() end
    if VM.SwitchGuildContext then
        VM:SwitchGuildContext("UI_OPEN_REQUESTS")
    end
    if VM.UpdateRosterCache then
        VM:UpdateRosterCache()
    end
    STATE.currentTab = 2
    HideAllPopups()
    ApplyDefaultWindowPosition()
    mainFrame:Show()
    self:RefreshAll()
end

function UI:OpenToVaultTab(isAuto)
    if not mainFrame then self:CreateMainFrame() end
    if isAuto then self:MarkAutoOpened() end
    if VM.SwitchGuildContext then
        VM:SwitchGuildContext("UI_OPEN_VAULT")
    end
    if VM.UpdateRosterCache then
        VM:UpdateRosterCache()
    end
    STATE.currentTab = 1
    HideAllPopups()
    ApplyDefaultWindowPosition()
    mainFrame:Show()
    self:RefreshAll()
end

function UI:UpdateRequestsTabBadge()
    if not mainFrame or not mainFrame.navButtons or not mainFrame.navButtons[2] then return end
    local openCount = 0
    if VM.Minimap and VM.Minimap.GetOpenRequestCounts then
        local pendingCount, approvedCount, preparedCount = VM.Minimap:GetOpenRequestCounts()
        openCount = (pendingCount or 0) + (approvedCount or 0) + (preparedCount or 0)
    elseif VM.db and VM.db.requests and not VM.isUnguilded then
        local isOff = VM:IsOfficer()
        local meLower = VM:GetPlayerName():lower()
        local myMain = VM:GetMainFor(VM:GetPlayerName())
        for _, req in pairs(VM.db.requests) do
            if req.status == "PENDING" or req.status == "APPROVED" or req.status == "PREPARED" then
                if isOff then
                    if req.status ~= "PREPARED" or (req.preparedBy and VM:NormalizeName(req.preparedBy):lower() == meLower) then
                        openCount = openCount + 1
                    end
                else
                    local reqMain = VM:GetMainFor(req.requester or "")
                    if reqMain ~= "" and myMain ~= "" and reqMain:lower() == myMain:lower() then
                        openCount = openCount + 1
                    end
                end
            end
        end
    end

    if openCount > 0 then
        mainFrame.navButtons[2]:SetText(string.format("Requests |cffffcc33(%d)|r", openCount))
    else
        mainFrame.navButtons[2]:SetText("Requests")
    end
end

--------------------------------------------------------------------------------
-- QUANTITY PICKER DROPDOWN (REUSABLE SCROLLABLE)
--------------------------------------------------------------------------------
function UI:CreateQtyPickerFrame()
    qtyPickerFrame = CreateFrame("Frame", "VaultManagerQtyPicker", UIParent, "BackdropTemplate")
    qtyPickerFrame:SetSize(74, 200)
    qtyPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    qtyPickerFrame:SetFrameLevel(250)
    qtyPickerFrame:SetClampedToScreen(true)
    ApplyModernBackdrop(qtyPickerFrame, { 0.05, 0.06, 0.08, 0.98 }, THEME.accent)
    qtyPickerFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerQtyPicker")

    local sf = CreateScrollArea(qtyPickerFrame, -4, 4)
    sf.content:SetSize(44, 1)
    qtyPickerFrame.scroll = sf
end

local function BuildQtyOptions(maxQty)
    local cap = math.max(1, math.floor(tonumber(maxQty) or 1))
    local opts = {}
    if cap <= 60 then
        for n = 1, cap do
            table.insert(opts, n)
        end
        return opts
    end
    local seen = {}
    local function Add(v)
        if v >= 1 and v <= cap and not seen[v] then
            seen[v] = true
            table.insert(opts, v)
        end
    end
    for n = 1, 40 do Add(n) end
    for n = 45, math.min(cap, 100), 5 do Add(n) end
    for n = 110, math.min(cap, 200), 10 do Add(n) end
    for n = 220, cap, 20 do Add(n) end
    Add(cap)
    return opts
end

function UI:OpenQtyPicker(anchor, maxQty, currentQty, onSelect)
    if not qtyPickerFrame then self:CreateQtyPickerFrame() end
    if qtyPickerFrame:IsShown() and qtyPickerFrame.currentAnchor == anchor then
        qtyPickerFrame:Hide()
        qtyPickerFrame.currentAnchor = nil
        return
    end

    qtyPickerFrame.currentAnchor = anchor
    qtyPickerFrame.onSelect = onSelect

    local opts = BuildQtyOptions(maxQty)
    local content = qtyPickerFrame.scroll.content
    for _, r in ipairs(qtyPickerFrame.scroll.rows) do r:Hide() end

    local y = 0
    for idx, val in ipairs(opts) do
        local row = qtyPickerFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(44, 20)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("CENTER", 0, 0)
            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
            end)
            row:SetScript("OnLeave", function(selfRow)
                local bg = selfRow.baseBg or THEME.rowOdd
                selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            end)
            row:SetScript("OnClick", function(selfRow)
                local chosen = selfRow.qtyValue
                local cb = qtyPickerFrame.onSelect
                qtyPickerFrame:Hide()
                qtyPickerFrame.currentAnchor = nil
                if cb then cb(chosen) end
            end)
            qtyPickerFrame.scroll.rows[idx] = row
        end

        local isSelected = (val == currentQty)
        row.qtyValue = val
        row.baseBg = isSelected and { 0.15, 0.28, 0.42, 1 } or ((idx % 2 == 0) and THEME.rowEven or THEME.rowOdd)
        row:SetBackdropColor(row.baseBg[1], row.baseBg[2], row.baseBg[3], row.baseBg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row.label:SetText(isSelected and ("|cffffcc33" .. val .. "|r") or tostring(val))
        row:Show()
        y = y + 21
    end

    content:SetHeight(math.max(1, y))
    qtyPickerFrame:SetHeight(math.min(200, math.max(32, y + 10)))
    qtyPickerFrame:ClearAllPoints()
    qtyPickerFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    qtyPickerFrame:Show()
end

--------------------------------------------------------------------------------
-- REQUESTS HELP MODAL
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- PER-TAB HELP (what everyone can do vs. what officers can do)
--------------------------------------------------------------------------------
local TAB_HELP = {
    VAULT = {
        title = "Vault & Requests — Help",
        body =
            "|cff26a6f2Everyone|r\n" ..
            "• Shows what is in the Guild Bank, per bank tab and category. Data comes from the last scan by any member with the addon.\n" ..
            "• The banner shows the tab rule: |cff44dd77Free-for-All|r (you pay nothing), |cffffcc33% of AH|r (you pay that share of the auction price, min 1g) or |cffff5555Locked|r (no requests).\n" ..
            "• Pick an amount and click |cff26a6f2Request|r. One request can hold up to 6 stacks. Your open request is shown as |cff44dd77Requested|r with a |cffff5555Cancel|r button.\n" ..
            "• |cff44dd77Avail|r subtracts items already requested by others (Res).\n" ..
            "• |cff26a6f2Bank Value|r shows the current worth of the bank at live AH prices.\n\n" ..
            "|cffffaa00Officers|r\n" ..
            "• |cff26a6f2Assign|r gives an item to a member directly (logged in the Ledger with the tab's price).\n" ..
            "• |cff26a6f2Scan Now|r rescans the open Guild Bank (normally automatic).",
    },
    LEDGER = {
        title = "Ledger — Help",
        body =
            "|cff26a6f2Everyone|r\n" ..
            "• Every deposit and withdrawal, grouped by main character (alts are counted under their main).\n" ..
            "• |cff44dd77Donated|r = what a member gave the bank. |cffff6666Received|r = what they took or bought (at the price they were charged).\n" ..
            "• Items are valued at the current AH price, so taking something out and putting it back always nets to 0g.\n" ..
            "• |cff26a6f2GUILD BANK / OPERATIONS|r holds guild expenses (Raid, Member, Tabs). |cff26a6f2SUBSIDY|r = the discount members got on % of AH tabs; |cff44dd77SURPLUS|r = extra from the 1g minimum.\n" ..
            "• Tags: |cff44dd77[PAYMENT]|r a member's payment for a request, |cff26a6f2[TRANSFER]|r an officer depositing collected payments (not a donation), |cffffd700[RETURN PAIRED]|r a withdrawal and its return cancelled out, |cffff5555[UNPAID]|r a written-off debt.\n" ..
            "• |cffff5555Unpaid|r next to a member = money they still owe or that was written off.\n\n" ..
            "|cffffaa00Officers|r\n" ..
            "• |cff26a6f2Reassign|r moves an entry to another member or to the guild (e.g. raid loot deposited by a raider).\n" ..
            "• |cffffd700Pair|r cancels a withdrawal against its return. |cffff5555X|r deletes an entry for the whole guild (it is not re-imported from the bank log).\n" ..
            "• |cffffd700+ Expense|r logs a guild expense; |cff44dd77+ Log Gold|r logs gold given outside the bank.",
    },
    RANKING = {
        title = "Ranking — Help",
        body =
            "|cff26a6f2Everyone|r\n" ..
            "• Contribution per main character: |cff44dd77Contributed|r (deposits and payments) minus |cffff6666Withdrawn|r (items taken or bought).\n" ..
            "• Values use the current AH price. Click a column to sort, the period button to limit it to this or last month.\n" ..
            "• |cff999999Free-for-All|r items can be left out with the checkbox. Former members (Legacy) are shown at the bottom.\n" ..
            "• Click a member to see the entries behind the numbers.\n\n" ..
            "|cffffaa00Officers|r\n" ..
            "• Something looks wrong? Fix it in the Ledger with |cff26a6f2Reassign|r, |cffffd700Pair|r or delete.",
    },
    ROSTER = {
        title = "Roster & Mains — Help",
        body =
            "|cff26a6f2Everyone|r\n" ..
            "• Shows guild members grouped by rank, with their alts under the main character.\n" ..
            "• Linking alts to a main makes the Ledger and Ranking count all characters of one player together.\n\n" ..
            "|cffffaa00Officers|r\n" ..
            "• |cff26a6f2Set as Alt|r / |cffff5555Unlink|r manage alt links for the whole guild.\n" ..
            "• |cff26a6f2Auto-Suggest Alts|r proposes links from matching notes; check them before saving.",
    },
}

local tabHelpFrame
function UI:ShowTabHelp(key)
    local help = TAB_HELP[key]
    if not help then return end
    if not tabHelpFrame then
        tabHelpFrame = CreateFrame("Frame", "VaultManagerTabHelp", UIParent, "BackdropTemplate")
        tabHelpFrame:SetSize(520, 380)
        tabHelpFrame:SetPoint("CENTER")
        tabHelpFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        tabHelpFrame:SetFrameLevel(210)
        tabHelpFrame:SetClampedToScreen(true)
        tabHelpFrame:SetMovable(true)
        tabHelpFrame:EnableMouse(true)
        tabHelpFrame:RegisterForDrag("LeftButton")
        tabHelpFrame:SetScript("OnDragStart", tabHelpFrame.StartMoving)
        tabHelpFrame:SetScript("OnDragStop", tabHelpFrame.StopMovingOrSizing)
        ApplyModernBackdrop(tabHelpFrame, THEME.bg, THEME.accent)
        table.insert(UISpecialFrames, "VaultManagerTabHelp")
        tabHelpFrame.title = tabHelpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabHelpFrame.title:SetPoint("TOPLEFT", 14, -12)
        local closeBtn = CreateModernButton(tabHelpFrame, 22, 22, "X", THEME.red)
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        closeBtn:SetScript("OnClick", function() tabHelpFrame:Hide() end)
        tabHelpFrame.body = tabHelpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tabHelpFrame.body:SetPoint("TOPLEFT", 14, -38)
        tabHelpFrame.body:SetPoint("BOTTOMRIGHT", -14, 14)
        tabHelpFrame.body:SetJustifyH("LEFT")
        tabHelpFrame.body:SetJustifyV("TOP")
    end
    if tabHelpFrame:IsShown() and tabHelpFrame.key == key then
        tabHelpFrame:Hide()
        return
    end
    tabHelpFrame.key = key
    tabHelpFrame.title:SetText("|cff26a6f2" .. help.title .. "|r")
    tabHelpFrame.body:SetText(help.body)
    tabHelpFrame:Show()
end

local function AddTabHelpButton(parent, key, anchorTo, anchorPoint, relPoint, x, y)
    local b = CreateModernButton(parent, 24, 22, "?", THEME.accent)
    b:SetPoint(anchorPoint, anchorTo, relPoint, x, y)
    b:SetScript("OnClick", function() UI:ShowTabHelp(key) end)
    b:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Help: what this tab shows and who can do what", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function UI:CreateRequestsHelpModal()
    requestsHelpFrame = CreateFrame("Frame", "VaultManagerRequestsHelpModal", UIParent, "BackdropTemplate")
    requestsHelpFrame:SetSize(520, 460)
    requestsHelpFrame:SetPoint("CENTER")
    requestsHelpFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    requestsHelpFrame:SetFrameLevel(210)
    requestsHelpFrame:SetClampedToScreen(true)
    requestsHelpFrame:SetMovable(true)
    requestsHelpFrame:EnableMouse(true)
    requestsHelpFrame:RegisterForDrag("LeftButton")
    requestsHelpFrame:SetScript("OnDragStart", requestsHelpFrame.StartMoving)
    requestsHelpFrame:SetScript("OnDragStop", requestsHelpFrame.StopMovingOrSizing)
    ApplyModernBackdrop(requestsHelpFrame, THEME.bg, THEME.accent)
    requestsHelpFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerRequestsHelpModal")

    local title = requestsHelpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff26a6f2Requests — Quick Reference|r")

    local closeBtn = CreateModernButton(requestsHelpFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() requestsHelpFrame:Hide() end)

    local body = requestsHelpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", 14, -38)
    body:SetPoint("BOTTOMRIGHT", -14, 14)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(
        "|cff26a6f2Statuses|r\n" ..
        "• |cffffcc33PENDING|r — Waiting for officer approval. Stock is not yet reserved.\n" ..
        "• |cff26a6f2APPROVED|r — Accepted. Items are soft-locked in the Vault until withdrawn.\n" ..
        "• |cff44dd77PREPARED|r — Withdrawn by an officer and awaiting Mail or Trade delivery.\n" ..
        "• |cffff5555UNPAID|r — Delivered by trade but not (fully) paid.\n" ..
        "• |cff999999HISTORY|r — Fulfilled, rejected, cancelled, or written off (pruned after 30 days).\n" ..
        "|cff26a6f2Everyone|r — request items in Vault & Requests or gold with + Request Gold; cancel your own pending/approved requests; one request holds at most 6 stacks. You get a message when your request is approved, ready or sent.\n\n" ..
        "|cffffaa00Officers|r — workflow (only the next step is active; finished steps turn green)\n" ..
        "• |cff26a6f2Approve + Withdraw|r / |cff26a6f2Withdraw All|r — Approve and take out in one click, or take out every approved request in a row.\n" ..
        "• |cff26a6f2Withdraw|r — Takes the items/gold out of the Guild Bank (any tab) into your bags.\n" ..
        "• |cff26a6f2Fulfill|r — Fills the open Mail or Trade with all your prepared orders for that member. You click Send/Trade; after Send the next member is filled automatically.\n" ..
        "• |cff44dd77Complete|r — Automatic on Send / finished trade. Clicking it asks whether the member paid.\n" ..
        "• |cffffaa00Awaiting CoD|r — Paid when the CoD money arrives in your mailbox; a returned mail puts the order back to PREPARED.\n" ..
        "• |cffffd700Return|r — Puts the items/gold back in the Guild Bank; request goes back to APPROVED.\n" ..
        "• |cffff5555Cancel|r — Cancels the request (items you keep are charged to you).\n" ..
        "• |cff44dd77Paid|r / |cffff5555Write Off|r — Settle an unpaid trade; write-offs are charged to GUILD (Member) and shown on the member.\n" ..
        "• |cffff5555Write Off|r (prepared) — If the officer holding an order left the guild."
    )
end

function UI:ToggleRequestsHelpModal()
    if not requestsHelpFrame then self:CreateRequestsHelpModal() end
    if requestsHelpFrame:IsShown() then
        requestsHelpFrame:Hide()
    else
        requestsHelpFrame:Show()
    end
end

--------------------------------------------------------------------------------
-- GOLD REQUEST MODAL (WITH GUILD EXPENSE CATEGORY)
--------------------------------------------------------------------------------
function UI:CreateGoldRequestModal()
    goldReqModalFrame = CreateFrame("Frame", "VaultManagerGoldRequestModal", UIParent, "BackdropTemplate")
    goldReqModalFrame:SetSize(380, 245)
    goldReqModalFrame:SetPoint("CENTER")
    goldReqModalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    goldReqModalFrame:SetFrameLevel(200)
    goldReqModalFrame:SetClampedToScreen(true)
    goldReqModalFrame:SetMovable(true)
    goldReqModalFrame:EnableMouse(true)
    goldReqModalFrame:RegisterForDrag("LeftButton")
    goldReqModalFrame:SetScript("OnDragStart", goldReqModalFrame.StartMoving)
    goldReqModalFrame:SetScript("OnDragStop", goldReqModalFrame.StopMovingOrSizing)
    ApplyModernBackdrop(goldReqModalFrame, THEME.bg, THEME.accent)
    goldReqModalFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerGoldRequestModal")

    local title = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cffffd700Request Guild Gold|r")

    local closeBtn = CreateModernButton(goldReqModalFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() goldReqModalFrame:Hide() end)

    local desc = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", 14, -34)
    desc:SetWidth(350)
    desc:SetJustifyH("LEFT")
    desc:SetText("For purchases or expenses made on behalf of the guild bank. Charged to GUILD (not your personal balance).")

    local catLbl = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLbl:SetPoint("TOPLEFT", 14, -74)
    catLbl:SetText("Category:")

    goldReqModalFrame.selectedCat = "RAID"
    goldReqModalFrame.catButtons = {}
    local catDefs = {
        { key = "RAID", label = "Raid" },
        { key = "MEMBER", label = "Member" },
        { key = "TABS", label = "Tabs" },
    }
    local function UpdateGoldCatButtons()
        for _, cBtn in ipairs(goldReqModalFrame.catButtons) do
            if cBtn.catKey == goldReqModalFrame.selectedCat then
                cBtn.customBg = { 0.15, 0.28, 0.42, 1 }
                cBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                SetButtonAccent(cBtn, THEME.accent)
                cBtn.label:SetTextColor(1, 0.85, 0.2)
            else
                cBtn.customBg = nil
                cBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                SetButtonAccent(cBtn, THEME.border)
                cBtn.label:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end
    goldReqModalFrame.UpdateCatButtons = UpdateGoldCatButtons

    for i, c in ipairs(catDefs) do
        local b = CreateModernButton(goldReqModalFrame, 72, 22, c.label)
        b:SetPoint("TOPLEFT", 80 + (i - 1) * 78, -70)
        b.catKey = c.key
        b:SetScript("OnClick", function(selfBtn)
            goldReqModalFrame.selectedCat = selfBtn.catKey
            UpdateGoldCatButtons()
        end)
        goldReqModalFrame.catButtons[i] = b
    end
    UpdateGoldCatButtons()

    local amtLbl = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amtLbl:SetPoint("TOPLEFT", 14, -108)
    amtLbl:SetText("Amount:")

    local goldBox = CreateModernEditBox(goldReqModalFrame, 74, 24, true)
    goldBox:SetPoint("TOPLEFT", 80, -104)
    goldReqModalFrame.goldBox = goldBox

    local goldUnit = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldUnit:SetPoint("LEFT", goldBox, "RIGHT", 6, 0)
    goldUnit:SetText("|cffffd700Gold|r")

    local silverBox = CreateModernEditBox(goldReqModalFrame, 46, 24, true)
    silverBox:SetPoint("LEFT", goldUnit, "RIGHT", 14, 0)
    silverBox:SetMaxLetters(2)
    goldReqModalFrame.silverBox = silverBox

    local silverUnit = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    silverUnit:SetPoint("LEFT", silverBox, "RIGHT", 6, 0)
    silverUnit:SetText("|cffc0c0c0Silver|r")

    local reasonLbl = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonLbl:SetPoint("TOPLEFT", 14, -144)
    reasonLbl:SetText("Reason:")

    local reasonBox = CreateModernEditBox(goldReqModalFrame, 280, 24, false)
    reasonBox:SetPoint("TOPLEFT", 80, -140)
    reasonBox:SetMaxLetters(100)
    reasonBox.placeholder = reasonBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reasonBox.placeholder:SetPoint("LEFT", 6, 0)
    reasonBox.placeholder:SetText("What is this guild expense for?")
    reasonBox:SetScript("OnTextChanged", function(eb)
        if eb:GetText() == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
    end)
    goldReqModalFrame.reasonBox = reasonBox

    local submitBtn = CreateModernButton(goldReqModalFrame, 130, 26, "Submit Request", THEME.accent)
    submitBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    submitBtn:SetScript("OnClick", function()
        local g = tonumber(goldBox:GetText()) or 0
        local s = tonumber(silverBox:GetText()) or 0
        if s > 99 then s = 99 end
        local copper = (g * 10000) + (s * 100)
        local reason = strtrim(reasonBox:GetText() or "")
        if copper <= 0 then
            VM:Print("|cffff4444Please enter an amount greater than 0.|r")
            return
        end
        if reason == "" then
            VM:Print("|cffff4444Please enter a reason for the guild expense.|r")
            return
        end
        VM.Fulfillment:CreateGoldRequest(copper, reason, goldReqModalFrame.selectedCat)
        goldReqModalFrame:Hide()
    end)

    local cancelBtn = CreateModernButton(goldReqModalFrame, 84, 26, "Cancel")
    cancelBtn:SetPoint("RIGHT", submitBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() goldReqModalFrame:Hide() end)
end

function UI:OpenGoldRequestModal()
    if not goldReqModalFrame then self:CreateGoldRequestModal() end
    goldReqModalFrame.selectedCat = "RAID"
    if goldReqModalFrame.UpdateCatButtons then goldReqModalFrame.UpdateCatButtons() end
    goldReqModalFrame.goldBox:SetText("")
    goldReqModalFrame.silverBox:SetText("")
    goldReqModalFrame.reasonBox:SetText("")
    goldReqModalFrame.reasonBox.placeholder:Show()
    goldReqModalFrame:Show()
    goldReqModalFrame.goldBox:SetFocus()
end

--------------------------------------------------------------------------------
-- GUILD EXPENSE / OFFICER WRITE-OFF MODAL (LEDGER)
--------------------------------------------------------------------------------
function UI:CreateGuildExpenseModal()
    guildExpenseModalFrame = CreateFrame("Frame", "VaultManagerGuildExpenseModal", UIParent, "BackdropTemplate")
    guildExpenseModalFrame:SetSize(380, 245)
    guildExpenseModalFrame:SetPoint("CENTER")
    guildExpenseModalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    guildExpenseModalFrame:SetFrameLevel(200)
    guildExpenseModalFrame:SetClampedToScreen(true)
    guildExpenseModalFrame:SetMovable(true)
    guildExpenseModalFrame:EnableMouse(true)
    guildExpenseModalFrame:RegisterForDrag("LeftButton")
    guildExpenseModalFrame:SetScript("OnDragStart", guildExpenseModalFrame.StartMoving)
    guildExpenseModalFrame:SetScript("OnDragStop", guildExpenseModalFrame.StopMovingOrSizing)
    ApplyModernBackdrop(guildExpenseModalFrame, THEME.bg, THEME.accent)
    guildExpenseModalFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerGuildExpenseModal")

    local title = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff26a6f2Log Guild Expense / Write-Off|r")

    local closeBtn = CreateModernButton(guildExpenseModalFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() guildExpenseModalFrame:Hide() end)

    local desc = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", 14, -34)
    desc:SetWidth(350)
    desc:SetJustifyH("LEFT")
    desc:SetText("Records a guild-level expense or adjustment directly under GUILD BANK / OPERATIONS.")

    local catLbl = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    catLbl:SetPoint("TOPLEFT", 14, -74)
    catLbl:SetText("Category:")

    guildExpenseModalFrame.selectedCat = "MEMBER"
    guildExpenseModalFrame.catButtons = {}
    local catDefs = {
        { key = "RAID", label = "Raid" },
        { key = "MEMBER", label = "Member" },
        { key = "TABS", label = "Tabs" },
    }
    local function UpdateExpCatButtons()
        for _, cBtn in ipairs(guildExpenseModalFrame.catButtons) do
            if cBtn.catKey == guildExpenseModalFrame.selectedCat then
                cBtn.customBg = { 0.15, 0.28, 0.42, 1 }
                cBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                SetButtonAccent(cBtn, THEME.accent)
                cBtn.label:SetTextColor(1, 0.85, 0.2)
            else
                cBtn.customBg = nil
                cBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                SetButtonAccent(cBtn, THEME.border)
                cBtn.label:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end
    guildExpenseModalFrame.UpdateCatButtons = UpdateExpCatButtons

    for i, c in ipairs(catDefs) do
        local b = CreateModernButton(guildExpenseModalFrame, 72, 22, c.label)
        b:SetPoint("TOPLEFT", 80 + (i - 1) * 78, -70)
        b.catKey = c.key
        b:SetScript("OnClick", function(selfBtn)
            guildExpenseModalFrame.selectedCat = selfBtn.catKey
            UpdateExpCatButtons()
        end)
        guildExpenseModalFrame.catButtons[i] = b
    end
    UpdateExpCatButtons()

    local amtLbl = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amtLbl:SetPoint("TOPLEFT", 14, -108)
    amtLbl:SetText("Amount:")

    local goldBox = CreateModernEditBox(guildExpenseModalFrame, 74, 24, true)
    goldBox:SetPoint("TOPLEFT", 80, -104)
    guildExpenseModalFrame.goldBox = goldBox

    local goldUnit = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldUnit:SetPoint("LEFT", goldBox, "RIGHT", 6, 0)
    goldUnit:SetText("|cffffd700Gold|r")

    local silverBox = CreateModernEditBox(guildExpenseModalFrame, 46, 24, true)
    silverBox:SetPoint("LEFT", goldUnit, "RIGHT", 14, 0)
    silverBox:SetMaxLetters(2)
    guildExpenseModalFrame.silverBox = silverBox

    local silverUnit = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    silverUnit:SetPoint("LEFT", silverBox, "RIGHT", 6, 0)
    silverUnit:SetText("|cffc0c0c0Silver|r")

    local noteLbl = guildExpenseModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLbl:SetPoint("TOPLEFT", 14, -144)
    noteLbl:SetText("Note:")

    local noteBox = CreateModernEditBox(guildExpenseModalFrame, 280, 24, false)
    noteBox:SetPoint("TOPLEFT", 80, -140)
    noteBox:SetMaxLetters(100)
    noteBox.placeholder = noteBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noteBox.placeholder:SetPoint("LEFT", 6, 0)
    noteBox.placeholder:SetText("Reason or description...")
    noteBox:SetScript("OnTextChanged", function(eb)
        if eb:GetText() == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
    end)
    guildExpenseModalFrame.noteBox = noteBox

    local saveBtn = CreateModernButton(guildExpenseModalFrame, 130, 26, "Record Expense", THEME.accent)
    saveBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    saveBtn:SetScript("OnClick", function()
        if not VM:IsOfficer() then return end
        local g = tonumber(goldBox:GetText()) or 0
        local s = tonumber(silverBox:GetText()) or 0
        if s > 99 then s = 99 end
        local copper = (g * 10000) + (s * 100)
        local note = strtrim(noteBox:GetText() or "")
        if copper <= 0 then
            VM:Print("|cffff4444Please enter an amount greater than 0.|r")
            return
        end
        VM.Ledger:RecordGuildExpense(copper, guildExpenseModalFrame.selectedCat, note)
        VM:Print(string.format("Logged %s under GUILD (%s).",
            VM:FormatMoney(copper), VM.Ledger:GetGuildCategoryLabel(guildExpenseModalFrame.selectedCat) or "Member"))
        guildExpenseModalFrame:Hide()
    end)

    local cancelBtn = CreateModernButton(guildExpenseModalFrame, 84, 26, "Cancel")
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() guildExpenseModalFrame:Hide() end)
end

function UI:OpenGuildExpenseModal()
    if not VM:IsOfficer() then return end
    if not guildExpenseModalFrame then self:CreateGuildExpenseModal() end
    guildExpenseModalFrame.selectedCat = "MEMBER"
    if guildExpenseModalFrame.UpdateCatButtons then guildExpenseModalFrame.UpdateCatButtons() end
    guildExpenseModalFrame.goldBox:SetText("")
    guildExpenseModalFrame.silverBox:SetText("")
    guildExpenseModalFrame.noteBox:SetText("")
    guildExpenseModalFrame.noteBox.placeholder:Show()
    guildExpenseModalFrame:Show()
    guildExpenseModalFrame.goldBox:SetFocus()
end

--------------------------------------------------------------------------------
-- ASSIGN MODAL
--------------------------------------------------------------------------------
function UI:CreateAssignModal()
    assignModalFrame = CreateFrame("Frame", "VaultManagerAssignModal", UIParent, "BackdropTemplate")
    assignModalFrame:SetSize(370, 280)
    assignModalFrame:SetPoint("CENTER")
    assignModalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    assignModalFrame:SetFrameLevel(200)
    assignModalFrame:SetClampedToScreen(true)
    assignModalFrame:SetMovable(true)
    assignModalFrame:EnableMouse(true)
    assignModalFrame:RegisterForDrag("LeftButton")
    assignModalFrame:SetScript("OnDragStart", assignModalFrame.StartMoving)
    assignModalFrame:SetScript("OnDragStop", assignModalFrame.StopMovingOrSizing)
    ApplyModernBackdrop(assignModalFrame, THEME.bg, THEME.accent)
    assignModalFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerAssignModal")

    local title = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("|cff26a6f2Manual Item Assignment|r")
    assignModalFrame.title = title

    local closeBtn = CreateModernButton(assignModalFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() assignModalFrame:Hide() end)

    local itemLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemLbl:SetPoint("TOPLEFT", 12, -42)
    assignModalFrame.itemLbl = itemLbl

    local recLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recLbl:SetPoint("TOPLEFT", 12, -72)
    recLbl:SetText("Recipient:")

    local recBtn = CreateModernDropdown(assignModalFrame, 200, 24, "Select Member...")
    recBtn:SetPoint("TOPLEFT", 92, -68)
    recBtn:SetScript("OnClick", function(btn)
        UI:OpenRosterPicker(btn, true, function(chosen, guildCat)
            STATE.selectedAssignRecipient = chosen
            STATE.selectedAssignGuildCat = guildCat
            if chosen == "GUILD" then
                local catLbl = (VM.Ledger and VM.Ledger:GetGuildCategoryLabel(guildCat)) or "Member"
                recBtn:SetText("|cff26a6f2[Guild — " .. catLbl .. "]|r")
            else
                recBtn:SetText(chosen)
            end
        end, true)
    end)
    assignModalFrame.recBtn = recBtn

    local qtyLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("TOPLEFT", 12, -106)
    qtyLbl:SetText("Quantity:")

    local qtyBox = CreateModernEditBox(assignModalFrame, 60, 24, true)
    qtyBox:SetPoint("TOPLEFT", 92, -102)
    qtyBox:SetText("1")
    assignModalFrame.qtyBox = qtyBox

    local priceLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLbl:SetPoint("TOPLEFT", 12, -140)
    priceLbl:SetText("Total (Copper):")

    local priceBox = CreateModernEditBox(assignModalFrame, 100, 24, true)
    priceBox:SetPoint("TOPLEFT", 92, -136)
    assignModalFrame.priceBox = priceBox

    local totalLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalLbl:SetPoint("LEFT", priceBox, "RIGHT", 8, 0)
    assignModalFrame.totalLbl = totalLbl

    local payCb = CreateFrame("CheckButton", nil, assignModalFrame, "UICheckButtonTemplate")
    payCb:SetSize(20, 20)
    payCb:SetPoint("TOPLEFT", 12, -176)
    payCb.label = payCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    payCb.label:SetPoint("LEFT", payCb, "RIGHT", 4, 0)
    payCb.label:SetText("Payment received ([GOLD IN])")
    assignModalFrame.payCb = payCb

    qtyBox:SetScript("OnTextChanged", function()
        if not STATE.selectedAssignItem then return end
        local qty = math.max(1, tonumber(qtyBox:GetText()) or 1)
        local rule = VM:GetTabRule(STATE.selectedAssignTab)
        local effPrice = VM:GetEffectiveLivePrice(
            STATE.selectedAssignItem.itemID,
            STATE.selectedAssignItem.itemLink or STATE.selectedAssignItem.link,
            STATE.selectedAssignItem.ahPrice
        )
        local totalP = VM:CalculateMemberTotalPrice(effPrice, qty, rule)
        priceBox:SetText(tostring(totalP))
        totalLbl:SetText("= " .. VM:FormatMoney(totalP))
    end)

    priceBox:SetScript("OnTextChanged", function()
        local totalP = tonumber(priceBox:GetText()) or 0
        totalLbl:SetText("= " .. VM:FormatMoney(totalP))
    end)

    local confirmBtn = CreateModernButton(assignModalFrame, 130, 26, "Assign & Record", THEME.accent)
    confirmBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    confirmBtn:SetScript("OnClick", function()
        if not STATE.selectedAssignRecipient or STATE.selectedAssignRecipient == "" then
            VM:Print("|cffff4444Please select a recipient member first.|r")
            return
        end
        local item = STATE.selectedAssignItem
        if not item then return end
        local qty = math.max(1, tonumber(qtyBox:GetText()) or 1)
        local totalP = tonumber(priceBox:GetText()) or 0
        local unitP = (qty > 0) and math.floor(totalP / qty) or totalP
        local recipNorm = VM:NormalizeName(STATE.selectedAssignRecipient)
        local mainName = VM:GetMainFor(recipNorm)

        local rule = VM:GetTabRule(STATE.selectedAssignTab)
        local now = time()
        local tx = {
            id = string.format("OUT_ASGN_%d_%d", now, math.random(1000, 9999)),
            type = "OUT",
            player = VM:NormalizeName(mainName),
            rawSender = recipNorm,
            attributedTo = VM:NormalizeName(mainName),
            guildCategory = (recipNorm == "GUILD") and (STATE.selectedAssignGuildCat or "MEMBER") or nil,
            recipient = recipNorm,
            itemID = item.itemID,
            itemLink = item.itemLink or item.link,
            itemName = item.name,
            count = qty,
            unitPriceAtTime = VM:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice),
            chargedUnitPrice = unitP,
            chargedTotalPrice = totalP,
            priceMode = rule.mode,
            pricePercent = rule.percent,
            isFFA = (rule.mode == "FREE"),
            tab = STATE.selectedAssignTab,
            timestamp = now,
            updatedAt = now,
            officer = VM:GetPlayerName(),
            source = "MANUAL_ASSIGN",
            isManual = true,
            deleted = false
        }
        VM.db.ledger[tx.id] = tx
        VM.Comms:BroadcastTransaction(tx)

        if payCb:GetChecked() and totalP > 0 and recipNorm ~= "GUILD" then
            VM.Ledger:RecordPayment(recipNorm, totalP, VM:GetPlayerName(), "MANUAL", "Manual assign payment")
        end

        VM:Print(string.format("Assigned %dx %s to |cffffff00%s|r (Charged: %s).", qty, item.name, recipNorm, VM:FormatMoney(totalP)))
        assignModalFrame:Hide()
        if VM.UI then VM.UI:RefreshAll() end
    end)

    local cancelBtn = CreateModernButton(assignModalFrame, 90, 26, "Cancel")
    cancelBtn:SetPoint("BOTTOMRIGHT", -148, 12)
    cancelBtn:SetScript("OnClick", function() assignModalFrame:Hide() end)
end

function UI:OpenAssignModal(item, tabIndex)
    if not assignModalFrame then self:CreateAssignModal() end
    STATE.selectedAssignItem = item
    STATE.selectedAssignTab = tabIndex
    STATE.selectedAssignRecipient = ""
    STATE.selectedAssignGuildCat = nil
    assignModalFrame.recBtn:SetText("Select Member...")

    assignModalFrame.itemLbl:SetText(string.format("Item: %s (Stock: %d)", item.link or item.name, item.count))
    assignModalFrame.qtyBox:SetText("1")

    local rule = VM:GetTabRule(tabIndex)
    local effPrice = VM:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice)
    local totalCharged = VM:CalculateMemberTotalPrice(effPrice, 1, rule)

    assignModalFrame.priceBox:SetText(tostring(totalCharged))
    assignModalFrame.totalLbl:SetText("= " .. VM:FormatMoney(totalCharged))
    assignModalFrame.payCb:SetChecked(totalCharged > 0)

    assignModalFrame:Show()
end

--------------------------------------------------------------------------------
-- EXPORT MODAL
--------------------------------------------------------------------------------
function UI:CreateExportModal()
    exportModalFrame = CreateFrame("Frame", "VaultManagerExportModal", UIParent, "BackdropTemplate")
    exportModalFrame:SetSize(600, 420)
    exportModalFrame:SetPoint("CENTER")
    exportModalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    exportModalFrame:SetFrameLevel(200)
    exportModalFrame:SetClampedToScreen(true)
    exportModalFrame:SetMovable(true)
    exportModalFrame:EnableMouse(true)
    exportModalFrame:RegisterForDrag("LeftButton")
    exportModalFrame:SetScript("OnDragStart", exportModalFrame.StartMoving)
    exportModalFrame:SetScript("OnDragStop", exportModalFrame.StopMovingOrSizing)
    ApplyModernBackdrop(exportModalFrame, THEME.bg, THEME.accent)
    exportModalFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerExportModal")

    local title = exportModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff26a6f2Vault Manager — Data Export|r")

    local closeBtn = CreateModernButton(exportModalFrame, 24, 24, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() exportModalFrame:Hide() end)

    local csvToggle = CreateFrame("CheckButton", nil, exportModalFrame, "UICheckButtonTemplate")
    csvToggle:SetSize(22, 22)
    csvToggle:SetPoint("TOPLEFT", 14, -42)
    csvToggle.label = csvToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    csvToggle.label:SetPoint("LEFT", csvToggle, "RIGHT", 4, 0)
    csvToggle.label:SetText("CSV Format (otherwise Markdown)")

    local sf = CreateScrollArea(exportModalFrame, -75, 40)
    sf.content:SetSize(560, 1)
    exportModalFrame.scroll = sf

    local editBox = CreateFrame("EditBox", nil, sf.content)
    editBox:SetWidth(550)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf.editBox = editBox
    exportModalFrame.editBox = editBox
    editBox:SetPoint("TOPLEFT", 0, 0)

    csvToggle:SetScript("OnClick", function()
        UI:RefreshExportContent()
    end)
    exportModalFrame.csvToggle = csvToggle

    local copyNote = exportModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyNote:SetPoint("BOTTOMLEFT", 14, 12)
    copyNote:SetText("Press Ctrl+C to copy selected text.")
end

function UI:OpenExportModal()
    if not exportModalFrame then self:CreateExportModal() end
    if exportModalFrame.csvToggle then exportModalFrame.csvToggle:Show() end
    exportModalFrame:Show()
    self:RefreshExportContent()
end

function UI:OpenExportModalText(text)
    if not exportModalFrame then self:CreateExportModal() end
    if exportModalFrame.csvToggle then exportModalFrame.csvToggle:Hide() end
    exportModalFrame:Show()
    if exportModalFrame.editBox then
        exportModalFrame.editBox:SetText(text)
        exportModalFrame.editBox:HighlightText()
        exportModalFrame.editBox:SetFocus()
    end
end

function UI:RefreshExportContent()
    if not exportModalFrame or not exportModalFrame:IsShown() then return end
    local isCSV = (exportModalFrame.csvToggle and exportModalFrame.csvToggle:IsShown() and exportModalFrame.csvToggle:GetChecked()) or false
    local uiPrefs = GetUIPrefs()
    local priceMode = VM:GetValuationMode()
    local sortBy = uiPrefs.rankingSortBy or "net"
    local sortDir = uiPrefs.rankingSortDir or "desc"
    local period = uiPrefs.rankingPeriod or "ALL"
    local hideOff = uiPrefs.hideOfficers or false
    local showLeg = uiPrefs.showLegacyRanking ~= false
    local ranked = VM.Ranking:GetRankingData(sortBy, sortDir, priceMode, period, hideOff, showLeg)

    local function StripColor(str)
        return tostring(str or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end

    local basisDesc = "Live AH"
    local lines = {}
    if isCSV then
        table.insert(lines, string.format("# Valuation Basis: %s | Sort: %s (%s)", basisDesc, sortBy, sortDir))
        table.insert(lines, "Rank,Player,Contributed,Received,NetBalance")
        for idx, grp in ipairs(ranked) do
            local rankBadge = grp.isLegacy and "-" or ("#" .. idx)
            table.insert(lines, string.format("%s,%s,%d,%d,%d",
                rankBadge, grp.mainName, grp.totalContributed, grp.totalWithdrawn, grp.netBalance))
        end
    else
        table.insert(lines, string.format("### Vault Manager Export — Valuation: **%s** | Sort: **%s** (%s)", basisDesc, sortBy, sortDir))
        table.insert(lines, "| Rank | Player | Contributed | Received | Net Balance |")
        table.insert(lines, "| :--- | :--- | :--- | :--- | :--- |")
        for idx, grp in ipairs(ranked) do
            local rankBadge = grp.isLegacy and "-" or ("#" .. idx)
            table.insert(lines, string.format("| %s | %s | %s | %s | %s |",
                rankBadge,
                grp.mainName,
                StripColor(VM:FormatMoney(grp.totalContributed)),
                StripColor(VM:FormatMoney(grp.totalWithdrawn)),
                StripColor(VM:FormatMoney(grp.netBalance))))
        end
    end

    local text = table.concat(lines, "\n")
    if exportModalFrame.editBox then
        exportModalFrame.editBox:SetText(text)
        exportModalFrame.editBox:HighlightText()
        exportModalFrame.editBox:SetFocus()
    end
end

--------------------------------------------------------------------------------
-- CUSTOM SEARCHABLE ROSTER DROPDOWN (WITH CATEGORIZED "GUILD" ENTRIES)
--------------------------------------------------------------------------------
function UI:CreateRosterPickerFrame()
    rosterPickerFrame = CreateFrame("Frame", "VaultManagerRosterPicker", UIParent, "BackdropTemplate")
    rosterPickerFrame:SetSize(224, 260)
    rosterPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rosterPickerFrame:SetFrameLevel(250)
    rosterPickerFrame:SetClampedToScreen(true)
    ApplyModernBackdrop(rosterPickerFrame, { 0.05, 0.06, 0.08, 0.98 }, THEME.accent)
    rosterPickerFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerRosterPicker")

    local search = CreateModernEditBox(rosterPickerFrame, 184, 22, false)
    search:SetPoint("TOPLEFT", 6, -6)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search.placeholder:SetText("Filter name...")
    rosterPickerFrame.search = search

    local closeBtn = CreateModernButton(rosterPickerFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() rosterPickerFrame:Hide() end)

    local sf = CreateScrollArea(rosterPickerFrame, -34, 6)
    sf.content:SetSize(190, 1)
    rosterPickerFrame.scroll = sf

    local debouncedFilter = CreateDebouncer(0.12, function()
        if rosterPickerFrame and rosterPickerFrame:IsShown() then
            UI:RefreshRosterPicker((rosterPickerFrame.search:GetText() or ""):lower())
        end
    end)

    search:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        debouncedFilter()
    end)
end

function UI:OpenRosterPicker(anchor, includeLegacy, onSelect, includeGuildOption)
    if not rosterPickerFrame then self:CreateRosterPickerFrame() end
    rosterPickerFrame.includeLegacy = includeLegacy and true or false
    rosterPickerFrame.includeGuildOption = includeGuildOption and true or false
    rosterPickerFrame.onSelect = onSelect
    rosterPickerFrame.search:SetText("")

    rosterPickerFrame:ClearAllPoints()
    rosterPickerFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    rosterPickerFrame:Show()
    rosterPickerFrame.search:SetFocus()
    self:RefreshRosterPicker("")
end

function UI:RefreshRosterPicker(filter)
    if not rosterPickerFrame or not rosterPickerFrame.scroll then return end
    local names = VM:GetGuildRosterNames(rosterPickerFrame.includeLegacy)
    local content = rosterPickerFrame.scroll.content
    if not content then return end
    for _, r in ipairs(rosterPickerFrame.scroll.rows) do r:Hide() end

    local y = 0
    local idx = 0

    local function AcquirePickerRow()
        idx = idx + 1
        local row = rosterPickerFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(188, 22)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -4, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
            end)
            row:SetScript("OnLeave", function(selfRow)
                local bg = selfRow.baseBg or THEME.rowOdd
                selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            end)
            row:SetScript("OnClick", function(selfRow)
                local chosen = selfRow.entryName
                local chosenCat = selfRow.guildCategory
                local cb = rosterPickerFrame.onSelect
                rosterPickerFrame:Hide()
                if cb and chosen then cb(chosen, chosenCat) end
            end)
            rosterPickerFrame.scroll.rows[idx] = row
        end
        return row
    end

    if rosterPickerFrame.includeGuildOption then
        local guildOpts = {
            { cat = "RAID", label = "|cff26a6f2[Guild — Raid]|r", searchKey = "guild bank raid" },
            { cat = "MEMBER", label = "|cff26a6f2[Guild — Member]|r", searchKey = "guild bank member" },
            { cat = "TABS", label = "|cff26a6f2[Guild — Tabs]|r", searchKey = "guild bank tabs" },
        }
        for _, gOpt in ipairs(guildOpts) do
            if filter == "" or gOpt.searchKey:find(filter, 1, true) then
                local gRow = AcquirePickerRow()
                gRow.entryName = "GUILD"
                gRow.guildCategory = gOpt.cat
                gRow.baseBg = THEME.rowSpecial
                gRow:SetBackdropColor(gRow.baseBg[1], gRow.baseBg[2], gRow.baseBg[3], gRow.baseBg[4])
                gRow:ClearAllPoints()
                gRow:SetPoint("TOPLEFT", 0, -y)
                gRow.label:SetText(gOpt.label)
                gRow:Show()
                y = y + 23
            end
        end
    end

    for _, name in ipairs(names) do
        if filter == "" or name:lower():find(filter, 1, true) then
            local row = AcquirePickerRow()
            row.entryName = name
            row.guildCategory = nil
            row.baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
            row:SetBackdropColor(row.baseBg[1], row.baseBg[2], row.baseBg[3], row.baseBg[4])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            local isLeg = VM:IsLegacyMember(name)
            row.label:SetText(isLeg and (VM:ColorizeName(name, "808080") .. " |cff808080(Legacy)|r") or VM:ColorizeName(name))
            row:Show()
            y = y + 23
        end
    end
    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- RANKING PERIOD DROPDOWN PICKER
--------------------------------------------------------------------------------
function UI:CreateRankingPeriodPickerFrame()
    rankingPeriodDropdownFrame = CreateFrame("Frame", "VaultManagerRankingPeriodPicker", UIParent, "BackdropTemplate")
    rankingPeriodDropdownFrame:SetSize(120, 80)
    rankingPeriodDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rankingPeriodDropdownFrame:SetFrameLevel(250)
    rankingPeriodDropdownFrame:SetClampedToScreen(true)
    ApplyModernBackdrop(rankingPeriodDropdownFrame, { 0.05, 0.06, 0.08, 0.98 }, THEME.accent)
    rankingPeriodDropdownFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerRankingPeriodPicker")

    local options = {
        { key = "ALL", label = "All-Time" },
        { key = "CURRENT", label = "Current Month" },
        { key = "PREVIOUS", label = "Previous Month" },
    }

    rankingPeriodDropdownFrame.buttons = {}
    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, rankingPeriodDropdownFrame, "BackdropTemplate")
        btn:SetSize(112, 22)
        btn:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
        ApplyModernBackdrop(btn, THEME.rowOdd, { 0, 0, 0, 0 })

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", 6, 0)
        btn.label:SetText(opt.label)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(THEME.rowOdd[1], THEME.rowOdd[2], THEME.rowOdd[3], THEME.rowOdd[4])
        end)
        btn:SetScript("OnClick", function()
            rankingPeriodDropdownFrame:Hide()
            local prefs = GetUIPrefs()
            prefs.rankingPeriod = opt.key
            if mainFrame and mainFrame.panels and mainFrame.panels[4] and mainFrame.panels[4].periodBtn then
                mainFrame.panels[4].periodBtn:SetText(opt.label)
            end
            UI:RefreshRanking()
        end)
        rankingPeriodDropdownFrame.buttons[i] = btn
    end
end

function UI:OpenRankingPeriodPicker(anchor)
    if not rankingPeriodDropdownFrame then self:CreateRankingPeriodPickerFrame() end
    rankingPeriodDropdownFrame:ClearAllPoints()
    rankingPeriodDropdownFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    rankingPeriodDropdownFrame:Show()
end

--------------------------------------------------------------------------------
-- BANK VALUE DROPDOWN PANEL
--------------------------------------------------------------------------------
function UI:CreateBankValDropdown()
    bankValDropdownFrame = CreateFrame("Frame", "VaultManagerBankValDropdown", UIParent, "BackdropTemplate")
    bankValDropdownFrame:SetSize(290, 240)
    bankValDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    bankValDropdownFrame:SetFrameLevel(200)
    bankValDropdownFrame:SetClampedToScreen(true)
    ApplyModernBackdrop(bankValDropdownFrame, THEME.bg, THEME.accent)
    bankValDropdownFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerBankValDropdown")

    local sf = CreateScrollArea(bankValDropdownFrame, -10, 10)
    sf.content:SetSize(260, 1)
    bankValDropdownFrame.scroll = sf
end

function UI:RefreshBankValDropdown()
    if not bankValDropdownFrame or not bankValDropdownFrame:IsShown() then return end
    local wealth = VM:CalculateBankWealth()
    local content = bankValDropdownFrame.scroll.content
    if not content then return end
    if not bankValDropdownFrame.rows then bankValDropdownFrame.rows = {} end
    for _, r in ipairs(bankValDropdownFrame.rows) do r:Hide() end

    local rowIdx = 0
    local y = 0

    local function GetRow()
        rowIdx = rowIdx + 1
        local row = bankValDropdownFrame.rows[rowIdx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(260, 22)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            bankValDropdownFrame.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    local r1 = GetRow()
    r1:SetBackdropColor(THEME.rowEven[1], THEME.rowEven[2], THEME.rowEven[3], THEME.rowEven[4])
    r1:ClearAllPoints()
    r1:SetPoint("TOPLEFT", 0, -y)
    r1.label:SetText(string.format("|cffffd700Total Value (Gold + Items):|r %s", VM:FormatMoney(wealth.total)))
    y = y + 24

    local r2 = GetRow()
    r2:SetBackdropColor(THEME.rowOdd[1], THEME.rowOdd[2], THEME.rowOdd[3], THEME.rowOdd[4])
    r2:ClearAllPoints()
    r2:SetPoint("TOPLEFT", 0, -y)
    r2.label:SetText(string.format("  • Guild Bank Gold: %s", VM:FormatMoney(wealth.gold)))
    y = y + 22

    local r3 = GetRow()
    r3:SetBackdropColor(THEME.rowEven[1], THEME.rowEven[2], THEME.rowEven[3], THEME.rowEven[4])
    r3:ClearAllPoints()
    r3:SetPoint("TOPLEFT", 0, -y)
    r3.label:SetText(string.format("  • Items Subtotal: %s", VM:FormatMoney(wealth.itemsTotal)))
    y = y + 24

    local sep = bankValDropdownFrame.sep
    if not sep then
        sep = content:CreateTexture(nil, "OVERLAY")
        sep:SetHeight(1)
        sep:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        bankValDropdownFrame.sep = sep
    end
    sep:ClearAllPoints()
    sep:SetPoint("TOPLEFT", 6, -y)
    sep:SetPoint("TOPRIGHT", -6, -y)
    y = y + 6

    for idx, tabInfo in ipairs(wealth.tabs) do
        local rTab = GetRow()
        local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        rTab:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        rTab:ClearAllPoints()
        rTab:SetPoint("TOPLEFT", 0, -y)
        rTab.label:SetText(string.format("Tab %s: %s (%d items) — %s",
            tostring(tabInfo.index), tabInfo.name, tabInfo.itemCount, VM:FormatMoney(tabInfo.value)))
        y = y + 22
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- MAIN FRAME (6 TABS)
--------------------------------------------------------------------------------
function UI:CreateMainFrame()
    mainFrame = CreateFrame("Frame", "VaultManagerMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(800, 560)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetToplevel(true)
    mainFrame:SetFrameLevel(100)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    -- Height can be dragged larger for a better overview (width stays fixed: rows use fixed columns)
    if mainFrame.SetResizable then mainFrame:SetResizable(true) end
    local maxH = math.max(560, math.floor(((GetScreenHeight and GetScreenHeight()) or 1080) - 40))
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizeBounds(800, 560, 800, maxH)
    else
        if mainFrame.SetMinResize then mainFrame:SetMinResize(800, 560) end
        if mainFrame.SetMaxResize then mainFrame:SetMaxResize(800, maxH) end
    end
    mainFrame:EnableMouse(true)
    mainFrame:EnableKeyboard(true)
    if mainFrame.SetPropagateKeyboardInput then
        mainFrame:SetPropagateKeyboardInput(true)
    end
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = selfFrame:GetPoint()
        local prefs = GetUIPrefs()
        prefs.windowPos = { point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
    end)
    mainFrame:SetScript("OnKeyDown", function(selfFrame, key)
        -- Consume ESC (closes our window only, not the game menu); let all other keys through
        if selfFrame.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
            selfFrame:SetPropagateKeyboardInput(key ~= "ESCAPE")
        end
        if key == "ESCAPE" then
            if qtyPickerFrame and qtyPickerFrame:IsShown() then
                qtyPickerFrame:Hide()
            elseif goldReqModalFrame and goldReqModalFrame:IsShown() then
                goldReqModalFrame:Hide()
            elseif guildExpenseModalFrame and guildExpenseModalFrame:IsShown() then
                guildExpenseModalFrame:Hide()
            elseif requestsHelpFrame and requestsHelpFrame:IsShown() then
                requestsHelpFrame:Hide()
            elseif assignModalFrame and assignModalFrame:IsShown() then
                assignModalFrame:Hide()
            elseif exportModalFrame and exportModalFrame:IsShown() then
                exportModalFrame:Hide()
            elseif rosterPickerFrame and rosterPickerFrame:IsShown() then
                rosterPickerFrame:Hide()
            elseif rankingPeriodDropdownFrame and rankingPeriodDropdownFrame:IsShown() then
                rankingPeriodDropdownFrame:Hide()
            elseif bankValDropdownFrame and bankValDropdownFrame:IsShown() then
                bankValDropdownFrame:Hide()
            else
                UI.userClosedAt = GetTime()
                mainFrame:Hide()
            end
        elseif key == "TAB" or key == "PADLSHOULDER" or key == "PADRSHOULDER" then
            local delta = (key == "PADLSHOULDER") and -1 or 1
            local nextTab = STATE.currentTab + delta
            if nextTab > 6 then nextTab = 1 elseif nextTab < 1 then nextTab = 6 end
            UI:SelectTab(nextTab)
        end
    end)
    if mainFrame.SetScript then
        pcall(function()
            mainFrame:SetScript("OnGamePadButtonDown", function(_, button)
                if button == "PADLSHOULDER" then
                    local prevTab = STATE.currentTab - 1
                    if prevTab < 1 then prevTab = 6 end
                    UI:SelectTab(prevTab)
                elseif button == "PADRSHOULDER" then
                    local nextTab = STATE.currentTab + 1
                    if nextTab > 6 then nextTab = 1 end
                    UI:SelectTab(nextTab)
                elseif button == "PAD2" then
                    if qtyPickerFrame and qtyPickerFrame:IsShown() then
                        qtyPickerFrame:Hide()
                    elseif goldReqModalFrame and goldReqModalFrame:IsShown() then
                        goldReqModalFrame:Hide()
                    elseif guildExpenseModalFrame and guildExpenseModalFrame:IsShown() then
                        guildExpenseModalFrame:Hide()
                    elseif requestsHelpFrame and requestsHelpFrame:IsShown() then
                        requestsHelpFrame:Hide()
                    elseif assignModalFrame and assignModalFrame:IsShown() then
                        assignModalFrame:Hide()
                    elseif exportModalFrame and exportModalFrame:IsShown() then
                        exportModalFrame:Hide()
                    elseif rosterPickerFrame and rosterPickerFrame:IsShown() then
                        rosterPickerFrame:Hide()
                    else
                        mainFrame:Hide()
                    end
                end
            end)
        end)
    end
    ApplyModernBackdrop(mainFrame, THEME.bg, THEME.border)
    mainFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerMainFrame")

    mainFrame:SetScript("OnHide", function(selfFrame)
        local now = GetTime()
        local autoAt = UI.autoOpenedAt or 0
        local userAt = UI.userClosedAt or 0
        -- Diagnostics: who hid the window (shown with /vm debug)
        if userAt < now - 0.2 and debugstack then
            local stack = tostring(debugstack(2, 4, 0) or ""):gsub("Interface\\AddOns\\", ""):gsub("\n", " < ")
            VM:LogDebug("MainFrame hidden by: " .. stack:sub(1, 220))
        end
        if (now - autoAt) < AUTO_OPEN_STICKY_SEC and userAt < autoAt and C_Timer and C_Timer.After then
            -- Hidden by something else right after auto-opening (CloseSpecialWindows etc.): show again
            C_Timer.After(0.05, function()
                if not selfFrame:IsShown() and (UI.userClosedAt or 0) < autoAt then
                    selfFrame:Show()
                    UI:RefreshAll()
                end
            end)
        end
    end)

    local prefs = GetUIPrefs()
    if prefs.uiScale then
        mainFrame:SetScale(prefs.uiScale)
    end
    if prefs.windowHeight and prefs.windowHeight >= 560 then
        mainFrame:SetHeight(math.min(prefs.windowHeight, maxH))
    end

    local resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
    if resizeGrip.SetNormalTexture then
        resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    end
    resizeGrip:SetScript("OnMouseDown", function()
        mainFrame:StartSizing("BOTTOM")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        local h = math.floor((mainFrame:GetHeight() or 560) + 0.5)
        GetUIPrefs().windowHeight = h
        -- Re-anchor at the top-left so the saved position matches the new size
        local point, _, relativePoint, xOfs, yOfs = mainFrame:GetPoint()
        GetUIPrefs().windowPos = { point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
        UI:RefreshAll()
    end)
    resizeGrip:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to resize height", 1, 1, 1)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.resizeGrip = resizeGrip
    if prefs.windowPos then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(prefs.windowPos.point or "CENTER", UIParent, prefs.windowPos.relativePoint or "CENTER", prefs.windowPos.xOfs or 0, prefs.windowPos.yOfs or 0)
    end

    local headerBar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    headerBar:SetHeight(38)
    headerBar:SetPoint("TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", -1, -1)
    ApplyModernBackdrop(headerBar, { 0.05, 0.06, 0.08, 1 }, { 0.15, 0.17, 0.22, 1 })

    local accentLine = headerBar:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", 0, 0)
    accentLine:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)

    local title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    local ver = "v" .. (VM.GetAddonVersion and VM:GetAddonVersion() or "1.4.3")
    if VM.BUILD then
        ver = ver .. "  |cffffaa00dev " .. tostring(VM.BUILD):match("^(%S+)") .. "|r"
    end
    title:SetText(string.format("|cff26a6f2VAULT|r |cffffffffMANAGER|r |cff8899aa%s|r", ver))

    -- Topbar Guild Sync status button (replaces duplicate Scan Bank button)
    mainFrame.scanStatusBtn = CreateModernButton(headerBar, 114, 22, "Data Synced", THEME.accent)
    mainFrame.scanStatusBtn:SetPoint("LEFT", title, "RIGHT", 14, 0)
    mainFrame.scanStatusBtn:SetScript("OnClick", function()
        if VM.Comms and VM.Comms.RequestManualSync then
            local ok, waitSec = VM.Comms:RequestManualSync()
            if ok then
                VM:Print("Checked online guild members for newer vault data.")
            elseif waitSec and waitSec > 0 then
                VM:Print(string.format("Sync already checked. Please wait %ds.", waitSec))
            end
        end
    end)
    mainFrame.scanStatusBtn:HookScript("OnEnter", function(selfBtn)
        if selfBtn.tooltipText and selfBtn.tooltipText ~= "" then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText(selfBtn.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    mainFrame.scanStatusBtn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local closeBtn = CreateModernButton(headerBar, 24, 24, "X", THEME.red)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function()
        UI.userClosedAt = GetTime()
        mainFrame:Hide()
        HideAllPopups()
    end)

    mainFrame.scanInfo = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Role badge: makes it obvious which functions are available to you
    local roleBtn = CreateFrame("Frame", nil, headerBar, "BackdropTemplate")
    roleBtn:SetSize(96, 20)
    roleBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    ApplyModernBackdrop(roleBtn, { 0.08, 0.09, 0.12, 1 }, THEME.border)
    roleBtn:EnableMouse(true)
    roleBtn.text = roleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roleBtn.text:SetPoint("CENTER", 0, 0)
    roleBtn:SetScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText(selfBtn.tip or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    roleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.roleBadge = roleBtn

    mainFrame.scanInfo:SetPoint("RIGHT", roleBtn, "LEFT", -10, 0)
    mainFrame.scanInfo:SetPoint("LEFT", mainFrame.scanStatusBtn, "RIGHT", 12, 0)
    mainFrame.scanInfo:SetJustifyH("RIGHT")
    mainFrame.scanInfo:SetTextColor(0.65, 0.70, 0.78)

    local tabNames = { "Vault & Requests", "Requests", "Ledger", "Ranking", "Roster & Mains", "Settings" }
    mainFrame.navButtons = {}
    for i, name in ipairs(tabNames) do
        local btn = CreateModernButton(mainFrame, 124, 28, name)
        btn:SetPoint("TOPLEFT", 14 + (i - 1) * 128, -48)

        btn.activeBar = btn:CreateTexture(nil, "OVERLAY")
        btn.activeBar:SetHeight(2)
        btn.activeBar:SetPoint("BOTTOMLEFT", 1, 1)
        btn.activeBar:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.activeBar:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        btn.activeBar:Hide()

        btn:SetScript("OnClick", function()
            self:SelectTab(i)
        end)
        mainFrame.navButtons[i] = btn
    end

    mainFrame.panels = {}
    for i = 1, 6 do
        local p = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
        p:SetPoint("TOPLEFT", 14, -84)
        p:SetPoint("BOTTOMRIGHT", -14, 14)
        ApplyModernBackdrop(p, THEME.panel, THEME.border)
        p:Hide()
        mainFrame.panels[i] = p
    end

    self:BuildInventoryPanel(mainFrame.panels[1])
    self:BuildRequestsPanel(mainFrame.panels[2])
    self:BuildLedgerPanel(mainFrame.panels[3])
    self:BuildRankingPanel(mainFrame.panels[4])
    self:BuildRosterPanel(mainFrame.panels[5])
    self:BuildSettingsPanel(mainFrame.panels[6])
end

--------------------------------------------------------------------------------
-- TAB 1: VAULT & REQUESTS
--------------------------------------------------------------------------------
local CAT_ORDER = { "Gear", "Consumables", "Crafting Mats", "Crafting Reagents", "Recipes", "Other" }

function UI:BuildInventoryPanel(panel)
    panel.bankTabButtons = {}
    for i = 1, 6 do
        local b = CreateModernButton(panel, 82, 24, "Tab " .. i)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 86, -8)
        b.tabIndex = i
        b:SetScript("OnClick", function(selfBtn)
            if STATE.selectedBankTab ~= selfBtn.tabIndex then
                STATE.selectedBankTab = selfBtn.tabIndex
                if qtyPickerFrame then qtyPickerFrame:Hide() end
            end
            UI:RefreshInventory()
        end)
        panel.bankTabButtons[i] = b
    end

    local scanBtn = CreateModernButton(panel, 78, 24, "Scan Now", THEME.green)
    scanBtn:SetPoint("TOPRIGHT", -10, -8)
    AttachHelp(scanBtn, "Rescans the open Guild Bank (tabs and logs). This happens automatically when you open the bank; use it if something looks out of date.")
    scanBtn:SetScript("OnClick", function()
        if VM.BankScanner and VM.BankScanner.ForceScan then
            if IsBankCurrentlyOpen() then
                VM:Print("Scanning Guild Bank tabs and logs...")
            end
            VM.BankScanner:ForceScan()
        end
    end)
    panel.scanBtn = scanBtn

    local bankValBtn = CreateModernButton(panel, 145, 24, "Bank Value: 0g (v)", THEME.accent)
    AttachHelp(bankValBtn, "Total worth of the Guild Bank (gold plus items at current AH prices). Click for a breakdown per tab.")
    bankValBtn:SetPoint("TOPRIGHT", scanBtn, "TOPLEFT", -6, 0)
    bankValBtn:SetScript("OnClick", function()
        if not bankValDropdownFrame then UI:CreateBankValDropdown() end
        local wealth = VM:CalculateBankWealth()
        local isOpen = bankValDropdownFrame:IsShown()
        if isOpen then
            bankValDropdownFrame:Hide()
            bankValBtn:SetText("Bank Value: " .. VM:FormatMoneyShort(wealth.total) .. " (v)")
        else
            bankValDropdownFrame:ClearAllPoints()
            bankValDropdownFrame:SetPoint("TOPLEFT", bankValBtn, "BOTTOMLEFT", 0, -2)
            bankValDropdownFrame:Show()
            bankValBtn:SetText("Bank Value: " .. VM:FormatMoneyShort(wealth.total) .. " (^)")
            UI:RefreshBankValDropdown()
        end
    end)
    panel.bankValBtn = bankValBtn

    local filterStrip = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterStrip:SetHeight(28)
    filterStrip:SetPoint("TOPLEFT", 10, -36)
    filterStrip:SetPoint("TOPRIGHT", -10, -36)
    ApplyModernBackdrop(filterStrip, { 0.05, 0.06, 0.08, 0.9 }, THEME.border)

    local ruleBannerBtn = CreateFrame("Button", nil, filterStrip)
    ruleBannerBtn:SetPoint("LEFT", 8, 0)
    ruleBannerBtn:SetSize(430, 24)
    ruleBannerBtn.text = ruleBannerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ruleBannerBtn.text:SetPoint("LEFT", 0, 0)
    ruleBannerBtn.text:SetJustifyH("LEFT")
    panel.ruleBannerBtn = ruleBannerBtn

    ruleBannerBtn:SetScript("OnEnter", function(selfBtn)
        selfBtn.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText(VM:IsOfficer() and "Click to configure Tab Rules in Settings" or "Click to view Tab Rules in Settings")
        GameTooltip:Show()
    end)
    ruleBannerBtn:SetScript("OnLeave", function(selfBtn)
        selfBtn.text:SetTextColor(0.9, 0.9, 0.9)
        GameTooltip:Hide()
    end)
    ruleBannerBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        UI:SelectTab(6)
    end)

    local searchBox = CreateModernEditBox(filterStrip, 140, 22, false)
    searchBox:SetPoint("RIGHT", -6, 0)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 8, 0)
    searchBox.placeholder:SetText("Search item...")

    local debouncedVaultSearch = CreateDebouncer(0.15, function()
        if mainFrame and mainFrame:IsShown() and STATE.currentTab == 1 then
            UI:RefreshInventory()
        end
    end)

    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        STATE.searchQuery = txt:lower()
        debouncedVaultSearch()
    end)
    panel.searchBox = searchBox

    local toggleAllBtn = CreateModernButton(filterStrip, 84, 22, "Expand All")
    toggleAllBtn:SetPoint("RIGHT", searchBox, "LEFT", -6, 0)
    panel.helpBtn = AddTabHelpButton(filterStrip, "VAULT", toggleAllBtn, "RIGHT", "LEFT", -6, 0)
    toggleAllBtn:SetScript("OnClick", function()
        local list = (panel.visibleCategories and #panel.visibleCategories > 0) and panel.visibleCategories or CAT_ORDER
        local anyCollapsed = false
        for _, catName in ipairs(list) do
            if not STATE.vaultCategoryExpanded[catName] then
                anyCollapsed = true
                break
            end
        end
        for _, catName in ipairs(list) do
            STATE.vaultCategoryExpanded[catName] = anyCollapsed
        end
        UI:RefreshInventory()
    end)
    panel.toggleAllBtn = toggleAllBtn

    panel.scroll = CreateScrollArea(panel, -68, 8)
end

if not VM_HiddenScanTooltip then
    CreateFrame("GameTooltip", "VM_HiddenScanTooltip", UIParent, "GameTooltipTemplate")
end

local RequestDelayedInventoryRefresh = CreateDebouncer(0.5, function()
    if mainFrame and mainFrame:IsShown() and STATE.currentTab == 1 and UI.RefreshInventory then
        UI:RefreshInventory()
    end
end)

local queriedItemIDs = {}

local KNOWN_ITEM_TYPES = {
    ["Weapon"] = true,
    ["Armor"] = true,
    ["Consumable"] = true,
    ["Trade Goods"] = true,
    ["Reagent"] = true,
    ["Recipe"] = true,
}

local VALID_CACHED_CATEGORIES = {
    ["Gear"] = true,
    ["Consumables"] = true,
    ["Crafting Mats"] = true,
    ["Crafting Reagents"] = true,
    ["Recipes"] = true,
    ["Other"] = true,
}

local GEAR_SLOTS = {
    ["Head"] = true, ["Neck"] = true, ["Shoulder"] = true, ["Back"] = true,
    ["Chest"] = true, ["Shirt"] = true, ["Tabard"] = true, ["Wrist"] = true,
    ["Hands"] = true, ["Waist"] = true, ["Legs"] = true, ["Feet"] = true,
    ["Finger"] = true, ["Trinket"] = true, ["One-Hand"] = true, ["Two-Hand"] = true,
    ["Main Hand"] = true, ["Off Hand"] = true, ["Held In Off-hand"] = true,
    ["Ranged"] = true, ["Thrown"] = true, ["Relic"] = true, ["Shield"] = true,
}

local function IsGearTooltipLine(txt, trimmed)
    if not txt or txt == "" then return false end
    if trimmed and GEAR_SLOTS[trimmed] then return true end
    if txt:match("%d+ Armor") or trimmed == "Armor" then return true end
    if txt:match("Speed %d") then return true end
    if not (trimmed and trimmed:find("^Use:")) and txt:find("Damage", 1, true) then return true end
    return false
end

local function GetItemCategory(item)
    if not item then return "Other" end

    if item.cachedCategory and VALID_CACHED_CATEGORIES[item.cachedCategory] then
        return item.cachedCategory
    end

    local itemType = (item.itemType and item.itemType ~= "") and item.itemType or nil
    local equipSlot = (item.equipSlot and item.equipSlot ~= "") and item.equipSlot or nil

    local numID = tonumber(item.itemID)
    if not numID and item.link and type(item.link) == "string" then
        numID = tonumber(item.link:match("item:(%d+)"))
    end
    if not numID and item.itemLink and type(item.itemLink) == "string" then
        numID = tonumber(item.itemLink:match("item:(%d+)"))
    end
    if numID and numID <= 0 then numID = nil end

    local r1
    local needLookup = not item.infoChecked and (not itemType or not KNOWN_ITEM_TYPES[itemType] or (not equipSlot and itemType ~= "Consumable" and itemType ~= "Trade Goods" and itemType ~= "Reagent" and itemType ~= "Recipe"))
    if needLookup and type(GetItemInfo) == "function" then
        local lookup
        local link = item.link or item.itemLink
        if link and type(link) == "string" and link:find("|Hitem:", 1, true) then
            lookup = link
        elseif numID then
            lookup = numID
        end

        if lookup then
            local r2, r3, r4, r5, r6, r7, r8, r9, r10
            r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = GetItemInfo(lookup)
            if not r1 and numID and lookup ~= numID then
                r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = GetItemInfo(numID)
            end

            if r1 then
                item.infoChecked = true
                local foundType, foundEquip
                local rets = { r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 }
                for idx = 1, 10 do
                    local val = rets[idx]
                    if type(val) == "string" then
                        if not foundType and KNOWN_ITEM_TYPES[val] then
                            foundType = val
                        end
                        if not foundEquip and val:find("^INVTYPE_") then
                            foundEquip = val
                        end
                    end
                end

                itemType = foundType or itemType or "Other"
                item.itemType = itemType
                equipSlot = foundEquip or equipSlot or ""
                item.equipSlot = equipSlot
            end
        end
    end

    itemType = itemType or ""
    equipSlot = equipSlot or ""

    local tip = _G["VM_HiddenScanTooltip"] or CreateFrame("GameTooltip", "VM_HiddenScanTooltip", nil, "GameTooltipTemplate")
    local numLines = 0
    if numID then
        pcall(function()
            tip:SetOwner(WorldFrame, "ANCHOR_NONE")
            tip:ClearLines()
            tip:SetHyperlink("item:" .. tostring(numID))
            numLines = tip:NumLines() or 0
        end)
    end

    if numLines <= 1 then
        local attempts = numID and (queriedItemIDs[numID] or 0) or 0
        if attempts < 3 then
            if numID then queriedItemIDs[numID] = attempts + 1 end
            RequestDelayedInventoryRefresh()
        end
    end

    local hasTeaches = false
    local hasGearText = false
    local hasUse = false
    local hasCraftingReagent = false

    for i = 1, numLines do
        local leftFs = _G["VM_HiddenScanTooltipTextLeft" .. i]
        local rightFs = _G["VM_HiddenScanTooltipTextRight" .. i]
        local leftText = leftFs and leftFs:GetText() or nil
        local rightText = rightFs and rightFs:GetText() or nil

        if leftText and type(leftText) == "string" then
            local cleanLeft = leftText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local trimLeft = cleanLeft:match("^%s*(.-)%s*$") or cleanLeft
            if cleanLeft:lower():find("crafting reagent", 1, true) then hasCraftingReagent = true end
            if cleanLeft:find("Use: Teaches", 1, true) then hasTeaches = true end
            if IsGearTooltipLine(cleanLeft, trimLeft) then hasGearText = true end
            if trimLeft:find("^Use:") then hasUse = true end
        end

        if rightText and type(rightText) == "string" then
            local cleanRight = rightText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local trimRight = cleanRight:match("^%s*(.-)%s*$") or cleanRight
            if cleanRight:lower():find("crafting reagent", 1, true) then hasCraftingReagent = true end
            if cleanRight:find("Use: Teaches", 1, true) then hasTeaches = true end
            if IsGearTooltipLine(cleanRight, trimRight) then hasGearText = true end
            if trimRight:find("^Use:") then hasUse = true end
        end
    end

    local rawName = item.name or ""
    if rawName == "" and type(r1) == "string" then rawName = r1 end
    if rawName == "" and item.link and type(item.link) == "string" then rawName = item.link:match("%[(.-)%]") or "" end
    if rawName == "" and item.itemLink and type(item.itemLink) == "string" then rawName = item.itemLink:match("%[(.-)%]") or "" end
    if rawName == "" and numLines >= 1 then
        local left1 = _G["VM_HiddenScanTooltipTextLeft1"]
        if left1 and left1:GetText() then rawName = left1:GetText() end
    end

    local cleanName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local bracketName = cleanName:match("%[(.-)%]")
    cleanName = bracketName or cleanName
    cleanName = cleanName:gsub("^%[", ""):gsub("%]$", "")
    cleanName = cleanName:match("^%s*(.-)%s*$") or cleanName

    local isRecipeName = cleanName:find("^Pattern:") or cleanName:find("^Recipe:") or
                         cleanName:find("^Plans:") or cleanName:find("^Formula:") or
                         cleanName:find("^Schematic:") or cleanName:find("^Manual:")

    local isRecipe = isRecipeName or hasTeaches or (itemType == "Recipe")
    local isGearInfo = (itemType == "Weapon" or itemType == "Armor" or
        (equipSlot ~= "" and equipSlot:find("^INVTYPE_") and equipSlot ~= "INVTYPE_BAG"))
    local isGear = hasGearText or isGearInfo
    local isConsumable = ((hasUse and not isGear and not isRecipe) or (itemType == "Consumable"))
    local isCraftingReagent = hasCraftingReagent or (itemType == "Reagent")
    local isCraftingMat = (itemType == "Trade Goods")

    local category
    if isRecipe then
        category = "Recipes"
    elseif isGear then
        category = "Gear"
    elseif isConsumable then
        category = "Consumables"
    elseif isCraftingReagent then
        category = "Crafting Reagents"
    elseif isCraftingMat then
        category = "Crafting Mats"
    else
        category = "Other"
    end

    if category ~= "Other" or numLines > 1 then
        item.cachedCategory = category
    end

    return category
end

local function CreateInventoryRow(content)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(732, 30)
    row:EnableMouse(true)
    ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(22, 22)
    row.iconBtn:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 0, 0)

    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetSize(220, 26)
    row.nameBtn:SetPoint("LEFT", 36, 0)
    row.nameText = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetAllPoints()
    row.nameText:SetJustifyH("LEFT")

    row.stockText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.stockText:SetPoint("LEFT", 260, 0)
    row.stockText:SetWidth(112)
    row.stockText:SetJustifyH("LEFT")

    row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.priceText:SetPoint("LEFT", 374, 0)
    row.priceText:SetWidth(108)
    row.priceText:SetJustifyH("LEFT")

    row.qtyBtn = CreateModernDropdown(row, 46, 22, "1")
    row.qtyBtn:SetPoint("LEFT", 486, 0)

    row.reqBtn = CreateModernButton(row, 68, 22, "Request", THEME.accent)
    row.reqBtn:SetPoint("LEFT", 538, 0)

    row.assignBtn = CreateModernButton(row, 68, 22, "Assign", { 0.20, 0.60, 0.80, 1 })
    row.assignBtn:SetPoint("LEFT", 612, 0)

    row.cancelBtn = CreateModernButton(row, 46, 22, "Cancel", THEME.red)
    row.cancelBtn:SetPoint("LEFT", 486, 0)
    row.cancelBtn:Hide()
    row.cancelBtn:SetScript("OnClick", function()
        if row.openReqId and VM.Fulfillment then VM.Fulfillment:CancelOwnRequest(row.openReqId) end
    end)
    row.cancelBtn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Cancel your open request for this item", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.cancelBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local function OnRowEnter(anchor)
        row:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], THEME.rowHover[4])
        local itm = row.itemData
        if itm then
            ShowItemTooltip(anchor, itm.itemLink or itm.link, itm.itemID, itm.name)
        end
    end
    local function OnRowLeave()
        local bg = row.baseBg or THEME.rowOdd
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        HideItemTooltip()
    end

    row:SetScript("OnEnter", function(selfRow) OnRowEnter(selfRow) end)
    row:SetScript("OnLeave", OnRowLeave)
    row.iconBtn:SetScript("OnEnter", function(selfBtn) OnRowEnter(selfBtn) end)
    row.iconBtn:SetScript("OnLeave", OnRowLeave)
    row.nameBtn:SetScript("OnEnter", function(selfBtn) OnRowEnter(selfBtn) end)
    row.nameBtn:SetScript("OnLeave", OnRowLeave)

    row.qtyBtn:SetScript("OnClick", function(selfBtn)
        local avail = row.maxPick or row.available or 1
        local curr = row.selectedQty or 1
        local stateKey = row.qtyStateKey
        UI:OpenQtyPicker(selfBtn, avail, curr, function(chosen)
            if stateKey then
                STATE.selectedVaultQty[stateKey] = chosen
            end
            UI:RefreshInventory()
        end)
    end)

    row.reqBtn:SetScript("OnClick", function(selfBtn)
        if not row.itemData or not selfBtn:IsEnabled() then return end
        local qty = row.selectedQty or 1
        -- Immediate visual response before the list refreshes
        selfBtn:SetText("Sent...")
        ApplyButtonState(selfBtn, "done")
        local req = VM.Fulfillment:CreateRequest(row.tabIndex, row.itemKey, qty)
        if not req then
            UI:RefreshInventory()
        end
    end)
    row.reqBtn:HookScript("OnEnter", function(selfBtn)
        if selfBtn.tooltipText then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(selfBtn.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row.reqBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    row.assignBtn:SetScript("OnClick", function()
        if not row.itemData then return end
        UI:OpenAssignModal(row.itemData, row.tabIndex)
    end)

    return row
end

function UI:RefreshInventory()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[1] then return end
    local panel = mainFrame.panels[1]
    if not panel or not panel.scroll or not panel.bankTabButtons then return end
    local inv = VM.db and VM.db.inventory
    if not inv or not inv.tabs then return end

    if panel.bankValBtn then
        local wealth = VM:CalculateBankWealth()
        local isOpen = bankValDropdownFrame and bankValDropdownFrame:IsShown()
        panel.bankValBtn:SetText(string.format("Bank Value: %s %s", VM:FormatMoneyShort(wealth.total), isOpen and "(^)" or "(v)"))
        if isOpen then
            UI:RefreshBankValDropdown()
        end
    end

    local firstPurchasedTab = nil
    local selectedIsValid = false
    local visibleSlot = 0
    for i = 1, 6 do
        local btn = panel.bankTabButtons[i]
        local tabData = inv.tabs[i]
        local isPurchased = (tabData ~= nil) and (tabData.isPurchased ~= false) and VM:IsTabPurchased(i)
        if isPurchased then
            if not firstPurchasedTab then firstPurchasedTab = i end
            if i == STATE.selectedBankTab then selectedIsValid = true end
            visibleSlot = visibleSlot + 1
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 10 + (visibleSlot - 1) * 86, -8)
            btn:Show()
            btn:SetText(tabData.name or ("Tab " .. i))
        else
            btn:Hide()
        end
    end

    if not selectedIsValid then
        STATE.selectedBankTab = firstPurchasedTab or 1
    end

    for i = 1, 6 do
        local btn = panel.bankTabButtons[i]
        if btn:IsShown() then
            if i == STATE.selectedBankTab then
                btn.customBg = { 0.15, 0.28, 0.42, 1 }
                btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                SetButtonAccent(btn, THEME.accent)
            else
                btn.customBg = nil
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                SetButtonAccent(btn, THEME.border)
            end
        end
    end

    local rule = VM:GetTabRule(STATE.selectedBankTab)
    if panel.ruleBannerBtn and panel.ruleBannerBtn.text then
        if rule.mode == "LOCKED" then
            panel.ruleBannerBtn.text:SetText("|cffff5555LOCKED TAB|r  |cff999999— Requests disabled|r")
        elseif rule.mode == "PERCENT" then
            panel.ruleBannerBtn.text:SetText(string.format("|cffffcc33MEMBER PRICE: %d%% OF AH (min 1g)|r  |cff999999— Remainder booked to GUILD|r", rule.percent or 50))
        else
            panel.ruleBannerBtn.text:SetText("|cff44dd77FREE-FOR-ALL|r  |cff999999— Free withdrawal (100% AH value tracked in ledger)|r")
        end
    end

    local content = panel.scroll.content
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    panel.scroll.catHeaders = panel.scroll.catHeaders or {}
    for _, h in pairs(panel.scroll.catHeaders) do h:Hide() end

    local tabData = inv.tabs[STATE.selectedBankTab]
    if not tabData or tabData.isPurchased == false then
        panel.visibleCategories = {}
        content:SetHeight(1)
        return
    end

    local cats = {
        ["Gear"] = {},
        ["Consumables"] = {},
        ["Crafting Mats"] = {},
        ["Crafting Reagents"] = {},
        ["Recipes"] = {},
        ["Other"] = {}
    }

    for _, item in pairs(tabData.items or {}) do
        if STATE.searchQuery == "" or (item.name and item.name:lower():find(STATE.searchQuery, 1, true)) then
            local cat = GetItemCategory(item)
            if not cats[cat] then cat = "Other" end
            table.insert(cats[cat], item)
        end
    end

    panel.visibleCategories = {}
    for _, catName in ipairs(CAT_ORDER) do
        table.sort(cats[catName], function(a, b) return (a.name or "") < (b.name or "") end)
        if #cats[catName] > 0 then
            table.insert(panel.visibleCategories, catName)
        end
    end

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, catName in ipairs(panel.visibleCategories) do
            if not STATE.vaultCategoryExpanded[catName] then
                anyCollapsed = true
                break
            end
        end
        panel.toggleAllBtn:SetText(anyCollapsed and "Expand All" or "Collapse All")
    end

    local isOff = VM:IsOfficer()
    local y = 0
    local rowIdx = 0

    for _, catName in ipairs(CAT_ORDER) do
        local catItems = cats[catName]
        if #catItems > 0 then
            local isExpanded = (STATE.searchQuery ~= "") or (STATE.vaultCategoryExpanded[catName] == true)
            local header = panel.scroll.catHeaders[catName]
            if not header then
                header = CreateFrame("Button", nil, content, "BackdropTemplate")
                header:SetSize(732, 24)
                ApplyModernBackdrop(header, THEME.headerBg, THEME.border)
                header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                header.text:SetPoint("LEFT", 8, 0)
                header.catName = catName
                header:SetScript("OnClick", function(selfHdr)
                    if STATE.searchQuery == "" then
                        STATE.vaultCategoryExpanded[selfHdr.catName] = not STATE.vaultCategoryExpanded[selfHdr.catName]
                        UI:RefreshInventory()
                    end
                end)
                panel.scroll.catHeaders[catName] = header
            end

            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 4, -y)
            header.text:SetText(string.format("%s  %s (%d)", isExpanded and "[-]" or "[+]", catName, #catItems))
            header:Show()
            y = y + 26

            if isExpanded then
                for idx, item in ipairs(catItems) do
                    rowIdx = rowIdx + 1
                    local row = panel.scroll.rows[rowIdx]
                    if not row then
                        row = CreateInventoryRow(content)
                        panel.scroll.rows[rowIdx] = row
                    end

                    local baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
                    row.baseBg = baseBg
                    row.itemData = item
                    row.tabIndex = STATE.selectedBankTab
                    local itemKey = (item.itemID and item.itemID ~= 0) and item.itemID or item.name
                    row.itemKey = itemKey

                    local reserved = VM:GetReservedCount(itemKey, STATE.selectedBankTab)
                    local available = math.max(0, (item.count or 0) - reserved)
                    row.available = available
                    local maxReq = VM:GetMaxRequestQty(item.itemID, item.itemLink or item.link)
                    row.maxPick = maxReq and math.min(available, maxReq) or available
                    local myOpenQty, myOpenReq = VM.Fulfillment:GetMyOpenRequestCount(itemKey, STATE.selectedBankTab)
                    row.openReqId = (myOpenReq and (myOpenReq.status == "PENDING" or myOpenReq.status == "APPROVED")) and myOpenReq.id or nil

                    local qtyStateKey = tostring(STATE.selectedBankTab) .. ":" .. tostring(itemKey)
                    row.qtyStateKey = qtyStateKey
                    local selectedQty = tonumber(STATE.selectedVaultQty[qtyStateKey]) or 1
                    if row.maxPick > 0 and selectedQty > row.maxPick then
                        selectedQty = row.maxPick
                        STATE.selectedVaultQty[qtyStateKey] = selectedQty
                    elseif selectedQty < 1 then
                        selectedQty = 1
                    end
                    row.selectedQty = selectedQty

                    row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 4, -y)
                    row:Show()

                    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.nameText:SetText(item.link or item.name)

                    local mineTag = (myOpenQty > 0) and string.format(" |cff44dd77(You: %d)|r", myOpenQty) or ""
                    if reserved > 0 then
                        row.stockText:SetText(string.format("Avail: |cff44dd77%d|r |cff888888(Res:%d)|r%s", available, reserved, mineTag))
                    else
                        row.stockText:SetText(string.format("Stock: |cff44dd77%d|r%s", available, mineTag))
                    end

                    local effectivePrice = VM:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice)
                    if effectivePrice > 0 then
                        if rule.mode == "PERCENT" then
                            local memberPrice = VM:CalculateMemberTotalPrice(effectivePrice, selectedQty, rule)
                            row.priceText:SetText("Price: " .. VM:FormatMoney(memberPrice))
                        else
                            row.priceText:SetText("AH: " .. VM:FormatMoney(effectivePrice))
                        end
                    else
                        row.priceText:SetText("|cff777777AH: Unknown|r")
                    end

                    row.reqBtn.tooltipText = nil
                    row.cancelBtn:Hide()
                    if myOpenQty > 0 then
                        -- Immediate feedback + protection against duplicate requests
                        row.reqBtn:SetText("Requested")
                        ApplyButtonState(row.reqBtn, "done")
                        row.reqBtn.tooltipText = "You already have an open request for this item. Cancel it to change the amount."
                        row.qtyBtn:Hide()
                        if row.openReqId then row.cancelBtn:Show() end
                    elseif rule.mode == "LOCKED" or available <= 0 then
                        row.reqBtn:SetText("Request")
                        row.reqBtn:SetModernEnabled(false)
                        row.qtyBtn:Hide()
                    else
                        row.reqBtn:SetText("Request")
                        row.reqBtn:SetModernEnabled(true)
                        if maxReq then
                            row.reqBtn.tooltipText = string.format("Max %d per request (%d stacks).", maxReq, VM.MAX_REQUEST_STACKS)
                        end
                        row.qtyBtn:SetText(tostring(selectedQty))
                        row.qtyBtn:Show()
                    end

                    if isOff then
                        row.assignBtn:Show()
                        row.assignBtn:SetModernEnabled(rule.mode ~= "LOCKED" and available > 0)
                    else
                        row.assignBtn:Hide()
                    end

                    y = y + 32
                end
            end
        end
    end
    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 2: REQUESTS
--------------------------------------------------------------------------------
local REQ_SECTIONS = {
    { key = "PENDING", title = "Pending Approval", color = "|cffffcc33" },
    { key = "APPROVED", title = "Approved — Ready for Bank Withdrawal", color = "|cff26a6f2" },
    { key = "PREPARED", title = "Prepared — Withdrawn & Awaiting Delivery", color = "|cff44dd77" },
    { key = "UNPAID", title = "Unpaid & Awaiting Payment", color = "|cffff5555" },
    { key = "HISTORY", title = "History — Fulfilled, Rejected & Written Off", color = "|cff999999" },
}

function UI:BuildRequestsPanel(panel)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local reqGoldBtn = CreateModernButton(topBar, 114, 24, "+ Request Gold", THEME.gold)
    reqGoldBtn:SetPoint("LEFT", 0, 0)
    reqGoldBtn:SetScript("OnClick", function()
        UI:OpenGoldRequestModal()
    end)
    panel.reqGoldBtn = reqGoldBtn

    local helpBtn = CreateModernButton(topBar, 60, 24, "? Help", THEME.accent)
    helpBtn:SetPoint("LEFT", reqGoldBtn, "RIGHT", 6, 0)
    helpBtn:SetScript("OnClick", function()
        UI:ToggleRequestsHelpModal()
    end)
    helpBtn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Open quick reference for request statuses and officer buttons")
        GameTooltip:Show()
    end)
    helpBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    panel.helpBtn = helpBtn

    local toggleAllBtn = CreateModernButton(topBar, 84, 24, "Expand All")
    toggleAllBtn:SetPoint("RIGHT", 0, 0)
    toggleAllBtn:SetScript("OnClick", function()
        local keys = (panel.visibleSections and #panel.visibleSections > 0) and panel.visibleSections or { "PENDING", "APPROVED", "PREPARED", "UNPAID", "HISTORY" }
        local anyCollapsed = false
        for _, k in ipairs(keys) do
            if not STATE.requestSectionExpanded[k] then
                anyCollapsed = true
                break
            end
        end
        for _, k in ipairs(keys) do
            STATE.requestSectionExpanded[k] = anyCollapsed
        end
        UI:RefreshRequests()
    end)
    panel.toggleAllBtn = toggleAllBtn

    local withdrawAllBtn = CreateModernButton(topBar, 110, 24, "Withdraw All", THEME.accent)
    withdrawAllBtn:SetPoint("RIGHT", toggleAllBtn, "LEFT", -6, 0)
    withdrawAllBtn:SetScript("OnClick", function(selfBtn)
        if selfBtn:IsEnabled() and VM.Delivery then VM.Delivery:WithdrawAllApproved() end
    end)
    withdrawAllBtn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Withdraw every approved request from the open Guild Bank, one after another (each one is verified).", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    withdrawAllBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    withdrawAllBtn:Hide()
    panel.withdrawAllBtn = withdrawAllBtn

    local summaryText = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("RIGHT", withdrawAllBtn, "LEFT", -10, 0)
    summaryText:SetPoint("LEFT", helpBtn, "RIGHT", 8, 0)
    summaryText:SetJustifyH("RIGHT")
    panel.summaryText = summaryText

    panel.scroll = CreateScrollArea(panel, -42, 8)
end

local function IsSameOfficerName(nameA, nameB)
    local a = VM:NormalizeName(nameA)
    local b = VM:NormalizeName(nameB)
    if a == "" or b == "" then return false end
    local la, lb = a:lower(), b:lower()
    if la == lb then return true end
    if not la:find("%s") and lb:sub(1, #la + 1) == (la .. " ") then return true end
    if not lb:find("%s") and la:sub(1, #lb + 1) == (lb .. " ") then return true end
    return false
end

local function CreateRequestRow(content)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(732, 44)
    row:EnableMouse(true)
    ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("TOPLEFT", 10, -6)
    row.info:SetWidth(472)
    row.info:SetJustifyH("LEFT")

    row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.meta:SetPoint("TOPLEFT", 10, -24)
    row.meta:SetWidth(472)
    row.meta:SetJustifyH("LEFT")

    -- Up to 5 right-aligned workflow buttons, laid out per request state in RefreshRequests
    row.btns = {}
    for i = 1, 5 do
        row.btns[i] = CreateModernButton(row, 58, 22, "", THEME.accent)
        row.btns[i]:Hide()
    end
    row.btn1, row.btn2, row.btn3 = row.btns[1], row.btns[2], row.btns[3]

    local function AttachBtnTooltip(btn)
        btn:HookScript("OnEnter", function(selfBtn)
            if selfBtn.tooltipText and selfBtn.tooltipText ~= "" then
                GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                GameTooltip:SetText(selfBtn.tooltipText, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    for i = 1, 5 do AttachBtnTooltip(row.btns[i]) end

    row:SetScript("OnEnter", function(selfRow)
        selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        local r = selfRow.reqData
        if r and not r.isGoldRequest and r.itemLink and r.itemLink ~= "GOLD" then
            ShowItemTooltip(selfRow, r.itemLink, r.itemID, r.itemName)
        end
    end)
    row:SetScript("OnLeave", function(selfRow)
        local bg = selfRow.baseBg or THEME.rowOdd
        selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        HideItemTooltip()
    end)

    local function ExecuteAction(actionKey, req)
        if not req or not actionKey then return end
        -- Buttons shift between states (Prepare -> Complete); block accidental double clicks
        local nowGT = GetTime()
        if row.actionLockUntil and nowGT < row.actionLockUntil then return end
        row.actionLockUntil = nowGT + 1.0
        if actionKey == "APPROVE" then
            VM.Fulfillment:ApproveRequest(req.id)
        elseif actionKey == "REJECT" or actionKey == "CANCEL" then
            VM.Fulfillment:RejectRequest(req.id)
        elseif actionKey == "CANCEL_OWN" then
            VM.Fulfillment:CancelOwnRequest(req.id)
        elseif actionKey == "PREPARE" or actionKey == "WITHDRAW" then
            VM.Fulfillment:PrepareRequest(req.id)
        elseif actionKey == "FULFILL" then
            VM.Fulfillment:FulfillPrepared(req.id)
        elseif actionKey == "RETURN" then
            VM.Fulfillment:ReturnPreparedRequest(req.id)
        elseif actionKey == "DEBT_PAID" then
            VM.Fulfillment:MarkDebtPaid(req.id)
        elseif actionKey == "DEBT_WRITEOFF" then
            local owed = VM.Fulfillment:GetOwedAmount(req)
            local desc = string.format("%s owes %s for %dx %s", req.requester or "?", VM:FormatMoneyPlain(owed), req.count or 1, req.itemName or "Item")
            local dlg = StaticPopup_Show and StaticPopup_Show("VAULTMANAGER_WRITEOFF_DEBT", desc, req.requester or "?")
            if dlg then dlg.data = { reqID = req.id } end
        elseif actionKey == "APPROVE_WITHDRAW" then
            VM.Fulfillment:ApproveAndWithdraw(req.id)
        elseif actionKey == "COD_RETURNED" then
            VM.Fulfillment:MarkCodReturned(req.id)
        elseif actionKey == "COMPLETE" then
            local due = req.isGoldRequest and 0 or VM.Fulfillment:GetExpectedMemberPayment(req)
            if due > 0 and StaticPopup_Show then
                local desc = string.format("%dx %s for %s", req.count or 1, req.itemName or "Item", req.requester or "?")
                local dlg = StaticPopup_Show("VAULTMANAGER_COMPLETE_MANUAL", desc, VM:FormatMoneyPlain(due))
                if dlg then dlg.data = { reqID = req.id } end
            else
                VM.Fulfillment:CompleteManually(req.id, true)
            end
        elseif actionKey == "RELEASE" then
            VM.Fulfillment:ReleasePreparedRequest(req.id)
        elseif actionKey == "WRITEOFF" then
            local desc
            if req.isGoldRequest then
                desc = string.format("Gold Request: %s (for %s)",
                    VM:FormatMoneyPlain(req.goldAmount or req.quotedTotalPrice or 0), req.requester or "?")
            else
                desc = string.format("%dx %s (for %s)",
                    req.count or 1, req.itemName or "Item", req.requester or "?")
            end
            local departed = VM:NormalizeName(req.preparedBy or "?")
            local dlg = StaticPopup_Show and StaticPopup_Show("VAULTMANAGER_WRITEOFF", desc, departed)
            if dlg then
                dlg.data = { reqID = req.id }
            else
                VM.Fulfillment:WriteOffRequest(req.id)
            end
        end
    end

    for i = 1, 5 do
        row.btns[i]:SetScript("OnClick", function(selfBtn)
            if selfBtn:IsEnabled() then ExecuteAction(selfBtn.actionKey, row.reqData) end
        end)
    end

    return row
end

local METHOD_LABELS = {
    BANK = " (Bank)",
    MAIL = " (Mail)",
    TRADE = " (Trade)",
    WRITEOFF = " (Write-Off)",
}

function UI:RefreshRequests()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[2] then return end
    local panel = mainFrame.panels[2]
    if not panel or not panel.scroll then return end
    local content = panel.scroll.content
    if not content then return end

    if VM.UpdateRosterCache then VM:UpdateRosterCache() end
    self:UpdateRequestsTabBadge()

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    panel.scroll.secHeaders = panel.scroll.secHeaders or {}
    for _, h in pairs(panel.scroll.secHeaders) do h:Hide() end

    local buckets = {
        PENDING = {},
        APPROVED = {},
        PREPARED = {},
        UNPAID = {},
        HISTORY = {},
    }

    for _, req in pairs(VM.db.requests or {}) do
        if req.status == "PENDING" then
            table.insert(buckets.PENDING, req)
        elseif req.status == "APPROVED" then
            table.insert(buckets.APPROVED, req)
        elseif req.status == "PREPARED" then
            table.insert(buckets.PREPARED, req)
        elseif VM.Fulfillment:GetOwedAmount(req) > 0 then
            table.insert(buckets.UNPAID, req)
        else
            table.insert(buckets.HISTORY, req)
        end
    end

    local function SortNewest(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end
    table.sort(buckets.PENDING, SortNewest)
    table.sort(buckets.APPROVED, SortNewest)
    table.sort(buckets.PREPARED, function(a, b)
        return (a.preparedAt or a.createdAt or 0) > (b.preparedAt or b.createdAt or 0)
    end)
    table.sort(buckets.UNPAID, function(a, b)
        return (a.completedAt or 0) > (b.completedAt or 0)
    end)
    table.sort(buckets.HISTORY, function(a, b)
        return (a.completedAt or a.updatedAt or a.createdAt or 0) > (b.completedAt or b.updatedAt or b.createdAt or 0)
    end)

    if panel.summaryText then
        local unpaidTxt = (#buckets.UNPAID > 0) and string.format("  |  |cffff5555Unpaid: %d|r", #buckets.UNPAID) or ""
        panel.summaryText:SetText(string.format("|cffffcc33Pending: %d|r  |  |cff26a6f2Approved: %d|r  |  |cff44dd77Prepared: %d|r%s  |  |cff888888History: %d|r",
            #buckets.PENDING, #buckets.APPROVED, #buckets.PREPARED, unpaidTxt, #buckets.HISTORY))
    end

    panel.visibleSections = {}
    for _, sec in ipairs(REQ_SECTIONS) do
        if #buckets[sec.key] > 0 then
            table.insert(panel.visibleSections, sec.key)
        end
    end

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, k in ipairs(panel.visibleSections) do
            if not STATE.requestSectionExpanded[k] then
                anyCollapsed = true
                break
            end
        end
        panel.toggleAllBtn:SetText(anyCollapsed and "Expand All" or "Collapse All")
    end

    local statusColors = {
        PENDING = "|cffffcc33PENDING|r",
        APPROVED = "|cff26a6f2APPROVED|r",
        PREPARED = "|cff44dd77PREPARED|r",
        FULFILLED = "|cff44dd77FULFILLED|r",
        REJECTED = "|cffff5555REJECTED|r",
        WRITTEN_OFF = "|cffff5555WRITTEN OFF|r",
    }

    local isOff = VM:IsOfficer()
    local me = VM:GetPlayerName()
    local y = 0
    local rowIdx = 0

    if panel.withdrawAllBtn then
        local n = (isOff and VM.Delivery) and #VM.Delivery:GetWithdrawableApproved() or 0
        if isOff then
            panel.withdrawAllBtn:SetText(string.format("Withdraw All (%d)", n))
            ApplyButtonState(panel.withdrawAllBtn, (n > 0 and not (VM.Delivery and VM.Delivery.batch)) and "active" or "disabled")
            panel.withdrawAllBtn:Show()
        else
            panel.withdrawAllBtn:Hide()
        end
    end

    for _, sec in ipairs(REQ_SECTIONS) do
        local list = buckets[sec.key]
        if #list > 0 then
            local isExpanded = STATE.requestSectionExpanded[sec.key] == true
            local hdr = panel.scroll.secHeaders[sec.key]
            if not hdr then
                hdr = CreateFrame("Button", nil, content, "BackdropTemplate")
                hdr:SetSize(732, 24)
                ApplyModernBackdrop(hdr, THEME.headerBg, THEME.border)
                hdr.text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                hdr.text:SetPoint("LEFT", 8, 0)
                hdr.secKey = sec.key
                hdr:SetScript("OnClick", function(selfHdr)
                    STATE.requestSectionExpanded[selfHdr.secKey] = not STATE.requestSectionExpanded[selfHdr.secKey]
                    UI:RefreshRequests()
                end)
                panel.scroll.secHeaders[sec.key] = hdr
            end

            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", 4, -y)
            hdr.text:SetText(string.format("%s  %s%s (%d)|r", isExpanded and "[-]" or "[+]", sec.color, sec.title, #list))
            hdr:Show()
            y = y + 26

            if isExpanded then
                for idx, req in ipairs(list) do
                    rowIdx = rowIdx + 1
                    local row = panel.scroll.rows[rowIdx]
                    if not row then
                        row = CreateRequestRow(content)
                        panel.scroll.rows[rowIdx] = row
                    end

                    local baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
                    row.baseBg = baseBg
                    row.reqData = req
                    row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 4, -y)
                    row:Show()

                    local prepLeftGuild = (req.status == "PREPARED" and req.preparedBy and req.preparedBy ~= "" and VM:IsLegacyMember(req.preparedBy))
                    local statusLabel = statusColors[req.status] or req.status
                    if req.status == "REJECTED" and req.completedMethod == "CANCELLED" then
                        statusLabel = "|cffff8844CANCELLED|r"
                    end
                    local owed = VM.Fulfillment:GetOwedAmount(req)
                    local tabTag = ""
                    if not req.isGoldRequest and req.tab and tonumber(req.tab) and tonumber(req.tab) > 0 then
                        local tData = VM.db.inventory and VM.db.inventory.tabs and VM.db.inventory.tabs[tonumber(req.tab)]
                        local tName = tData and tData.name
                        tabTag = (tName and tName ~= "" and tName ~= ("Tab " .. req.tab))
                            and string.format("  |cff8899aa[Tab %d: %s]|r", req.tab, tName)
                            or string.format("  |cff8899aa[Tab %d]|r", req.tab)
                    end

                    -- Line 1: Main info
                    if req.isGoldRequest then
                        local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                        local catLbl = (VM.Ledger and VM.Ledger.GetGuildCategoryLabel and VM.Ledger:GetGuildCategoryLabel(req.guildCategory)) or "Raid"
                        local catTag = string.format(" |cff26a6f2[%s]|r", catLbl)
                        local reasonTxt = (req.reason and req.reason ~= "") and (" — " .. req.reason) or ""
                        local leftTag = prepLeftGuild and " |cffff4444[OFFICER LEFT]|r" or ""
                        row.info:SetText(string.format("[%s]  %s  —  |cffffd700Gold Request:|r%s %s|cffcccccc%s|r%s",
                            statusLabel,
                            VM:ColorizeName(req.requester),
                            catTag,
                            VM:FormatMoney(gAmt),
                            reasonTxt,
                            leftTag))
                    else
                        local liveUnit = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
                        local reqRule = { mode = req.priceMode or "FREE", percent = req.pricePercent or 50 }
                        local liveTotal = VM:CalculateMemberTotalPrice(liveUnit, req.count or 1, reqRule)
                        local reqTotal = (req.quotedTotalPrice ~= nil) and req.quotedTotalPrice or ((req.quotedUnitPrice or 0) * (req.count or 1))

                        local priceNote = ""
                        if reqTotal > 0 and liveTotal > 0 and liveTotal ~= reqTotal then
                            priceNote = string.format("  |cffaaaaaa(Req: %s | Live: %s)|r", VM:FormatMoney(reqTotal), VM:FormatMoney(liveTotal))
                        elseif liveTotal > 0 then
                            priceNote = string.format("  |cffaaaaaa(%s)|r", VM:FormatMoney(liveTotal))
                        elseif reqTotal > 0 then
                            priceNote = string.format("  |cffaaaaaa(%s)|r", VM:FormatMoney(reqTotal))
                        end

                        local leftTag = prepLeftGuild and " |cffff4444[OFFICER LEFT]|r" or ""
                        row.info:SetText(string.format("[%s]  %s  —  %dx %s%s%s%s",
                            statusLabel,
                            VM:ColorizeName(req.requester),
                            req.count or 1,
                            req.itemLink or req.itemName or "Item",
                            priceNote,
                            tabTag,
                            leftTag))
                    end

                    -- Line 2: Timestamps & Officer metadata
                    local metaParts = {}
                    if req.createdAt and req.createdAt > 0 then
                        table.insert(metaParts, "Requested: " .. date("%d/%m %H:%M", req.createdAt))
                    end
                    if req.status == "REJECTED" and req.completedMethod == "CANCELLED" then
                        local cTime = (req.completedAt and req.completedAt > 0) and (" " .. date("%d/%m %H:%M", req.completedAt)) or ""
                        table.insert(metaParts, "Cancelled" .. cTime .. " by requester")
                    elseif req.status == "REJECTED" then
                        if req.approvedBy and req.approvedBy ~= "" then
                            local rejTime = (req.completedAt and req.completedAt > 0) and (" " .. date("%d/%m %H:%M", req.completedAt)) or ""
                            local label = (req.approvedAt and req.approvedAt > 0) and "Cancelled" or "Rejected"
                            table.insert(metaParts, string.format("%s%s by: %s", label, rejTime, VM:ColorizeName(req.approvedBy)))
                        end
                    elseif req.approvedBy and req.approvedBy ~= "" then
                        table.insert(metaParts, "Approved by: " .. VM:ColorizeName(req.approvedBy))
                    end
                    if req.preparedBy and req.preparedBy ~= "" and (req.status == "PREPARED" or req.status == "WRITTEN_OFF") then
                        local prepTime = (req.preparedAt and req.preparedAt > 0) and (" " .. date("%d/%m %H:%M", req.preparedAt)) or ""
                        table.insert(metaParts, string.format("Withdrawn by: %s%s", VM:ColorizeName(req.preparedBy, prepLeftGuild and "ff6666" or nil), prepTime))
                    end
                    if req.status == "FULFILLED" then
                        local hasCompTime = (req.completedAt and req.completedAt > 0)
                        local hasCompBy = (req.fulfilledBy and req.fulfilledBy ~= "")
                        if hasCompTime or hasCompBy then
                            local methodTag = METHOD_LABELS[req.completedMethod or ""] or ""
                            local compStr = "Completed:"
                            if hasCompTime then
                                compStr = compStr .. " " .. date("%d/%m %H:%M", req.completedAt)
                            end
                            if hasCompBy then
                                compStr = compStr .. " by " .. VM:ColorizeName(req.fulfilledBy)
                            end
                            table.insert(metaParts, compStr .. methodTag)
                        end
                    elseif req.status == "WRITTEN_OFF" then
                        local woTime = (req.completedAt and req.completedAt > 0) and (" " .. date("%d/%m %H:%M", req.completedAt)) or ""
                        local woBy = (req.fulfilledBy and req.fulfilledBy ~= "") and (" by " .. VM:ColorizeName(req.fulfilledBy)) or ""
                        table.insert(metaParts, "Written off" .. woTime .. woBy)
                    end
                    local metaStr = "|cff999999" .. table.concat(metaParts, "  |  ") .. "|r"
                    if owed > 0 then
                        if req.completedMethod == "MAIL" then
                            metaStr = metaStr .. string.format("  |cffffaa00Awaiting CoD payment %s|r", VM:FormatMoney(owed))
                        else
                            metaStr = metaStr .. string.format("  |cffff5555Owes %s|r", VM:FormatMoney(owed))
                        end
                    end
                    if req.deliveryPref == "MAIL" or req.deliveryPref == "TRADE" then
                        metaStr = metaStr .. string.format("  |cff8899aa[%s]|r", req.deliveryPref == "MAIL" and "Mail" or "Trade")
                    end
                    row.meta:SetText(metaStr)

                    -- Workflow buttons: only the next step is active; finished steps turn green and dim
                    for _, b in ipairs(row.btns) do
                        b:Hide()
                        b.actionKey = nil
                        b.tooltipText = nil
                    end

                    local specs = {}
                    local function AddBtn(label, key, state, accent, tip, width)
                        table.insert(specs, { label = label, key = key, state = state, accent = accent, tip = tip, width = width })
                    end
                    local isOwnReq = VM:IsSameCharacter(req.requester, me)
                    local deliverHint = req.isGoldRequest and "gold" or "items"

                    if req.status == "PENDING" then
                        if isOff then
                            AddBtn("Approve", "APPROVE", "active", THEME.green, "Approve request, lock the price and reserve stock in the Vault.")
                            AddBtn("Approve + Withdraw", "APPROVE_WITHDRAW", "active", THEME.accent, "Approve and immediately withdraw it from the open Guild Bank.", 116)
                            AddBtn("Reject", "REJECT", "active", THEME.red, "Decline this pending request.")
                        elseif isOwnReq then
                            AddBtn("Cancel", "CANCEL_OWN", "active", THEME.red, "Cancel your request.")
                        end
                    elseif req.status == "APPROVED" then
                        if isOff then
                            local claim = VM.Fulfillment:GetActiveClaim(req)
                            if claim and not IsSameOfficerName(claim, me) then
                                AddBtn("Withdraw", "WITHDRAW", "disabled", THEME.accent, string.format("%s is withdrawing this request right now.", claim))
                            elseif claim then
                                AddBtn("Withdrawing", "WITHDRAW", "disabled", THEME.accent, "Withdrawal in progress...")
                            else
                                AddBtn("Withdraw", "WITHDRAW", "active", THEME.accent,
                                    string.format("Withdraw the %s from the Guild Bank into your bags (switches to the right tab automatically).", deliverHint))
                            end
                            AddBtn("Fulfill", "FULFILL", "disabled", THEME.accent, "Withdraw first.")
                            AddBtn("Complete", "COMPLETE", "disabled", THEME.green, "Completes automatically when the mail is sent or the trade finishes.")
                            AddBtn("Cancel", "CANCEL", "active", THEME.red, "Cancel this approved request and release reserved stock.")
                        elseif isOwnReq then
                            AddBtn("Cancel", "CANCEL_OWN", "active", THEME.red, "Cancel your request.")
                        end
                    elseif req.status == "PREPARED" and isOff then
                        if prepLeftGuild then
                            AddBtn("Write Off", "WRITEOFF", "active", THEME.red, "Officer left the guild. Write off and charge 100% value to the departed officer.")
                            AddBtn("Release", "RELEASE", "active", THEME.border, "Return this order to APPROVED (if the items were put back in the bank).")
                        elseif IsSameOfficerName(req.preparedBy, me) then
                            local started = VM.Fulfillment.fulfillStarted[req.id]
                            AddBtn("Withdraw", "WITHDRAW", "done", THEME.green, "Withdrawn from the Guild Bank.")
                            AddBtn("Fulfill", "FULFILL", started and "done" or "active", THEME.accent,
                                "Fill the open Mail or Trade window with ALL your prepared orders for this member (you click Send / Trade yourself).")
                            AddBtn("Complete", "COMPLETE", "active", THEME.green,
                                started and "Completes automatically when sent/traded. Click only if you delivered another way (you will be asked whether it was paid)."
                                or "Completes automatically when the mail is sent or the trade finishes. Click to mark it delivered by hand (you will be asked whether it was paid).")
                            AddBtn("Return", "RETURN", "active", THEME.gold, "Put the items/gold back in the Guild Bank and set the request back to APPROVED.")
                            AddBtn("Cancel", "CANCEL", "active", THEME.red, "Cancel the request. Items you keep are charged to you — use Return to put them back.")
                        else
                            local tip = "Prepared by " .. tostring(req.preparedBy or "?")
                            AddBtn("Withdraw", "WITHDRAW", "done", THEME.green, tip)
                            AddBtn("Fulfill", "FULFILL", "disabled", THEME.accent, tip)
                            AddBtn("Complete", "COMPLETE", "disabled", THEME.green, tip)
                        end
                    elseif req.status == "FULFILLED" and owed > 0 and isOff then
                        if req.completedMethod == "MAIL" then
                            AddBtn("Paid", "DEBT_PAID", "active", THEME.green, "The CoD money arrived (recorded automatically when it shows up in your mailbox).")
                            AddBtn("Returned", "COD_RETURNED", "active", THEME.gold, "The CoD mail came back unpaid: the request goes back to PREPARED with you and the charge is reversed.")
                        else
                            AddBtn("Paid", "DEBT_PAID", "active", THEME.green, "The member paid the outstanding amount to you (recorded as their payment).")
                            AddBtn("Write Off", "DEBT_WRITEOFF", "active", THEME.red, "Write off the unpaid amount: charged to GUILD (Member), shown as unpaid on the member in the Ledger.")
                        end
                    end

                    local x = 728
                    for i = #specs, 1, -1 do
                        local spec = specs[i]
                        local b = row.btns[i]
                        local w = spec.width or 58
                        b:SetSize(w, 22)
                        b:ClearAllPoints()
                        b:SetPoint("RIGHT", row, "LEFT", x, 0)
                        SetButtonAccent(b, spec.accent)
                        b:SetText(spec.label)
                        b.actionKey = spec.key
                        b.tooltipText = spec.tip
                        ApplyButtonState(b, spec.state)
                        b:Show()
                        x = x - (w + 4)
                    end
                    local textWidth = (#specs > 0) and (x - 14) or 710

                    row.info:SetWidth(textWidth)
                    row.meta:SetWidth(textWidth)

                    y = y + 46
                end
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

-- === END OF PART 1 (PASTE PART 2 DIRECTLY BELOW THIS LINE) ===
--------------------------------------------------------------------------------
-- TAB 3: LEDGER
--------------------------------------------------------------------------------
function UI:BuildLedgerPanel(panel)
    local uiPrefs = GetUIPrefs()

    -- Row 1: Search, Export & Officer Quick Tools
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -6)
    topBar:SetPoint("TOPRIGHT", -10, -6)

    local searchBox = CreateModernEditBox(topBar, 165, 22, false)
    searchBox:SetPoint("LEFT", 0, 0)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 6, 0)
    searchBox.placeholder:SetText("Filter member, item or tag...")

    local debouncedLedgerSearch = CreateDebouncer(0.15, function()
        if mainFrame and mainFrame:IsShown() and STATE.currentTab == 3 then
            UI:RefreshLedger()
        end
    end)

    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        STATE.ledgerSearchQuery = txt:lower()
        debouncedLedgerSearch()
    end)
    panel.searchBox = searchBox

    local exportBtn = CreateModernButton(topBar, 58, 22, "Export", THEME.accent)
    exportBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    exportBtn:SetScript("OnClick", function()
        UI:OpenExportModal()
    end)
    panel.exportBtn = exportBtn

    -- Officer tools container (shown/hidden dynamically in RefreshLedger)
    local officerBar = CreateFrame("Frame", nil, topBar)
    officerBar:SetSize(344, 24)
    officerBar:SetPoint("RIGHT", 0, 0)

    local expenseBtn = CreateModernButton(officerBar, 76, 22, "+ Expense", THEME.gold)
    expenseBtn:SetPoint("LEFT", 0, 0)
    expenseBtn:SetScript("OnClick", function()
        UI:OpenGuildExpenseModal()
    end)
    expenseBtn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Log a guild expense or write-off under GUILD (Raid / Member / Tabs)")
        GameTooltip:Show()
    end)
    expenseBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local memberBtn = CreateModernDropdown(officerBar, 126, 22, "Donor...")
    memberBtn:SetPoint("LEFT", expenseBtn, "RIGHT", 6, 0)
    memberBtn:SetScript("OnClick", function(btn)
        UI:OpenRosterPicker(btn, false, function(chosen, guildCat)
            STATE.manualLedgerDonor = chosen
            STATE.manualLedgerGuildCat = guildCat
            if chosen == "GUILD" then
                local catLbl = (VM.Ledger and VM.Ledger:GetGuildCategoryLabel(guildCat)) or "Member"
                btn:SetText("|cff26a6f2[Guild-" .. catLbl .. "]|r")
            else
                btn:SetText(chosen)
            end
        end, true)
    end)
    panel.donorBtn = memberBtn

    local goldBox = CreateModernEditBox(officerBar, 48, 22, true)
    goldBox:SetPoint("LEFT", memberBtn, "RIGHT", 4, 0)
    goldBox.placeholder = goldBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    goldBox.placeholder:SetPoint("LEFT", 6, 0)
    goldBox.placeholder:SetText("Gold")
    goldBox:SetScript("OnTextChanged", function(eb)
        if eb:GetText() == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
    end)
    panel.goldBox = goldBox

    local addGoldBtn = CreateModernButton(officerBar, 80, 22, "+ Log Gold", THEME.green)
    addGoldBtn:SetPoint("LEFT", goldBox, "RIGHT", 4, 0)
    addGoldBtn:SetScript("OnClick", function()
        if not VM:IsOfficer() then return end
        local g = tonumber(goldBox:GetText()) or 0
        if STATE.manualLedgerDonor ~= "" and g > 0 then
            VM.Ledger:RecordGoldDeposit(STATE.manualLedgerDonor, g * 10000, "MANUAL_GOLD", nil, nil, nil, nil, STATE.manualLedgerGuildCat)
            VM:Print(string.format("Logged %dg donated by |cffffff00%s|r.", g, STATE.manualLedgerDonor))
            goldBox:SetText("")
            STATE.manualLedgerDonor = ""
            STATE.manualLedgerGuildCat = nil
            memberBtn:SetText("Donor...")
            UI:RefreshLedger()
        end
    end)
    panel.officerBar = officerBar

    -- Row 2: Recessed Filter Strip
    local filterStrip = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterStrip:SetHeight(28)
    filterStrip:SetPoint("TOPLEFT", 10, -38)
    filterStrip:SetPoint("TOPRIGHT", -10, -38)
    ApplyModernBackdrop(filterStrip, { 0.05, 0.06, 0.08, 0.9 }, THEME.border)


    local ffaToggle = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    ffaToggle:SetSize(20, 20)
    ffaToggle:SetPoint("LEFT", 145, 0)
    ffaToggle:SetChecked(uiPrefs.includeFFA ~= false)
    ffaToggle.label = filterStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ffaToggle.label:SetPoint("LEFT", ffaToggle, "RIGHT", 4, 0)
    ffaToggle.label:SetText("Include Free-for-All")
    ffaToggle:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.includeFFA = cb:GetChecked() and true or false
        UI:RefreshLedger()
    end)
    panel.ffaToggle = ffaToggle

    local hideLegacyCb = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    hideLegacyCb:SetSize(20, 20)
    hideLegacyCb:SetPoint("LEFT", 295, 0)
    hideLegacyCb:SetChecked(uiPrefs.hideLegacyLedger or false)
    hideLegacyCb.label = filterStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideLegacyCb.label:SetPoint("LEFT", hideLegacyCb, "RIGHT", 4, 0)
    hideLegacyCb.label:SetText("Hide Legacy")
    hideLegacyCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.hideLegacyLedger = cb:GetChecked() and true or false
        UI:RefreshLedger()
    end)
    panel.hideLegacyCb = hideLegacyCb

    local toggleAllBtn = CreateModernButton(filterStrip, 84, 22, "Expand All")
    toggleAllBtn:SetPoint("RIGHT", -6, 0)
    panel.helpBtn = AddTabHelpButton(filterStrip, "LEDGER", toggleAllBtn, "RIGHT", "LEFT", -6, 0)
    toggleAllBtn:SetScript("OnClick", function()
        local anyCollapsed = false
        for _, mainKey in ipairs(panel.visibleMainKeys or {}) do
            if not STATE.expandedMains[mainKey] then
                anyCollapsed = true
                break
            end
        end
        for _, mainKey in ipairs(panel.visibleMainKeys or {}) do
            STATE.expandedMains[mainKey] = anyCollapsed
        end
        UI:RefreshLedger()
    end)
    panel.toggleAllBtn = toggleAllBtn

    panel.scroll = CreateScrollArea(panel, -70, 8)
end

local function CreateLedgerRow(content)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(732, 28)
    row:EnableMouse(true)
    ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

    row.expandBtn = CreateModernButton(row, 20, 20, "+")
    row.expandBtn:SetPoint("LEFT", 6, 0)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 32, 0)
    row.nameText:SetWidth(295)
    row.nameText:SetJustifyH("LEFT")

    row.donatedText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.donatedText:SetPoint("LEFT", 332, 0)
    row.donatedText:SetWidth(195)
    row.donatedText:SetJustifyH("LEFT")

    row.receivedText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.receivedText:SetPoint("LEFT", 532, 0)
    row.receivedText:SetWidth(192)
    row.receivedText:SetJustifyH("LEFT")

    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("LEFT", 36, 0)
    row.subText:SetWidth(545)
    row.subText:SetJustifyH("LEFT")

    row.actionBtn = CreateModernButton(row, 108, 20, "Reassign", THEME.accent)
    row.actionBtn:SetPoint("RIGHT", -8, 0)

    row.deleteBtn = CreateModernButton(row, 20, 20, "X", THEME.red)
    row.deleteBtn:SetPoint("RIGHT", -8, 0)
    row.deleteBtn:Hide()

    row.pairBtn = CreateModernButton(row, 52, 20, "Pair", THEME.gold)
    row.pairBtn:SetPoint("RIGHT", -32, 0)
    row.pairBtn:Hide()
    row.pairBtn:HookScript("OnEnter", function(selfBtn)
        if selfBtn.tooltipText then
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText(selfBtn.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row.pairBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnEnter", function(selfRow)
        selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        local tx = selfRow.txData
        if tx and selfRow.showItemTooltip then
            ShowItemTooltip(selfRow, tx.itemLink, tx.itemID, tx.itemName, tx)
        end
    end)
    row:SetScript("OnLeave", function(selfRow)
        local bg = selfRow.baseBg or THEME.rowOdd
        selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        if selfRow.showItemTooltip then
            HideItemTooltip()
        end
    end)

    row.expandBtn:SetScript("OnClick", function()
        if row.groupMainKey then
            STATE.expandedMains[row.groupMainKey] = not STATE.expandedMains[row.groupMainKey]
            UI:RefreshLedger()
        end
    end)

    row.actionBtn:SetScript("OnClick", function(selfBtn)
        local tx = row.txData
        if not tx or tx.isDerived then return end
        if row.actionMode == "ASSIGN_UNATTRIBUTED" then
            UI:OpenRosterPicker(selfBtn, false, function(chosenName, guildCat)
                VM.Ledger:AssignUnattributed(tx.id, chosenName, guildCat)
            end, true)
        elseif row.actionMode == "REASSIGN" then
            UI:OpenRosterPicker(selfBtn, false, function(chosenName, guildCat)
                VM.Ledger:ReassignTransaction(tx.id, chosenName, guildCat)
            end, true)
        end
    end)

    row.deleteBtn:SetScript("OnClick", function()
        local tx = row.txData
        if not tx or tx.isDerived then return end
        local dlg = StaticPopup_Show and StaticPopup_Show("VAULTMANAGER_DELETE_TX", DescribeTxPlain(tx))
        if dlg then
            dlg.data = { txID = tx.id }
        end
    end)

    row.pairBtn:SetScript("OnClick", function()
        local tx = row.txData
        if not tx or tx.isDerived then return end
        if tx.voided then
            VM.Ledger:UnpairTransaction(tx.id)
            return
        end
        local partner = VM.Ledger:FindPairCandidate(tx)
        if not partner then
            VM:Print("No matching withdrawal/return found to pair with (same main, item and count within 30 days).")
            return
        end
        local outTx = (tx.type == "OUT") and tx or partner
        local inTx = (tx.type == "OUT") and partner or tx
        local dlg = StaticPopup_Show and StaticPopup_Show("VAULTMANAGER_PAIR_TX", DescribeTxPlain(outTx), DescribeTxPlain(inTx))
        if dlg then
            dlg.data = { a = outTx.id, b = inTx.id }
        end
    end)

    return row
end

local function LedgerTxMatchesSearch(tx, q)
    if q == "" then return true end
    if (tx.itemName and tx.itemName:lower():find(q, 1, true))
        or (tx.player and tx.player:lower():find(q, 1, true))
        or (tx.rawSender and tx.rawSender:lower():find(q, 1, true))
        or (tx.note and tx.note:lower():find(q, 1, true))
        or (tx.guildCategory and tx.guildCategory:lower():find(q, 1, true))
        or (tx.derivedKind and tx.derivedKind:lower():find(q, 1, true))
        or (tx.source == "WRITE_OFF" and ("write-off writeoff"):find(q, 1, true)) then
        return true
    end
    return false
end

local function LedgerGroupMatchesSearch(grp, q)
    if q == "" then return true end
    if grp.mainName and grp.mainName:lower():find(q, 1, true) then return true end
    if grp.mainName == "GUILD" and ("guild bank guild operations"):find(q, 1, true) then return true end
    for _, tx in ipairs(grp.transactions or {}) do
        if LedgerTxMatchesSearch(tx, q) then
            return true
        end
    end
    return false
end

function UI:RefreshLedger()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[3] then return end
    local panel = mainFrame.panels[3]
    if not panel or not panel.scroll then return end
    local content = panel.scroll.content
    if not content then return end

    if VM.UpdateRosterCache then VM:UpdateRosterCache() end

    local isOff = VM:IsOfficer()
    if panel.officerBar then
        if isOff then panel.officerBar:Show() else panel.officerBar:Hide() end
    end

    local uiPrefs = GetUIPrefs()
    if panel.ffaToggle then panel.ffaToggle:SetChecked(uiPrefs.includeFFA ~= false) end
    if panel.hideLegacyCb then panel.hideLegacyCb:SetChecked(uiPrefs.hideLegacyLedger or false) end

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    if panel.scroll.legacyHeader then panel.scroll.legacyHeader:Hide() end

    local useHist = nil -- values are always at the current AH price
    local hideLegacy = uiPrefs.hideLegacyLedger or false
    local q = STATE.ledgerSearchQuery or ""
    local allGroups = VM.Ledger:GetAggregatedByMain(useHist)

    local primaryGroups = {}
    local legacyGroups = {}
    panel.visibleMainKeys = {}

    for _, grp in ipairs(allGroups) do
        if LedgerGroupMatchesSearch(grp, q) then
            if grp.isLegacy then
                if not hideLegacy then
                    table.insert(legacyGroups, grp)
                end
            else
                table.insert(primaryGroups, grp)
                table.insert(panel.visibleMainKeys, grp.mainName)
            end
        end
    end

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, k in ipairs(panel.visibleMainKeys) do
            if not STATE.expandedMains[k] then anyCollapsed = true; break end
        end
        panel.toggleAllBtn:SetText(anyCollapsed and "Expand All" or "Collapse All")
    end

    local rowIdx = 0
    local y = 0

    local function AcquireRow()
        rowIdx = rowIdx + 1
        local row = panel.scroll.rows[rowIdx]
        if not row then
            row = CreateLedgerRow(content)
            panel.scroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    local unpaidByMain = VM.Ledger.GetUnpaidByMain and VM.Ledger:GetUnpaidByMain() or {}

    local function RenderGroup(grp)
        local isExpanded = (q ~= "") or (STATE.expandedMains[grp.mainName] == true)
        local header = AcquireRow()
        local isSpecial = (grp.mainName == "UNATTRIBUTED" or grp.mainName == "GUILD")
        local baseBg = grp.isLegacy and THEME.rowLegacy or (isSpecial and THEME.rowSpecial or THEME.rowEven)

        header.baseBg = baseBg
        header.groupMainKey = grp.mainName
        header.txData = nil
        header.showItemTooltip = false
        header.actionMode = nil

        header:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        header:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.85)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 4, -y)

        header.expandBtn:Show()
        header.expandBtn:SetText(isExpanded and "-" or "+")
        header.subText:Hide()
        header.actionBtn:Hide()
        header.deleteBtn:Hide()
        header.pairBtn:Hide()
        header.nameText:Show()
        header.donatedText:Show()
        header.receivedText:Show()

        local entryCountStr = string.format("|cff888888(%d)|r", #grp.transactions)
        local goldSubNote = (grp.totalGoldIn and grp.totalGoldIn > 0 and grp.totalGoldIn < grp.totalInValue)
            and string.format(" |cff999999(%s g)|r", VM:FormatMoneyShort(grp.totalGoldIn))
            or ""

        if grp.mainName == "UNATTRIBUTED" then
            header.nameText:SetText("|cffff5555UNATTRIBUTED DEPOSITS|r  " .. entryCountStr)
            header.donatedText:SetText("Donated: " .. VM:FormatMoney(grp.totalInValue))
            header.receivedText:SetText("")
        elseif grp.mainName == "GUILD" then
            header.nameText:SetText("|cff26a6f2GUILD BANK / OPERATIONS|r  " .. entryCountStr)
            header.donatedText:SetText("In: " .. VM:FormatMoney(grp.totalInValue))
            header.receivedText:SetText("Out: " .. VM:FormatMoney(grp.totalOutValue))
        elseif grp.isLegacy then
            header.nameText:SetText(string.format("%s |cff808080[Legacy]|r %s", VM:ColorizeName(grp.mainName, "808080"), entryCountStr))
            header.donatedText:SetText("|cff808080Donated: " .. VM:FormatMoney(grp.totalInValue) .. "|r")
            header.receivedText:SetText("|cff808080Received: " .. VM:FormatMoney(grp.totalOutValue) .. "|r")
        else
            local unpaid = unpaidByMain[grp.mainName]
            local unpaidTag = ""
            if unpaid and (unpaid.outstanding + unpaid.writtenOff) > 0 then
                unpaidTag = string.format("  |cffff5555Unpaid: %s|r", VM:FormatMoneyShort(unpaid.outstanding + unpaid.writtenOff))
            end
            header.nameText:SetText(string.format("%s  %s%s", VM:ColorizeName(grp.mainName), entryCountStr, unpaidTag))
            header.donatedText:SetText("Donated: " .. VM:FormatMoney(grp.totalInValue) .. goldSubNote)
            header.receivedText:SetText("Received: " .. VM:FormatMoney(grp.totalOutValue))
        end

        y = y + 30

        if isExpanded then
            local headerMatchesQuery = (q == "")
                or (grp.mainName and grp.mainName:lower():find(q, 1, true))
                or (grp.mainName == "GUILD" and ("guild bank guild operations"):find(q, 1, true))

            for _, tx in ipairs(grp.transactions) do
                if headerMatchesQuery or LedgerTxMatchesSearch(tx, q) then
                    local sub = AcquireRow()
                    local subBg = THEME.rowOdd
                    local isSummary = (tx.type == "SUMMARY" or tx.itemLink == "SUMMARY")
                    local isDerived = (tx.isDerived == true)
                    local isGold = (not isSummary) and (not isDerived) and (tx.itemID == 0 or tx.itemLink == "GOLD")
                    local isItemTx = (not isSummary) and (not isGold)

                    sub.baseBg = subBg
                    sub.groupMainKey = nil
                    sub.txData = tx
                    sub.showItemTooltip = isItemTx
                    sub.actionMode = nil

                    sub:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                    sub:SetBackdropBorderColor(0, 0, 0, 0)
                    sub:ClearAllPoints()
                    sub:SetPoint("TOPLEFT", 4, -y)

                    sub.expandBtn:Hide()
                    sub.nameText:Hide()
                    sub.donatedText:Hide()
                    sub.receivedText:Hide()
                    sub.subText:Show()
                    sub.actionBtn:Hide()
                    sub.deleteBtn:Hide()
                    sub.pairBtn:Hide()

                    local dir
                    if isSummary then
                        dir = "|cff8899aaSUMMARY|r"
                    elseif isDerived then
                        dir = (tx.derivedKind == "SURPLUS") and "|cff44dd77SURPLUS|r" or "|cff26a6f2SUBSIDY|r"
                    elseif tx.source == "WRITE_OFF" then
                        dir = "|cffff4444WRITE-OFF|r"
                    elseif tx.type == "OUT" then
                        dir = isGold and "|cffff6666GOLD OUT|r" or "|cffff6666OUT|r"
                    else
                        dir = isGold and "|cffffd700GOLD IN|r" or "|cff44dd77IN|r"
                    end

                    local val = VM.Ledger:GetTransactionValue(tx, useHist)
                    local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                    local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED" and tx.player ~= "GUILD")
                        and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

                    local catLabel = (grp.mainName == "GUILD" and tx.guildCategory and VM.Ledger.GetGuildCategoryLabel)
                        and VM.Ledger:GetGuildCategoryLabel(tx.guildCategory) or nil
                    local catTag = catLabel and string.format(" |cff26a6f2[%s]|r", catLabel) or ""

                    local rawTag = ""
                    if tx.rawSender and tx.rawSender ~= "" and tx.rawSender ~= tx.player and tx.rawSender ~= "UNATTRIBUTED" then
                        local verb
                        if isDerived then
                            verb = (tx.derivedKind == "SURPLUS") and "from" or "for"
                        else
                            verb = (tx.type == "OUT") and "by" or "from"
                        end
                        rawTag = string.format(" |cffaaaaaa(%s %s)|r", verb, VM:ColorizeName(tx.rawSender))
                    end

                    local noteTag = (tx.note and tx.note ~= "") and (" |cffcccccc— " .. tx.note .. "|r") or ""
                    if tx.voided then
                        noteTag = " |cffffd700[RETURN PAIRED — 0g]|r" .. noteTag
                    elseif tx.source == "TRANSFER" then
                        noteTag = " |cff26a6f2[TRANSFER]|r" .. noteTag
                    elseif tx.source == "PAYMENT" then
                        noteTag = " |cff44dd77[PAYMENT]|r" .. noteTag
                    elseif tx.source == "DEBT_WRITEOFF" then
                        noteTag = (tx.type == "IN") and (" |cffff5555[UNPAID — WRITTEN OFF]|r" .. noteTag)
                            or (" |cffff5555[UNPAID DEBT WRITTEN OFF]|r" .. noteTag)
                    end

                    local ruleTag = ""
                    if tx.type == "OUT" and not isGold and not isSummary and not isDerived and tx.source ~= "WRITE_OFF" then
                        if tx.isFFA or tx.priceMode == "FREE" then
                            ruleTag = " |cff44dd77(FFA)|r"
                        elseif tx.priceMode == "PERCENT" or (tx.chargedUnitPrice ~= nil and tx.unitPriceAtTime and tx.chargedUnitPrice < tx.unitPriceAtTime and tx.chargedUnitPrice > 0) then
                            local pct = tx.pricePercent or 50
                            ruleTag = string.format(" |cff26a6f2(%d%% AH)|r", pct)
                        end
                    end

                    if isSummary then
                        sub.subText:SetText(string.format("|cff999999%s|r [%s] %s — In: %s | Out: %s",
                            dateStr, dir, tx.itemName or "Monthly Summary",
                            VM:FormatMoney(tx.contributed or 0), VM:FormatMoney(tx.received or 0)))
                    elseif isDerived then
                        sub.subText:SetText(string.format("|cff999999%s|r [%s]%s%s: %dx %s — %s%s",
                            dateStr, dir, catTag, rawTag, tx.count or 1, tx.itemLink or tx.itemName or "Item", VM:FormatMoney(val), noteTag))
                    elseif isGold then
                        sub.subText:SetText(string.format("|cff999999%s|r [%s]%s%s%s: %s%s",
                            dateStr, dir, catTag, charTag, rawTag, VM:FormatMoney(val), noteTag))
                    elseif grp.isLegacy then
                        sub.subText:SetText(string.format("|cff808080%s [%s]%s: %dx %s — %s%s%s|r",
                            dateStr, tx.source == "WRITE_OFF" and "WRITE-OFF" or (tx.type == "OUT" and "OUT" or "IN"),
                            charTag, tx.count or 1, tx.itemName or "Item", VM:FormatMoney(val), ruleTag, noteTag))
                    else
                        sub.subText:SetText(string.format("|cff999999%s|r [%s]%s%s%s: %dx %s — %s%s%s",
                            dateStr, dir, catTag, charTag, rawTag, tx.count or 1, tx.itemLink or tx.itemName or "Item", VM:FormatMoney(val), ruleTag, noteTag))
                    end

                    local showDelete = isOff and (not isDerived) and (not isSummary) and VM.Ledger:CanDeleteTransaction(tx)
                    local showAction = false
                    local showPair = false
                    if isOff and isItemTx and not isDerived then
                        if tx.voided then
                            sub.pairBtn:SetText("Unpair")
                            sub.pairBtn.tooltipText = "Undo the return pairing; both entries count again."
                            showPair = true
                        elseif VM.Ledger:FindPairCandidate(tx) then
                            sub.pairBtn:SetText("Pair")
                            sub.pairBtn.tooltipText = "Pair this item with its matching withdrawal/return so both net to 0g regardless of price changes."
                            showPair = true
                        end
                    end

                    if isOff and not isSummary and not isDerived then
                        if grp.mainName == "UNATTRIBUTED" then
                            sub.actionMode = "ASSIGN_UNATTRIBUTED"
                            sub.actionBtn:SetText("Assign Member")
                            showAction = true
                        else
                            sub.actionMode = "REASSIGN"
                            sub.actionBtn:SetText("Reassign")
                            showAction = true
                        end
                    end

                    local rightEdge = -8
                    if showDelete then
                        sub.deleteBtn:Show()
                        rightEdge = -32
                    end
                    if showPair then
                        sub.pairBtn:ClearAllPoints()
                        sub.pairBtn:SetPoint("RIGHT", rightEdge, 0)
                        sub.pairBtn:Show()
                        rightEdge = rightEdge - 56
                    end
                    if showAction then
                        sub.actionBtn:ClearAllPoints()
                        sub.actionBtn:SetPoint("RIGHT", rightEdge, 0)
                        sub.actionBtn:Show()
                        rightEdge = rightEdge - 112
                    end
                    sub.subText:SetWidth(math.max(300, 690 + rightEdge))

                    y = y + 25
                end
            end
        end
    end

    for _, grp in ipairs(primaryGroups) do
        RenderGroup(grp)
    end

    if #legacyGroups > 0 then
        local legExpanded = (q ~= "") or STATE.ledgerLegacyExpanded
        local legHdr = panel.scroll.legacyHeader
        if not legHdr then
            legHdr = CreateFrame("Button", nil, content, "BackdropTemplate")
            legHdr:SetSize(732, 24)
            ApplyModernBackdrop(legHdr, THEME.rowLegacy, THEME.border)
            legHdr.text = legHdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            legHdr.text:SetPoint("LEFT", 8, 0)
            legHdr:SetScript("OnClick", function()
                if (STATE.ledgerSearchQuery or "") == "" then
                    STATE.ledgerLegacyExpanded = not STATE.ledgerLegacyExpanded
                    UI:RefreshLedger()
                end
            end)
            panel.scroll.legacyHeader = legHdr
        end

        y = y + 4
        legHdr:ClearAllPoints()
        legHdr:SetPoint("TOPLEFT", 4, -y)
        legHdr.text:SetText(string.format("%s  |cff888888Legacy Members (%d)|r", legExpanded and "[-]" or "[+]", #legacyGroups))
        legHdr:Show()
        y = y + 26

        if legExpanded then
            for _, grp in ipairs(legacyGroups) do
                RenderGroup(grp)
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 4: RANKING
--------------------------------------------------------------------------------
function UI:BuildRankingPanel(panel)
    local uiPrefs = GetUIPrefs()
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -6)
    topBar:SetPoint("TOPRIGHT", -10, -6)


    local exportBtn = CreateModernButton(topBar, 76, 24, "Export", THEME.accent)
    exportBtn:SetPoint("RIGHT", 0, 0)
    panel.helpBtn = AddTabHelpButton(topBar, "RANKING", exportBtn, "RIGHT", "LEFT", -6, 0)
    exportBtn:SetScript("OnClick", function()
        UI:OpenExportModal()
    end)

    local filterStrip = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterStrip:SetHeight(28)
    filterStrip:SetPoint("TOPLEFT", 10, -38)
    filterStrip:SetPoint("TOPRIGHT", -10, -38)
    ApplyModernBackdrop(filterStrip, { 0.05, 0.06, 0.08, 0.9 }, THEME.border)

    local showLegacyCb = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    showLegacyCb:SetSize(20, 20)
    showLegacyCb:SetPoint("LEFT", 8, 0)
    showLegacyCb.label = showLegacyCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showLegacyCb.label:SetPoint("LEFT", showLegacyCb, "RIGHT", 4, 0)
    showLegacyCb.label:SetText("Include Legacy Members")
    showLegacyCb:SetChecked(uiPrefs.showLegacyRanking ~= false)
    showLegacyCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.showLegacyRanking = cb:GetChecked() and true or false
        UI:RefreshRanking()
    end)
    panel.showLegacyCb = showLegacyCb

    local hideOfficersCb = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    hideOfficersCb:SetSize(20, 20)
    hideOfficersCb:SetPoint("LEFT", 180, 0)
    hideOfficersCb.label = hideOfficersCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideOfficersCb.label:SetPoint("LEFT", hideOfficersCb, "RIGHT", 4, 0)
    hideOfficersCb.label:SetText("Hide Officers")
    hideOfficersCb:SetChecked(uiPrefs.hideOfficers or false)
    hideOfficersCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.hideOfficers = cb:GetChecked() and true or false
        UI:RefreshRanking()
    end)
    panel.hideOfficersCb = hideOfficersCb

    local periodBtn = CreateModernDropdown(filterStrip, 112, 22, "All-Time")
    periodBtn:SetPoint("LEFT", 294, 0)
    periodBtn:SetScript("OnClick", function(btn)
        if rankingPeriodDropdownFrame and rankingPeriodDropdownFrame:IsShown() then
            rankingPeriodDropdownFrame:Hide()
        else
            UI:OpenRankingPeriodPicker(btn)
        end
    end)
    panel.periodBtn = periodBtn

    local ffaRankCb = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    ffaRankCb:SetSize(20, 20)
    ffaRankCb:SetPoint("LEFT", 414, 0)
    ffaRankCb.label = ffaRankCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ffaRankCb.label:SetPoint("LEFT", ffaRankCb, "RIGHT", 4, 0)
    ffaRankCb.label:SetText("Include Free-for-All")
    ffaRankCb:SetChecked(uiPrefs.includeFFA ~= false)
    ffaRankCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.includeFFA = cb:GetChecked() and true or false
        UI:RefreshRanking()
    end)
    panel.ffaRankCb = ffaRankCb

    local toggleAllBtn = CreateModernButton(filterStrip, 84, 22, "Expand All")
    toggleAllBtn:SetPoint("RIGHT", -6, 0)
    toggleAllBtn:SetScript("OnClick", function()
        local anyCollapsed = false
        for _, mainKey in ipairs(panel.visibleRankingMains or {}) do
            if not STATE.expandedRankingMains[mainKey] then
                anyCollapsed = true
                break
            end
        end
        for _, mainKey in ipairs(panel.visibleRankingMains or {}) do
            STATE.expandedRankingMains[mainKey] = anyCollapsed
        end
        UI:RefreshRanking()
    end)
    panel.toggleAllBtn = toggleAllBtn

    local colHeader = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    colHeader:SetSize(744, 24)
    colHeader:SetPoint("TOPLEFT", 10, -70)
    ApplyModernBackdrop(colHeader, { 0.06, 0.07, 0.09, 1 }, THEME.border)

    local cRank = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cRank:SetPoint("LEFT", 10, 0)
    cRank:SetText("#")

    panel.sortHeaders = {}

    local function CreateSortHeader(name, key, x, width)
        local btn = CreateFrame("Button", nil, colHeader)
        btn:SetSize(width, 24)
        btn:SetPoint("LEFT", x, 0)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", 0, 0)
        btn.label:SetText(name)
        btn.sortKey = key

        btn:SetScript("OnClick", function(selfBtn)
            local prefs = GetUIPrefs()
            if prefs.rankingSortBy == selfBtn.sortKey then
                prefs.rankingSortDir = (prefs.rankingSortDir == "asc") and "desc" or "asc"
            else
                prefs.rankingSortBy = selfBtn.sortKey
                prefs.rankingSortDir = (selfBtn.sortKey == "name") and "asc" or "desc"
            end
            UI:RefreshRanking()
        end)
        panel.sortHeaders[key] = btn
        return btn
    end

    CreateSortHeader("Player (Main)", "name", 60, 220)
    CreateSortHeader("Contributed", "contributed", 290, 140)
    CreateSortHeader("Received", "withdrawn", 440, 140)
    CreateSortHeader("Net Balance", "net", 590, 140)

    panel.scroll = CreateScrollArea(panel, -96, 8)
end

local function CreateRankingRow(content)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(732, 26)
    row:EnableMouse(true)
    ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

    row.expandBtn = CreateModernButton(row, 20, 20, "+")
    row.expandBtn:SetPoint("LEFT", 6, 0)

    row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rankText:SetPoint("LEFT", 30, 0)
    row.rankText:SetWidth(26)
    row.rankText:SetJustifyH("LEFT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 60, 0)
    row.nameText:SetWidth(220)
    row.nameText:SetJustifyH("LEFT")

    row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.goldText:SetPoint("LEFT", 290, 0)
    row.goldText:SetWidth(140)
    row.goldText:SetJustifyH("LEFT")

    row.itemsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemsText:SetPoint("LEFT", 440, 0)
    row.itemsText:SetWidth(140)
    row.itemsText:SetJustifyH("LEFT")

    row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.totalText:SetPoint("LEFT", 590, 0)
    row.totalText:SetWidth(140)
    row.totalText:SetJustifyH("LEFT")

    row.detailText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detailText:SetPoint("LEFT", 34, 0)
    row.detailText:SetWidth(690)
    row.detailText:SetJustifyH("LEFT")

    row:SetScript("OnEnter", function(selfRow)
        selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        if selfRow.showItemTooltip and selfRow.txData then
            local tx = selfRow.txData
            ShowItemTooltip(selfRow, tx.itemLink, tx.itemID, tx.itemName, tx)
        end
    end)
    row:SetScript("OnLeave", function(selfRow)
        local bg = selfRow.baseBg or THEME.rowOdd
        selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        if selfRow.showItemTooltip then
            HideItemTooltip()
        end
    end)

    row.expandBtn:SetScript("OnClick", function()
        if row.groupMainKey then
            STATE.expandedRankingMains[row.groupMainKey] = not STATE.expandedRankingMains[row.groupMainKey]
            UI:RefreshRanking()
        end
    end)

    return row
end

function UI:RefreshRanking()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[4] then return end
    local panel = mainFrame.panels[4]
    if not panel or not panel.scroll or not panel.sortHeaders then return end
    local content = panel.scroll.content
    if not content then return end

    if VM.UpdateRosterCache then VM:UpdateRosterCache() end

    local uiPrefs = GetUIPrefs()
    if panel.showLegacyCb then panel.showLegacyCb:SetChecked(uiPrefs.showLegacyRanking ~= false) end
    if panel.hideOfficersCb then panel.hideOfficersCb:SetChecked(uiPrefs.hideOfficers or false) end
    if panel.ffaRankCb then panel.ffaRankCb:SetChecked(uiPrefs.includeFFA ~= false) end
    if panel.periodBtn then
        local p = uiPrefs.rankingPeriod or "ALL"
        panel.periodBtn:SetText((p == "ALL") and "All-Time" or ((p == "CURRENT") and "Current Month" or "Previous Month"))
    end

    local sortBy = uiPrefs.rankingSortBy or "net"
    local sortDir = uiPrefs.rankingSortDir or "desc"
    local baseNames = { name = "Player (Main)", contributed = "Contributed", withdrawn = "Received", net = "Net Balance" }

    for key, btn in pairs(panel.sortHeaders) do
        local indicator = ""
        if key == sortBy then
            indicator = (sortDir == "asc") and " (^)" or " (v)"
            btn.label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            btn.label:SetTextColor(0.9, 0.9, 0.9, 1)
        end
        btn.label:SetText((baseNames[key] or key) .. indicator)
    end

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    local priceMode = VM:GetValuationMode()
    local period = uiPrefs.rankingPeriod or "ALL"
    local hideOff = uiPrefs.hideOfficers or false
    local showLeg = uiPrefs.showLegacyRanking ~= false

    local ranked = VM.Ranking:GetRankingData(sortBy, sortDir, priceMode, period, hideOff, showLeg)

    panel.visibleRankingMains = {}
    for _, grp in ipairs(ranked) do
        table.insert(panel.visibleRankingMains, grp.mainName)
    end

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, k in ipairs(panel.visibleRankingMains) do
            if not STATE.expandedRankingMains[k] then
                anyCollapsed = true
                break
            end
        end
        panel.toggleAllBtn:SetText(anyCollapsed and "Expand All" or "Collapse All")
    end

    local rowIdx = 0
    local function AcquireRow()
        rowIdx = rowIdx + 1
        local row = panel.scroll.rows[rowIdx]
        if not row then
            row = CreateRankingRow(content)
            panel.scroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    local y = 0
    for idx, grp in ipairs(ranked) do
        local isExpanded = STATE.expandedRankingMains[grp.mainName]
        local row = AcquireRow()
        local baseBg = grp.isLegacy and THEME.rowLegacy or ((idx % 2 == 0) and THEME.rowEven or THEME.rowOdd)

        row.baseBg = baseBg
        row.groupMainKey = grp.mainName
        row.txData = nil
        row.showItemTooltip = false

        row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -y)

        row.detailText:Hide()
        row.expandBtn:Show()
        row.expandBtn:SetText(isExpanded and "-" or "+")
        row.rankText:Show()
        row.nameText:Show()
        row.goldText:Show()
        row.itemsText:Show()
        row.totalText:Show()

        local dispContributed = grp.totalContributed
        local dispReceived = grp.totalWithdrawn
        local dispNet = grp.netBalance

        if grp.isLegacy then
            row.rankText:SetText("|cff808080-|r")
            row.nameText:SetText(VM:ColorizeName(grp.mainName, "808080") .. " |cff808080[Legacy]|r")
            row.goldText:SetText("|cff808080" .. VM:FormatMoney(dispContributed) .. "|r")
            row.itemsText:SetText("|cff808080" .. VM:FormatMoney(dispReceived) .. "|r")
            row.totalText:SetText("|cff808080" .. VM:FormatMoney(dispNet) .. "|r")
        else
            local rankBadge
            if idx == 1 then rankBadge = "|cffffd700#1|r"
            elseif idx == 2 then rankBadge = "|cffc0c0c0#2|r"
            elseif idx == 3 then rankBadge = "|cffcd7f32#3|r"
            else rankBadge = "|cff888888#" .. idx .. "|r" end

            local netColor = "|cffaaaaaa"
            if dispNet > 0 then
                netColor = "|cff44dd77"
            elseif dispNet < 0 then
                netColor = "|cffff5555"
            end

            row.rankText:SetText(rankBadge)
            row.nameText:SetText(VM:ColorizeName(grp.mainName))
            row.goldText:SetText(VM:FormatMoney(dispContributed))
            row.itemsText:SetText(VM:FormatMoney(dispReceived))
            row.totalText:SetText(netColor .. VM:FormatMoney(dispNet) .. "|r")
        end

        y = y + 28

        if isExpanded and grp.transactions then
            for _, tx in ipairs(grp.transactions) do
                local sub = AcquireRow()
                local subBg = THEME.rowOdd
                local isSummary = (tx.type == "SUMMARY" or tx.itemLink == "SUMMARY")
                local isGold = (not isSummary) and (tx.itemID == 0 or tx.itemLink == "GOLD")
                local isItemTx = (not isSummary) and (not isGold)

                sub.baseBg = subBg
                sub.groupMainKey = nil
                sub.txData = tx
                sub.showItemTooltip = isItemTx

                sub:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                sub:ClearAllPoints()
                sub:SetPoint("TOPLEFT", 6, -y)

                sub.expandBtn:Hide()
                sub.rankText:Hide()
                sub.nameText:Hide()
                sub.goldText:Hide()
                sub.itemsText:Hide()
                sub.totalText:Hide()
                sub.detailText:Show()

                local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                if isSummary then
                    sub.detailText:SetText(string.format("|cff888888%s|r |cff8899aa[SUMMARY]|r %s  —  In: %s  |  Out: %s",
                        dateStr,
                        tx.itemName or "Monthly Summary",
                        VM:FormatMoney(tx.contributed or 0),
                        VM:FormatMoney(tx.received or 0)))
                else
                    local dir
                    if tx.source == "WRITE_OFF" then
                        dir = "|cffff4444[WRITE-OFF]|r"
                    elseif tx.type == "OUT" then
                        dir = isGold and "|cffff6666[GOLD OUT]|r" or "|cffff6666[OUT]|r"
                    else
                        dir = isGold and "|cffffd700[GOLD IN]|r" or "|cff44dd77[IN]|r"
                    end
                    local itemDisplay = isGold and "Gold" or (tx.itemLink or tx.itemName or "Item")
                    local liveVal = VM.Ranking:GetTransactionValuation(tx)
                    local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED")
                        and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

                    sub.detailText:SetText(string.format("|cff888888%s|r %s %s%s  —  %s",
                        dateStr, dir, itemDisplay, charTag, VM:FormatMoney(liveVal)))
                end

                y = y + 22
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 5: ROSTER & MAINS (FOLDABLE RANK GROUPS + NESTED ALTS)
--------------------------------------------------------------------------------
function UI:BuildRosterPanel(panel)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local searchBox = CreateModernEditBox(topBar, 180, 24, false)
    searchBox:SetPoint("LEFT", 0, 0)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 8, 0)
    searchBox.placeholder:SetText("Filter character...")

    local debouncedRosterSearch = CreateDebouncer(0.15, function()
        if mainFrame and mainFrame:IsShown() and STATE.currentTab == 5 then
            UI:RefreshRoster()
        end
    end)

    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        STATE.rosterSearchFilter = txt:lower()
        debouncedRosterSearch()
    end)
    panel.searchBox = searchBox

    local unlinkedCb = CreateFrame("CheckButton", nil, topBar, "UICheckButtonTemplate")
    unlinkedCb:SetSize(20, 20)
    unlinkedCb:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    unlinkedCb.label = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unlinkedCb.label:SetPoint("LEFT", unlinkedCb, "RIGHT", 4, 0)
    unlinkedCb.label:SetText("Unlinked Only")
    unlinkedCb:SetScript("OnClick", function(cb)
        STATE.rosterUnlinkedOnly = cb:GetChecked() and true or false
        UI:RefreshRoster()
    end)
    panel.unlinkedCb = unlinkedCb

    local autoSuggestBtn = CreateModernButton(topBar, 128, 24, "Auto-Suggest Alts", THEME.accent)
    autoSuggestBtn:SetPoint("LEFT", unlinkedCb.label, "RIGHT", 14, 0)
    autoSuggestBtn:SetScript("OnClick", function()
        if not VM:IsOfficer() then return end
        local names = VM:GetGuildRosterNames(false)
        local count = 0
        for i = 1, #names do
            for j = i + 1, #names do
                local n1, n2 = names[i], names[j]
                if n1:len() >= 4 and n2:len() >= 4 and n1:sub(1, 4):lower() == n2:sub(1, 4):lower() then
                    local m1 = VM:GetMainFor(n1)
                    local m2 = VM:GetMainFor(n2)
                    if m1 == n1 and m2 == n2 and n1 ~= n2 then
                        VM:SetMainCharacter(n1, { n2 })
                        count = count + 1
                    end
                end
            end
        end
        VM:Print(string.format("Auto-suggested and linked %d alt pairs.", count))
        UI:RefreshRoster()
    end)
    panel.autoSuggestBtn = autoSuggestBtn

    local toggleAllBtn = CreateModernButton(topBar, 88, 24, "Expand All")
    toggleAllBtn:SetPoint("RIGHT", 0, 0)
    panel.helpBtn = AddTabHelpButton(topBar, "ROSTER", toggleAllBtn, "RIGHT", "LEFT", -6, 0)
    toggleAllBtn:SetScript("OnClick", function()
        local anyCollapsed = false
        for _, rk in ipairs(panel.visibleRankKeys or {}) do
            if not STATE.rosterRankExpanded[rk] then
                anyCollapsed = true
                break
            end
        end
        if not anyCollapsed then
            for _, mKey in ipairs(panel.visibleMainTreeKeys or {}) do
                if not STATE.expandedTreeMains[mKey] then
                    anyCollapsed = true
                    break
                end
            end
        end
        for _, rk in ipairs(panel.visibleRankKeys or {}) do
            STATE.rosterRankExpanded[rk] = anyCollapsed
        end
        for _, mKey in ipairs(panel.visibleMainTreeKeys or {}) do
            STATE.expandedTreeMains[mKey] = anyCollapsed
        end
        UI:RefreshRoster()
    end)
    panel.toggleAllBtn = toggleAllBtn

    panel.treeScroll = CreateScrollArea(panel, -44, 8)
end

local function CreateRosterRow(content)
    local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
    row:SetSize(732, 26)
    row:EnableMouse(true)
    ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

    row.expandBtn = CreateModernButton(row, 20, 20, "+")
    row.expandBtn:SetPoint("LEFT", 12, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 38, 0)
    row.label:SetWidth(420)
    row.label:SetJustifyH("LEFT")

    row.btn1 = CreateModernButton(row, 85, 20, "Set as Alt", THEME.accent)
    row.btn1:SetPoint("RIGHT", -95, 0)

    row.btn2 = CreateModernButton(row, 85, 20, "Unlink", THEME.red)
    row.btn2:SetPoint("RIGHT", -6, 0)

    row:SetScript("OnEnter", function(selfRow)
        selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
    end)
    row:SetScript("OnLeave", function(selfRow)
        local bg = selfRow.baseBg or THEME.rowOdd
        selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    end)

    row.expandBtn:SetScript("OnClick", function()
        if row.mainKey then
            STATE.expandedTreeMains[row.mainKey] = not STATE.expandedTreeMains[row.mainKey]
            UI:RefreshRoster()
        end
    end)

    row.btn1:SetScript("OnClick", function(selfBtn)
        if not VM:IsOfficer() then return end
        if row.isAltRow then
            if row.charName and row.parentMain then
                VM:SetMainCharacter(row.charName, { row.parentMain })
            end
        else
            local targetChar = row.charName
            if targetChar then
                UI:OpenRosterPicker(selfBtn, true, function(targetMain)
                    if targetMain and targetMain ~= targetChar and targetMain ~= "GUILD" then
                        VM:SetMainCharacter(targetMain, { targetChar })
                    end
                end, false)
            end
        end
    end)

    row.btn2:SetScript("OnClick", function()
        if not VM:IsOfficer() then return end
        if row.isAltRow and row.charName then
            VM:UnlinkCharacter(row.charName)
        end
    end)

    return row
end

function UI:RefreshRoster()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[5] then return end
    local panel = mainFrame.panels[5]
    if not panel or not panel.treeScroll then return end
    local content = panel.treeScroll.content
    if not content then return end

    local isOff = VM:IsOfficer()
    if panel.unlinkedCb then
        if isOff then
            panel.unlinkedCb:Show()
            panel.unlinkedCb.label:Show()
            panel.unlinkedCb:SetChecked(STATE.rosterUnlinkedOnly)
        else
            panel.unlinkedCb:Hide()
            panel.unlinkedCb.label:Hide()
            STATE.rosterUnlinkedOnly = false
        end
    end
    if panel.autoSuggestBtn then
        if isOff then panel.autoSuggestBtn:Show() else panel.autoSuggestBtn:Hide() end
    end

    for _, r in ipairs(panel.treeScroll.rows) do r:Hide() end
    panel.treeScroll.rankHeaders = panel.treeScroll.rankHeaders or {}
    for _, h in pairs(panel.treeScroll.rankHeaders) do h:Hide() end

    local filter = STATE.rosterSearchFilter or ""
    local unlinkedOnly = isOff and STATE.rosterUnlinkedOnly
    local hierarchy = VM:GetRosterHierarchy(true)

    local rankBuckets = {}
    local rankOrder = {}
    local legacyEntries = {}
    panel.visibleMainTreeKeys = {}

    for _, entry in ipairs(hierarchy) do
        local alts = entry.alts or {}
        local passesUnlinked = (not unlinkedOnly) or (#alts == 0)

        local matchesFilter = (filter == "" or entry.name:lower():find(filter, 1, true))
        if not matchesFilter then
            for _, alt in ipairs(alts) do
                if alt:lower():find(filter, 1, true) then
                    matchesFilter = true
                    break
                end
            end
        end

        if passesUnlinked and matchesFilter then
            if entry.isLegacy then
                table.insert(legacyEntries, entry)
            else
                local rIdx = entry.rankIndex or 999
                if not rankBuckets[rIdx] then
                    rankBuckets[rIdx] = {
                        rankIndex = rIdx,
                        rankName = entry.rankName or VM:GetRankName(rIdx),
                        mains = {},
                        totalAlts = 0,
                    }
                    table.insert(rankOrder, rIdx)
                end
                table.insert(rankBuckets[rIdx].mains, entry)
                rankBuckets[rIdx].totalAlts = rankBuckets[rIdx].totalAlts + #alts
                if #alts > 0 then
                    table.insert(panel.visibleMainTreeKeys, entry.name)
                end
            end
        end
    end

    table.sort(rankOrder)
    panel.visibleRankKeys = rankOrder

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, rk in ipairs(rankOrder) do
            if not STATE.rosterRankExpanded[rk] then anyCollapsed = true; break end
        end
        if not anyCollapsed then
            for _, mKey in ipairs(panel.visibleMainTreeKeys) do
                if not STATE.expandedTreeMains[mKey] then anyCollapsed = true; break end
            end
        end
        panel.toggleAllBtn:SetText(anyCollapsed and "Expand All" or "Collapse All")
    end

    local rowIdx = 0
    local y = 0

    local function AcquireRow()
        rowIdx = rowIdx + 1
        local row = panel.treeScroll.rows[rowIdx]
        if not row then
            row = CreateRosterRow(content)
            panel.treeScroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    local function GetSectionHeader(key, isLegacySection)
        local hdr = panel.treeScroll.rankHeaders[key]
        if not hdr then
            hdr = CreateFrame("Button", nil, content, "BackdropTemplate")
            hdr:SetSize(732, 24)
            ApplyModernBackdrop(hdr, isLegacySection and THEME.rowLegacy or THEME.headerBg, THEME.border)
            hdr.text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hdr.text:SetPoint("LEFT", 8, 0)
            hdr.sectionKey = key
            hdr.isLegacySection = isLegacySection
            hdr:SetScript("OnClick", function(selfHdr)
                if (STATE.rosterSearchFilter or "") == "" then
                    if selfHdr.isLegacySection then
                        STATE.rosterLegacyExpanded = not STATE.rosterLegacyExpanded
                    else
                        STATE.rosterRankExpanded[selfHdr.sectionKey] = not STATE.rosterRankExpanded[selfHdr.sectionKey]
                    end
                    UI:RefreshRoster()
                end
            end)
            panel.treeScroll.rankHeaders[key] = hdr
        end
        return hdr
    end

    local function RenderMainEntry(mainEntry)
        local mainName = mainEntry.name
        local alts = mainEntry.alts or {}
        local hasAlts = (#alts > 0)
        local isExpanded = STATE.expandedTreeMains[mainName] or (filter ~= "")
        local baseBg = mainEntry.isLegacy and THEME.rowLegacy or ((rowIdx % 2 == 0) and THEME.rowEven or THEME.rowOdd)

        local row = AcquireRow()
        row.baseBg = baseBg
        row.mainKey = mainName
        row.charName = mainName
        row.parentMain = nil
        row.isAltRow = false

        row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 4, -y)

        if hasAlts then
            row.expandBtn:Show()
            row.expandBtn:SetText(isExpanded and "-" or "+")
            row.label:SetPoint("LEFT", 38, 0)
        else
            row.expandBtn:Hide()
            row.label:SetPoint("LEFT", 18, 0)
        end

        if mainEntry.isLegacy then
            row.label:SetText(string.format("%s |cff808080[Legacy]%s|r",
                VM:ColorizeName(mainName, "808080"),
                hasAlts and string.format(" (%d alts)", #alts) or ""))
        else
            row.label:SetText(string.format("%s%s",
                VM:ColorizeName(mainName),
                hasAlts and string.format(" |cff888888(%d alts)|r", #alts) or ""))
        end

        if isOff then
            row.btn1:Show()
            row.btn1:SetText("Set as Alt")
        else
            row.btn1:Hide()
        end
        row.btn2:Hide()

        y = y + 27

        if hasAlts and isExpanded then
            for _, altName in ipairs(alts) do
                if filter == "" or altName:lower():find(filter, 1, true) or mainName:lower():find(filter, 1, true) then
                    local subBg = THEME.rowOdd
                    local subRow = AcquireRow()
                    subRow.baseBg = subBg
                    subRow.mainKey = nil
                    subRow.charName = altName
                    subRow.parentMain = mainName
                    subRow.isAltRow = true

                    subRow:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                    subRow:ClearAllPoints()
                    subRow:SetPoint("TOPLEFT", 4, -y)

                    subRow.expandBtn:Hide()
                    subRow.label:SetPoint("LEFT", 44, 0)
                    subRow.label:SetText(string.format("|cff888888└─ |r%s", VM:ColorizeName(altName)))

                    if isOff then
                        subRow.btn1:Show()
                        subRow.btn1:SetText("Make Main")
                        subRow.btn2:Show()
                        subRow.btn2:SetText("Unlink")
                    else
                        subRow.btn1:Hide()
                        subRow.btn2:Hide()
                    end

                    y = y + 25
                end
            end
        end
    end

    for _, rIdx in ipairs(rankOrder) do
        local bucket = rankBuckets[rIdx]
        local isRankExpanded = (filter ~= "") or unlinkedOnly or (STATE.rosterRankExpanded[rIdx] == true)
        local hdr = GetSectionHeader(rIdx, false)
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", 4, -y)

        local altNote = (bucket.totalAlts > 0) and string.format(", %d alts", bucket.totalAlts) or ""
        hdr.text:SetText(string.format("%s  |cffffffff%s|r  |cff8899aa(%d mains%s)|r",
            isRankExpanded and "[-]" or "[+]", bucket.rankName, #bucket.mains, altNote))
        hdr:Show()
        y = y + 26

        if isRankExpanded then
            for _, mainEntry in ipairs(bucket.mains) do
                RenderMainEntry(mainEntry)
            end
            y = y + 2
        end
    end

    if #legacyEntries > 0 then
        local isLegExpanded = (filter ~= "") or (STATE.rosterLegacyExpanded == true)
        local hdr = GetSectionHeader("LEGACY", true)
        y = y + 4
        hdr:ClearAllPoints()
        hdr:SetPoint("TOPLEFT", 4, -y)
        hdr.text:SetText(string.format("%s  |cff888888Legacy Members (%d)|r",
            isLegExpanded and "[-]" or "[+]", #legacyEntries))
        hdr:Show()
        y = y + 26

        if isLegExpanded then
            for _, mainEntry in ipairs(legacyEntries) do
                RenderMainEntry(mainEntry)
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 6: SETTINGS (COMPRESSED NON-PURCHASED TABS)
--------------------------------------------------------------------------------
local function FormatTabRange(indices)
    if not indices or #indices == 0 then return "" end
    if #indices == 1 then
        return "Tab " .. tostring(indices[1])
    end
    local consecutive = true
    for i = 2, #indices do
        if indices[i] ~= indices[i - 1] + 1 then
            consecutive = false
            break
        end
    end
    if consecutive then
        return string.format("Tabs %d-%d", indices[1], indices[#indices])
    end
    local parts = {}
    for _, v in ipairs(indices) do table.insert(parts, tostring(v)) end
    return "Tabs " .. table.concat(parts, ", ")
end

local function MakeCheck(parent, label, help, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(label)
    if onClick then cb:SetScript("OnClick", onClick) end
    AttachHelp(cb, help)
    return cb
end

local function MakeHeader(parent, title, desc, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 0, y or 0)
    t:SetText(title)
    local d
    if desc then
        d = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
        d:SetWidth(700)
        d:SetJustifyH("LEFT")
        d:SetText(desc)
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, desc and -18 or -4)
    line:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    line:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
    return t, d
end

local function MakeSub(parent, text, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 0, y)
    t:SetText(text)
    return t
end

function UI:BuildSettingsPanel(panel)
    panel.scroll = CreateScrollArea(panel, -6, 6)
    local content = panel.scroll.content

    ----------------------------------------------------------------------------
    -- MEMBER SETTINGS (everyone, own client only)
    ----------------------------------------------------------------------------
    local mem = CreateFrame("Frame", nil, content)
    mem:SetSize(728, 290)
    mem:SetPoint("TOPLEFT", 6, -4)
    panel.memberSec = mem
    MakeHeader(mem, "|cff26a6f2Member Settings|r", "Personal preferences. They only change your own Vault Manager.", 0)

    local scaleLabel = mem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 0, -46)
    scaleLabel:SetText("Window scale (50% - 200%):")
    local scaleEditBox = CreateModernEditBox(mem, 50, 22, true)
    scaleEditBox:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    scaleEditBox:SetText("100")
    local scaleValDisplay = mem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValDisplay:SetPoint("LEFT", scaleEditBox, "RIGHT", 8, 0)
    local scaleApplyBtn = CreateModernButton(mem, 55, 22, "Apply", THEME.accent)
    scaleApplyBtn:SetPoint("LEFT", scaleValDisplay, "RIGHT", 8, 0)
    scaleApplyBtn:SetScript("OnClick", function()
        local val = tonumber(scaleEditBox:GetText()) or 100
        if val < 50 then val = 50 elseif val > 200 then val = 200 end
        scaleEditBox:SetText(tostring(val))
        local prefs = GetUIPrefs()
        prefs.uiScale = val / 100
        if mainFrame then mainFrame:SetScale(val / 100) end
        scaleValDisplay:SetText(string.format("(%d%%)", val))
    end)
    AttachHelp(scaleApplyBtn, "Changes the size of the Vault Manager window. Drag the bottom-right corner of the window to make it taller. /vm reset restores 100% and centers the window.")
    panel.UpdateScaleButtons = function()
        local pct = math.floor((GetUIPrefs().uiScale or 1.0) * 100 + 0.5)
        scaleEditBox:SetText(tostring(pct))
        scaleValDisplay:SetText(string.format("(%d%%)", pct))
    end

    panel.minimapCb = MakeCheck(mem, "Show minimap button", "Shows the Vault Manager button on the edge of the minimap. Its badge counts open requests.", function(cb)
        if VM.Minimap and VM.Minimap.SetHidden then VM.Minimap:SetHidden(not cb:GetChecked()) end
    end)
    panel.minimapCb:SetPoint("TOPLEFT", 0, -74)
    panel.chatNotifCb = MakeCheck(mem, "Chat messages", "Vault Manager messages in your chat (request updates, payments, scans). Errors are always shown.", function(cb)
        GetUIPrefs().enableChatNotifications = cb:GetChecked() and true or false
    end)
    panel.chatNotifCb:SetPoint("TOPLEFT", 240, -74)
    panel.newerVerNotifCb = MakeCheck(mem, "Tell me about new versions", "Prints a chat message when a guild member runs a newer Vault Manager version.", function(cb)
        GetUIPrefs().notifyNewerVersion = cb:GetChecked() and true or false
    end)
    panel.newerVerNotifCb:SetPoint("TOPLEFT", 480, -74)
    panel.legacyFilterCb = MakeCheck(mem, "Include former members in Ranking", "Characters who left the guild (Legacy Members) are listed at the bottom of the Ranking by default. You can also toggle this on the Ranking tab.", function(cb)
        GetUIPrefs().showLegacyRanking = cb:GetChecked() and true or false
    end)
    panel.legacyFilterCb:SetPoint("TOPLEFT", 0, -100)

    local delivLabel = mem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delivLabel:SetPoint("TOPLEFT", 4, -132)
    delivLabel:SetText("How I want to receive my requests:")
    local delivMailBtn = CreateModernButton(mem, 56, 20, "Mail")
    delivMailBtn:SetPoint("LEFT", delivLabel, "RIGHT", 8, 0)
    local delivTradeBtn = CreateModernButton(mem, 56, 20, "Trade")
    delivTradeBtn:SetPoint("LEFT", delivMailBtn, "RIGHT", 4, 0)
    local function SetDeliv(v)
        local prefs = GetUIPrefs()
        prefs.deliveryPref = (prefs.deliveryPref == v) and nil or v
        UI:RefreshSettings()
    end
    delivMailBtn:SetScript("OnClick", function() SetDeliv("MAIL") end)
    delivTradeBtn:SetScript("OnClick", function() SetDeliv("TRADE") end)
    AttachHelp(delivMailBtn, "Officers see this on your new requests. Mail: sent to you, usually with Cash on Delivery (you pay when you take it out of the mailbox). Click again to clear.")
    AttachHelp(delivTradeBtn, "Officers see this on your new requests. Trade: you meet the officer and pay in the trade window. Click again to clear.")
    panel.delivMailBtn, panel.delivTradeBtn = delivMailBtn, delivTradeBtn

    MakeSub(mem, "|cff26a6f2Sync & Diagnostics|r", -164)
    local diagInfo = mem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diagInfo:SetPoint("TOPLEFT", 0, -184)
    diagInfo:SetWidth(560)
    diagInfo:SetJustifyH("LEFT")
    panel.diagInfo = diagInfo
    local requestSyncBtn = CreateModernButton(mem, 140, 24, "Request Guild Sync", THEME.accent)
    requestSyncBtn:SetPoint("TOPRIGHT", -10, -180)
    requestSyncBtn:SetScript("OnClick", function()
        if VM.Comms and VM.Comms.RequestManualSync then
            local ok, waitSec = VM.Comms:RequestManualSync()
            if ok then
                VM:Print("Requested guild sync from online members.")
            elseif waitSec and waitSec > 0 then
                VM:Print(string.format("Sync already checked. Please wait %ds.", waitSec))
            end
        end
        if VM.BankScanner and VM.BankScanner.ForceScan and IsBankCurrentlyOpen() then
            VM.BankScanner:ForceScan()
        end
    end)
    AttachHelp(requestSyncBtn, "Asks online guild members for newer vault, request and ledger data. Data also syncs automatically when you log in. Type /vm diag for technical details.")

    MakeSub(mem, "|cff26a6f2Local Maintenance|r", -222)
    local resetPosBtn = CreateModernButton(mem, 156, 24, "Reset Window Position")
    resetPosBtn:SetPoint("TOPLEFT", 0, -244)
    resetPosBtn:SetScript("OnClick", function()
        GetUIPrefs().windowPos = nil
        GetUIPrefs().windowHeight = nil
        if mainFrame then mainFrame:SetHeight(560) end
        ApplyDefaultWindowPosition()
        if VM.Minimap and VM.Minimap.ResetPosition then VM.Minimap:ResetPosition() end
        VM:Print("Window size/position and minimap button position reset.")
    end)
    AttachHelp(resetPosBtn, "Moves the window back to the default position and size, and the minimap button back to its default place.")
    local clearCacheBtn = CreateModernButton(mem, 136, 24, "Clear Local Cache", { 0.85, 0.35, 0.35, 1 })
    clearCacheBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", 10, 0)
    clearCacheBtn:SetScript("OnClick", function()
        if VM.db then
            VM.db.inventory = { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
            VM.db.vault = VM.db.inventory
            VM.db.scanMetadata = VM.db.inventory
            VM.db.processedBankLogs = {}
            VM.db.requests = {}
            VM.db.fulfillments = VM.db.requests
        end
        if VM.Comms then
            VM.Comms.peerHasNewerData = false
            VM.Comms.isSyncingUntil = 0
        end
        if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
        VM:Print("Local cache cleared (ledger, roster, and tab rules preserved). Click Request Guild Sync to reload it.")
        if VM.UI then VM.UI:RefreshAll() end
    end)
    AttachHelp(clearCacheBtn, "Only on YOUR client: forgets the cached vault contents and requests, then reloads them from the guild. Nothing is deleted for anyone else. The Ledger and rules are kept.")

    ----------------------------------------------------------------------------
    -- OFFICER SETTINGS (dimmed and locked until you are an officer)
    ----------------------------------------------------------------------------
    local off = CreateFrame("Frame", nil, content)
    off:SetSize(728, 116)
    panel.officerSec = off
    local _, offDesc = MakeHeader(off, "|cffffaa00Officer Settings|r", "", 0)
    panel.officerStatus = offDesc

    MakeSub(off, "|cff26a6f2Officer Workflow|r", -46)
    panel.autoOpenBankCb = MakeCheck(off, "Open Vault Manager at the Guild Bank", "Opens Vault Manager automatically when you open the Guild Bank: on Requests when orders are waiting, otherwise on Vault & Requests. When off, a small reminder pop-up is shown instead.", function(cb)
        GetUIPrefs().autoOpenAtBank = cb:GetChecked() and true or false
    end)
    panel.autoOpenBankCb:SetPoint("TOPLEFT", 0, -68)
    panel.whisperCb = MakeCheck(off, "Whisper members about status", "Sends members (or their online alt) a whisper when their request is approved, ready, sent or declined. Payment messages after a trade are always sent.", function(cb)
        GetUIPrefs().memberWhispers = cb:GetChecked() and true or false
    end)
    panel.whisperCb:SetPoint("TOPLEFT", 270, -68)
    panel.autoMailCb = MakeCheck(off, "Fill next mail after Send", "At the mailbox: after you click Send, the next member's prepared orders are filled in automatically. You still click Send yourself.", function(cb)
        GetUIPrefs().autoFillNextMail = cb:GetChecked() and true or false
    end)
    panel.autoMailCb:SetPoint("TOPLEFT", 510, -68)
    panel.officerControls = { panel.autoOpenBankCb, panel.whisperCb, panel.autoMailCb }

    ----------------------------------------------------------------------------
    -- GUILD CONFIGURATION (Guild Master / officer rank only)
    ----------------------------------------------------------------------------
    local adm = CreateFrame("Frame", nil, content)
    adm:SetSize(728, 100)
    panel.adminSec = adm
    local admTitle = MakeSub(adm, "|cff26a6f2Guild Configuration|r  |cff999999(Guild Master and the guild's officer rank)|r", 0)
    panel.adminNote = adm:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.adminNote:SetPoint("TOPLEFT", admTitle, "BOTTOMLEFT", 0, -3)
    panel.adminNote:SetWidth(700)
    panel.adminNote:SetJustifyH("LEFT")
    panel.adminNote:SetText("These settings apply to the whole guild and are shared with every member automatically.")

    local ruleTitle = adm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ruleTitle:SetPoint("TOPLEFT", 0, -38)
    ruleTitle:SetText("Guild Bank tab rules")
    local ruleHelp = adm:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ruleHelp:SetPoint("LEFT", ruleTitle, "RIGHT", 8, 0)
    ruleHelp:SetText("Free-for-All: members pay nothing (100% value still counts in the Ledger).  % of AH: members pay this share of the AH price (min 1g), the rest is a guild subsidy.  Locked: no requests.")
    ruleHelp:SetWidth(560)
    ruleHelp:SetJustifyH("LEFT")
    panel.ruleTitle = ruleTitle

    panel.tabRuleRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, adm, "BackdropTemplate")
        r:SetSize(716, 25)
        r.tabIndex = i
        ApplyModernBackdrop(r, (i % 2 == 0) and THEME.rowEven or THEME.rowOdd, { 0, 0, 0, 0 })
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", 10, 0)
        r.label:SetWidth(96)
        r.label:SetJustifyH("LEFT")
        r.freeBtn = CreateModernButton(r, 80, 20, "Free-for-All")
        r.freeBtn:SetPoint("LEFT", 110, 0)
        r.pctBtn = CreateModernButton(r, 68, 20, "% of AH")
        r.pctBtn:SetPoint("LEFT", 194, 0)
        r.pctBox = CreateModernEditBox(r, 36, 20, true)
        r.pctBox:SetPoint("LEFT", 266, 0)
        r.pctBox:SetText("50")
        r.lockBtn = CreateModernButton(r, 62, 20, "Locked")
        r.lockBtn:SetPoint("LEFT", 306, 0)
        r.saveBtn = CreateModernButton(r, 62, 20, "Save", THEME.accent)
        r.saveBtn:SetPoint("LEFT", 374, 0)
        AttachHelp(r.saveBtn, "Saves the rule for this tab and shares it with the guild. Prices of requests that are already approved do not change.")
        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", 446, 0)
        r.status:SetWidth(262)
        r.status:SetJustifyH("LEFT")
        r.freeBtn:SetScript("OnClick", function() if VM:IsAdmin() then r.selectedMode = "FREE"; UI:RefreshSettings() end end)
        r.pctBtn:SetScript("OnClick", function() if VM:IsAdmin() then r.selectedMode = "PERCENT"; UI:RefreshSettings() end end)
        r.lockBtn:SetScript("OnClick", function() if VM:IsAdmin() then r.selectedMode = "LOCKED"; UI:RefreshSettings() end end)
        local function SaveRule()
            if not VM:IsAdmin() then return end
            local pct = tonumber(r.pctBox:GetText()) or 50
            if pct <= 0 then pct = 50; r.pctBox:SetText("50") end
            r.userEditedPct = false
            VM:SetTabRule(r.tabIndex, r.selectedMode or "FREE", pct)
        end
        r.saveBtn:SetScript("OnClick", SaveRule)
        r.pctBox:SetScript("OnTextChanged", function() if VM:IsAdmin() then r.userEditedPct = true end end)
        r.pctBox:SetScript("OnEnterPressed", function(selfBox) selfBox:ClearFocus(); SaveRule() end)
        r:Hide()
        panel.tabRuleRows[i] = r
    end
    local unpurchasedNote = adm:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    unpurchasedNote:SetJustifyH("LEFT")
    unpurchasedNote:Hide()
    panel.unpurchasedNote = unpurchasedNote

    -- Officer ranks + guild reset (positioned below the tab rules)
    local admLower = CreateFrame("Frame", nil, adm)
    admLower:SetSize(716, 140)
    panel.adminLower = admLower
    local rankTitle = admLower:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rankTitle:SetPoint("TOPLEFT", 0, 0)
    rankTitle:SetText("Officer ranks")
    local rankHelp = admLower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rankHelp:SetPoint("LEFT", rankTitle, "RIGHT", 8, 0)
    rankHelp:SetWidth(600)
    rankHelp:SetJustifyH("LEFT")
    rankHelp:SetText("Tick extra ranks (e.g. Raid Leader, Officer Alt) that may approve, withdraw and manage the Ledger. They cannot change these settings.")
    panel.rankChecks = {}
    for i = 1, 10 do
        local cb = CreateFrame("CheckButton", nil, admLower, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", ((i - 1) % 5) * 143, -20 - math.floor((i - 1) / 5) * 22)
        cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.label:SetWidth(118)
        cb.label:SetJustifyH("LEFT")
        cb:SetScript("OnClick", function(selfCb)
            if not selfCb.rankIndex then return end
            VM:SetOfficerRank(selfCb.rankIndex, selfCb:GetChecked() and true or false)
            UI:RefreshSettings()
        end)
        AttachHelp(cb, "Members of this rank get the officer functions in Vault Manager. Withdrawing still needs the rank's Guild Bank rights in WoW. The Guild Master and the 2nd rank always have full access.")
        cb:Hide()
        panel.rankChecks[i] = cb
    end

    local resetTitle = admLower:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resetTitle:SetPoint("TOPLEFT", 0, -78)
    resetTitle:SetText("Guild-wide reset")
    local resetGuildBtn = CreateModernButton(admLower, 132, 24, "Reset Guild Data...", { 0.85, 0.20, 0.20, 1 })
    resetGuildBtn:SetPoint("TOPLEFT", 0, -96)
    resetGuildBtn:SetScript("OnClick", function(selfBtn)
        if not selfBtn:IsEnabled() then return end
        local pending = VM:GetPendingReset()
        if pending and VM:IsGuildMaster() then
            UI:ShowResetApproval(pending)
        else
            UI:ShowResetGuildConfirm()
        end
    end)
    AttachHelp(resetGuildBtn, "Clears the Ledger, requests and vault data for EVERY member and rebuilds them from the Guild Bank logs on the next scan. Tab rules, officer ranks and alt links are kept. Needs the Guild Master's approval.")
    panel.resetGuildBtn = resetGuildBtn
    local maintDesc = admLower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maintDesc:SetPoint("LEFT", resetGuildBtn, "RIGHT", 10, 0)
    maintDesc:SetWidth(560)
    maintDesc:SetJustifyH("LEFT")
    panel.maintDesc = maintDesc
end

function UI:RefreshSettings()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[6] then return end
    local panel = mainFrame.panels[6]
    if not panel or not panel.tabRuleRows then return end

    local uiPrefs = GetUIPrefs()
    local isOfficer = VM:IsOfficer()
    local isOff = VM:IsAdmin()   -- guild configuration: Guild Master + officer rank

    -- Member settings
    if panel.UpdateScaleButtons then panel.UpdateScaleButtons() end
    if panel.minimapCb then panel.minimapCb:SetChecked(not (VM.db and VM.db.minimap and VM.db.minimap.hide == true)) end
    if panel.legacyFilterCb then panel.legacyFilterCb:SetChecked(uiPrefs.showLegacyRanking ~= false) end
    if panel.chatNotifCb then panel.chatNotifCb:SetChecked(uiPrefs.enableChatNotifications ~= false) end
    if panel.newerVerNotifCb then panel.newerVerNotifCb:SetChecked(uiPrefs.notifyNewerVersion ~= false) end
    if panel.delivMailBtn then
        local pref = uiPrefs.deliveryPref
        for _, pair in ipairs({ { panel.delivMailBtn, "MAIL" }, { panel.delivTradeBtn, "TRADE" } }) do
            local btn, v = pair[1], pair[2]
            if pref == v then
                btn.customBg = { 0.15, 0.28, 0.42, 1 }
                btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                btn.label:SetTextColor(1, 0.82, 0)
            else
                btn.customBg = nil
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                btn.label:SetTextColor(0.75, 0.75, 0.75)
            end
        end
    end
    if panel.diagInfo then
        local gKey = VM:GetActiveGuildKey() or "None"
        local inv = VM.db and VM.db.inventory
        local lastScan = inv and inv.lastScan or 0
        local scanTimeStr = lastScan > 0 and date("%d/%m %H:%M", lastScan) or "Never"
        local scanBy = (inv and (inv.lastScanBy or inv.scannedBy)) or "None"
        -- Sync compatibility instead of a bare protocol number: who else runs Vault Manager and who is outdated
        local syncLine
        local seen, outdated = 0, {}
        if VM.Comms and VM.Comms.GetPeerCompatibility then seen, outdated = VM.Comms:GetPeerCompatibility() end
        if seen == 0 then
            syncLine = "Sync: |cff999999no other members with Vault Manager seen yet this session|r"
        elseif #outdated == 0 then
            syncLine = string.format("Sync: |cff44dd77%d member(s) with Vault Manager seen recently, all compatible|r", seen)
        else
            local names = {}
            for i = 1, math.min(3, #outdated) do names[i] = outdated[i] end
            if #outdated > 3 then table.insert(names, string.format("+%d more", #outdated - 3)) end
            syncLine = string.format("Sync: %d member(s) seen recently, |cffff8844%d on an older version (%s) — their data may not sync fully until they update|r",
                seen, #outdated, table.concat(names, ", "))
        end
        panel.diagInfo:SetText(string.format("Version: |cffffffffv%s|r (build %s)  |  Guild: |cffffffff%s|r  |  Last bank scan: |cffffffff%s|r (%s)\n%s",
            VM:GetAddonVersion(), tostring(VM.BUILD or "-"), gKey, scanBy, scanTimeStr, syncLine))
    end

    -- Officer settings: dimmed and locked until you are an officer
    if panel.officerStatus then
        if isOff then
            panel.officerStatus:SetText("|cff44dd77You have full officer access (Guild Master / officer rank).|r")
        elseif isOfficer then
            panel.officerStatus:SetText("|cff44dd77Officer workflow available.|r |cff999999Guild configuration below needs the Guild Master or the guild's officer rank.|r")
        else
            panel.officerStatus:SetText("|cffff8844Read-only: these settings are available to officers. Ask an officer if you need a change.|r")
        end
    end
    panel.officerSec:SetAlpha(isOfficer and 1 or 0.45)
    for _, cb in ipairs(panel.officerControls or {}) do
        if cb.SetEnabled then cb:SetEnabled(isOfficer) end
    end
    if panel.autoOpenBankCb then panel.autoOpenBankCb:SetChecked(uiPrefs.autoOpenAtBank ~= false) end
    if panel.whisperCb then panel.whisperCb:SetChecked(uiPrefs.memberWhispers ~= false) end
    if panel.autoMailCb then panel.autoMailCb:SetChecked(uiPrefs.autoFillNextMail ~= false) end

    panel.adminSec:SetAlpha(isOff and 1 or 0.45)
    if panel.adminNote then
        panel.adminNote:SetText(isOff and "These settings apply to the whole guild and are shared with every member automatically."
            or "|cffff8844Locked: only the Guild Master and the guild's officer rank can change these settings.|r")
    end

    if panel.resetGuildBtn then
        ApplyButtonState(panel.resetGuildBtn, isOff and "active" or "disabled")
        local pending = VM:GetPendingReset()
        if pending then
            panel.maintDesc:SetText(string.format("|cffffaa00Reset requested by %s — waiting for Guild Master approval.|r", pending.by or "?"))
        else
            panel.maintDesc:SetText("Step 1: the Guild Master or officer rank requests it (type RESET). Step 2: the Guild Master approves it (type RESET).")
        end
    end

    if panel.rankChecks then
        local ranks = VM:GetGuildRankList()
        for i, cb in ipairs(panel.rankChecks) do
            local r = ranks[i]
            if r then
                cb.rankIndex = r.index
                local fixed = VM:IsAdminRank(r.index)
                cb.label:SetText(r.name .. (fixed and " |cff888888(always)|r" or ""))
                cb:SetChecked(VM:IsOfficerRank(r.index))
                local editable = isOff and not fixed
                if cb.SetEnabled then cb:SetEnabled(editable) end
                cb.label:SetTextColor(editable and 1 or 0.6, editable and 1 or 0.6, editable and 1 or 0.6)
                cb:Show()
            else
                cb.rankIndex = nil
                cb:Hide()
            end
        end
    end

    local function StyleButton(btn, isActive, activeBg, activeBorder, activeText)
        if not isOff then
            btn.customBg = nil
            btn:Disable()
            btn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.4)
            btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.4)
            btn.label:SetTextColor(0.4, 0.4, 0.4)
        elseif isActive then
            btn.customBg = activeBg
            btn:Enable()
            btn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], 1)
            SetButtonAccent(btn, activeBorder)
            btn.label:SetTextColor(activeText[1], activeText[2], activeText[3])
        else
            btn.customBg = nil
            btn:Enable()
            btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            SetButtonAccent(btn, THEME.border)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    -- Tab rule rows (inside Guild Configuration)
    local y = 60
    local unpurchasedTabs = {}
    for i = 1, 6 do
        local r = panel.tabRuleRows[i]
        if not VM:IsTabPurchased(i) then
            r:Hide()
            table.insert(unpurchasedTabs, i)
        else
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:Show()
            y = y + 27

            local tabData = VM.db.inventory and VM.db.inventory.tabs and VM.db.inventory.tabs[i]
            local tabName = (tabData and tabData.name) or string.format("Tab %d", i)
            local rule = VM:GetTabRule(i)
            r.label:SetText(string.format("Tab %d: %s", i, tabName))
            if not r.userEditedPct then r.pctBox:SetText(tostring(rule.percent or 50)) end
            if not r.selectedMode then r.selectedMode = rule.mode or "FREE" end

            local mode = rule.mode or "FREE"
            local byStr = (rule.updatedBy and rule.updatedBy ~= "") and (" (set by " .. rule.updatedBy .. ")") or ""
            if mode == "LOCKED" then
                r.status:SetText(string.format("|cffff5555ACTIVE: Locked%s|r", byStr))
            elseif mode == "PERCENT" then
                r.status:SetText(string.format("|cffffcc33ACTIVE: %d%% of AH%s|r", rule.percent or 50, byStr))
            else
                r.status:SetText(string.format("|cff44dd77ACTIVE: Free-for-All%s|r", byStr))
            end

            local selMode = r.selectedMode or mode
            StyleButton(r.freeBtn, selMode == "FREE", { 0.10, 0.28, 0.18, 1 }, { 0.20, 0.80, 0.40, 1 }, { 0.3, 0.9, 0.5 })
            StyleButton(r.pctBtn, selMode == "PERCENT", { 0.32, 0.26, 0.10, 1 }, { 0.90, 0.70, 0.20, 1 }, { 1, 0.85, 0.2 })
            StyleButton(r.lockBtn, selMode == "LOCKED", { 0.32, 0.12, 0.12, 1 }, { 0.90, 0.30, 0.30, 1 }, { 1, 0.4, 0.4 })
            if not isOff then
                r.saveBtn.customBg = nil
                r.saveBtn:Disable()
                r.saveBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.4)
                r.saveBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.4)
                r.saveBtn.label:SetTextColor(0.4, 0.4, 0.4)
            else
                r.saveBtn.customBg = THEME.accent
                r.saveBtn:Enable()
                r.saveBtn:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                SetButtonAccent(r.saveBtn, THEME.accent)
                r.saveBtn.label:SetTextColor(1, 1, 1)
            end
            if isOff and selMode == "PERCENT" then
                r.pctBox:Enable()
                r.pctBox:SetBackdropColor(0.05, 0.06, 0.08, 1)
                r.pctBox:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                r.pctBox:SetAlpha(1.0)
            else
                r.pctBox:ClearFocus()
                r.pctBox:Disable()
                r.pctBox:SetBackdropColor(0.05, 0.06, 0.08, 0.4)
                r.pctBox:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.3)
                r.pctBox:SetAlpha(0.4)
            end
        end
    end
    if #unpurchasedTabs > 0 and panel.unpurchasedNote then
        panel.unpurchasedNote:ClearAllPoints()
        panel.unpurchasedNote:SetPoint("TOPLEFT", 4, -(y + 2))
        panel.unpurchasedNote:SetText(string.format("|cff888888%s: not purchased (buy them in the Guild Bank to set rules)|r", FormatTabRange(unpurchasedTabs)))
        panel.unpurchasedNote:Show()
        y = y + 20
    elseif panel.unpurchasedNote then
        panel.unpurchasedNote:Hide()
    end
    panel.adminLower:ClearAllPoints()
    panel.adminLower:SetPoint("TOPLEFT", 0, -(y + 12))
    local admHeight = y + 12 + 130
    panel.adminSec:SetHeight(admHeight)

    -- Stack the sections in the scroll area
    local top = 4
    panel.memberSec:ClearAllPoints()
    panel.memberSec:SetPoint("TOPLEFT", 6, -top)
    top = top + panel.memberSec:GetHeight() + 10
    panel.officerSec:ClearAllPoints()
    panel.officerSec:SetPoint("TOPLEFT", 6, -top)
    top = top + panel.officerSec:GetHeight() + 4
    panel.adminSec:ClearAllPoints()
    panel.adminSec:SetPoint("TOPLEFT", 6, -top)
    top = top + admHeight + 10
    panel.scroll.content:SetHeight(top)
end

--------------------------------------------------------------------------------
-- MAIL FULFILLMENT SELECTOR PANEL (OFFICER PREPARED QUEUE)
--------------------------------------------------------------------------------
function UI:CreateMailFulfillmentPanel()
    mailPanelFrame = CreateFrame("Frame", "VaultManagerMailPanel", UIParent, "BackdropTemplate")
    mailPanelFrame:SetSize(330, 250)
    mailPanelFrame:SetPoint("CENTER")
    mailPanelFrame:SetFrameStrata("DIALOG")
    mailPanelFrame:SetFrameLevel(180)
    mailPanelFrame:SetClampedToScreen(true)
    mailPanelFrame:SetMovable(true)
    mailPanelFrame:EnableMouse(true)
    mailPanelFrame:RegisterForDrag("LeftButton")
    mailPanelFrame:SetScript("OnDragStart", mailPanelFrame.StartMoving)
    mailPanelFrame:SetScript("OnDragStop", mailPanelFrame.StopMovingOrSizing)
    ApplyModernBackdrop(mailPanelFrame, THEME.bg, THEME.accent)
    mailPanelFrame:Hide()

    local title = mailPanelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff26a6f2Prepared Requests — Mail|r")

    local closeBtn = CreateModernButton(mailPanelFrame, 20, 20, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() mailPanelFrame:Hide() end)

    local sub = mailPanelFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 12, -28)
    sub:SetText("Click Fill Mail to populate Send Mail, then click Send.")

    mailPanelFrame.scroll = CreateScrollArea(mailPanelFrame, -46, 8)
    mailPanelFrame.scroll.content:SetSize(292, 1)
end

function UI:ShowMailFulfillmentPanel(orders)
    if not mailPanelFrame then self:CreateMailFulfillmentPanel() end
    if not orders or #orders == 0 then
        mailPanelFrame:Hide()
        return
    end

    mailPanelFrame:ClearAllPoints()
    if MailFrame and MailFrame:IsVisible() then
        mailPanelFrame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    else
        mailPanelFrame:SetPoint("CENTER", 220, 40)
    end

    -- Group item orders per member (one mail each); gold requests get their own row/mail
    local groups, order = {}, {}
    for _, req in ipairs(orders) do
        local key = req.isGoldRequest and ("GOLD:" .. req.id) or ("M:" .. VM:GetMainFor(VM:NormalizeName(req.requester)) .. ":" .. VM:NormalizeName(req.requester))
        if not groups[key] then
            groups[key] = { requester = req.requester, reqs = {}, isGold = req.isGoldRequest }
            table.insert(order, key)
        end
        table.insert(groups[key].reqs, req)
    end

    local content = mailPanelFrame.scroll.content
    for _, r in ipairs(mailPanelFrame.scroll.rows) do r:Hide() end

    local y = 0
    for idx, key in ipairs(order) do
        local grp = groups[key]
        local row = mailPanelFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(292, 38)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.line1:SetPoint("TOPLEFT", 6, -4)
            row.line1:SetWidth(170)
            row.line1:SetJustifyH("LEFT")

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", 6, -20)
            row.line2:SetWidth(170)
            row.line2:SetJustifyH("LEFT")

            row.fillBtn = CreateModernButton(row, 62, 22, "Fill Mail", THEME.accent)
            row.fillBtn:SetPoint("RIGHT", -52, 0)
            row.fillBtn:SetScript("OnClick", function()
                local g = row.group
                if not g or not VM.Fulfillment then return end
                if g.isGold then
                    VM.Fulfillment:PopulateMail(g.reqs[1])
                    VM.Fulfillment.fulfillStarted[g.reqs[1].id] = true
                else
                    VM.Fulfillment:PopulateMailFor(g.requester)
                end
                UI:RefreshRequests()
            end)

            row.nameBtn = CreateModernButton(row, 44, 22, "Name", THEME.border)
            row.nameBtn:SetPoint("RIGHT", -4, 0)
            row.nameBtn:SetScript("OnClick", function()
                if VM.Delivery and not VM.Delivery:SwapMailRecipient() then
                    VM:Print("Fill the mail first; then this switches between full name and first name.")
                end
            end)
            row.nameBtn:HookScript("OnEnter", function(selfBtn)
                GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                GameTooltip:SetText("Switch the recipient between the full name and the first name", 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row.nameBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

            mailPanelFrame.scroll.rows[idx] = row
        end

        local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        row.group = grp
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()

        if grp.isGold then
            local req = grp.reqs[1]
            local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
            row.line1:SetText(string.format("%s — |cffffd700%s|r", VM:ColorizeName(req.requester), VM:FormatMoneyShort(gAmt)))
            row.line2:SetText("Send Money: " .. (req.reason or "Guild expense"))
        else
            local cod = 0
            for _, r in ipairs(grp.reqs) do cod = cod + (VM.Fulfillment:GetExpectedMemberPayment(r) or 0) end
            local what = (#grp.reqs == 1) and string.format("%dx %s", grp.reqs[1].count or 1, grp.reqs[1].itemLink or grp.reqs[1].itemName or "Item")
                or string.format("%d requests", #grp.reqs)
            row.line1:SetText(string.format("%s — %s", VM:ColorizeName(grp.requester), what))
            row.line2:SetText(cod > 0 and ("CoD: " .. VM:FormatMoneyShort(cod)) or "Free-for-All (No CoD)")
        end

        y = y + 40
    end

    content:SetHeight(math.max(1, y))
    mailPanelFrame:SetHeight(math.min(260, math.max(100, y + 60)))
    mailPanelFrame:Show()
end

function UI:HideMailFulfillmentPanel()
    if mailPanelFrame then mailPanelFrame:Hide() end
end

--------------------------------------------------------------------------------
-- TRADE FULFILLMENT PROMPT (AUTO-SHOWN ON MATCHING PREPARED REQUEST)
--------------------------------------------------------------------------------
function UI:CreateTradeFulfillmentPrompt()
    tradePromptFrame = CreateFrame("Frame", "VaultManagerTradePrompt", UIParent, "BackdropTemplate")
    tradePromptFrame:SetSize(350, 150)
    tradePromptFrame:SetPoint("CENTER")
    tradePromptFrame:SetFrameStrata("DIALOG")
    tradePromptFrame:SetFrameLevel(190)
    tradePromptFrame:SetClampedToScreen(true)
    tradePromptFrame:SetMovable(true)
    tradePromptFrame:EnableMouse(true)
    tradePromptFrame:RegisterForDrag("LeftButton")
    tradePromptFrame:SetScript("OnDragStart", tradePromptFrame.StartMoving)
    tradePromptFrame:SetScript("OnDragStop", tradePromptFrame.StopMovingOrSizing)
    ApplyModernBackdrop(tradePromptFrame, THEME.bg, THEME.green)
    tradePromptFrame:Hide()

    local title = tradePromptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("|cff44dd77Prepared Request Ready|r")

    local closeBtn = CreateModernButton(tradePromptFrame, 20, 20, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() tradePromptFrame:Hide() end)

    local promptText = tradePromptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    promptText:SetPoint("TOPLEFT", 12, -30)
    promptText:SetWidth(326)
    promptText:SetJustifyH("LEFT")
    tradePromptFrame.promptText = promptText

    local fillAllBtn = CreateModernButton(tradePromptFrame, 96, 20, "Fill All", THEME.green)
    fillAllBtn:SetPoint("TOPRIGHT", -34, -8)
    fillAllBtn:SetScript("OnClick", function()
        local target = tradePromptFrame.targetName
        if not target or not VM.Fulfillment then return end
        if tradePromptFrame.hasOrders then
            VM.Fulfillment:PopulateTradeAll(target)
        elseif VM.Delivery then
            VM.Delivery:WhisperDebtReminder(target)
        end
        UI:RefreshRequests()
    end)
    fillAllBtn:HookScript("OnEnter", function(selfBtn)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
        GameTooltip:SetText(tradePromptFrame.hasOrders
            and "Place all prepared orders for this member in the trade and whisper the total to pay (incl. older debt)."
            or "Whisper the member how much they still owe.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    fillAllBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    tradePromptFrame.fillAllBtn = fillAllBtn

    tradePromptFrame.scroll = CreateScrollArea(tradePromptFrame, -62, 8)
    tradePromptFrame.scroll.content:SetSize(312, 1)
end

function UI:ShowTradeFulfillmentPrompt(targetName, orders, outstanding)
    if not tradePromptFrame then self:CreateTradeFulfillmentPrompt() end
    orders = orders or {}
    outstanding = tonumber(outstanding) or 0
    if #orders == 0 and outstanding <= 0 then
        tradePromptFrame:Hide()
        return
    end
    tradePromptFrame.targetName = targetName
    tradePromptFrame.hasOrders = (#orders > 0)
    tradePromptFrame.fillAllBtn:SetText(#orders > 0 and "Fill All" or "Remind")

    tradePromptFrame:ClearAllPoints()
    if TradeFrame and TradeFrame:IsVisible() then
        tradePromptFrame:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 6, 0)
    else
        tradePromptFrame:SetPoint("TOP", 0, -140)
    end

    local countWord = (#orders == 1) and "a prepared request" or string.format("%d prepared requests", #orders)
    local debtTxt = (outstanding > 0) and string.format("  |cffff5555Still owes %s from earlier.|r", VM:FormatMoney(outstanding)) or ""
    if #orders > 0 then
        tradePromptFrame.promptText:SetText(string.format("%s has %s in your inventory. Fulfill now?%s",
            VM:ColorizeName(targetName), countWord, debtTxt))
    else
        tradePromptFrame.promptText:SetText(string.format("%s has no prepared orders.%s", VM:ColorizeName(targetName), debtTxt))
    end

    local content = tradePromptFrame.scroll.content
    for _, r in ipairs(tradePromptFrame.scroll.rows) do r:Hide() end

    local y = 0
    for idx, req in ipairs(orders) do
        local row = tradePromptFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(312, 36)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.line1:SetPoint("TOPLEFT", 6, -4)
            row.line1:SetWidth(220)
            row.line1:SetJustifyH("LEFT")

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", 6, -19)
            row.line2:SetWidth(220)
            row.line2:SetJustifyH("LEFT")

            row.fillBtn = CreateModernButton(row, 74, 22, "Fill Trade", THEME.green)
            row.fillBtn:SetPoint("RIGHT", -4, 0)
            row.fillBtn:SetScript("OnClick", function()
                local r = row.reqData
                if r and VM.Fulfillment then
                    VM.Fulfillment:PopulateTrade(r)
                    VM.Fulfillment.fulfillStarted[r.id] = true
                    UI:RefreshRequests()
                end
            end)
            row.fillBtn:HookScript("OnEnter", function(selfBtn)
                GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
                GameTooltip:SetText("Place items/gold in Trade window and whisper member the amount due")
                GameTooltip:Show()
            end)
            row.fillBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

            tradePromptFrame.scroll.rows[idx] = row
        end

        local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        row.reqData = req
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()

        if req.isGoldRequest then
            local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
            row.line1:SetText(string.format("|cffffd700Gold Request:|r %s", VM:FormatMoney(gAmt)))
            row.line2:SetText(req.reason or "Guild expense")
        else
            local due = VM.Fulfillment and VM.Fulfillment:GetExpectedMemberPayment(req) or 0
            row.line1:SetText(string.format("%dx %s", req.count or 1, req.itemLink or req.itemName or "Item"))
            row.line2:SetText(due > 0 and ("Member pays: " .. VM:FormatMoneyShort(due)) or "Free-for-All (No payment)")
        end

        y = y + 38
    end

    content:SetHeight(math.max(1, y))
    tradePromptFrame:SetHeight(math.min(250, math.max(115, y + 76)))
    tradePromptFrame:Show()
end

function UI:HideTradeFulfillmentPrompt()
    if tradePromptFrame then tradePromptFrame:Hide() end
end

--------------------------------------------------------------------------------
-- RELOG REMINDER POPUP (UNFULFILLED PREPARED REQUESTS)
--------------------------------------------------------------------------------
function UI:ShowResetGuildConfirm()
    if not VM:IsAdmin() then
        VM:Print("|cffff4444Only the Guild Master or the guild's officer rank can reset guild data.|r")
        return
    end
    local step = VM:IsGuildMaster() and "You are the Guild Master: the reset happens immediately."
        or "Step 1 of 2: the Guild Master must approve before anything is deleted."
    if StaticPopup_Show then StaticPopup_Show("VAULTMANAGER_RESET_REQUEST", step) end
end

function UI:ShowResetApproval(request)
    if not request or not VM:IsGuildMaster() then return end
    if StaticPopup_Show then
        local dlg = StaticPopup_Show("VAULTMANAGER_RESET_APPROVE", request.by or "An officer")
        if dlg then dlg.data = { id = request.id } end
    end
end

-- Small reminder shown to officers at the Guild Bank when auto-open is off (or as a fallback)
local bankReminderFrame
function UI:ShowBankReminder(pendingCount, approvedCount, preparedCount)
    if not bankReminderFrame then
        bankReminderFrame = CreateFrame("Frame", "VaultManagerBankReminder", UIParent, "BackdropTemplate")
        bankReminderFrame:SetSize(330, 64)
        bankReminderFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
        bankReminderFrame:SetFrameStrata("DIALOG")
        bankReminderFrame:SetClampedToScreen(true)
        bankReminderFrame:SetMovable(true)
        bankReminderFrame:EnableMouse(true)
        bankReminderFrame:RegisterForDrag("LeftButton")
        bankReminderFrame:SetScript("OnDragStart", bankReminderFrame.StartMoving)
        bankReminderFrame:SetScript("OnDragStop", bankReminderFrame.StopMovingOrSizing)
        ApplyModernBackdrop(bankReminderFrame, THEME.bg, THEME.gold)
        bankReminderFrame.text = bankReminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bankReminderFrame.text:SetPoint("TOPLEFT", 10, -10)
        bankReminderFrame.text:SetWidth(310)
        bankReminderFrame.text:SetJustifyH("LEFT")
        local openBtn = CreateModernButton(bankReminderFrame, 120, 20, "Open Requests", THEME.accent)
        openBtn:SetPoint("BOTTOMLEFT", 10, 8)
        openBtn:SetScript("OnClick", function()
            bankReminderFrame:Hide()
            UI:OpenToRequestsTab()
        end)
        local closeBtn = CreateModernButton(bankReminderFrame, 60, 20, "Dismiss", THEME.border)
        closeBtn:SetPoint("BOTTOMRIGHT", -10, 8)
        closeBtn:SetScript("OnClick", function() bankReminderFrame:Hide() end)
        bankReminderFrame.elapsed = 0
        bankReminderFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
            selfFrame.elapsed = selfFrame.elapsed + elapsed
            if selfFrame.elapsed > 20 then selfFrame:Hide() end
        end)
    end
    local parts = {}
    if (pendingCount or 0) > 0 then table.insert(parts, string.format("|cffffcc33%d pending|r", pendingCount)) end
    if (approvedCount or 0) > 0 then table.insert(parts, string.format("|cff26a6f2%d approved|r", approvedCount)) end
    if (preparedCount or 0) > 0 then table.insert(parts, string.format("|cff44dd77%d prepared by you|r", preparedCount)) end
    bankReminderFrame.text:SetText("|cff26a6f2Vault Manager|r — Guild Bank requests: " .. table.concat(parts, ", "))
    bankReminderFrame.elapsed = 0
    bankReminderFrame:Show()
end

function UI:CreateRelogReminderFrame()
    relogReminderFrame = CreateFrame("Frame", "VaultManagerRelogReminder", UIParent, "BackdropTemplate")
    relogReminderFrame:SetSize(400, 220)
    relogReminderFrame:SetPoint("TOP", 0, -130)
    relogReminderFrame:SetFrameStrata("DIALOG")
    relogReminderFrame:SetFrameLevel(195)
    relogReminderFrame:SetClampedToScreen(true)
    relogReminderFrame:SetMovable(true)
    relogReminderFrame:EnableMouse(true)
    relogReminderFrame:RegisterForDrag("LeftButton")
    relogReminderFrame:SetScript("OnDragStart", relogReminderFrame.StartMoving)
    relogReminderFrame:SetScript("OnDragStop", relogReminderFrame.StopMovingOrSizing)
    ApplyModernBackdrop(relogReminderFrame, THEME.bg, THEME.gold)
    relogReminderFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerRelogReminder")

    local title = relogReminderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cffffcc33Vault Manager — Unfulfilled Prepared Requests|r")

    local closeBtn = CreateModernButton(relogReminderFrame, 20, 20, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() relogReminderFrame:Hide() end)

    local sub = relogReminderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 14, -34)
    sub:SetWidth(372)
    sub:SetJustifyH("LEFT")
    sub:SetText("You still have Guild Bank items/gold withdrawn for delivery:")

    relogReminderFrame.scroll = CreateScrollArea(relogReminderFrame, -54, 42)
    relogReminderFrame.scroll.content:SetSize(362, 1)

    local openBtn = CreateModernButton(relogReminderFrame, 120, 24, "Open Requests", THEME.accent)
    openBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    openBtn:SetScript("OnClick", function()
        relogReminderFrame:Hide()
        UI:OpenToRequestsTab()
    end)

    local dismissBtn = CreateModernButton(relogReminderFrame, 80, 24, "Dismiss")
    dismissBtn:SetPoint("RIGHT", openBtn, "LEFT", -8, 0)
    dismissBtn:SetScript("OnClick", function() relogReminderFrame:Hide() end)
end

function UI:ShowRelogPreparedReminder(orders)
    if not relogReminderFrame then self:CreateRelogReminderFrame() end
    if not orders or #orders == 0 then return end

    local content = relogReminderFrame.scroll.content
    for _, r in ipairs(relogReminderFrame.scroll.rows) do r:Hide() end

    local y = 0
    for idx, req in ipairs(orders) do
        local row = relogReminderFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(362, 24)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            relogReminderFrame.scroll.rows[idx] = row
        end
        local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()

        if req.isGoldRequest then
            local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
            row.label:SetText(string.format("%s — |cffffd700Gold (%s)|r (%s)",
                VM:ColorizeName(req.requester), VM:FormatMoneyShort(gAmt), req.reason or "Guild expense"))
        else
            row.label:SetText(string.format("%s — %dx %s",
                VM:ColorizeName(req.requester), req.count or 1, req.itemLink or req.itemName or "Item"))
        end
        y = y + 26
    end

    content:SetHeight(math.max(1, y))
    relogReminderFrame:SetHeight(math.min(250, math.max(150, y + 106)))
    relogReminderFrame:Show()
end

--------------------------------------------------------------------------------
-- NAVIGATION & MASTER REFRESH
--------------------------------------------------------------------------------
function UI:UpdateScanStatusButton()
    if not mainFrame or not mainFrame.scanStatusBtn then return end
    local btn = mainFrame.scanStatusBtn
    if VM.Comms and VM.Comms.GetSyncButtonStatus then
        local _, text, color, tooltip = VM.Comms:GetSyncButtonStatus()
        btn:SetText(text)
        btn.customBg = color
        btn:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
        SetButtonAccent(btn, color)
        btn.tooltipText = tooltip
    elseif VM.BankScanner then
        local _, text, color = VM.BankScanner:GetScanStatus()
        btn:SetText(text)
        btn.customBg = color
        btn:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
    end
end

function UI:RefreshAllTabs()
    self:RefreshInventory()
    self:RefreshRequests()
    self:RefreshLedger()
    self:RefreshRanking()
    self:RefreshRoster()
    self:RefreshSettings()
end

function UI:SelectTab(tabIndex)
    if not tabIndex or tabIndex < 1 or tabIndex > 6 then return end
    STATE.currentTab = tabIndex
    HideAllPopups()
    self:RefreshAll()
end
UI.ShowTab = UI.SelectTab

function UI:UpdateRoleBadge()
    local badge = mainFrame and mainFrame.roleBadge
    if not badge then return end
    if VM:IsAdmin() then
        badge.text:SetText("|cffffaa00Officer|r |cff888888·|r |cffffd700Admin|r")
        badge.tip = "You have full access: officer functions (approve, withdraw, deliver, Ledger corrections) and guild configuration (tab rules, officer ranks, guild reset)."
    elseif VM:IsOfficer() then
        badge.text:SetText("|cffffaa00Officer|r")
        badge.tip = "You can approve, withdraw and deliver requests and correct the Ledger. Guild configuration (tab rules, officer ranks, reset) needs the Guild Master or the guild's officer rank."
    else
        badge.text:SetText("|cff26a6f2Member|r")
        badge.tip = "You can browse the vault, request items and gold, cancel your own requests and follow the Ledger and Ranking. Officer buttons are hidden or greyed out."
    end
end

function UI:RefreshAll()
    self:UpdateRoleBadge()
    if VM.Minimap and VM.Minimap.UpdateBadge then
        VM.Minimap:UpdateBadge()
    end
    self:UpdateRequestsTabBadge()

    if mailPanelFrame and mailPanelFrame:IsShown() and VM.Fulfillment then
        local mine = VM.Fulfillment:GetMyPreparedOrders()
        local mailOpen = VM.Fulfillment.isMailOpen or (MailFrame and MailFrame:IsVisible())
        if #mine > 0 and mailOpen then
            self:ShowMailFulfillmentPanel(mine)
        else
            mailPanelFrame:Hide()
        end
    end

    if not mainFrame or not mainFrame:IsShown() then return end
    if not mainFrame.navButtons or not mainFrame.panels or not mainFrame.scanInfo then return end

    if VM.isUnguilded then
        mainFrame.scanInfo:SetText("Not in a guild")
        self:UpdateScanStatusButton()
        for i = 1, 6 do
            if mainFrame.panels[i] then
                mainFrame.panels[i]:Hide()
            end
        end
        return
    end

    self:UpdateScanStatusButton()

    if VM.newerVersionAvailable then
        mainFrame.scanInfo:SetText("|cffffcc33Update available|r")
    else
        local inv = VM.db and VM.db.inventory
        local lastScan = inv and inv.lastScan or 0
        if lastScan > 0 then
            local diff = math.max(0, time() - lastScan)
            local hours = math.floor(diff / 3600)
            local mins = math.floor((diff % 3600) / 60)
            local timeAgo = hours > 0 and string.format("%dh %dm", hours, mins) or string.format("%dm", mins)
            local scanBy = inv.lastScanBy or inv.scannedBy or "?"
            local syncedFrom = inv.lastSyncedFrom
            local syncNote = (syncedFrom and syncedFrom ~= "" and syncedFrom ~= VM:GetPlayerName() and syncedFrom ~= scanBy)
                and string.format(" (synced via %s)", syncedFrom) or ""

            local colorTag = "|cff44dd77"
            if diff > 86400 then colorTag = "|cffff5555"
            elseif diff > 21600 then colorTag = "|cffffcc33" end

            mainFrame.scanInfo:SetText(string.format("Vault scanned %s ago by %s%s", colorTag .. timeAgo .. "|r", scanBy, syncNote))
        else
            mainFrame.scanInfo:SetText("Vault not yet scanned")
        end
    end

    for i = 1, 6 do
        local btn = mainFrame.navButtons[i]
        local panel = mainFrame.panels[i]
        if btn and panel then
            if i == STATE.currentTab then
                if btn.activeBar then btn.activeBar:Show() end
                btn.customBg = { 0.14, 0.20, 0.28, 1 }
                btn:SetBackdropColor(0.14, 0.20, 0.28, 1)
                SetButtonAccent(btn, THEME.accent)
                panel:Show()
            else
                if btn.activeBar then btn.activeBar:Hide() end
                btn.customBg = nil
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                SetButtonAccent(btn, THEME.border)
                panel:Hide()
            end
        end
    end

    if STATE.currentTab ~= 1 and bankValDropdownFrame then
        bankValDropdownFrame:Hide()
    end

    if STATE.currentTab == 1 then self:RefreshInventory()
    elseif STATE.currentTab == 2 then self:RefreshRequests()
    elseif STATE.currentTab == 3 then self:RefreshLedger()
    elseif STATE.currentTab == 4 then self:RefreshRanking()
    elseif STATE.currentTab == 5 then self:RefreshRoster()
    elseif STATE.currentTab == 6 then self:RefreshSettings()
    end
end
