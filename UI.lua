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

local function ApplyDefaultWindowPosition()
    if not mainFrame then return end
    local prefs = GetUIPrefs()
    if prefs.windowPos then return end
    mainFrame:ClearAllPoints()
    if GuildBankFrame and GuildBankFrame:IsVisible() then
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

    if tx and tx.unitPriceAtTime and tx.unitPriceAtTime > 0 then
        GameTooltip:AddLine(" ")
        local isLocked
        if isHistoricalOverride ~= nil then
            isLocked = isHistoricalOverride and true or false
        else
            local uiPrefs = GetUIPrefs()
            isLocked = (uiPrefs.rankingPriceMode == "locked")
        end
        local lockedTotal = tx.unitPriceAtTime * (tx.count or 1)
        local curPrice = (tx.itemID and tx.itemID > 0) and (VM:GetEffectiveLivePrice(tx.itemID, tx.itemLink, tx.unitPriceAtTime) or 0) or tx.unitPriceAtTime
        local curTotal = curPrice * (tx.count or 1)

        if isLocked then
            GameTooltip:AddLine(string.format("Locked Value (at time): %s (Active)", VM:FormatMoney(lockedTotal)), 0.9, 0.8, 0.2)
            GameTooltip:AddLine(string.format("Current AH Value: %s", VM:FormatMoney(curTotal)), 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(string.format("Locked Value (at time): %s", VM:FormatMoney(lockedTotal)), 0.6, 0.6, 0.6)
            GameTooltip:AddLine(string.format("Current AH Value: %s (Active)", VM:FormatMoney(curTotal)), 0.2, 0.8, 0.9)
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

function UI:OpenToRequestsTab()
    if not mainFrame then self:CreateMainFrame() end
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
function UI:CreateRequestsHelpModal()
    requestsHelpFrame = CreateFrame("Frame", "VaultManagerRequestsHelpModal", UIParent, "BackdropTemplate")
    requestsHelpFrame:SetSize(480, 390)
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
        "• |cff999999HISTORY|r — Fulfilled, rejected, cancelled, or written off (pruned after 30 days).\n\n" ..
        "|cff26a6f2Officer Actions|r\n" ..
        "• |cff44dd77Approve|r — Accepts a pending request and reserves Vault stock.\n" ..
        "• |cffff5555Reject|r — Declines a pending request without logging to the Ledger.\n" ..
        "• |cff26a6f2Prepare|r — Withdraws items/gold from the open Guild Bank into your bags and assigns delivery to you. Open Mail or Trade with the member to fill automatically.\n" ..
        "• |cff44dd77Complete|r — Marks the request delivered and logs it to the Ledger. (Mail, Trade, and direct Guild Bank withdrawals also auto-complete.)\n" ..
        "• |cffccccccRelease|r — Returns a prepared order back to APPROVED if you put items back.\n" ..
        "• |cffff5555Cancel|r — Cancels an approved/prepared request and releases stock.\n" ..
        "• |cffff5555Write Off|r — Available if the officer holding a prepared order left the guild; charges 100% value to the departed officer."
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
            VM.Ledger:RecordGoldDeposit(recipNorm, totalP, "MANUAL_ASSIGN_PAYMENT", recipNorm, mainName)
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
    local priceMode = uiPrefs.rankingPriceMode or "live"
    local sortBy = uiPrefs.rankingSortBy or "net"
    local sortDir = uiPrefs.rankingSortDir or "desc"
    local period = uiPrefs.rankingPeriod or "ALL"
    local hideOff = uiPrefs.hideOfficers or false
    local showLeg = uiPrefs.showLegacyRanking ~= false
    local ranked = VM.Ranking:GetRankingData(sortBy, sortDir, priceMode, period, hideOff, showLeg)

    local function StripColor(str)
        return tostring(str or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end

    local basisDesc = (priceMode == "locked") and "Historical / Locked at Time" or "Live AH"
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
    mainFrame:SetScript("OnKeyDown", function(_, key)
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

    local prefs = GetUIPrefs()
    if prefs.uiScale then
        mainFrame:SetScale(prefs.uiScale)
    end
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
        mainFrame:Hide()
        HideAllPopups()
    end)

    mainFrame.scanInfo = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mainFrame.scanInfo:SetPoint("RIGHT", closeBtn, "LEFT", -12, 0)
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
    scanBtn:SetScript("OnClick", function()
        if VM.BankScanner and VM.BankScanner.ForceScan then
            VM.BankScanner:ForceScan()
            VM:Print("Scanning Guild Bank tabs and logs...")
        end
    end)
    panel.scanBtn = scanBtn

    local bankValBtn = CreateModernButton(panel, 145, 24, "Bank Value: 0g (v)", THEME.accent)
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
        local avail = row.available or 1
        local curr = row.selectedQty or 1
        local stateKey = row.qtyStateKey
        UI:OpenQtyPicker(selfBtn, avail, curr, function(chosen)
            if stateKey then
                STATE.selectedVaultQty[stateKey] = chosen
            end
            UI:RefreshInventory()
        end)
    end)

    row.reqBtn:SetScript("OnClick", function()
        if not row.itemData then return end
        local qty = row.selectedQty or 1
        VM.Fulfillment:CreateRequest(row.tabIndex, row.itemKey, qty)
    end)

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

                    local qtyStateKey = tostring(STATE.selectedBankTab) .. ":" .. tostring(itemKey)
                    row.qtyStateKey = qtyStateKey
                    local selectedQty = tonumber(STATE.selectedVaultQty[qtyStateKey]) or 1
                    if available > 0 and selectedQty > available then
                        selectedQty = available
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

                    if reserved > 0 then
                        row.stockText:SetText(string.format("Avail: |cff44dd77%d|r |cff888888(Res:%d)|r", available, reserved))
                    else
                        row.stockText:SetText(string.format("Stock: |cff44dd77%d|r", available))
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

                    if rule.mode == "LOCKED" or available <= 0 then
                        row.reqBtn:SetModernEnabled(false)
                        row.qtyBtn:Hide()
                    else
                        row.reqBtn:SetModernEnabled(true)
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
        local keys = (panel.visibleSections and #panel.visibleSections > 0) and panel.visibleSections or { "PENDING", "APPROVED", "PREPARED", "HISTORY" }
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

    local summaryText = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("RIGHT", toggleAllBtn, "LEFT", -10, 0)
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

    -- Right-aligned 3-column action buttons (no gap on 2-button rows)
    row.btn1 = CreateModernButton(row, 76, 22, "", THEME.accent)
    row.btn1:SetPoint("LEFT", 490, 0)

    row.btn2 = CreateModernButton(row, 76, 22, "", THEME.green)
    row.btn2:SetPoint("LEFT", 572, 0)

    row.btn3 = CreateModernButton(row, 70, 22, "", THEME.red)
    row.btn3:SetPoint("LEFT", 654, 0)

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
    AttachBtnTooltip(row.btn1)
    AttachBtnTooltip(row.btn2)
    AttachBtnTooltip(row.btn3)

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
        if actionKey == "APPROVE" then
            VM.Fulfillment:ApproveRequest(req.id)
        elseif actionKey == "REJECT" or actionKey == "CANCEL" then
            VM.Fulfillment:RejectRequest(req.id)
        elseif actionKey == "PREPARE" then
            VM.Fulfillment:PrepareRequest(req.id)
        elseif actionKey == "COMPLETE" then
            VM.Fulfillment:CompleteRequest(req.id)
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

    row.btn1:SetScript("OnClick", function(selfBtn) ExecuteAction(selfBtn.actionKey, row.reqData) end)
    row.btn2:SetScript("OnClick", function(selfBtn) ExecuteAction(selfBtn.actionKey, row.reqData) end)
    row.btn3:SetScript("OnClick", function(selfBtn) ExecuteAction(selfBtn.actionKey, row.reqData) end)

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
        HISTORY = {},
    }

    for _, req in pairs(VM.db.requests or {}) do
        if req.status == "PENDING" then
            table.insert(buckets.PENDING, req)
        elseif req.status == "APPROVED" then
            table.insert(buckets.APPROVED, req)
        elseif req.status == "PREPARED" then
            table.insert(buckets.PREPARED, req)
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
    table.sort(buckets.HISTORY, function(a, b)
        return (a.completedAt or a.updatedAt or a.createdAt or 0) > (b.completedAt or b.updatedAt or b.createdAt or 0)
    end)

    if panel.summaryText then
        panel.summaryText:SetText(string.format("|cffffcc33Pending: %d|r  |  |cff26a6f2Approved: %d|r  |  |cff44dd77Prepared: %d|r  |  |cff888888History: %d|r",
            #buckets.PENDING, #buckets.APPROVED, #buckets.PREPARED, #buckets.HISTORY))
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

                    -- Line 1: Main info
                    if req.isGoldRequest then
                        local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                        local catLbl = (VM.Ledger and VM.Ledger.GetGuildCategoryLabel and VM.Ledger:GetGuildCategoryLabel(req.guildCategory)) or "Raid"
                        local catTag = string.format(" |cff26a6f2[%s]|r", catLbl)
                        local reasonTxt = (req.reason and req.reason ~= "") and (" — " .. req.reason) or ""
                        local leftTag = prepLeftGuild and " |cffff4444[OFFICER LEFT]|r" or ""
                        row.info:SetText(string.format("[%s]  %s  —  |cffffd700Gold Request:|r%s %s|cffcccccc%s|r%s",
                            statusColors[req.status] or req.status,
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
                        row.info:SetText(string.format("[%s]  %s  —  %dx %s%s%s",
                            statusColors[req.status] or req.status,
                            VM:ColorizeName(req.requester),
                            req.count or 1,
                            req.itemLink or req.itemName or "Item",
                            priceNote,
                            leftTag))
                    end

                    -- Line 2: Timestamps & Officer metadata
                    local metaParts = {}
                    if req.createdAt and req.createdAt > 0 then
                        table.insert(metaParts, "Requested: " .. date("%d/%m %H:%M", req.createdAt))
                    end
                    if req.status == "REJECTED" then
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
                    row.meta:SetText("|cff999999" .. table.concat(metaParts, "  |  ") .. "|r")

                    -- Right-aligned action buttons (Officers only)
                    row.btn1:Hide()
                    row.btn2:Hide()
                    row.btn3:Hide()
                    row.btn1.actionKey = nil
                    row.btn2.actionKey = nil
                    row.btn3.actionKey = nil
                    row.btn1.tooltipText = nil
                    row.btn2.tooltipText = nil
                    row.btn3.tooltipText = nil

                    local textWidth = 710

                    if isOff then
                        if req.status == "PENDING" then
                            SetButtonAccent(row.btn2, THEME.green)
                            row.btn2:SetText("Approve")
                            row.btn2.actionKey = "APPROVE"
                            row.btn2.tooltipText = "Approve request and reserve stock in the Vault."
                            row.btn2:Show()

                            SetButtonAccent(row.btn3, THEME.red)
                            row.btn3:SetText("Reject")
                            row.btn3.actionKey = "REJECT"
                            row.btn3.tooltipText = "Decline this pending request without logging to the Ledger."
                            row.btn3:Show()
                            textWidth = 554
                        elseif req.status == "APPROVED" then
                            SetButtonAccent(row.btn1, THEME.accent)
                            row.btn1:SetText("Prepare")
                            row.btn1.actionKey = "PREPARE"
                            row.btn1.tooltipText = "Withdraw items/gold from the open Guild Bank and assign delivery to you."
                            row.btn1:Show()

                            SetButtonAccent(row.btn2, THEME.green)
                            row.btn2:SetText("Complete")
                            row.btn2.actionKey = "COMPLETE"
                            row.btn2.tooltipText = "Mark delivered manually and log to the Ledger."
                            row.btn2:Show()

                            SetButtonAccent(row.btn3, THEME.red)
                            row.btn3:SetText("Cancel")
                            row.btn3.actionKey = "CANCEL"
                            row.btn3.tooltipText = "Cancel this approved request and release reserved stock."
                            row.btn3:Show()
                            textWidth = 472
                        elseif req.status == "PREPARED" then
                            if prepLeftGuild then
                                SetButtonAccent(row.btn2, THEME.red)
                                row.btn2:SetText("Write Off")
                                row.btn2.actionKey = "WRITEOFF"
                                row.btn2.tooltipText = "Officer left the guild. Write off and charge 100% value to the departed officer."
                                row.btn2:Show()

                                SetButtonAccent(row.btn3, THEME.border)
                                row.btn3:SetText("Release")
                                row.btn3.actionKey = "RELEASE"
                                row.btn3.tooltipText = "Return this order to APPROVED (if items were returned to the bank)."
                                row.btn3:Show()
                                textWidth = 554
                            elseif IsSameOfficerName(req.preparedBy, me) then
                                SetButtonAccent(row.btn1, THEME.green)
                                row.btn1:SetText("Complete")
                                row.btn1.actionKey = "COMPLETE"
                                row.btn1.tooltipText = "Mark delivered manually and log to the Ledger."
                                row.btn1:Show()

                                SetButtonAccent(row.btn2, THEME.border)
                                row.btn2:SetText("Release")
                                row.btn2.actionKey = "RELEASE"
                                row.btn2.tooltipText = "Return order to APPROVED if you put the items/gold back in the bank."
                                row.btn2:Show()

                                SetButtonAccent(row.btn3, THEME.red)
                                row.btn3:SetText("Cancel")
                                row.btn3.actionKey = "CANCEL"
                                row.btn3.tooltipText = "Cancel this prepared request."
                                row.btn3:Show()
                                textWidth = 472
                            end
                        end
                    end

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
