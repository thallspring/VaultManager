local _, VM = ...
VM.UI = {}
local UI = VM.UI

local mainFrame
local popupFrame
local rosterPickerFrame
local qtyPickerFrame
local goldReqModalFrame
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
    selectedAssignItem = nil,
    selectedAssignTab = 1,
    manualLedgerDonor = "",
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
    btnBg = { 0.16, 0.18, 0.23, 1.0 },
    btnHover = { 0.22, 0.26, 0.34, 1.0 },
    btnDisabled = { 0.10, 0.11, 0.13, 0.6 },
}

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
    }
    for k, v in pairs(defaults) do
        if VM.db.uiPrefs[k] == nil then
            VM.db.uiPrefs[k] = v
        end
    end
    return VM.db.uiPrefs
end

local function ShowItemTooltip(selfFrame, itemLink, itemID, itemName, tx)
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
        local uiPrefs = GetUIPrefs()
        local isLocked = (uiPrefs.rankingPriceMode == "locked")
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
            self:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            local bd = self.accentColor or THEME.border
            self:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.85)
        end
    end)

    btn.SetText = function(self, t) self.label:SetText(t) end
    btn.SetModernEnabled = function(self, enabled)
        if enabled then
            self:Enable()
            self:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
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
    if exportModalFrame then exportModalFrame:Hide() end
    if assignModalFrame then assignModalFrame:Hide() end
    if rankingPeriodDropdownFrame then rankingPeriodDropdownFrame:Hide() end
    if bankValDropdownFrame then bankValDropdownFrame:Hide() end
end

function UI:Init()
    self:CreateMainFrame()
    self:CreateOfficerPopupFrame()
    self:CreateRosterPickerFrame()
    self:CreateQtyPickerFrame()
    self:CreateGoldRequestModal()
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
        mainFrame:Show()
        self:RefreshAll()
    end
end

