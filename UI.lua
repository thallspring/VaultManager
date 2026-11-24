local _, VM = ...
VM.UI = {}
local UI = VM.UI

local mainFrame
local popupFrame
local rosterPickerFrame
local exportModalFrame
local currentTab = 1
local selectedBankTab = 1
local vaultCategoryExpanded = {}
local searchQuery = ""
local expandedMains = {}
local expandedTreeMains = {}
local settingsSearchFilter = ""
local selectedAltChar = ""
local selectedMainChar = ""
local rankingSortMode = "TOTAL" -- "TOTAL" | "GOLD" | "ITEMS"

local THEME = {
    bg = { 0.07, 0.08, 0.10, 0.96 },
    panel = { 0.10, 0.11, 0.14, 0.95 },
    rowEven = { 0.12, 0.13, 0.17, 0.75 },
    rowOdd = { 0.09, 0.10, 0.13, 0.75 },
    rowHover = { 0.18, 0.22, 0.30, 0.90 },
    border = { 0.22, 0.25, 0.32, 1.0 },
    accent = { 0.15, 0.65, 0.95, 1.0 },
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

local function GetUIPrefs()
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local defaults = {
        useHistoricalPrices = false,
        showLockedPrices = false,
        rankingPriceMode = "live",
        hideOfficers = false,
        showLegacyRanking = true,
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
            self.label:SetTextColor(1, 1, 1)
        else
            self:Disable()
            self:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.6)
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
    dd.label:SetPoint("LEFT", 8, 0)
    dd.label:SetPoint("RIGHT", -20, 0)
    dd.label:SetJustifyH("LEFT")

    local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
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

function UI:Init()
    self:CreateMainFrame()
    self:CreateOfficerPopupFrame()
    self:CreateRosterPickerFrame()
    self:CreateExportModal()
    self:CreateAssignModal()
    self:CreateRankingPeriodPickerFrame()
    self:CreateBankValDropdown()
end

function UI:Toggle()
    if not mainFrame then self:CreateMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
        if rosterPickerFrame then rosterPickerFrame:Hide() end
        if exportModalFrame then exportModalFrame:Hide() end
        if assignModalFrame then assignModalFrame:Hide() end
        if rankingPeriodDropdownFrame then rankingPeriodDropdownFrame:Hide() end
        if bankValDropdownFrame then bankValDropdownFrame:Hide() end
    else
        if VM.SwitchGuildContext then
            VM:SwitchGuildContext("UI_TOGGLE")
        end
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
            elseif GuildRoster then GuildRoster() end
        end
        mainFrame:Show()
        self:RefreshAll()
    end
end

--------------------------------------------------------------------------------
-- ASSIGN MODAL
--------------------------------------------------------------------------------
local assignModalFrame
local selectedAssignRecipient = ""
local selectedAssignItem = nil
local selectedAssignTab = 1

function UI:CreateAssignModal()
    assignModalFrame = CreateFrame("Frame", "VaultManagerAssignModal", UIParent, "BackdropTemplate")
    assignModalFrame:SetSize(360, 280)
    assignModalFrame:SetPoint("CENTER")
    assignModalFrame:SetFrameStrata("FULLSCREEN_DIALOG")
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

    local closeBtn = CreateModernButton(assignModalFrame, 22, 22, "X", { 0.85, 0.25, 0.25, 1 })
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function() assignModalFrame:Hide() end)

    local itemLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemLbl:SetPoint("TOPLEFT", 12, -42)
    assignModalFrame.itemLbl = itemLbl

    local recLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recLbl:SetPoint("TOPLEFT", 12, -72)
    recLbl:SetText("Recipient:")

    local recBtn = CreateModernDropdown(assignModalFrame, 200, 24, "Select Member...")
    recBtn:SetPoint("TOPLEFT", 80, -68)
    recBtn:SetScript("OnClick", function(btn)
        UI:OpenRosterPicker(btn, true, function(chosen)
            selectedAssignRecipient = chosen
            recBtn:SetText(chosen)
        end)
    end)
    assignModalFrame.recBtn = recBtn

    local qtyLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("TOPLEFT", 12, -106)
    qtyLbl:SetText("Quantity:")

    local qtyBox = CreateModernEditBox(assignModalFrame, 60, 24, true)
    qtyBox:SetPoint("TOPLEFT", 80, -102)
    qtyBox:SetText("1")
    assignModalFrame.qtyBox = qtyBox

    local priceLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLbl:SetPoint("TOPLEFT", 12, -140)
    priceLbl:SetText("Price (Unit):")

    local priceBox = CreateModernEditBox(assignModalFrame, 100, 24, true)
    priceBox:SetPoint("TOPLEFT", 80, -136)
    assignModalFrame.priceBox = priceBox

    local totalLbl = assignModalFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalLbl:SetPoint("LEFT", priceBox, "RIGHT", 10, 0)
    assignModalFrame.totalLbl = totalLbl

    local payCb = CreateFrame("CheckButton", nil, assignModalFrame, "UICheckButtonTemplate")
    payCb:SetSize(20, 20)
    payCb:SetPoint("TOPLEFT", 12, -176)
    payCb.label = payCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    payCb.label:SetPoint("LEFT", payCb, "RIGHT", 4, 0)
    payCb.label:SetText("Payment received ([GOLD IN])")
    assignModalFrame.payCb = payCb

    qtyBox:SetScript("OnTextChanged", function()
        local qty = tonumber(qtyBox:GetText()) or 1
        local uPrice = tonumber(priceBox:GetText()) or 0
        totalLbl:SetText("Total: " .. VM:FormatMoney(uPrice * qty))
    end)
    priceBox:SetScript("OnTextChanged", function()
        local qty = tonumber(qtyBox:GetText()) or 1
        local uPrice = tonumber(priceBox:GetText()) or 0
        totalLbl:SetText("Total: " .. VM:FormatMoney(uPrice * qty))
    end)

    local confirmBtn = CreateModernButton(assignModalFrame, 130, 26, "Assign & Record", THEME.accent)
    confirmBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    confirmBtn:SetScript("OnClick", function()
        if not selectedAssignRecipient or selectedAssignRecipient == "" then
            VM:Print("|cffff4444Please select a recipient member first.|r")
            return
        end
        local qty = tonumber(qtyBox:GetText()) or 1
        local unitP = tonumber(priceBox:GetText()) or 0
        local totalP = unitP * qty
        local mainName = VM:GetMainFor(selectedAssignRecipient)

        local rule = VM:GetTabRule(selectedAssignTab)
        local tx = {
            id = string.format("OUT_ASGN_%d_%d", time(), math.random(1000, 9999)),
            type = "OUT",
            player = VM:NormalizeName(mainName),
            recipient = VM:NormalizeName(selectedAssignRecipient),
            itemID = selectedAssignItem.itemID,
            itemLink = selectedAssignItem.itemLink or selectedAssignItem.link,
            itemName = selectedAssignItem.name,
            count = qty,
            unitPriceAtTime = VM:GetEffectiveLivePrice(selectedAssignItem.itemID, selectedAssignItem.itemLink or selectedAssignItem.link, selectedAssignItem.ahPrice),
            chargedUnitPrice = unitP,
            priceMode = rule.mode,
            pricePercent = rule.percent,
            isFFA = (rule.mode == "FREE"),
            tab = selectedAssignTab,
            timestamp = time(),
            updatedAt = time(),
            officer = VM:GetPlayerName(),
            source = "MANUAL_ASSIGN",
            isManual = true,
            deleted = false
        }
        VM.db.ledger[tx.id] = tx
        VM.Comms:BroadcastTransaction(tx)

        if payCb:GetChecked() and totalP > 0 then
            VM.Ledger:RecordGoldDeposit(selectedAssignRecipient, totalP, "MANUAL_ASSIGN_PAYMENT", selectedAssignRecipient, mainName)
        end

        VM:Print(string.format("Assigned %dx %s to |cffffff00%s|r (Charged: %s).", qty, selectedAssignItem.name, selectedAssignRecipient, VM:FormatMoney(totalP)))
        assignModalFrame:Hide()
        if VM.UI then VM.UI:RefreshAll() end
    end)

    local cancelBtn = CreateModernButton(assignModalFrame, 90, 26, "Cancel")
    cancelBtn:SetPoint("BOTTOMRIGHT", -148, 12)
    cancelBtn:SetScript("OnClick", function() assignModalFrame:Hide() end)
end

function UI:OpenAssignModal(item, tabIndex)
    if not assignModalFrame then self:CreateAssignModal() end
    selectedAssignItem = item
    selectedAssignTab = tabIndex
    selectedAssignRecipient = ""
    assignModalFrame.recBtn:SetText("Select Member...")

    assignModalFrame.itemLbl:SetText(string.format("Item: %s (Stock: %d)", item.link or item.name, item.count))
    assignModalFrame.qtyBox:SetText("1")

    local rule = VM:GetTabRule(tabIndex)
    local effPrice = VM:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice)
    local unitCharged = 0
    if rule.mode == "PERCENT" and effPrice > 0 then
        unitCharged = math.floor(effPrice * ((rule.percent or 50) / 100))
    elseif rule.mode == "FREE" then
        unitCharged = 0
    else
        unitCharged = effPrice
    end

    assignModalFrame.priceBox:SetText(tostring(unitCharged))
    assignModalFrame.totalLbl:SetText("Total: " .. VM:FormatMoney(unitCharged))
    assignModalFrame.payCb:SetChecked(unitCharged > 0)

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

    local closeBtn = CreateModernButton(exportModalFrame, 24, 24, "X", { 0.85, 0.25, 0.25, 1 })
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

function UI:OpenExportModalText(text, customTitle)
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
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
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
-- CUSTOM SEARCHABLE ROSTER DROPDOWN
--------------------------------------------------------------------------------
function UI:CreateRosterPickerFrame()
    rosterPickerFrame = CreateFrame("Frame", "VaultManagerRosterPicker", UIParent, "BackdropTemplate")
    rosterPickerFrame:SetSize(220, 260)
    rosterPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ApplyModernBackdrop(rosterPickerFrame, { 0.05, 0.06, 0.08, 0.98 }, THEME.accent)
    rosterPickerFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerRosterPicker")

    local search = CreateModernEditBox(rosterPickerFrame, 180, 22, false)
    search:SetPoint("TOPLEFT", 6, -6)
    search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.placeholder:SetPoint("LEFT", 6, 0)
    search.placeholder:SetText("Filter name...")
    rosterPickerFrame.search = search

    local closeBtn = CreateModernButton(rosterPickerFrame, 22, 22, "X", { 0.85, 0.25, 0.25, 1 })
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() rosterPickerFrame:Hide() end)

    local sf = CreateScrollArea(rosterPickerFrame, -34, 6)
    sf.content:SetSize(186, 1)
    rosterPickerFrame.scroll = sf

    search:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        UI:RefreshRosterPicker(txt:lower())
    end)