function UI:UpdateRequestsTabBadge()
    if not mainFrame or not mainFrame.navButtons or not mainFrame.navButtons[2] then return end
    local openCount = 0
    if VM.Minimap and VM.Minimap.GetOpenRequestCounts then
        local pendingCount, approvedCount = VM.Minimap:GetOpenRequestCounts()
        openCount = (pendingCount or 0) + (approvedCount or 0)
    elseif VM.db and VM.db.requests and not VM.isUnguilded then
        local isOff = VM:IsOfficer()
        local myMain = VM:GetMainFor(VM:GetPlayerName())
        for _, req in pairs(VM.db.requests) do
            if req.status == "PENDING" or req.status == "APPROVED" then
                if isOff then
                    openCount = openCount + 1
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
-- GOLD REQUEST MODAL
--------------------------------------------------------------------------------
function UI:CreateGoldRequestModal()
    goldReqModalFrame = CreateFrame("Frame", "VaultManagerGoldRequestModal", UIParent, "BackdropTemplate")
    goldReqModalFrame:SetSize(380, 210)
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

    local amtLbl = goldReqModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amtLbl:SetPoint("TOPLEFT", 14, -74)
    amtLbl:SetText("Amount:")

    local goldBox = CreateModernEditBox(goldReqModalFrame, 74, 24, true)
    goldBox:SetPoint("TOPLEFT", 80, -70)
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
    reasonLbl:SetPoint("TOPLEFT", 14, -110)
    reasonLbl:SetText("Reason:")

    local reasonBox = CreateModernEditBox(goldReqModalFrame, 280, 24, false)
    reasonBox:SetPoint("TOPLEFT", 80, -106)
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
        VM.Fulfillment:CreateGoldRequest(copper, reason)
        goldReqModalFrame:Hide()
    end)

    local cancelBtn = CreateModernButton(goldReqModalFrame, 84, 26, "Cancel")
    cancelBtn:SetPoint("RIGHT", submitBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", function() goldReqModalFrame:Hide() end)
end

function UI:OpenGoldRequestModal()
    if not goldReqModalFrame then self:CreateGoldRequestModal() end
    goldReqModalFrame.goldBox:SetText("")
    goldReqModalFrame.silverBox:SetText("")
    goldReqModalFrame.reasonBox:SetText("")
    goldReqModalFrame.reasonBox.placeholder:Show()
    goldReqModalFrame:Show()
    goldReqModalFrame.goldBox:SetFocus()
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
        UI:OpenRosterPicker(btn, true, function(chosen)
            STATE.selectedAssignRecipient = chosen
            recBtn:SetText(chosen == "GUILD" and "|cff26a6f2[Guild Bank / Guild]|r" or chosen)
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
-- CUSTOM SEARCHABLE ROSTER DROPDOWN (WITH OPTIONAL "GUILD" ENTRY)
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
                local cb = rosterPickerFrame.onSelect
                rosterPickerFrame:Hide()
                if cb and chosen then cb(chosen) end
            end)
            rosterPickerFrame.scroll.rows[idx] = row
        end
        return row
    end

    if rosterPickerFrame.includeGuildOption then
        if filter == "" or ("guild bank / guild"):find(filter, 1, true) then
            local gRow = AcquirePickerRow()
            gRow.entryName = "GUILD"
            gRow.baseBg = THEME.rowSpecial
            gRow:SetBackdropColor(gRow.baseBg[1], gRow.baseBg[2], gRow.baseBg[3], gRow.baseBg[4])
            gRow:ClearAllPoints()
            gRow:SetPoint("TOPLEFT", 0, -y)
            gRow.label:SetText("|cff26a6f2[Guild Bank / Guild]|r")
            gRow:Show()
            y = y + 24
        end
    end

    for _, name in ipairs(names) do
        if filter == "" or name:lower():find(filter, 1, true) then
            local row = AcquirePickerRow()
            row.entryName = name
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

    mainFrame.scanStatusBtn = CreateModernButton(headerBar, 110, 22, "Scan Bank", { 0.25, 0.55, 0.85, 1 })
    mainFrame.scanStatusBtn:SetPoint("LEFT", title, "RIGHT", 14, 0)
    mainFrame.scanStatusBtn:SetScript("OnClick", function()
        VM.BankScanner:ForceScan()
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
        local anyCollapsed = false
        for _, catName in ipairs(CAT_ORDER) do
            if not STATE.vaultCategoryExpanded[catName] then
                anyCollapsed = true
                break
            end
        end
        for _, catName in ipairs(CAT_ORDER) do
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

    -- Fast-path: use cached category for all 6 valid categories (including Crafting Reagents & Other)
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

    -- Show only purchased bank tabs & ensure selectedBankTab points to a purchased tab
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
                btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                btn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            else
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            end
        end
    end

    local rule = VM:GetTabRule(STATE.selectedBankTab)
    if panel.ruleBannerBtn and panel.ruleBannerBtn.text then
        if rule.mode == "LOCKED" then
            panel.ruleBannerBtn.text:SetText("|cffff5555LOCKED TAB|r  |cff999999— Requests disabled|r")
        elseif rule.mode == "PERCENT" then
            panel.ruleBannerBtn.text:SetText(string.format("|cffffcc33MEMBER PRICE: %d%% OF AH (rounded, min 1g)|r  |cff999999— Paid on delivery|r", rule.percent or 50))
        else
            panel.ruleBannerBtn.text:SetText("|cff44dd77FREE-FOR-ALL|r  |cff999999— Free withdrawal (AH value tracked in ledger)|r")
        end
    end

    local content = panel.scroll.content
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    panel.scroll.catHeaders = panel.scroll.catHeaders or {}
    for _, h in pairs(panel.scroll.catHeaders) do h:Hide() end

    local tabData = inv.tabs[STATE.selectedBankTab]
    if not tabData or tabData.isPurchased == false then
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
    for _, catName in ipairs(CAT_ORDER) do
        table.sort(cats[catName], function(a, b) return (a.name or "") < (b.name or "") end)
    end

    if panel.toggleAllBtn then
        local anyCollapsed = false
        for _, catName in ipairs(CAT_ORDER) do
            if #cats[catName] > 0 and not STATE.vaultCategoryExpanded[catName] then
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

                    local reserved = VM:GetReservedCount(item.itemID, STATE.selectedBankTab)
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
function UI:BuildRequestsPanel(panel)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local reqGoldBtn = CreateModernButton(topBar, 120, 24, "+ Request Gold", { 0.90, 0.72, 0.20, 1 })
    reqGoldBtn:SetPoint("LEFT", 0, 0)
    reqGoldBtn:SetScript("OnClick", function()
        UI:OpenGoldRequestModal()
    end)
    panel.reqGoldBtn = reqGoldBtn

    local summaryText = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summaryText:SetPoint("RIGHT", 0, 0)
    summaryText:SetJustifyH("RIGHT")
    panel.summaryText = summaryText

    panel.scroll = CreateScrollArea(panel, -42, 8)
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

    row.btn1 = CreateModernButton(row, 76, 22, "", THEME.green)
    row.btn1:SetPoint("LEFT", 490, 0)

    row.btn2 = CreateModernButton(row, 76, 22, "", THEME.accent)
    row.btn2:SetPoint("LEFT", 572, 0)

    row.btn3 = CreateModernButton(row, 70, 22, "", THEME.red)
    row.btn3:SetPoint("LEFT", 654, 0)

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

    row.btn1:SetScript("OnClick", function()
        local r = row.reqData
        if not r then return end
        if r.status == "PENDING" then
            VM.Fulfillment:ApproveRequest(r.id)
        elseif r.status == "APPROVED" then
            VM.Fulfillment.activeOrder = r
            if r.isGoldRequest then
                VM:Print(string.format("Prepared gold request (%s) for |cffffff00%s|r. Open Mail or Trade to auto-fill!",
                    VM:FormatMoney(r.goldAmount or r.quotedTotalPrice or 0), r.requester))
            else
                VM:Print(string.format("Prepared %dx %s for |cffffff00%s|r. Open Mail or Trade to auto-fill!",
                    r.count or 1, r.itemLink or r.itemName or "Item", r.requester))
            end
        end
    end)

    row.btn2:SetScript("OnClick", function()
        local r = row.reqData
        if r and r.status == "APPROVED" then
            VM.Fulfillment:CompleteRequest(r.id)
        end
    end)

    row.btn3:SetScript("OnClick", function()
        local r = row.reqData
        if r and (r.status == "PENDING" or r.status == "APPROVED") then
            VM.Fulfillment:RejectRequest(r.id)
        end
    end)

    return row
end

local METHOD_LABELS = {
    BANK = " (Bank)",
    MAIL = " (Mail)",
    TRADE = " (Trade)",
}

function UI:RefreshRequests()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[2] then return end
    local panel = mainFrame.panels[2]
    if not panel or not panel.scroll then return end
    local content = panel.scroll.content
    if not content then return end

    self:UpdateRequestsTabBadge()

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    panel.scroll.secHeaders = panel.scroll.secHeaders or {}
    for _, h in pairs(panel.scroll.secHeaders) do h:Hide() end

    local buckets = {
        PENDING = {},
        APPROVED = {},
        HISTORY = {},
    }

    for _, req in pairs(VM.db.requests or {}) do
        if req.status == "PENDING" then
            table.insert(buckets.PENDING, req)
        elseif req.status == "APPROVED" then
            table.insert(buckets.APPROVED, req)
        else
            table.insert(buckets.HISTORY, req)
        end
    end

    local function SortNewest(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end
    table.sort(buckets.PENDING, SortNewest)
    table.sort(buckets.APPROVED, SortNewest)
    table.sort(buckets.HISTORY, function(a, b)
        return (a.completedAt or a.updatedAt or a.createdAt or 0) > (b.completedAt or b.updatedAt or b.createdAt or 0)
    end)

    if panel.summaryText then
        panel.summaryText:SetText(string.format("|cffffcc33Pending: %d|r  |  |cff26a6f2Approved: %d|r  |  |cff888888History: %d|r",
            #buckets.PENDING, #buckets.APPROVED, #buckets.HISTORY))
    end

    local sections = {
        { key = "PENDING", title = "Pending Approval", color = "|cffffcc33" },
        { key = "APPROVED", title = "Approved — Ready for Delivery", color = "|cff26a6f2" },
        { key = "HISTORY", title = "History — Fulfilled & Rejected", color = "|cff999999" },
    }

    local statusColors = {
        PENDING = "|cffffcc33PENDING|r",
        APPROVED = "|cff26a6f2APPROVED|r",
        FULFILLED = "|cff44dd77FULFILLED|r",
        REJECTED = "|cffff5555REJECTED|r",
    }

    local isOff = VM:IsOfficer()
    local y = 0
    local rowIdx = 0

    for _, sec in ipairs(sections) do
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

                    -- Line 1: Main info
                    if req.isGoldRequest then
                        local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
                        local reasonTxt = (req.reason and req.reason ~= "") and (" — " .. req.reason) or ""
                        row.info:SetText(string.format("[%s]  %s  —  |cffffd700Gold Request:|r %s|cffcccccc%s|r",
                            statusColors[req.status] or req.status,
                            VM:ColorizeName(req.requester),
                            VM:FormatMoney(gAmt),
                            reasonTxt))
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

                        row.info:SetText(string.format("[%s]  %s  —  %dx %s%s",
                            statusColors[req.status] or req.status,
                            VM:ColorizeName(req.requester),
                            req.count or 1,
                            req.itemLink or req.itemName or "Item",
                            priceNote))
                    end

                    -- Line 2: Timestamps & Officer metadata
                    local metaParts = {}
                    if req.createdAt and req.createdAt > 0 then
                        table.insert(metaParts, "Requested: " .. date("%d/%m %H:%M", req.createdAt))
                    end
                    if req.approvedBy and req.approvedBy ~= "" then
                        if req.status == "REJECTED" and (not req.approvedAt or req.approvedAt == 0) then
                            local rejTime = (req.completedAt and req.completedAt > 0) and (" " .. date("%d/%m %H:%M", req.completedAt)) or ""
                            table.insert(metaParts, string.format("Rejected%s by: %s", rejTime, VM:ColorizeName(req.approvedBy)))
                        else
                            table.insert(metaParts, "Approved by: " .. VM:ColorizeName(req.approvedBy))
                        end
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
                    end
                    row.meta:SetText("|cff999999" .. table.concat(metaParts, "  |  ") .. "|r")

                    -- Action buttons (Officers only)
                    row.btn1:Hide()
                    row.btn2:Hide()
                    row.btn3:Hide()

                    if isOff then
                        if req.status == "PENDING" then
                            SetButtonAccent(row.btn1, THEME.green)
                            row.btn1:SetText("Approve")
                            row.btn1:Show()

                            SetButtonAccent(row.btn3, THEME.red)
                            row.btn3:SetText("Reject")
                            row.btn3:Show()
                        elseif req.status == "APPROVED" then
                            SetButtonAccent(row.btn1, THEME.accent)
                            row.btn1:SetText("Prepare")
                            row.btn1:Show()

                            SetButtonAccent(row.btn2, THEME.green)
                            row.btn2:SetText("Complete")
                            row.btn2:Show()

                            SetButtonAccent(row.btn3, THEME.red)
                            row.btn3:SetText("Cancel")
                            row.btn3:Show()
                        end
                    end

                    y = y + 46
                end
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

-- === END OF PART 1 (PASTE PART 2 DIRECTLY BELOW THIS LINE IN STEP 8) ===
--------------------------------------------------------------------------------
-- TAB 3: LEDGER
--------------------------------------------------------------------------------
function UI:BuildLedgerPanel(panel)
    local uiPrefs = GetUIPrefs()

    -- Row 1: Search, Export & Officer Quick Gold Log
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(30)
    topBar:SetPoint("TOPLEFT", 10, -6)
    topBar:SetPoint("TOPRIGHT", -10, -6)

    local searchBox = CreateModernEditBox(topBar, 190, 22, false)
    searchBox:SetPoint("LEFT", 0, 0)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 6, 0)
    searchBox.placeholder:SetText("Filter member, item or note...")

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

    local exportBtn = CreateModernButton(topBar, 70, 22, "Export", THEME.accent)
    exportBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    exportBtn:SetScript("OnClick", function()
        UI:OpenExportModal()
    end)
    panel.exportBtn = exportBtn

    -- Officer manual gold container (shown/hidden dynamically in RefreshLedger)
    local officerBar = CreateFrame("Frame", nil, topBar)
    officerBar:SetSize(272, 24)
    officerBar:SetPoint("RIGHT", 0, 0)

    local memberBtn = CreateModernDropdown(officerBar, 128, 22, "Donor...")
    memberBtn:SetPoint("LEFT", 0, 0)
    memberBtn:SetScript("OnClick", function(btn)
        UI:OpenRosterPicker(btn, false, function(chosen)
            STATE.manualLedgerDonor = chosen
            btn:SetText(chosen == "GUILD" and "|cff26a6f2[Guild]|r" or chosen)
        end, true)
    end)
    panel.donorBtn = memberBtn

    local goldBox = CreateModernEditBox(officerBar, 52, 22, true)
    goldBox:SetPoint("LEFT", memberBtn, "RIGHT", 4, 0)
    goldBox.placeholder = goldBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    goldBox.placeholder:SetPoint("LEFT", 6, 0)
    goldBox.placeholder:SetText("Gold")
    goldBox:SetScript("OnTextChanged", function(eb)
        if eb:GetText() == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
    end)
    panel.goldBox = goldBox

    local addGoldBtn = CreateModernButton(officerBar, 82, 22, "+ Log Gold", THEME.green)
    addGoldBtn:SetPoint("LEFT", goldBox, "RIGHT", 4, 0)
    addGoldBtn:SetScript("OnClick", function()
        if not VM:IsOfficer() then return end
        local g = tonumber(goldBox:GetText()) or 0
        if STATE.manualLedgerDonor ~= "" and g > 0 then
            VM.Ledger:RecordGoldDeposit(STATE.manualLedgerDonor, g * 10000, "MANUAL_GOLD")
            VM:Print(string.format("Logged %dg donated by |cffffff00%s|r.", g, STATE.manualLedgerDonor))
            goldBox:SetText("")
            STATE.manualLedgerDonor = ""
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

    local priceToggle = CreateFrame("CheckButton", nil, filterStrip, "UICheckButtonTemplate")
    priceToggle:SetSize(20, 20)
    priceToggle:SetPoint("LEFT", 8, 0)
    priceToggle:SetChecked(uiPrefs.useHistoricalPrices or false)
    priceToggle.label = filterStrip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    priceToggle.label:SetPoint("LEFT", priceToggle, "RIGHT", 4, 0)
    priceToggle.label:SetText("Historical price")
    priceToggle:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.useHistoricalPrices = cb:GetChecked() and true or false
        UI:RefreshLedger()
    end)
    panel.priceToggle = priceToggle

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

    -- Header columns (fixed width for vertical scanning)
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

    -- Sub-row single text line
    row.subText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.subText:SetPoint("LEFT", 36, 0)
    row.subText:SetWidth(545)
    row.subText:SetJustifyH("LEFT")

    row.actionBtn = CreateModernButton(row, 108, 20, "Reassign", THEME.accent)
    row.actionBtn:SetPoint("RIGHT", -8, 0)

    row.deleteBtn = CreateModernButton(row, 20, 20, "X", THEME.red)
    row.deleteBtn:SetPoint("RIGHT", -8, 0)
    row.deleteBtn:Hide()

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
        if not tx then return end
        if row.actionMode == "ASSIGN_UNATTRIBUTED" then
            UI:OpenRosterPicker(selfBtn, false, function(chosenName)
                VM.Ledger:AssignUnattributed(tx.id, chosenName)
            end, true)
        elseif row.actionMode == "REASSIGN" then
            UI:OpenRosterPicker(selfBtn, false, function(chosenName)
                VM.Ledger:ReassignTransaction(tx.id, chosenName)
            end, true)
        end
    end)

    row.deleteBtn:SetScript("OnClick", function()
        local tx = row.txData
        if tx then
            VM.Ledger:DeleteTransaction(tx.id)
        end
    end)

    return row
end

local function LedgerGroupMatchesSearch(grp, q)
    if q == "" then return true end
    if grp.mainName and grp.mainName:lower():find(q, 1, true) then return true end
    if grp.mainName == "GUILD" and ("guild bank guild operations"):find(q, 1, true) then return true end
    for _, tx in ipairs(grp.transactions or {}) do
        if (tx.itemName and tx.itemName:lower():find(q, 1, true))
            or (tx.player and tx.player:lower():find(q, 1, true))
            or (tx.rawSender and tx.rawSender:lower():find(q, 1, true))
            or (tx.note and tx.note:lower():find(q, 1, true)) then
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

    local isOff = VM:IsOfficer()
    if panel.officerBar then
        if isOff then panel.officerBar:Show() else panel.officerBar:Hide() end
    end

    local uiPrefs = GetUIPrefs()
    if panel.priceToggle then panel.priceToggle:SetChecked(uiPrefs.useHistoricalPrices or false) end
    if panel.ffaToggle then panel.ffaToggle:SetChecked(uiPrefs.includeFFA ~= false) end
    if panel.hideLegacyCb then panel.hideLegacyCb:SetChecked(uiPrefs.hideLegacyLedger or false) end

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    if panel.scroll.legacyHeader then panel.scroll.legacyHeader:Hide() end

    local useHist = uiPrefs.useHistoricalPrices
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
            header.nameText:SetText(string.format("%s  %s", VM:ColorizeName(grp.mainName), entryCountStr))
            header.donatedText:SetText("Donated: " .. VM:FormatMoney(grp.totalInValue) .. goldSubNote)
            header.receivedText:SetText("Received: " .. VM:FormatMoney(grp.totalOutValue))
        end

        y = y + 30

        if isExpanded then
            for _, tx in ipairs(grp.transactions) do
                local showTx = true
                if q ~= "" and not grp.mainName:lower():find(q, 1, true) then
                    showTx = (tx.itemName and tx.itemName:lower():find(q, 1, true))
                        or (tx.player and tx.player:lower():find(q, 1, true))
                        or (tx.rawSender and tx.rawSender:lower():find(q, 1, true))
                        or (tx.note and tx.note:lower():find(q, 1, true))
                        or false
                end

                if showTx then
                    local sub = AcquireRow()
                    local subBg = THEME.rowOdd
                    local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                    local isItemTx = not isGold and (tx.itemLink ~= "SUMMARY") and (tx.type ~= "SUMMARY")

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

                    local dir
                    if tx.type == "SUMMARY" then
                        dir = "|cff8899aaSUMMARY|r"
                    elseif tx.type == "OUT" then
                        dir = isGold and "|cffff6666GOLD OUT|r" or "|cffff6666OUT|r"
                    else
                        dir = isGold and "|cffffd700GOLD IN|r" or "|cff44dd77IN|r"
                    end

                    local val = VM.Ledger:GetTransactionValue(tx, useHist)
                    local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                    local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED" and tx.player ~= "GUILD")
                        and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

                    local rawTag = ""
                    if tx.rawSender and tx.rawSender ~= "" and tx.rawSender ~= tx.player and tx.rawSender ~= "UNATTRIBUTED" then
                        local verb = (tx.type == "OUT") and "by" or "from"
                        rawTag = string.format(" |cffaaaaaa(%s %s)|r", verb, VM:ColorizeName(tx.rawSender))
                    end

                    local noteTag = (tx.note and tx.note ~= "") and (" |cffcccccc— " .. tx.note .. "|r") or ""

                    local ruleTag = ""
                    if tx.type == "OUT" and not isGold then
                        if tx.isFFA or tx.priceMode == "FREE" then
                            ruleTag = " |cff44dd77(FFA)|r"
                        elseif tx.priceMode == "PERCENT" or (tx.chargedUnitPrice ~= nil and tx.unitPriceAtTime and tx.chargedUnitPrice < tx.unitPriceAtTime and tx.chargedUnitPrice > 0) then
                            local pct = tx.pricePercent or 50
                            ruleTag = string.format(" |cff26a6f2(%d%% AH)|r", pct)
                        end
                    end

                    if tx.type == "SUMMARY" then
                        sub.subText:SetText(string.format("|cff999999%s|r [%s] %s — In: %s | Out: %s",
                            dateStr, dir, tx.itemName or "Monthly Summary",
                            VM:FormatMoney(tx.contributed or 0), VM:FormatMoney(tx.received or 0)))
                    elseif isGold then
                        sub.subText:SetText(string.format("|cff999999%s|r [%s]%s%s: %s%s",
                            dateStr, dir, charTag, rawTag, VM:FormatMoney(val), noteTag))
                    elseif grp.isLegacy then
                        sub.subText:SetText(string.format("|cff808080%s [%s]%s: %dx %s — %s%s|r",
                            dateStr, tx.type == "OUT" and "OUT" or "IN", charTag, tx.count or 1, tx.itemName or "Item", VM:FormatMoney(val), ruleTag))
                    else
                        sub.subText:SetText(string.format("|cff999999%s|r [%s]%s%s: %dx %s — %s%s%s",
                            dateStr, dir, charTag, rawTag, tx.count or 1, tx.itemLink or tx.itemName or "Item", VM:FormatMoney(val), ruleTag, noteTag))
                    end

                    local showDelete = isOff and (tx.isManual == true)
                    local showAction = false

                    if isOff and tx.type ~= "SUMMARY" then
                        if grp.mainName == "UNATTRIBUTED" then
                            sub.actionMode = "ASSIGN_UNATTRIBUTED"
                            sub.actionBtn:SetText("Assign Member")
                            showAction = true
                        elseif isGold or tx.type == "OUT" then
                            sub.actionMode = "REASSIGN"
                            sub.actionBtn:SetText("Reassign")
                            showAction = true
                        end
                    end

                    if showDelete then
                        sub.deleteBtn:Show()
                    end
                    if showAction then
                        sub.actionBtn:ClearAllPoints()
                        sub.actionBtn:SetPoint("RIGHT", showDelete and -32 or -8, 0)
                        sub.actionBtn:Show()
                        sub.subText:SetWidth(showDelete and 530 or 554)
                    else
                        sub.subText:SetWidth(showDelete and 650 or 680)
                    end

                    y = y + 25
                end
            end
        end
    end

    for _, grp in ipairs(primaryGroups) do
        RenderGroup(grp)
    end

    -- Collapsible Legacy Members section at bottom
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

    local histBtn = CreateModernButton(topBar, 110, 24, "Historical values")
    histBtn:SetPoint("LEFT", 0, 0)
    histBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "locked"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
        UI:RefreshRanking()
    end)
    panel.histBtn = histBtn

    local liveBtn = CreateModernButton(topBar, 105, 24, "Current values")
    liveBtn:SetPoint("LEFT", histBtn, "RIGHT", 4, 0)
    liveBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "live"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
        UI:RefreshRanking()
    end)
    panel.liveBtn = liveBtn

    local function UpdateBasisButtons()
        local mode = GetUIPrefs().rankingPriceMode or "live"
        if mode == "locked" then
            histBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
            histBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            histBtn.label:SetTextColor(1, 0.82, 0)
            liveBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            liveBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            liveBtn.label:SetTextColor(0.6, 0.6, 0.6)
        else
            liveBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
            liveBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            liveBtn.label:SetTextColor(1, 0.82, 0)
            histBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            histBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            histBtn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end
    panel.UpdateBasisButtons = UpdateBasisButtons
    UpdateBasisButtons()

    local exportBtn = CreateModernButton(topBar, 76, 24, "Export", THEME.accent)
    exportBtn:SetPoint("RIGHT", 0, 0)
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
    hideOfficersCb:SetPoint("LEFT", 185, 0)
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

    local periodBtn = CreateModernDropdown(filterStrip, 114, 22, "All-Time")
    periodBtn:SetPoint("LEFT", 300, 0)
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
    ffaRankCb:SetPoint("LEFT", 425, 0)
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

    local uiPrefs = GetUIPrefs()
    if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
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

    local priceMode = uiPrefs.rankingPriceMode or "live"
    local period = uiPrefs.rankingPeriod or "ALL"
    local hideOff = uiPrefs.hideOfficers or false
    local showLeg = uiPrefs.showLegacyRanking ~= false

    local ranked = VM.Ranking:GetRankingData(sortBy, sortDir, priceMode, period, hideOff, showLeg)

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
                local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                local isItemTx = not isGold and (tx.itemLink ~= "SUMMARY") and (tx.type ~= "SUMMARY")

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

                local dir = (tx.type == "OUT") and (isGold and "|cffff6666[GOLD OUT]|r" or "|cffff6666[OUT]|r")
                    or (isGold and "|cffffd700[GOLD IN]|r" or "|cff44dd77[IN]|r")
                local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                local itemDisplay = isGold and "Gold" or (tx.itemLink or tx.itemName or "Item")
                local lockedVal = VM.Ranking:GetTransactionValuation(tx, "locked")
                local liveVal = VM.Ranking:GetTransactionValuation(tx, "live")
                local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED")
                    and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

                local lockedDisplay, liveDisplay
                if priceMode == "locked" then
                    lockedDisplay = string.format("|cffffcc33Historical: %s (Active)|r", VM:FormatMoney(lockedVal))
                    liveDisplay = string.format("|cff888888Current: %s|r", VM:FormatMoney(liveVal))
                else
                    lockedDisplay = string.format("|cff888888Historical: %s|r", VM:FormatMoney(lockedVal))
                    liveDisplay = string.format("|cff26a6f2Current: %s (Active)|r", VM:FormatMoney(liveVal))
                end

                sub.detailText:SetText(string.format("|cff888888%s|r %s %s%s  —  %s  |  %s",
                    dateStr, dir, itemDisplay, charTag, lockedDisplay, liveDisplay))

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
    toggleAllBtn:SetScript("OnClick", function()
        local anyCollapsed = false
        for _, rk in ipairs(panel.visibleRankKeys or {}) do
            if not STATE.rosterRankExpanded[rk] then
                anyCollapsed = true
                break
            end
        end
        for _, rk in ipairs(panel.visibleRankKeys or {}) do
            STATE.rosterRankExpanded[rk] = anyCollapsed
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

function UI:BuildSettingsPanel(panel)
    -- Section 1: Guild Bank Tab Rules
    local ruleTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleTitle:SetPoint("TOPLEFT", 10, -10)
    panel.ruleTitle = ruleTitle

    panel.tabRuleRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        r:SetSize(744, 25)
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
        r.saveBtn:HookScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_TOP")
            GameTooltip:SetText("Save and broadcast tab rule to guild")
            GameTooltip:Show()
        end)
        r.saveBtn:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", 446, 0)
        r.status:SetWidth(290)
        r.status:SetJustifyH("LEFT")

        r.freeBtn:SetScript("OnClick", function()
            if not VM:IsOfficer() then return end
            r.selectedMode = "FREE"
            UI:RefreshSettings()
        end)
        r.pctBtn:SetScript("OnClick", function()
            if not VM:IsOfficer() then return end
            r.selectedMode = "PERCENT"
            UI:RefreshSettings()
        end)
        r.lockBtn:SetScript("OnClick", function()
            if not VM:IsOfficer() then return end
            r.selectedMode = "LOCKED"
            UI:RefreshSettings()
        end)
        r.saveBtn:SetScript("OnClick", function()
            if not VM:IsOfficer() then return end
            local p = tonumber(r.pctBox:GetText()) or 50
            if p <= 0 then p = 50; r.pctBox:SetText("50") end
            r.userEditedPct = false
            VM:SetTabRule(r.tabIndex, r.selectedMode or "FREE", p)
        end)
        r.pctBox:SetScript("OnTextChanged", function()
            if VM:IsOfficer() then r.userEditedPct = true end
        end)
        r.pctBox:SetScript("OnEnterPressed", function(selfBox)
            selfBox:ClearFocus()
            if not VM:IsOfficer() then return end
            local p = tonumber(selfBox:GetText()) or 50
            if p <= 0 then p = 50; selfBox:SetText("50") end
            r.userEditedPct = false
            VM:SetTabRule(r.tabIndex, r.selectedMode or "FREE", p)
        end)

        r:Hide()
        panel.tabRuleRows[i] = r
    end

    local unpurchasedNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    unpurchasedNote:SetJustifyH("LEFT")
    unpurchasedNote:Hide()
    panel.unpurchasedNote = unpurchasedNote

    -- Dynamic container for Sections 2, 3, and 4 (moves up when fewer bank tabs are purchased)
    local lower = CreateFrame("Frame", nil, panel)
    lower:SetSize(744, 215)
    lower:SetPoint("TOPLEFT", 10, -100)
    panel.lowerSections = lower

    -- Section 2: Interface & Notifications
    local uiPersTitle = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiPersTitle:SetPoint("TOPLEFT", 0, 0)
    uiPersTitle:SetText("|cff26a6f2Interface & Notifications|r")

    local scaleLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 0, -24)
    scaleLabel:SetText("UI Scale (50% - 200%):")

    local scaleEditBox = CreateModernEditBox(lower, 50, 22, true)
    scaleEditBox:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    scaleEditBox:SetText("100")

    local scaleValDisplay = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValDisplay:SetPoint("LEFT", scaleEditBox, "RIGHT", 8, 0)

    local scaleApplyBtn = CreateModernButton(lower, 55, 22, "Apply", THEME.accent)
    scaleApplyBtn:SetPoint("LEFT", scaleValDisplay, "RIGHT", 8, 0)
    scaleApplyBtn:SetScript("OnClick", function()
        local val = tonumber(scaleEditBox:GetText()) or 100
        if val < 50 then val = 50 elseif val > 200 then val = 200 end
        scaleEditBox:SetText(tostring(val))
        local scaleFactor = val / 100
        local prefs = GetUIPrefs()
        prefs.uiScale = scaleFactor
        if mainFrame then mainFrame:SetScale(scaleFactor) end
        scaleValDisplay:SetText(string.format("(%d%%)", val))
    end)

    panel.UpdateScaleButtons = function()
        local scale = GetUIPrefs().uiScale or 1.0
        local pct = math.floor(scale * 100 + 0.5)
        scaleEditBox:SetText(tostring(pct))
        scaleValDisplay:SetText(string.format("(%d%%)", pct))
    end

    local minimapCb = CreateFrame("CheckButton", nil, lower, "UICheckButtonTemplate")
    minimapCb:SetSize(20, 20)
    minimapCb:SetPoint("LEFT", scaleApplyBtn, "RIGHT", 24, 0)
    minimapCb.label = minimapCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minimapCb.label:SetPoint("LEFT", minimapCb, "RIGHT", 4, 0)
    minimapCb.label:SetText("Show Minimap Button")
    minimapCb:SetScript("OnClick", function(cb)
        local show = cb:GetChecked() and true or false
        if VM.Minimap and VM.Minimap.SetHidden then
            VM.Minimap:SetHidden(not show)
        end
        local prefs = GetUIPrefs()
        prefs.showMinimap = show
    end)
    panel.minimapCb = minimapCb

    local chatNotifCb = CreateFrame("CheckButton", nil, lower, "UICheckButtonTemplate")
    chatNotifCb:SetSize(20, 20)
    chatNotifCb:SetPoint("LEFT", minimapCb.label, "RIGHT", 20, 0)
    chatNotifCb.label = chatNotifCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chatNotifCb.label:SetPoint("LEFT", chatNotifCb, "RIGHT", 4, 0)
    chatNotifCb.label:SetText("Enable Chat Notifications")
    chatNotifCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.enableChatNotifications = cb:GetChecked() and true or false
    end)
    panel.chatNotifCb = chatNotifCb

    local basisLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    basisLabel:SetPoint("TOPLEFT", 0, -52)
    basisLabel:SetText("Default Ranking Mode:")

    local basisHistBtn = CreateModernButton(lower, 120, 20, "Historical values")
    basisHistBtn:SetPoint("LEFT", basisLabel, "RIGHT", 8, 0)
    basisHistBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "locked"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
    end)
    panel.basisHistBtn = basisHistBtn

    local basisCurrentBtn = CreateModernButton(lower, 120, 20, "Current values")
    basisCurrentBtn:SetPoint("LEFT", basisHistBtn, "RIGHT", 4, 0)
    basisCurrentBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "live"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
    end)
    panel.basisCurrentBtn = basisCurrentBtn

    panel.UpdateBasisButtons = function()
        local mode = GetUIPrefs().rankingPriceMode or "live"
        if mode == "locked" then
            basisHistBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
            basisHistBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            basisHistBtn.label:SetTextColor(1, 0.82, 0)
            basisCurrentBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            basisCurrentBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            basisCurrentBtn.label:SetTextColor(0.6, 0.6, 0.6)
        else
            basisCurrentBtn:SetBackdropColor(0.15, 0.28, 0.42, 1)
            basisCurrentBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            basisCurrentBtn.label:SetTextColor(1, 0.82, 0)
            basisHistBtn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            basisHistBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            basisHistBtn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    local newerVerNotifCb = CreateFrame("CheckButton", nil, lower, "UICheckButtonTemplate")
    newerVerNotifCb:SetSize(20, 20)
    newerVerNotifCb:SetPoint("LEFT", basisCurrentBtn, "RIGHT", 20, 0)
    newerVerNotifCb.label = newerVerNotifCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    newerVerNotifCb.label:SetPoint("LEFT", newerVerNotifCb, "RIGHT", 4, 0)
    newerVerNotifCb.label:SetText("Notify in Chat on Newer Addon Version")
    newerVerNotifCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.notifyNewerVersion = cb:GetChecked() and true or false
    end)
    panel.newerVerNotifCb = newerVerNotifCb

    local legacyFilterCb = CreateFrame("CheckButton", nil, lower, "UICheckButtonTemplate")
    legacyFilterCb:SetSize(20, 20)
    legacyFilterCb:SetPoint("TOPLEFT", 0, -78)
    legacyFilterCb.label = legacyFilterCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legacyFilterCb.label:SetPoint("LEFT", legacyFilterCb, "RIGHT", 4, 0)
    legacyFilterCb.label:SetText("Include Legacy Members in Ranking by default")
    legacyFilterCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.showLegacyRanking = cb:GetChecked() and true or false
    end)
    panel.legacyFilterCb = legacyFilterCb

    -- Section 3: Sync & Diagnostics
    local diagTitle = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diagTitle:SetPoint("TOPLEFT", 0, -108)
    diagTitle:SetText("|cff26a6f2Sync & Diagnostics|r")

    local diagInfo = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diagInfo:SetPoint("TOPLEFT", 0, -130)
    diagInfo:SetWidth(590)
    diagInfo:SetJustifyH("LEFT")
    panel.diagInfo = diagInfo

    local requestSyncBtn = CreateModernButton(lower, 140, 24, "Request Guild Sync", THEME.accent)
    requestSyncBtn:SetPoint("TOPRIGHT", 0, -126)
    requestSyncBtn:SetScript("OnClick", function()
        if VM.Comms and VM.Comms.SendHello then
            VM.Comms:SendHello()
        end
        if VM.BankScanner and VM.BankScanner.ForceScan and GuildBankFrame and GuildBankFrame:IsVisible() then
            VM.BankScanner:ForceScan()
        end
        VM:Print("Requested guild sync from online members.")
    end)
    panel.requestSyncBtn = requestSyncBtn

    -- Section 4: Local Maintenance
    local maintTitle = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maintTitle:SetPoint("TOPLEFT", 0, -168)
    maintTitle:SetText("|cff26a6f2Local Maintenance|r")

    local resetPosBtn = CreateModernButton(lower, 156, 24, "Reset Window Position")
    resetPosBtn:SetPoint("TOPLEFT", 0, -190)
    resetPosBtn:SetScript("OnClick", function()
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        local prefs = GetUIPrefs()
        prefs.windowPos = nil
        VM:Print("Window position reset to center.")
    end)
    panel.resetPosBtn = resetPosBtn

    local clearCacheBtn = CreateModernButton(lower, 136, 24, "Clear Local Cache", { 0.85, 0.35, 0.35, 1 })
    clearCacheBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", 10, 0)
    clearCacheBtn:SetScript("OnClick", function()
        if VM.db then
            VM.db.inventory = { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
            VM.db.vault = VM.db.inventory
            VM.db.scanMetadata = VM.db.inventory
            VM.db.processedBankLogs = {}
            VM.db.requests = {}
            VM.db.fulfillments = VM.db.requests
            VM.pendingTradePayments = {}
        end
        if VM.Minimap and VM.Minimap.UpdateBadge then VM.Minimap:UpdateBadge() end
        VM:Print("Local cache cleared (ledger, roster, and tab rules preserved).")
        if VM.UI then VM.UI:RefreshAll() end
    end)
    panel.clearCacheBtn = clearCacheBtn

    local maintDesc = lower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maintDesc:SetPoint("LEFT", clearCacheBtn, "RIGHT", 10, 0)
    maintDesc:SetWidth(425)
    maintDesc:SetJustifyH("LEFT")
    maintDesc:SetText("Clears bank & request cache (keeps ledger and rules).")
    panel.maintDesc = maintDesc
end

function UI:RefreshSettings()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[6] then return end
    local panel = mainFrame.panels[6]
    if not panel or not panel.tabRuleRows then return end

    local uiPrefs = GetUIPrefs()
    local isOff = VM:IsOfficer()

    if panel.ruleTitle then
        if isOff then
            panel.ruleTitle:SetText("|cff26a6f2Guild Bank Tab Rules|r  |cff44dd77(Officer Authorized)|r")
        else
            panel.ruleTitle:SetText("|cff26a6f2Guild Bank Tab Rules|r  |cffff5555[Read-Only (Officer Rank Required)]|r")
        end
    end

    if panel.UpdateScaleButtons then panel.UpdateScaleButtons() end
    if panel.minimapCb then
        local showMM = not (VM.db and VM.db.minimap and VM.db.minimap.hide == true)
        if uiPrefs.showMinimap ~= nil then showMM = uiPrefs.showMinimap end
        panel.minimapCb:SetChecked(showMM)
    end
    if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
    if panel.legacyFilterCb then panel.legacyFilterCb:SetChecked(uiPrefs.showLegacyRanking ~= false) end
    if panel.chatNotifCb then panel.chatNotifCb:SetChecked(uiPrefs.enableChatNotifications ~= false) end
    if panel.newerVerNotifCb then panel.newerVerNotifCb:SetChecked(uiPrefs.notifyNewerVersion ~= false) end

    if panel.diagInfo then
        local gKey = VM:GetActiveGuildKey() or "None"
        local protoVer = VM.VERSION or 6
        local addonVer = VM:GetAddonVersion()
        local inv = VM.db and VM.db.inventory
        local lastScan = inv and inv.lastScan or 0
        local scanTimeStr = lastScan > 0 and date("%d/%m %H:%M", lastScan) or "Never"
        local scanBy = (inv and (inv.lastScanBy or inv.scannedBy)) or "None"

        panel.diagInfo:SetText(string.format("Addon Version: |cffffffffv%s|r  |  Protocol: |cff26a6f2v%d|r  |  Guild Bucket: |cffffffff%s|r\nLast Bank Scan: |cffffffff%s|r (%s)",
            addonVer, protoVer, gKey, scanBy, scanTimeStr))
    end

    local function StyleButton(btn, isActive, activeBg, activeBorder, activeText)
        if not isOff then
            btn:Disable()
            btn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.4)
            btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.4)
            btn.label:SetTextColor(0.4, 0.4, 0.4)
        elseif isActive then
            btn:Enable()
            btn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], 1)
            btn:SetBackdropBorderColor(activeBorder[1], activeBorder[2], activeBorder[3], 1)
            btn.label:SetTextColor(activeText[1], activeText[2], activeText[3])
        else
            btn:Enable()
            btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.8)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    local y = 30
    local unpurchasedTabs = {}

    for i = 1, 6 do
        local r = panel.tabRuleRows[i]
        if not VM:IsTabPurchased(i) then
            r:Hide()
            table.insert(unpurchasedTabs, i)
        else
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 10, -y)
            r:Show()
            y = y + 27

            local tabData = VM.db.inventory and VM.db.inventory.tabs and VM.db.inventory.tabs[i]
            local tabName = (tabData and tabData.name) or string.format("Tab %d", i)
            local rule = VM:GetTabRule(i)
            r.label:SetText(string.format("Tab %d: %s", i, tabName))
            if not r.userEditedPct then
                r.pctBox:SetText(tostring(rule.percent or 50))
            end
            if not r.selectedMode then
                r.selectedMode = rule.mode or "FREE"
            end

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
                r.saveBtn:Disable()
                r.saveBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.4)
                r.saveBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.4)
                r.saveBtn.label:SetTextColor(0.4, 0.4, 0.4)
            else
                r.saveBtn:Enable()
                r.saveBtn:SetBackdropColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                r.saveBtn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
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
        panel.unpurchasedNote:SetPoint("TOPLEFT", 14, -(y + 2))
        panel.unpurchasedNote:SetText(string.format("|cff888888%s: Not purchased (unlock in Guild Bank to configure rules)|r",
            FormatTabRange(unpurchasedTabs)))
        panel.unpurchasedNote:Show()
        y = y + 20
    elseif panel.unpurchasedNote then
        panel.unpurchasedNote:Hide()
    end

    if panel.lowerSections then
        panel.lowerSections:ClearAllPoints()
        panel.lowerSections:SetPoint("TOPLEFT", 10, -(y + 12))
    end
end

--------------------------------------------------------------------------------
-- OFFICER BANK POPUP
--------------------------------------------------------------------------------
function UI:CreateOfficerPopupFrame()
    popupFrame = CreateFrame("Frame", "VaultManagerOfficerPopup", UIParent, "BackdropTemplate")
    popupFrame:SetSize(480, 270)
    popupFrame:SetPoint("TOP", 0, -110)
    popupFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    popupFrame:SetFrameLevel(200)
    popupFrame:SetClampedToScreen(true)
    popupFrame:SetMovable(true)
    popupFrame:EnableMouse(true)
    popupFrame:RegisterForDrag("LeftButton")
    popupFrame:SetScript("OnDragStart", popupFrame.StartMoving)
    popupFrame:SetScript("OnDragStop", popupFrame.StopMovingOrSizing)
    ApplyModernBackdrop(popupFrame, THEME.bg, THEME.accent)
    popupFrame:Hide()

    local title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff26a6f2APPROVED GUILD BANK REQUESTS|r")

    local closeBtn = CreateModernButton(popupFrame, 22, 22, "X", THEME.red)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() popupFrame:Hide() end)

    popupFrame.scroll = CreateScrollArea(popupFrame, -38, 10)
    popupFrame.scroll.content:SetSize(440, 1)