end

function UI:OpenRosterPicker(anchor, includeLegacy, onSelect)
    if not rosterPickerFrame then self:CreateRosterPickerFrame() end
    rosterPickerFrame.includeLegacy = includeLegacy
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
    for _, name in ipairs(names) do
        if filter == "" or name:lower():find(filter, 1, true) then
            idx = idx + 1
            local row = rosterPickerFrame.scroll.rows[idx]
            if not row then
                row = CreateFrame("Button", nil, content, "BackdropTemplate")
                row:SetSize(184, 22)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", 6, 0)
                row.label:SetPoint("RIGHT", -4, 0)
                row.label:SetJustifyH("LEFT")
                rosterPickerFrame.scroll.rows[idx] = row
            end

            ApplyModernBackdrop(row, (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd, { 0, 0, 0, 0 })
            row:SetPoint("TOPLEFT", 0, -y)
            row:Show()

            local isLeg = VM:IsLegacyMember(name)
            row.label:SetText(isLeg and (VM:ColorizeName(name, "808080") .. " |cff808080(Legacy)|r") or VM:ColorizeName(name))

            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
            end)
            row:SetScript("OnLeave", function(selfRow)
                local bg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
                selfRow:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            end)
            row:SetScript("OnClick", function()
                rosterPickerFrame:Hide()
                if rosterPickerFrame.onSelect then
                    rosterPickerFrame.onSelect(name)
                end
            end)

            y = y + 23
        end
    end
    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- RANKING PERIOD DROPDOWN PICKER
--------------------------------------------------------------------------------
local rankingPeriodDropdownFrame = nil

function UI:CreateRankingPeriodPickerFrame()
    rankingPeriodDropdownFrame = CreateFrame("Frame", "VaultManagerRankingPeriodPicker", UIParent, "BackdropTemplate")
    rankingPeriodDropdownFrame:SetSize(120, 80)
    rankingPeriodDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
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
            if not VM.db then VM.db = {} end
            VM.db.uiPrefs = VM.db.uiPrefs or {}
            VM.db.uiPrefs.rankingPeriod = opt.key
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
local bankValDropdownFrame = nil

function UI:CreateBankValDropdown()
    bankValDropdownFrame = CreateFrame("Frame", "VaultManagerBankValDropdown", UIParent, "BackdropTemplate")
    bankValDropdownFrame:SetSize(290, 240)
    bankValDropdownFrame:SetFrameStrata("DIALOG")
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
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -6, 0)
            row.label:SetJustifyH("LEFT")
            bankValDropdownFrame.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    -- 1. Total Value
    local r1 = GetRow()
    ApplyModernBackdrop(r1, THEME.rowEven, {0,0,0,0})
    r1:SetPoint("TOPLEFT", 0, -y)
    r1.label:SetText(string.format("|cffffd700Total Value (Gold + Items):|r %s", VM:FormatMoney(wealth.total)))
    y = y + 24

    -- 2. Guild Bank Gold
    local r2 = GetRow()
    ApplyModernBackdrop(r2, THEME.rowOdd, {0,0,0,0})
    r2:SetPoint("TOPLEFT", 0, -y)
    r2.label:SetText(string.format("  • Guild Bank Gold: %s", VM:FormatMoney(wealth.gold)))
    y = y + 22

    -- 3. Items Subtotal
    local r3 = GetRow()
    ApplyModernBackdrop(r3, THEME.rowEven, {0,0,0,0})
    r3:SetPoint("TOPLEFT", 0, -y)
    r3.label:SetText(string.format("  • Items Subtotal: %s", VM:FormatMoney(wealth.itemsTotal)))
    y = y + 24

    -- 4. Separator
    local sep = bankValDropdownFrame.sep
    if not sep then
        sep = bankValDropdownFrame:CreateTexture(nil, "OVERLAY")
        sep:SetHeight(1)
        sep:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        bankValDropdownFrame.sep = sep
    end
    sep:ClearAllPoints()
    sep:SetPoint("TOPLEFT", 6, -y)
    sep:SetPoint("TOPRIGHT", -6, -y)
    y = y + 6

    -- 5. Tabs
    for idx, tabInfo in ipairs(wealth.tabs) do
        local rTab = GetRow()
        ApplyModernBackdrop(rTab, (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd, {0,0,0,0})
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
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = selfFrame:GetPoint()
        local prefs = GetUIPrefs()
        prefs.windowPos = { point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
    end)
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
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local ver = "v" .. ((getMeta and getMeta("VaultManager", "Version")) or "1.4.2")
    title:SetText(string.format("|cff26a6f2VAULT|r |cffffffffMANAGER|r |cff8899aa%s|r", ver))

    mainFrame.scanStatusBtn = CreateModernButton(headerBar, 110, 22, "Scan Bank", { 0.25, 0.55, 0.85, 1 })
    mainFrame.scanStatusBtn:SetPoint("LEFT", title, "RIGHT", 14, 0)
    mainFrame.scanStatusBtn:SetScript("OnClick", function()
        VM.BankScanner:ForceScan()
    end)

    local closeBtn = CreateModernButton(headerBar, 24, 24, "X", { 0.85, 0.25, 0.25, 1 })
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function()
        mainFrame:Hide()
        if rosterPickerFrame then rosterPickerFrame:Hide() end
        if exportModalFrame then exportModalFrame:Hide() end
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
function UI:BuildInventoryPanel(panel)
    panel.bankTabButtons = {}
    for i = 1, 6 do
        local b = CreateModernButton(panel, 82, 24, "Tab " .. i)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 86, -8)
        b:SetScript("OnClick", function()
            if selectedBankTab ~= i then
                selectedBankTab = i
                vaultCategoryExpanded = {}
            end
            self:RefreshInventory()
        end)
        panel.bankTabButtons[i] = b
    end

    local scanBtn = CreateModernButton(panel, 78, 24, "Scan Now", { 0.25, 0.80, 0.45, 1 })
    scanBtn:SetPoint("TOPRIGHT", -10, -8)
    scanBtn:SetScript("OnClick", function()
        if VM.BankScanner and VM.BankScanner.ForceScan then
            VM.BankScanner:ForceScan()
            print("|cff00ccff[Vault Manager]|r Scanning Guild Bank tabs and logs...")
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

    -- Recessed Filter Strip (darker backdrop bar directly below)
    local filterStrip = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterStrip:SetHeight(28)
    filterStrip:SetPoint("TOPLEFT", 10, -36)
    filterStrip:SetPoint("TOPRIGHT", -10, -36)
    ApplyModernBackdrop(filterStrip, { 0.05, 0.06, 0.08, 0.9 }, THEME.border)

    local ruleBannerBtn = CreateFrame("Button", nil, filterStrip)
    ruleBannerBtn:SetPoint("LEFT", 8, 0)
    ruleBannerBtn:SetSize(450, 24)
    ruleBannerBtn.text = ruleBannerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ruleBannerBtn.text:SetPoint("LEFT", 0, 0)
    ruleBannerBtn.text:SetJustifyH("LEFT")
    panel.ruleBannerBtn = ruleBannerBtn

    ruleBannerBtn:SetScript("OnEnter", function(selfBtn)
        selfBtn.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
        if VM:IsOfficer() then
            GameTooltip:SetText("Click to configure Tab Rules in Settings")
        else
            GameTooltip:SetText("Click to view Tab Rules in Settings")
        end
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
    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        searchQuery = txt:lower()
        UI:RefreshInventory()
    end)
    panel.searchBox = searchBox

    panel.scroll = CreateScrollArea(panel, -68, 8)
end

if not VM_HiddenScanTooltip then
    CreateFrame("GameTooltip", "VM_HiddenScanTooltip", UIParent, "GameTooltipTemplate")
end

local refreshTimerFrame = CreateFrame("Frame")
local refreshTimerDelay = 0
local refreshTimerActive = false

refreshTimerFrame:Hide()
refreshTimerFrame:SetScript("OnUpdate", function(self, elapsed)
    refreshTimerDelay = refreshTimerDelay - elapsed
    if refreshTimerDelay <= 0 then
        self:Hide()
        refreshTimerActive = false
        if UI and UI.RefreshInventory then
            UI:RefreshInventory()
        end
    end
end)

local function RequestDelayedInventoryRefresh()
    if not refreshTimerActive then
        refreshTimerActive = true
        refreshTimerDelay = 0.5
        refreshTimerFrame:Show()
    end
end

local queriedItemIDs = {}

local KNOWN_ITEM_TYPES = {
    ["Weapon"] = true,
    ["Armor"] = true,
    ["Consumable"] = true,
    ["Trade Goods"] = true,
    ["Reagent"] = true,
    ["Recipe"] = true,
}

local GEAR_SLOTS = {
    ["Head"] = true,
    ["Neck"] = true,
    ["Shoulder"] = true,
    ["Back"] = true,
    ["Chest"] = true,
    ["Shirt"] = true,
    ["Tabard"] = true,
    ["Wrist"] = true,
    ["Hands"] = true,
    ["Waist"] = true,
    ["Legs"] = true,
    ["Feet"] = true,
    ["Finger"] = true,
    ["Trinket"] = true,
    ["One-Hand"] = true,
    ["Two-Hand"] = true,
    ["Main Hand"] = true,
    ["Off Hand"] = true,
    ["Held In Off-hand"] = true,
    ["Ranged"] = true,
    ["Thrown"] = true,
    ["Relic"] = true,
    ["Shield"] = true,
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

    -- Fast-path: use cached category if already set to one of the 4 specific categories
    if item.cachedCategory == "Gear" or item.cachedCategory == "Consumables" or
       item.cachedCategory == "Crafting Mats" or item.cachedCategory == "Recipes" then
        return item.cachedCategory
    end

    -- 1. Check if already stored on item in VM.db
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

    -- 2. Call GetItemInfo if itemType or equipSlot is missing
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

                if foundType then
                    itemType = foundType
                    item.itemType = foundType
                else
                    itemType = itemType or "Other"
                    item.itemType = itemType
                end

                if foundEquip then
                    equipSlot = foundEquip
                    item.equipSlot = foundEquip
                else
                    equipSlot = equipSlot or ""
                    item.equipSlot = equipSlot
                end
            end
        end
    end

    itemType = itemType or ""
    equipSlot = equipSlot or ""

    -- 3. Tooltip scanning via hidden GameTooltip
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

    -- Delayed refresh if tooltip data is not yet cached from server
    if numLines <= 1 then
        local attempts = numID and (queriedItemIDs[numID] or 0) or 0
        if attempts < 3 then
            if numID then
                queriedItemIDs[numID] = attempts + 1
            end
            RequestDelayedInventoryRefresh()
        end
    end

    local hasTeaches = false
    local hasGearText = false
    local hasUse = false

    for i = 1, numLines do
        local leftFs = _G["VM_HiddenScanTooltipTextLeft" .. i]
        local rightFs = _G["VM_HiddenScanTooltipTextRight" .. i]
        local leftText = leftFs and leftFs:GetText() or nil
        local rightText = rightFs and rightFs:GetText() or nil

        if leftText and type(leftText) == "string" then
            local cleanLeft = leftText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local trimLeft = cleanLeft:match("^%s*(.-)%s*$") or cleanLeft
            if cleanLeft:find("Use: Teaches", 1, true) then
                hasTeaches = true
            end
            if IsGearTooltipLine(cleanLeft, trimLeft) then
                hasGearText = true
            end
            if trimLeft:find("^Use:") then
                hasUse = true
            end
        end

        if rightText and type(rightText) == "string" then
            local cleanRight = rightText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local trimRight = cleanRight:match("^%s*(.-)%s*$") or cleanRight
            if cleanRight:find("Use: Teaches", 1, true) then
                hasTeaches = true
            end
            if IsGearTooltipLine(cleanRight, trimRight) then
                hasGearText = true
            end
            if trimRight:find("^Use:") then
                hasUse = true
            end
        end
    end

    -- Recipe prefix check by item name
    local rawName = item.name or ""
    if rawName == "" and type(r1) == "string" then
        rawName = r1
    end
    if rawName == "" and item.link and type(item.link) == "string" then
        rawName = item.link:match("%[(.-)%]") or ""
    end
    if rawName == "" and item.itemLink and type(item.itemLink) == "string" then
        rawName = item.itemLink:match("%[(.-)%]") or ""
    end
    if rawName == "" and numLines >= 1 then
        local left1 = _G["VM_HiddenScanTooltipTextLeft1"]
        if left1 and left1:GetText() then
            rawName = left1:GetText()
        end
    end

    local cleanName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local bracketName = cleanName:match("%[(.-)%]")
    cleanName = bracketName or cleanName
    cleanName = cleanName:gsub("^%[", ""):gsub("%]$", "")
    cleanName = cleanName:match("^%s*(.-)%s*$") or cleanName

    local isRecipeName = cleanName:find("^Pattern:") or cleanName:find("^Recipe:") or
                         cleanName:find("^Plans:") or cleanName:find("^Formula:") or
                         cleanName:find("^Schematic:") or cleanName:find("^Manual:")

    -- 4. Prioritized classification
    -- Priority 1: Recipes
    local isRecipe = isRecipeName or hasTeaches or (itemType == "Recipe")

    -- Priority 2: Gear
    local isGearInfo = (itemType == "Weapon" or itemType == "Armor" or
        (equipSlot ~= "" and equipSlot:find("^INVTYPE_") and equipSlot ~= "INVTYPE_BAG"))
    local isGear = hasGearText or isGearInfo

    -- Priority 3: Consumables
    local isConsumable = ((hasUse and not isGear and not isRecipe) or (itemType == "Consumable"))

    -- Priority 4: Crafting Mats
    local isCraftingMat = (itemType == "Trade Goods" or itemType == "Reagent")

    local category
    if isRecipe then
        category = "Recipes"
    elseif isGear then
        category = "Gear"
    elseif isConsumable then
        category = "Consumables"
    elseif isCraftingMat then
        category = "Crafting Mats"
    else
        category = "Other"
    end

    -- 5. Cache result (do NOT cache "Other" permanently if item was uncached)
    if category == "Gear" or category == "Consumables" or
       category == "Crafting Mats" or category == "Recipes" then
        item.cachedCategory = category
    elseif numLines > 1 then
        item.cachedCategory = "Other"
    end

    return category
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

    for i = 1, 6 do
        local btn = panel.bankTabButtons[i]
        local tabData = inv.tabs[i]
        if tabData then
            btn:Show()
            btn:SetText(tabData.name or ("Tab " .. i))
            if i == selectedBankTab then
                btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                btn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
            else
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
            end
        else
            btn:Hide()
        end
    end

    local rule = VM:GetTabRule(selectedBankTab)
    if panel.ruleBannerBtn and panel.ruleBannerBtn.text then
        if rule.mode == "LOCKED" then
            panel.ruleBannerBtn.text:SetText("|cffff5555LOCKED TAB|r  |cff999999— Requests disabled|r")
        elseif rule.mode == "PERCENT" then
            panel.ruleBannerBtn.text:SetText(string.format("|cffffcc33MEMBER PRICE: %d%% OF AUCTION HOUSE|r  |cff999999— Paid upon delivery|r", rule.percent or 50))
        else
            panel.ruleBannerBtn.text:SetText("|cff44dd77FREE-FOR-ALL|r  |cff999999— Free withdrawal (AH value tracked in ledger)|r")
        end
    end

    local content = panel.scroll.content
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end
    panel.scroll.catHeaders = panel.scroll.catHeaders or {}
    for _, h in pairs(panel.scroll.catHeaders) do h:Hide() end

    local tabData = inv.tabs[selectedBankTab]
    if not tabData then return end

    local cats = {
        ["Gear"] = {},
        ["Consumables"] = {},
        ["Crafting Mats"] = {},
        ["Recipes"] = {},
        ["Other"] = {}
    }
    local catOrder = { "Gear", "Consumables", "Crafting Mats", "Recipes", "Other" }

    for _, item in pairs(tabData.items) do
        if searchQuery == "" or (item.name and item.name:lower():find(searchQuery, 1, true)) then
            local cat = GetItemCategory(item)
            if not cats[cat] then cat = "Other" end
            table.insert(cats[cat], item)
        end
    end
    for _, catName in ipairs(catOrder) do
        table.sort(cats[catName], function(a, b) return (a.name or "") < (b.name or "") end)
    end

    local isOff = VM:IsOfficer()
    local y = 0
    local rowIdx = 0

    for _, catName in ipairs(catOrder) do
        local catItems = cats[catName]
        if #catItems > 0 then
            local isExpanded = (searchQuery ~= "") or (vaultCategoryExpanded[catName] == true)
            local header = panel.scroll.catHeaders[catName]
            if not header then
                header = CreateFrame("Button", nil, content, "BackdropTemplate")
                header:SetSize(732, 24)
                ApplyModernBackdrop(header, { 0.12, 0.15, 0.22, 0.95 }, THEME.border)
                header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                header.text:SetPoint("LEFT", 8, 0)
                panel.scroll.catHeaders[catName] = header
            end

            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 4, -y)
            header.text:SetText(string.format("%s  %s (%d)", isExpanded and "[-]" or "[+]", catName, #catItems))
            header:SetScript("OnClick", function()
                if searchQuery == "" then
                    vaultCategoryExpanded[catName] = not vaultCategoryExpanded[catName]
                    UI:RefreshInventory()
                end
            end)
            header:Show()
            y = y + 26

            if isExpanded then
                for idx, item in ipairs(catItems) do
                    rowIdx = rowIdx + 1
                    local row = panel.scroll.rows[rowIdx]
                    if not row then
                        row = CreateFrame("Frame", nil, content, "BackdropTemplate")
                        row:SetSize(732, 30)
                        row:EnableMouse(true)

                        row.icon = row:CreateTexture(nil, "ARTWORK")
                        row.icon:SetSize(22, 22)
                        row.icon:SetPoint("LEFT", 8, 0)
                        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                        row.iconBtn = CreateFrame("Button", nil, row)
                        row.iconBtn:SetSize(22, 22)
                        row.iconBtn:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 0, 0)

                        row.nameBtn = CreateFrame("Button", nil, row)
                        row.nameBtn:SetSize(225, 26)
                        row.nameBtn:SetPoint("LEFT", 36, 0)
                        row.nameText = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.nameText:SetAllPoints()
                        row.nameText:SetJustifyH("LEFT")

                        row.stockText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.stockText:SetPoint("LEFT", 266, 0)
                        row.stockText:SetWidth(110)
                        row.stockText:SetJustifyH("LEFT")

                        row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.priceText:SetPoint("LEFT", 380, 0)
                        row.priceText:SetWidth(110)
                        row.priceText:SetJustifyH("LEFT")

                        row.qtyBox = CreateModernEditBox(row, 34, 22, true)
                        row.qtyBox:SetPoint("LEFT", 495, 0)
                        row.qtyBox:SetText("1")

                        row.reqBtn = CreateModernButton(row, 68, 22, "Request", THEME.accent)
                        row.reqBtn:SetPoint("LEFT", 535, 0)

                        row.assignBtn = CreateModernButton(row, 68, 22, "Assign", { 0.20, 0.60, 0.80, 1 })
                        row.assignBtn:SetPoint("LEFT", 609, 0)

                        panel.scroll.rows[rowIdx] = row
                    end

                    local baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
                    ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
                    row:SetScript("OnEnter", function(selfRow)
                        selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], THEME.rowHover[4])
                        ShowItemTooltip(selfRow, item.itemLink or item.link, item.itemID, item.name)
                    end)
                    row:SetScript("OnLeave", function(selfRow)
                        selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
                        HideItemTooltip()
                    end)

                    row.iconBtn:SetScript("OnEnter", function(selfBtn)
                        row:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], THEME.rowHover[4])
                        ShowItemTooltip(selfBtn, item.itemLink or item.link, item.itemID, item.name)
                    end)
                    row.iconBtn:SetScript("OnLeave", function()
                        row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
                        HideItemTooltip()
                    end)

                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 4, -y)
                    row:Show()

                    local reserved = VM:GetReservedCount(item.itemID, selectedBankTab)
                    local available = math.max(0, item.count - reserved)

                    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.nameText:SetText(item.link or item.name)
                    row.nameBtn:SetScript("OnEnter", function(selfBtn)
                        row:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], THEME.rowHover[4])
                        ShowItemTooltip(selfBtn, item.itemLink or item.link, item.itemID, item.name)
                    end)
                    row.nameBtn:SetScript("OnLeave", function()
                        row:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
                        HideItemTooltip()
                    end)

                    if reserved > 0 then
                        row.stockText:SetText(string.format("Avail: |cff44dd77%d|r |cff888888(Res:%d)|r", available, reserved))
                    else
                        row.stockText:SetText(string.format("Stock: |cff44dd77%d|r", available))
                    end

                    local effectivePrice = VM:GetEffectiveLivePrice(item.itemID, item.itemLink or item.link, item.ahPrice)
                    if effectivePrice > 0 then
                        if rule.mode == "PERCENT" then
                            local memberPrice = math.floor(effectivePrice * ((rule.percent or 50) / 100))
                            row.priceText:SetText("Price: " .. VM:FormatMoney(memberPrice))
                        else
                            row.priceText:SetText("AH: " .. VM:FormatMoney(effectivePrice))
                        end
                    else
                        row.priceText:SetText("|cff777777AH: Unknown|r")
                    end

                    if rule.mode == "LOCKED" or available <= 0 then
                        row.reqBtn:SetModernEnabled(false)
                        row.qtyBox:Hide()
                    else
                        row.reqBtn:SetModernEnabled(true)
                        row.qtyBox:Show()
                        row.reqBtn:SetScript("OnClick", function()
                            local qty = tonumber(row.qtyBox:GetText()) or 1
                            local itemKey = (item.itemID and item.itemID ~= 0) and item.itemID or item.name
                            VM.Fulfillment:CreateRequest(selectedBankTab, itemKey, qty)
                        end)
                    end

                    if isOff then
                        row.assignBtn:Show()
                        if rule.mode == "LOCKED" or available <= 0 then
                            row.assignBtn:SetModernEnabled(false)
                        else
                            row.assignBtn:SetModernEnabled(true)
                            row.assignBtn:SetScript("OnClick", function()
                                UI:OpenAssignModal(item, selectedBankTab)
                            end)
                        end
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
    panel.scroll = CreateScrollArea(panel, -10, 8)