end

function UI:ShowOfficerBankPopup(orders)
    if not popupFrame then self:CreateOfficerPopupFrame() end
    if not popupFrame or not popupFrame.scroll then return end
    local content = popupFrame.scroll.content
    if not content then return end
    popupFrame:Show()
    for _, r in ipairs(popupFrame.scroll.rows) do r:Hide() end

    local y = 0
    for idx, req in ipairs(orders) do
        local row = popupFrame.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(440, 28)
            ApplyModernBackdrop(row, THEME.rowOdd, { 0, 0, 0, 0 })

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 8, 0)
            row.label:SetWidth(260)
            row.label:SetJustifyH("LEFT")

            row.prepBtn = CreateModernButton(row, 76, 22, "Prepare", THEME.accent)
            row.prepBtn:SetPoint("LEFT", 275, 0)
            row.prepBtn:SetScript("OnClick", function()
                local r = row.reqData
                if not r then return end
                VM.Fulfillment.activeOrder = r
                if r.isGoldRequest then
                    VM:Print(string.format("Withdraw %s for |cffffff00%s|r (%s), then open Mail or Trade.",
                        VM:FormatMoney(r.goldAmount or r.quotedTotalPrice or 0), r.requester, r.reason or "Guild expense"))
                else
                    VM:Print(string.format("Withdraw %dx %s from Tab %d, then open Mail or Trade with %s.",
                        r.count or 1, r.itemName or "Item", r.tab or 1, r.requester))
                end
            end)

            row.doneBtn = CreateModernButton(row, 76, 22, "Complete", THEME.green)
            row.doneBtn:SetPoint("LEFT", 356, 0)
            row.doneBtn:SetScript("OnClick", function()
                local r = row.reqData
                if not r then return end
                VM.Fulfillment:CompleteRequest(r.id)
                local remaining = VM.Fulfillment:GetApprovedOrders()
                if #remaining == 0 then
                    popupFrame:Hide()
                else
                    UI:ShowOfficerBankPopup(remaining)
                end
            end)

            popupFrame.scroll.rows[idx] = row
        end

        local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        row.reqData = req
        row:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 2, -y)
        row:Show()

        if req.isGoldRequest then
            local gAmt = tonumber(req.goldAmount or req.quotedTotalPrice or req.quotedUnitPrice) or 0
            row.label:SetText(string.format("%s: |cffffd700Gold (%s)|r",
                VM:ColorizeName(req.requester), VM:FormatMoneyShort(gAmt)))
        else
            row.label:SetText(string.format("%s: %dx %s (Tab %d)",
                VM:ColorizeName(req.requester), req.count or 1, req.itemLink or req.itemName or "Item", req.tab or 1))
        end

        y = y + 30
    end
    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- NAVIGATION & MASTER REFRESH
--------------------------------------------------------------------------------
function UI:UpdateScanStatusButton()
    if not mainFrame or not mainFrame.scanStatusBtn or not VM.BankScanner then return end
    local _, text, color = VM.BankScanner:GetScanStatus()
    mainFrame.scanStatusBtn:SetText(text)
    mainFrame.scanStatusBtn:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
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

function UI:RefreshAll()
    if VM.Minimap and VM.Minimap.UpdateBadge then
        VM.Minimap:UpdateBadge()
    end
    self:UpdateRequestsTabBadge()

    if not mainFrame or not mainFrame:IsShown() then return end
    if not mainFrame.navButtons or not mainFrame.panels or not mainFrame.scanInfo then return end

    if VM.isUnguilded then
        mainFrame.scanInfo:SetText("Not in a guild")
        if mainFrame.scanStatusBtn then
            mainFrame.scanStatusBtn:SetText("No Guild")
            mainFrame.scanStatusBtn:SetBackdropColor(0.4, 0.4, 0.4, 1)
        end
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
                btn:SetBackdropColor(0.14, 0.20, 0.28, 1)
                btn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                panel:Show()
            else
                if btn.activeBar then btn.activeBar:Hide() end
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
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