end

function UI:RefreshRequests()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[2] then return end
    local panel = mainFrame.panels[2]
    if not panel or not panel.scroll then return end
    local content = panel.scroll.content
    if not content then return end
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    local list = {}
    for _, req in pairs(VM.db.requests) do
        table.insert(list, req)
    end
    table.sort(list, function(a, b)
        local prio = { PENDING = 1, APPROVED = 2, FULFILLED = 3, REJECTED = 4 }
        if (prio[a.status] or 9) ~= (prio[b.status] or 9) then
            return (prio[a.status] or 9) < (prio[b.status] or 9)
        end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)

    local isOff = VM:IsOfficer()
    local y = 0
    for idx, req in ipairs(list) do
        local row = panel.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 30)

            row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.info:SetPoint("LEFT", 10, 0)
            row.info:SetWidth(470)
            row.info:SetJustifyH("LEFT")

            row.btn1 = CreateModernButton(row, 76, 22, "", { 0.25, 0.80, 0.45, 1 })
            row.btn1:SetPoint("LEFT", 490, 0)

            row.btn2 = CreateModernButton(row, 76, 22, "", THEME.accent)
            row.btn2:SetPoint("LEFT", 572, 0)

            row.btn3 = CreateModernButton(row, 70, 22, "", { 0.85, 0.30, 0.30, 1 })
            row.btn3:SetPoint("LEFT", 654, 0)

            panel.scroll.rows[idx] = row
        end

        local baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
        row:SetPoint("TOPLEFT", 4, -y)
        row:Show()
        row:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        end)
        row:SetScript("OnLeave", function(selfRow)
            selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        end)

        local statusColors = {
            PENDING = "|cffffcc33PENDING|r",
            APPROVED = "|cff26a6f2APPROVED|r",
            FULFILLED = "|cff44dd77FULFILLED|r",
            REJECTED = "|cffff5555REJECTED|r"
        }

        local liveUnit = VM:GetEffectiveLivePrice(req.itemID, req.itemLink, req.priceAtRequest or req.quotedUnitPrice)
        local liveCharged = liveUnit
        if req.priceMode == "PERCENT" and (req.pricePercent or 50) > 0 and liveUnit > 0 then
            liveCharged = math.floor(liveUnit * ((req.pricePercent or 50) / 100))
        elseif req.priceMode == "FREE" then
            liveCharged = 0
        end

        local priceNote = ""
        local reqTotal = (req.quotedUnitPrice or 0) * (req.count or 1)
        local liveTotal = liveCharged * (req.count or 1)
        if reqTotal > 0 and liveTotal > 0 and liveTotal ~= reqTotal then
            priceNote = string.format("  |cffaaaaaa(Req: %s | Live: %s)|r", VM:FormatMoney(reqTotal), VM:FormatMoney(liveTotal))
        elseif liveTotal > 0 then
            priceNote = string.format("  |cffaaaaaa(%s)|r", VM:FormatMoney(liveTotal))
        elseif reqTotal > 0 then
            priceNote = string.format("  |cffaaaaaa(%s)|r", VM:FormatMoney(reqTotal))
        end

        row.info:SetText(string.format("[%s]  %s  —  %dx %s%s",
            statusColors[req.status] or req.status,
            VM:ColorizeName(req.requester), req.count, req.itemLink or req.itemName, priceNote))

        row.btn1:Hide()
        row.btn2:Hide()
        row.btn3:Hide()

        if isOff then
            if req.status == "PENDING" then
                row.btn1:SetText("Approve")
                row.btn1:Show()
                row.btn1:SetScript("OnClick", function() VM.Fulfillment:ApproveRequest(req.id) end)

                row.btn3:SetText("Reject")
                row.btn3:Show()
                row.btn3:SetScript("OnClick", function() VM.Fulfillment:RejectRequest(req.id) end)
            elseif req.status == "APPROVED" then
                row.btn2:SetText("Fulfill")
                row.btn2:Show()
                row.btn2:SetScript("OnClick", function()
                    VM.Fulfillment.activeOrder = req
                    print(string.format("|cff00ccff[Vault Manager]|r Ready to fulfill for |cffffff00%s|r. Open Mail or Trade to auto-fill!", req.requester))
                end)

                row.btn1:SetText("Complete")
                row.btn1:Show()
                row.btn1:SetScript("OnClick", function() VM.Fulfillment:CompleteRequest(req.id) end)

                row.btn3:SetText("Cancel")
                row.btn3:Show()
                row.btn3:SetScript("OnClick", function() VM.Fulfillment:RejectRequest(req.id) end)
            end
        end

        y = y + 32
    end
    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 3: LEDGER
--------------------------------------------------------------------------------
function UI:BuildLedgerPanel(panel)
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local uiPrefs = GetUIPrefs()
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local priceToggle = CreateFrame("CheckButton", nil, topBar, "UICheckButtonTemplate")
    priceToggle:SetSize(22, 22)
    priceToggle:SetPoint("LEFT", 0, 0)
    priceToggle:SetChecked(uiPrefs.useHistoricalPrices or false)

    local toggleLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleLabel:SetPoint("LEFT", priceToggle, "RIGHT", 4, 0)
    toggleLabel:SetText("Historical price (otherwise live AH)")

    local ffaToggle = CreateFrame("CheckButton", nil, topBar, "UICheckButtonTemplate")
    ffaToggle:SetSize(22, 22)
    ffaToggle:SetPoint("LEFT", toggleLabel, "RIGHT", 16, 0)
    ffaToggle:SetChecked(uiPrefs.includeFFA ~= false)

    local ffaLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ffaLabel:SetPoint("LEFT", ffaToggle, "RIGHT", 4, 0)
    ffaLabel:SetText("Include Free-for-All")

    ffaToggle:SetScript("OnClick", function(cb)
        if not VM.db then VM.db = {} end
        VM.db.uiPrefs = VM.db.uiPrefs or {}
        local prefs = GetUIPrefs()
        prefs.includeFFA = cb:GetChecked()
        UI:RefreshLedger()
        UI:RefreshRanking()
    end)
    panel.ffaToggle = ffaToggle

    priceToggle:SetScript("OnClick", function(cb)
        if not VM.db then VM.db = {} end
        VM.db.uiPrefs = VM.db.uiPrefs or {}
        local prefs = GetUIPrefs()
        prefs.useHistoricalPrices = cb:GetChecked()
        UI:RefreshLedger()
        UI:RefreshRanking()
    end)

    local exportBtn = CreateModernButton(topBar, 76, 22, "Export", THEME.accent)
    exportBtn:SetPoint("RIGHT", -275, 0)
    exportBtn:SetScript("OnClick", function()
        UI:OpenExportModal()
    end)

    if VM:IsOfficer() then
        local manualMember = ""
        local memberBtn = CreateModernDropdown(topBar, 130, 22, "Donor...")
        memberBtn:SetPoint("RIGHT", -140, 0)
        memberBtn:SetScript("OnClick", function(btn)
            UI:OpenRosterPicker(btn, false, function(chosen)
                manualMember = chosen
                btn:SetText(chosen)
            end)
        end)

        local goldBox = CreateModernEditBox(topBar, 50, 22, true)
        goldBox:SetPoint("RIGHT", -86, 0)
        goldBox.placeholder = goldBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        goldBox.placeholder:SetPoint("LEFT", 6, 0)
        goldBox.placeholder:SetText("Gold")
        goldBox:SetScript("OnTextChanged", function(eb)
            if eb:GetText() == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
        end)

        local addGoldBtn = CreateModernButton(topBar, 82, 22, "+ Log Gold", { 0.25, 0.80, 0.45, 1 })
        addGoldBtn:SetPoint("RIGHT", 0, 0)
        addGoldBtn:SetScript("OnClick", function()
            local g = tonumber(goldBox:GetText()) or 0
            if manualMember ~= "" and g > 0 then
                VM.Ledger:RecordGoldDeposit(manualMember, g * 10000, "MANUAL_GOLD")
                print(string.format("|cff00ccff[Vault Manager]|r Logged %dg donated by |cffffff00%s|r.", g, manualMember))
                goldBox:SetText("")
                manualMember = ""
                memberBtn:SetText("Donor...")
                UI:RefreshAll()
            end
        end)
    end

    panel.scroll = CreateScrollArea(panel, -44, 8)
end

function UI:RefreshLedger()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[3] then return end
    local panel = mainFrame.panels[3]
    if not panel or not panel.scroll then return end
    local content = panel.scroll.content
    if not content then return end
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local uiPrefs = GetUIPrefs()
    if panel.ffaToggle then
        panel.ffaToggle:SetChecked(uiPrefs.includeFFA ~= false)
    end
    local useHist = uiPrefs.useHistoricalPrices
    local groups = VM.Ledger:GetAggregatedByMain(useHist)

    local rowIdx = 0
    local y = 0

    local function GetRow()
        rowIdx = rowIdx + 1
        local row = panel.scroll.rows[rowIdx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 28)

            row.expandBtn = CreateModernButton(row, 22, 20, "+")
            row.expandBtn:SetPoint("LEFT", 6, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 34, 0)
            row.text:SetWidth(530)
            row.text:SetJustifyH("LEFT")

            row.actionBtn = CreateModernButton(row, 125, 20, "Assign Member", THEME.accent)
            row.actionBtn:SetPoint("RIGHT", -8, 0)

            row.deleteBtn = CreateModernButton(row, 20, 20, "X", { 0.85, 0.30, 0.30, 1 })
            row.deleteBtn:SetPoint("RIGHT", -8, 0)
            row.deleteBtn:Hide()

            panel.scroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    for _, grp in ipairs(groups) do
        local isExpanded = expandedMains[grp.mainName]
        local header = GetRow()
        local baseBg = grp.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or THEME.rowEven
        ApplyModernBackdrop(header, baseBg, THEME.border)
        header:SetPoint("TOPLEFT", 4, -y)
        header:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        end)
        header:SetScript("OnLeave", function(selfRow)
            selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        end)

        header.expandBtn:Show()
        header.expandBtn:SetText(isExpanded and "-" or "+")
        header.expandBtn:SetScript("OnClick", function()
            expandedMains[grp.mainName] = not expandedMains[grp.mainName]
            UI:RefreshLedger()
        end)

        header.actionBtn:Hide()
        header.deleteBtn:Hide()
        header.text:SetPoint("LEFT", 34, 0)

        local goldSubNote = (grp.totalGoldIn and grp.totalGoldIn > 0)
            and string.format(" (incl. %s gold)", VM:FormatMoney(grp.totalGoldIn))
            or ""

        if grp.mainName == "UNATTRIBUTED" then
            header.text:SetText(string.format("|cffff5555UNATTRIBUTED DEPOSITS|r  —  Donated: %s%s  |cff999999(%d entries)|r",
                VM:FormatMoney(grp.totalInValue), goldSubNote, #grp.transactions))
        elseif grp.isLegacy then
            header.text:SetText(string.format("%s |cff808080[Legacy Member]|r  |cff707070—  Received: %s  |  Donated: %s%s  (%d entries)|r",
                VM:ColorizeName(grp.mainName, "808080"),
                VM:FormatMoney(grp.totalOutValue),
                VM:FormatMoney(grp.totalInValue),
                goldSubNote,
                #grp.transactions))
        else
            header.text:SetText(string.format("%s  —  Received: %s  |  Donated: %s%s  |cff999999(%d entries)|r",
                VM:ColorizeName(grp.mainName),
                VM:FormatMoney(grp.totalOutValue),
                VM:FormatMoney(grp.totalInValue),
                goldSubNote,
                #grp.transactions))
        end

        y = y + 30

        if isExpanded then
            for _, tx in ipairs(grp.transactions) do
                local sub = GetRow()
                local subBg = THEME.rowOdd
                ApplyModernBackdrop(sub, subBg, { 0, 0, 0, 0 })
                sub:SetPoint("TOPLEFT", 4, -y)
                sub:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
                end)
                sub:SetScript("OnLeave", function(selfRow)
                    selfRow:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                end)

                sub.expandBtn:Hide()
                sub.text:SetPoint("LEFT", 40, 0)
                sub.actionBtn:Hide()
                sub.deleteBtn:Hide()

                local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                local isItemTx = not isGold and (tx.itemLink ~= "SUMMARY")
                if isItemTx then
                    sub:EnableMouse(true)
                    sub:SetScript("OnEnter", function(selfSub)
                        selfSub:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
                        ShowItemTooltip(selfSub, tx.itemLink, tx.itemID, tx.itemName, tx)
                    end)
                    sub:SetScript("OnLeave", function(selfSub)
                        selfSub:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                        HideItemTooltip()
                    end)
                else
                    sub:EnableMouse(false)
                end
                local dir = (tx.type == "OUT") and (isGold and "|cffff6666GOLD OUT|r" or "|cffff6666OUT|r") or (isGold and "|cffffd700GOLD IN|r" or "|cff44dd77IN|r")
                local val = VM.Ledger:GetTransactionValue(tx, useHist)
                local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED") and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

                local ruleTag = ""
                if tx.type == "OUT" then
                    if tx.isFFA or tx.priceMode == "FREE" then
                        ruleTag = " |cff44dd77(Free-for-All)|r"
                    elseif tx.priceMode == "PERCENT" or (tx.chargedUnitPrice ~= nil and tx.unitPriceAtTime and tx.chargedUnitPrice < tx.unitPriceAtTime and tx.chargedUnitPrice > 0) then
                        local pct = tx.pricePercent or (tx.unitPriceAtTime and tx.unitPriceAtTime > 0 and math.floor((tx.chargedUnitPrice / tx.unitPriceAtTime) * 100 + 0.5)) or 50
                        ruleTag = string.format(" |cff26a6f2(%d%% AH)|r", pct)
                    end
                end

                if isGold then
                    local senderTag = (tx.rawSender and tx.rawSender ~= tx.player) and string.format(" (deposited by %s)", VM:ColorizeName(tx.rawSender)) or ""
                    sub.text:SetText(string.format("|cff999999%s|r [%s]%s%s: %s",
                        dateStr, dir, charTag, senderTag, VM:FormatMoney(val)))
                elseif grp.isLegacy then
                    sub.text:SetText(string.format("|cff808080%s [%s]%s: %dx %s — Value: %s%s|r",
                        dateStr, tx.type == "OUT" and "OUT" or "IN", charTag, tx.count, tx.itemName, VM:FormatMoney(val), ruleTag))
                else
                    sub.text:SetText(string.format("|cff999999%s|r [%s]%s: %dx %s  —  Value: %s%s",
                        dateStr, dir, charTag, tx.count, tx.itemLink or tx.itemName, VM:FormatMoney(val), ruleTag))
                end

                if grp.mainName == "UNATTRIBUTED" and VM:IsOfficer() then
                    sub.actionBtn:Show()
                    sub.actionBtn:SetText("Assign Member")
                    sub.actionBtn:SetScript("OnClick", function()
                        UI:OpenRosterPicker(sub.actionBtn, false, function(chosenName)
                            VM.Ledger:AssignUnattributed(tx.id, chosenName)
                        end)
                    end)
                elseif VM:IsOfficer() and isGold and tx.type == "IN" then
                    sub.actionBtn:Show()
                    sub.actionBtn:SetText("Reassign")
                    sub.actionBtn:SetScript("OnClick", function()
                        UI:OpenRosterPicker(sub.actionBtn, false, function(chosenName)
                            VM.Ledger:ReassignGoldDeposit(tx.id, chosenName)
                        end)
                    end)
                elseif VM:IsOfficer() and tx.isManual == true then
                    sub.deleteBtn:Show()
                    sub.deleteBtn:SetScript("OnClick", function()
                        VM.Ledger:DeleteTransaction(tx.id)
                    end)
                end

                y = y + 25
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 4: RANKING
--------------------------------------------------------------------------------
local expandedRankingMains = {}

function UI:BuildRankingPanel(panel)
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
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

    -- Recessed Filter Strip (darker backdrop bar directly below)
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
        prefs.showLegacyRanking = cb:GetChecked()
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
        prefs.hideOfficers = cb:GetChecked()
        UI:RefreshRanking()
    end)
    panel.hideOfficersCb = hideOfficersCb

    local periodBtn = CreateModernDropdown(filterStrip, 110, 22, "All-Time")
    periodBtn:SetPoint("LEFT", 305, 0)
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
        prefs.includeFFA = cb:GetChecked()
        UI:RefreshRanking()
        UI:RefreshLedger()
    end)
    panel.ffaRankCb = ffaRankCb

    -- Column headers with multi-column sorting
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

        btn:SetScript("OnClick", function()
            local prefs = GetUIPrefs()
            if prefs.rankingSortBy == key then
                prefs.rankingSortDir = (prefs.rankingSortDir == "asc") and "desc" or "asc"
            else
                prefs.rankingSortBy = key
                if key == "name" then
                    prefs.rankingSortDir = "asc"
                else
                    prefs.rankingSortDir = "desc"
                end
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

function UI:RefreshRanking()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[4] then return end
    local panel = mainFrame.panels[4]
    if not panel or not panel.scroll or not panel.sortHeaders then return end
    local content = panel.scroll.content
    if not content then return end

    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local uiPrefs = GetUIPrefs()

    if panel.UpdateBasisButtons then
        panel.UpdateBasisButtons()
    end
    if panel.showLegacyCb then
        panel.showLegacyCb:SetChecked(uiPrefs.showLegacyRanking ~= false)
    end
    if panel.hideOfficersCb then
        panel.hideOfficersCb:SetChecked(uiPrefs.hideOfficers or false)
    end
    if panel.ffaRankCb then
        panel.ffaRankCb:SetChecked(uiPrefs.includeFFA ~= false)
    end
    if panel.periodBtn then
        local p = uiPrefs.rankingPeriod or "ALL"
        panel.periodBtn:SetText((p == "ALL") and "All-Time" or ((p == "CURRENT") and "Current Month" or "Previous Month"))
    end

    local sortBy = uiPrefs.rankingSortBy or "net"
    local sortDir = uiPrefs.rankingSortDir or "desc"

    for key, btn in pairs(panel.sortHeaders) do
        local indicator = ""
        if key == sortBy then
            indicator = (sortDir == "asc") and " (^)" or " (v)"
            btn.label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            btn.label:SetTextColor(0.9, 0.9, 0.9, 1)
        end
        local baseNames = { name = "Player (Main)", contributed = "Contributed", withdrawn = "Received", net = "Net Balance" }
        btn.label:SetText((baseNames[key] or key) .. indicator)
    end

    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    local priceMode = uiPrefs.rankingPriceMode or "live"
    local period = uiPrefs.rankingPeriod or "ALL"
    local hideOff = uiPrefs.hideOfficers or false
    local showLeg = uiPrefs.showLegacyRanking ~= false

    local ranked = VM.Ranking:GetRankingData(sortBy, sortDir, priceMode, period, hideOff, showLeg)

    local rowIdx = 0
    local function GetRankingRow()
        rowIdx = rowIdx + 1
        local row = panel.scroll.rows[rowIdx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 26)

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

            panel.scroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    local y = 0
    for idx, grp in ipairs(ranked) do
        local isExpanded = expandedRankingMains[grp.mainName]
        local row = GetRankingRow()
        local baseBg = grp.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or ((idx % 2 == 0) and THEME.rowEven or THEME.rowOdd)
        ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
        row:SetPoint("TOPLEFT", 6, -y)
        row:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
        end)
        row:SetScript("OnLeave", function(selfRow)
            selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        end)

        row.detailText:Hide()
        row.expandBtn:Show()
        row.expandBtn:SetText(isExpanded and "-" or "+")
        row.expandBtn:SetScript("OnClick", function()
            expandedRankingMains[grp.mainName] = not expandedRankingMains[grp.mainName]
            UI:RefreshRanking()
        end)

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
            local rankBadge = tostring(idx)
            if idx == 1 then rankBadge = "|cffffd700#1|r"
            elseif idx == 2 then rankBadge = "|cffc0c0c0#2|r"
            elseif idx == 3 then rankBadge = "|cffcd7f32#3|r"
            else rankBadge = "|cff888888#" .. idx .. "|r" end

            row.rankText:SetText(rankBadge)
            row.nameText:SetText(VM:ColorizeName(grp.mainName))
            row.goldText:SetText(VM:FormatMoney(dispContributed))
            row.itemsText:SetText(VM:FormatMoney(dispReceived))
            row.totalText:SetText("|cff44dd77" .. VM:FormatMoney(dispNet) .. "|r")
        end

        y = y + 28

        if isExpanded and grp.transactions then
            for _, tx in ipairs(grp.transactions) do
                local sub = GetRankingRow()
                local subBg = THEME.rowOdd
                ApplyModernBackdrop(sub, subBg, { 0, 0, 0, 0 })
                sub:SetPoint("TOPLEFT", 6, -y)
                sub:SetScript("OnEnter", function(selfRow)
                    selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
                end)
                sub:SetScript("OnLeave", function(selfRow)
                    selfRow:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                end)

                sub.expandBtn:Hide()
                sub.rankText:Hide()
                sub.nameText:Hide()
                sub.goldText:Hide()
                sub.itemsText:Hide()
                sub.totalText:Hide()
                sub.detailText:Show()

                local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                local isItemTx = not isGold and (tx.itemLink ~= "SUMMARY")
                if isItemTx then
                    sub:EnableMouse(true)
                    sub:SetScript("OnEnter", function(selfSub)
                        selfSub:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
                        ShowItemTooltip(selfSub, tx.itemLink, tx.itemID, tx.itemName, tx)
                    end)
                    sub:SetScript("OnLeave", function(selfSub)
                        selfSub:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                        HideItemTooltip()
                    end)
                else
                    sub:EnableMouse(false)
                end

                local dir = (tx.type == "OUT") and (isGold and "|cffff6666[GOLD OUT]|r" or "|cffff6666[OUT]|r")
                    or (isGold and "|cffffd700[GOLD IN]|r" or "|cff44dd77[IN]|r")
                local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                local itemDisplay = isGold and "Gold" or (tx.itemLink or tx.itemName)
                local lockedVal = VM.Ranking:GetTransactionValuation(tx, "locked")
                local liveVal = VM.Ranking:GetTransactionValuation(tx, "live")
                local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED") and (" (" .. VM:ColorizeName(tx.player, grp.isLegacy and "808080" or nil) .. ")") or ""

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
-- TAB 5: ROSTER & MAINS
--------------------------------------------------------------------------------
function UI:BuildRosterPanel(panel)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local searchBox = CreateModernEditBox(topBar, 180, 24, false)
    searchBox:SetPoint("TOPLEFT", 0, 0)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 8, 0)
    searchBox.placeholder:SetText("Filter character...")
    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        settingsSearchFilter = txt:lower()
        UI:RefreshRoster()
    end)
    panel.searchBox = searchBox

    if VM:IsOfficer() then
        local autoSuggestBtn = CreateModernButton(topBar, 130, 24, "Auto-Suggest Alts", THEME.accent)
        autoSuggestBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
        autoSuggestBtn:SetScript("OnClick", function()
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
            print(string.format("|cff00ccff[Vault Manager]|r Auto-suggested and linked %d alt pairs.", count))
            UI:RefreshRoster()
        end)
    end

    panel.treeScroll = CreateScrollArea(panel, -44, 8)
end

function UI:RefreshRoster()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[5] then return end
    local panel = mainFrame.panels[5]
    if not panel or not panel.treeScroll then return end
    local content = panel.treeScroll.content
    if not content then return end

    for _, r in ipairs(panel.treeScroll.rows) do r:Hide() end

    local hierarchy = VM:GetRosterHierarchy(true)
    local rowIdx = 0
    local y = 0

    local function GetTreeRow()
        rowIdx = rowIdx + 1
        local row = panel.treeScroll.rows[rowIdx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 26)

            row.expandBtn = CreateModernButton(row, 20, 20, "+")
            row.expandBtn:SetPoint("LEFT", 4, 0)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 30, 0)
            row.label:SetWidth(380)
            row.label:SetJustifyH("LEFT")

            row.btn1 = CreateModernButton(row, 85, 20, "Set as Alt", THEME.accent)
            row.btn1:SetPoint("RIGHT", -95, 0)

            row.btn2 = CreateModernButton(row, 85, 20, "Unlink", { 0.85, 0.30, 0.30, 1 })
            row.btn2:SetPoint("RIGHT", -6, 0)

            panel.treeScroll.rows[rowIdx] = row
        end
        row:Show()
        return row
    end

    for _, mainEntry in ipairs(hierarchy) do
        local mainName = mainEntry.name
        local alts = mainEntry.alts or {}
        local hasAlts = (#alts > 0)
        local isExpanded = expandedTreeMains[mainName]

        local matchesFilter = (settingsSearchFilter == "" or mainName:lower():find(settingsSearchFilter, 1, true))
        if not matchesFilter then
            for _, alt in ipairs(alts) do
                if alt:lower():find(settingsSearchFilter, 1, true) then
                    matchesFilter = true
                    break
                end
            end
        end

        if matchesFilter then
            local baseBg = mainEntry.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or ((rowIdx % 2 == 0) and THEME.rowEven or THEME.rowOdd)
            local row = GetTreeRow()
            ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetScript("OnEnter", function(selfRow)
                selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
            end)
            row:SetScript("OnLeave", function(selfRow)
                selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
            end)

            row.expandBtn:SetPoint("LEFT", 4, 0)
            if hasAlts then
                row.expandBtn:Show()
                row.expandBtn:SetText(isExpanded and "-" or "+")
                row.expandBtn:SetScript("OnClick", function()
                    expandedTreeMains[mainName] = not expandedTreeMains[mainName]
                    UI:RefreshRoster()
                end)
            else
                row.expandBtn:Hide()
            end

            row.label:SetPoint("LEFT", hasAlts and 30 or 10, 0)
            if mainEntry.isLegacy then
                row.label:SetText(string.format("%s |cff808080[Legacy]%s|r", VM:ColorizeName(mainName, "808080"), hasAlts and string.format(" (%d alts)", #alts) or ""))
            else
                row.label:SetText(string.format("%s%s", VM:ColorizeName(mainName), hasAlts and string.format(" |cff888888(%d alts)|r", #alts) or ""))
            end

            row.btn1:Show()
            row.btn1:SetText("Set as Alt")
            row.btn1:SetScript("OnClick", function(btn)
                UI:OpenRosterPicker(btn, true, function(targetMain)
                    if targetMain ~= mainName then
                        VM:SetMainCharacter(targetMain, { mainName })
                    end
                end)
            end)

            row.btn2:Hide()

            y = y + 28

            if hasAlts and (isExpanded or settingsSearchFilter ~= "") then
                for _, altName in ipairs(alts) do
                    if settingsSearchFilter == "" or altName:lower():find(settingsSearchFilter, 1, true) then
                        local subBg = THEME.rowOdd
                        local subRow = GetTreeRow()
                        ApplyModernBackdrop(subRow, subBg, { 0, 0, 0, 0 })
                        subRow:SetPoint("TOPLEFT", 4, -y)
                        subRow:SetScript("OnEnter", function(selfRow)
                            selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], 1)
                        end)
                        subRow:SetScript("OnLeave", function(selfRow)
                            selfRow:SetBackdropColor(subBg[1], subBg[2], subBg[3], subBg[4])
                        end)

                        subRow.expandBtn:Hide()
                        subRow.label:SetPoint("LEFT", 35, 0)
                        subRow.label:SetText(string.format("|cff888888└─ |r%s", VM:ColorizeName(altName)))

                        subRow.btn1:Show()
                        subRow.btn1:SetText("Make Main")
                        subRow.btn1:SetScript("OnClick", function()
                            VM:SetMainCharacter(altName, { mainName })
                        end)

                        subRow.btn2:Show()
                        subRow.btn2:SetText("Unlink")
                        subRow.btn2:SetScript("OnClick", function()
                            VM:UnlinkCharacter(altName)
                        end)

                        y = y + 25
                    end
                end
            end
        end
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 6: SETTINGS
--------------------------------------------------------------------------------
function UI:BuildSettingsPanel(panel)
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local isOff = VM:IsOfficer()

    -- Section 1: Guild Bank Tab Rules
    local ruleTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleTitle:SetPoint("TOPLEFT", 10, -10)
    if isOff then
        ruleTitle:SetText("|cff26a6f2Guild Bank Tab Rules|r  |cff44dd77(Officer Authorized)|r")
    else
        ruleTitle:SetText("|cff26a6f2Guild Bank Tab Rules|r  |cffff5555[Read-Only (Officer Rank Required)]|r")
    end

    panel.tabRuleRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        r:SetSize(744, 26)
        r:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 28)
        ApplyModernBackdrop(r, (i % 2 == 0) and THEME.rowEven or THEME.rowOdd, { 0, 0, 0, 0 })

        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", 10, 0)
        r.label:SetWidth(85)
        r.label:SetJustifyH("LEFT")

        r.freeBtn = CreateModernButton(r, 75, 20, "Free-for-All")
        r.freeBtn:SetPoint("LEFT", 100, 0)

        r.pctBtn = CreateModernButton(r, 65, 20, "% of AH")
        r.pctBtn:SetPoint("LEFT", 178, 0)

        r.pctBox = CreateModernEditBox(r, 34, 20, true)
        r.pctBox:SetPoint("LEFT", 246, 0)
        r.pctBox:SetText("50")

        r.lockBtn = CreateModernButton(r, 55, 20, "Locked")
        r.lockBtn:SetPoint("LEFT", 283, 0)

        r.saveBtn = CreateModernButton(r, 105, 20, "Save & Broadcast", THEME.accent)
        r.saveBtn:SetPoint("LEFT", 341, 0)

        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", 452, 0)
        r.status:SetWidth(285)
        r.status:SetJustifyH("LEFT")

        panel.tabRuleRows[i] = r
    end

    -- Section 2: Interface & Notifications
    local uiPersTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiPersTitle:SetPoint("TOPLEFT", 10, -206)
    uiPersTitle:SetText("|cff26a6f2Interface & Notifications|r")

    -- UI Scale Buttons (85%, 100%, 115%)
    local scaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("TOPLEFT", 10, -228)
    scaleLabel:SetText("UI Scale:")

    local scale85Btn = CreateModernButton(panel, 45, 20, "85%")
    scale85Btn:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    scale85Btn:SetScript("OnClick", function()
        if not VM.db then VM.db = {} end
        VM.db.uiPrefs = VM.db.uiPrefs or {}
        VM.db.uiPrefs.uiScale = 0.85
        if mainFrame then mainFrame:SetScale(0.85) end
        if panel.UpdateScaleButtons then panel.UpdateScaleButtons() end
    end)
    panel.scale85Btn = scale85Btn

    local scale100Btn = CreateModernButton(panel, 45, 20, "100%")
    scale100Btn:SetPoint("LEFT", scale85Btn, "RIGHT", 4, 0)
    scale100Btn:SetScript("OnClick", function()
        if not VM.db then VM.db = {} end
        VM.db.uiPrefs = VM.db.uiPrefs or {}
        VM.db.uiPrefs.uiScale = 1.0
        if mainFrame then mainFrame:SetScale(1.0) end
        if panel.UpdateScaleButtons then panel.UpdateScaleButtons() end
    end)
    panel.scale100Btn = scale100Btn

    local scale115Btn = CreateModernButton(panel, 45, 20, "115%")
    scale115Btn:SetPoint("LEFT", scale100Btn, "RIGHT", 4, 0)
    scale115Btn:SetScript("OnClick", function()
        if not VM.db then VM.db = {} end
        VM.db.uiPrefs = VM.db.uiPrefs or {}
        VM.db.uiPrefs.uiScale = 1.15
        if mainFrame then mainFrame:SetScale(1.15) end
        if panel.UpdateScaleButtons then panel.UpdateScaleButtons() end
    end)
    panel.scale115Btn = scale115Btn

    local function UpdateScaleButtons()
        local scale = GetUIPrefs().uiScale or 1.0
        local function StyleScaleBtn(btn, val)
            if math.abs(scale - val) < 0.01 then
                btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
                btn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
                btn.label:SetTextColor(1, 0.82, 0)
            else
                btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
                btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
                btn.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end
        StyleScaleBtn(scale85Btn, 0.85)
        StyleScaleBtn(scale100Btn, 1.0)
        StyleScaleBtn(scale115Btn, 1.15)
    end
    panel.UpdateScaleButtons = UpdateScaleButtons

    -- Show Minimap Button checkbox
    local minimapCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    minimapCb:SetSize(20, 20)
    minimapCb:SetPoint("LEFT", scale115Btn, "RIGHT", 24, 0)
    minimapCb.label = minimapCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minimapCb.label:SetPoint("LEFT", minimapCb, "RIGHT", 4, 0)
    minimapCb.label:SetText("Show Minimap Button")
    minimapCb:SetScript("OnClick", function(cb)
        if VM.Minimap and VM.Minimap.SetHidden then
            VM.Minimap.SetHidden(not cb:GetChecked())
        end
        local prefs = GetUIPrefs()
        prefs.showMinimap = cb:GetChecked()
        if VM.db and VM.db.minimap then
            VM.db.minimap.hide = not cb:GetChecked()
        end
    end)
    panel.minimapCb = minimapCb

    -- Enable Chat Notifications checkbox
    local chatNotifCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    chatNotifCb:SetSize(20, 20)
    chatNotifCb:SetPoint("LEFT", minimapCb.label, "RIGHT", 20, 0)
    chatNotifCb.label = chatNotifCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chatNotifCb.label:SetPoint("LEFT", chatNotifCb, "RIGHT", 4, 0)
    chatNotifCb.label:SetText("Enable Chat Notifications")
    chatNotifCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.enableChatNotifications = cb:GetChecked()
    end)
    panel.chatNotifCb = chatNotifCb

    -- Default Ranking Mode Selector ("Historical values" / "Current values")
    local basisLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    basisLabel:SetPoint("TOPLEFT", 10, -256)
    basisLabel:SetText("Default Ranking Mode:")

    local basisHistBtn = CreateModernButton(panel, 120, 20, "Historical values")
    basisHistBtn:SetPoint("LEFT", basisLabel, "RIGHT", 8, 0)
    basisHistBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "locked"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
        UI:RefreshRanking()
    end)
    panel.basisHistBtn = basisHistBtn

    local basisCurrentBtn = CreateModernButton(panel, 120, 20, "Current values")
    basisCurrentBtn:SetPoint("LEFT", basisHistBtn, "RIGHT", 4, 0)
    basisCurrentBtn:SetScript("OnClick", function()
        local prefs = GetUIPrefs()
        prefs.rankingPriceMode = "live"
        if panel.UpdateBasisButtons then panel.UpdateBasisButtons() end
        UI:RefreshRanking()
    end)
    panel.basisCurrentBtn = basisCurrentBtn

    local function UpdateBasisButtons()
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
    panel.UpdateBasisButtons = UpdateBasisButtons

    -- Notify in Chat on Newer Addon Version checkbox
    local newerVerNotifCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    newerVerNotifCb:SetSize(20, 20)
    newerVerNotifCb:SetPoint("LEFT", basisCurrentBtn, "RIGHT", 20, 0)
    newerVerNotifCb.label = newerVerNotifCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    newerVerNotifCb.label:SetPoint("LEFT", newerVerNotifCb, "RIGHT", 4, 0)
    newerVerNotifCb.label:SetText("Notify in Chat on Newer Addon Version")
    newerVerNotifCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.notifyNewerVersion = cb:GetChecked()
    end)
    panel.newerVerNotifCb = newerVerNotifCb

    -- Include Legacy Members by default checkbox
    local legacyFilterCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    legacyFilterCb:SetSize(20, 20)
    legacyFilterCb:SetPoint("TOPLEFT", 10, -282)
    legacyFilterCb.label = legacyFilterCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legacyFilterCb.label:SetPoint("LEFT", legacyFilterCb, "RIGHT", 4, 0)
    legacyFilterCb.label:SetText("Include Legacy Members by default")
    legacyFilterCb:SetScript("OnClick", function(cb)
        local prefs = GetUIPrefs()
        prefs.showLegacyRanking = cb:GetChecked()
        UI:RefreshRanking()
    end)
    panel.legacyFilterCb = legacyFilterCb

    -- Section 3: Sync & Diagnostics
    local diagTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diagTitle:SetPoint("TOPLEFT", 10, -312)
    diagTitle:SetText("|cff26a6f2Sync & Diagnostics|r")

    local diagInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diagInfo:SetPoint("TOPLEFT", 10, -334)
    diagInfo:SetWidth(590)
    diagInfo:SetJustifyH("LEFT")
    panel.diagInfo = diagInfo

    local requestSyncBtn = CreateModernButton(panel, 140, 24, "Request Guild Sync", THEME.accent)
    requestSyncBtn:SetPoint("TOPRIGHT", -10, -330)
    requestSyncBtn:SetScript("OnClick", function()
        if VM.Comms and VM.Comms.SendHello then
            VM.Comms:SendHello()
        end
        if VM.Comms and VM.Comms.BroadcastLedgerSync then
            VM.Comms:BroadcastLedgerSync()
        end
        if VM.BankScanner and VM.BankScanner.ForceScan then
            VM.BankScanner:ForceScan()
        end
        VM:Print("Requested guild sync & broadcasted state.")
    end)
    panel.requestSyncBtn = requestSyncBtn

    -- Section 4: Local Maintenance
    local maintTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maintTitle:SetPoint("TOPLEFT", 10, -380)
    maintTitle:SetText("|cff26a6f2Local Maintenance|r")

    local resetPosBtn = CreateModernButton(panel, 160, 24, "Reset Window Position")
    resetPosBtn:SetPoint("TOPLEFT", 10, -402)
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

    local clearCacheBtn = CreateModernButton(panel, 140, 24, "Clear Local Cache", { 0.85, 0.35, 0.35, 1 })
    clearCacheBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", 10, 0)
    clearCacheBtn:SetScript("OnClick", function()
        if VM.db then
            VM.db.inventory = { lastScan = 0, scannedBy = "", gold = 0, tabs = {} }
            VM.db.vault = VM.db.inventory
            VM.db.processedBankLogs = {}
            VM.db.requests = {}
            VM.db.fulfillments = VM.db.requests
            VM.pendingTradePayments = {}
        end
        VM:Print("Local cache cleared (ledger, roster, and tab rules preserved).")
        if VM.UI then VM.UI:RefreshAll() end
    end)
    panel.clearCacheBtn = clearCacheBtn

    local maintDesc = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maintDesc:SetPoint("LEFT", clearCacheBtn, "RIGHT", 12, 0)
    maintDesc:SetText("Clears temporary bank and request cache without affecting ledger or rules.")
    panel.maintDesc = maintDesc
end

function UI:RefreshSettings()
    if not VM.db then VM.db = {} end
    VM.db.uiPrefs = VM.db.uiPrefs or {}
    local uiPrefs = GetUIPrefs()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[6] then return end
    local panel = mainFrame.panels[6]
    if not panel or not panel.tabRuleRows then return end
    local isOff = VM:IsOfficer()

    if panel.UpdateScaleButtons then
        panel.UpdateScaleButtons()
    end
    if panel.minimapCb then
        local showMM = (VM.db.minimap and VM.db.minimap.hide == true) and false or true
        if uiPrefs.showMinimap ~= nil then showMM = uiPrefs.showMinimap end
        panel.minimapCb:SetChecked(showMM)
    end
    if panel.UpdateBasisButtons then
        panel.UpdateBasisButtons()
    end
    if panel.legacyFilterCb then
        panel.legacyFilterCb:SetChecked(uiPrefs.showLegacyRanking ~= false)
    end
    if panel.chatNotifCb then
        panel.chatNotifCb:SetChecked(uiPrefs.enableChatNotifications ~= false)
    end
    if panel.newerVerNotifCb then
        panel.newerVerNotifCb:SetChecked(uiPrefs.notifyNewerVersion ~= false)
    end

    if panel.diagInfo then
        local gKey = VM:GetActiveGuildKey() or "None"
        local protoVer = VM.VERSION or 6
        local addonVer = VM:GetAddonVersion()
        local inv = VM.db and VM.db.inventory
        local lastScan = inv and inv.lastScan or 0
        local scanTimeStr = lastScan > 0 and date("%d/%m %H:%M", lastScan) or "Never"
        local scanBy = (inv and (inv.lastScanBy or inv.scannedBy)) or "None"

        -- Calculate rule signature status
        local validSigs = 0
        local totalRules = 0
        if VM.db and VM.db.tabRules then
            local guildName = GetGuildInfo("player") or VM:GetActiveGuildKey() or ""
            for idx, rule in pairs(VM.db.tabRules) do
                if rule then
                    totalRules = totalRules + 1
                    local expected = VM:ComputeRuleSignature(guildName, idx, rule)
                    if rule.sig and rule.sig == expected then
                        validSigs = validSigs + 1
                    end
                end
            end
        end
        local sigStatus = (totalRules == 0) and "|cffaaaaaaNo Rules Set|r" or (validSigs == totalRules and "|cff44dd77All Signatures Valid|r" or string.format("|cffff5555%d/%d Valid|r", validSigs, totalRules))

        panel.diagInfo:SetText(string.format("Addon Version: |cffffffffv%s|r  |  Protocol: |cff26a6f2v%d|r  |  Rule Signatures: %s\nLast Bank Scan: |cffffffff%s|r (%s)  |  Guild Bucket: |cffffffff%s|r",
            addonVer, protoVer, sigStatus, scanBy, scanTimeStr, gKey))
    end

    for i = 1, 6 do
        local r = panel.tabRuleRows[i]
        local isPurchased = VM:IsTabPurchased(i)
        r:Show()

        if not isPurchased then
            r.label:SetText(string.format("Tab %d: Not purchased", i))
            r.status:SetText("|cff888888Not purchased|r")

            r.freeBtn:Disable()
            r.pctBtn:Disable()
            r.lockBtn:Disable()
            r.saveBtn:Disable()
            r.pctBox:Disable()
            r.pctBox:ClearFocus()

            r.freeBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.25)
            r.freeBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.2)
            r.freeBtn.label:SetTextColor(0.35, 0.35, 0.35)

            r.pctBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.25)
            r.pctBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.2)
            r.pctBtn.label:SetTextColor(0.35, 0.35, 0.35)

            r.lockBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.25)
            r.lockBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.2)
            r.lockBtn.label:SetTextColor(0.35, 0.35, 0.35)

            r.saveBtn:SetBackdropColor(THEME.btnDisabled[1], THEME.btnDisabled[2], THEME.btnDisabled[3], 0.25)
            r.saveBtn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.2)
            r.saveBtn.label:SetTextColor(0.35, 0.35, 0.35)

            r.pctBox:SetBackdropColor(0.05, 0.06, 0.08, 0.2)
            r.pctBox:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 0.15)
            r.pctBox:SetAlpha(0.25)

            r.freeBtn:SetScript("OnClick", nil)
            r.pctBtn:SetScript("OnClick", nil)
            r.lockBtn:SetScript("OnClick", nil)
            r.saveBtn:SetScript("OnClick", nil)
            r.pctBox:SetScript("OnTextChanged", nil)
            r.pctBox:SetScript("OnEnterPressed", nil)
        else
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

            local selMode = r.selectedMode or mode
            StyleButton(r.freeBtn, selMode == "FREE", {0.10, 0.28, 0.18, 1}, {0.20, 0.80, 0.40, 1}, {0.3, 0.9, 0.5})
            StyleButton(r.pctBtn, selMode == "PERCENT", {0.32, 0.26, 0.10, 1}, {0.90, 0.70, 0.20, 1}, {1, 0.85, 0.2})
            StyleButton(r.lockBtn, selMode == "LOCKED", {0.32, 0.12, 0.12, 1}, {0.90, 0.30, 0.30, 1}, {1, 0.4, 0.4})

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

            if isOff then
                r.freeBtn:SetScript("OnClick", function()
                    r.selectedMode = "FREE"
                    UI:RefreshSettings()
                end)
                r.pctBtn:SetScript("OnClick", function()
                    r.selectedMode = "PERCENT"
                    UI:RefreshSettings()
                end)
                r.lockBtn:SetScript("OnClick", function()
                    r.selectedMode = "LOCKED"
                    UI:RefreshSettings()
                end)
                r.saveBtn:SetScript("OnClick", function()
                    local p = tonumber(r.pctBox:GetText()) or 50
                    if p <= 0 then p = 50 r.pctBox:SetText("50") end
                    r.userEditedPct = false
                    VM:SetTabRule(i, r.selectedMode, p)
                end)
                r.pctBox:SetScript("OnTextChanged", function(selfBox)
                    r.userEditedPct = true
                end)
                r.pctBox:SetScript("OnEnterPressed", function(selfBox)
                    selfBox:ClearFocus()
                    local p = tonumber(selfBox:GetText()) or 50
                    if p <= 0 then p = 50 selfBox:SetText("50") end
                    r.userEditedPct = false
                    VM:SetTabRule(i, r.selectedMode, p)
                end)
            else
                r.freeBtn:SetScript("OnClick", nil)
                r.pctBtn:SetScript("OnClick", nil)
                r.lockBtn:SetScript("OnClick", nil)
                r.saveBtn:SetScript("OnClick", nil)
                r.pctBox:SetScript("OnTextChanged", nil)
                r.pctBox:SetScript("OnEnterPressed", nil)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- OFFICER BANK POPUP
--------------------------------------------------------------------------------
function UI:CreateOfficerPopupFrame()
    popupFrame = CreateFrame("Frame", "VaultManagerOfficerPopup", UIParent, "BackdropTemplate")
    popupFrame:SetSize(480, 270)
    popupFrame:SetPoint("TOP", 0, -110)
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

    local closeBtn = CreateModernButton(popupFrame, 22, 22, "X", { 0.85, 0.25, 0.25, 1 })
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

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetPoint("LEFT", 8, 0)
            row.label:SetWidth(260)
            row.label:SetJustifyH("LEFT")

            row.prepBtn = CreateModernButton(row, 76, 22, "Prepare", THEME.accent)
            row.prepBtn:SetPoint("LEFT", 275, 0)

            row.doneBtn = CreateModernButton(row, 76, 22, "Complete", { 0.25, 0.80, 0.45, 1 })
            row.doneBtn:SetPoint("LEFT", 356, 0)

            popupFrame.scroll.rows[idx] = row
        end

        ApplyModernBackdrop(row, (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd, { 0, 0, 0, 0 })
        row:SetPoint("TOPLEFT", 2, -y)
        row:Show()
        row.label:SetText(string.format("%s: %dx %s (Tab %d)",
            VM:ColorizeName(req.requester), req.count, req.itemLink or req.itemName, req.tab))

        row.prepBtn:SetScript("OnClick", function()
            VM.Fulfillment.activeOrder = req
            print(string.format("|cff00ccff[Vault Manager]|r Withdraw %dx %s from Tab %d, then open Mail or Trade with %s.",
                req.count, req.itemName, req.tab, req.requester))
        end)

        row.doneBtn:SetScript("OnClick", function()
            VM.Fulfillment:CompleteRequest(req.id)
            local remaining = VM.Fulfillment:GetApprovedOrders()
            if #remaining == 0 then
                popupFrame:Hide()
            else
                UI:ShowOfficerBankPopup(remaining)
            end
        end)

        y = y + 30
    end
    content:SetHeight(math.max(1, y))
end

function UI:UpdateScanStatusButton()
    if not mainFrame or not mainFrame.scanStatusBtn or not VM.BankScanner then return end
    local status, text, color = VM.BankScanner:GetScanStatus()
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
    currentTab = tabIndex
    if rosterPickerFrame then rosterPickerFrame:Hide() end
    if bankValDropdownFrame then bankValDropdownFrame:Hide() end
    if exportModalFrame then exportModalFrame:Hide() end
    if assignModalFrame then assignModalFrame:Hide() end
    if rankingPeriodDropdownFrame then rankingPeriodDropdownFrame:Hide() end
    if tabIndex == 1 then
        vaultCategoryExpanded = {}
    end
    self:RefreshAll()
end
UI.ShowTab = UI.SelectTab

function UI:RefreshAll()
    if not mainFrame or not mainFrame:IsShown() then return end
    if not mainFrame.navButtons or not mainFrame.panels or not mainFrame.scanInfo then return end

    if VM.isUnguilded then
        mainFrame.scanInfo:SetText("Not in a guild")
        if mainFrame.scanStatusBtn then
            mainFrame.scanStatusBtn:SetText("No Guild")
            mainFrame.scanStatusBtn:SetBackdropColor(0.4, 0.4, 0.4, 1)
        end
        for i = 1, 6 do
            if mainFrame.panels and mainFrame.panels[i] then
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
            local diff = time() - lastScan
            local hours = math.floor(diff / 3600)
            local mins = math.floor((diff % 3600) / 60)
            local timeAgo = hours > 0 and string.format("%dh %dm", hours, mins) or string.format("%dm", mins)
            local scanBy = inv.lastScanBy or inv.scannedBy or "?"
            local syncedFrom = inv.lastSyncedFrom
            local syncNote = (syncedFrom and syncedFrom ~= "" and syncedFrom ~= VM:GetPlayerName() and syncedFrom ~= scanBy) and string.format(" (synced via %s)", syncedFrom) or ""

            local colorTag = "|cff44dd77" -- green < 6h
            if diff > 86400 then colorTag = "|cffff5555" -- red > 24h
            elseif diff > 21600 then colorTag = "|cffffcc33" end -- yellow 6-24h

            mainFrame.scanInfo:SetText(string.format("Vault scanned %s ago by %s%s", colorTag .. timeAgo .. "|r", scanBy, syncNote))
        else
            mainFrame.scanInfo:SetText("Vault not yet scanned")
        end
    end

    for i = 1, 6 do
        local btn = mainFrame.navButtons[i]
        local panel = mainFrame.panels[i]
        if btn and panel then
            if i == currentTab then
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

    if currentTab ~= 1 then
        if bankValDropdownFrame then bankValDropdownFrame:Hide() end
    end

    if currentTab == 1 then self:RefreshInventory()
    elseif currentTab == 2 then self:RefreshRequests()
    elseif currentTab == 3 then self:RefreshLedger()
    elseif currentTab == 4 then self:RefreshRanking()
    elseif currentTab == 5 then self:RefreshRoster()
    elseif currentTab == 6 then self:RefreshSettings()
    end
end

