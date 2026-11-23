local _, VM = ...
VM.UI = {}
local UI = VM.UI

local mainFrame
local popupFrame
local rosterPickerFrame
local exportModalFrame
local currentTab = 1
local selectedBankTab = 1
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
end

function UI:Toggle()
    if not mainFrame then self:CreateMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
        if rosterPickerFrame then rosterPickerFrame:Hide() end
        if exportModalFrame then exportModalFrame:Hide() end
    else
        if IsInGuild() then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
            elseif GuildRoster then GuildRoster() end
        end
        mainFrame:Show()
        self:RefreshAll()
    end
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
    exportModalFrame:Show()
    self:RefreshExportContent()
end

function UI:RefreshExportContent()
    if not exportModalFrame or not exportModalFrame:IsShown() then return end
    local isCSV = exportModalFrame.csvToggle:GetChecked()
    local useHist = VM.db.uiPrefs.useHistoricalPrices
    local ranked = VM.Ledger:GetDonationRanking("TOTAL", useHist)

    local lines = {}
    if isCSV then
        table.insert(lines, "Main,TotalInValue,GoldIn,ItemsIn")
        for _, grp in ipairs(ranked) do
            table.insert(lines, string.format("%s,%d,%d,%d",
                grp.mainName, grp.totalInValue, grp.totalGoldIn, grp.totalItemsIn))
        end
    else
        table.insert(lines, "| Main Character | Total Donated | Pure Gold | Mats & Gear |")
        table.insert(lines, "|---|---|---|---|")
        for _, grp in ipairs(ranked) do
            table.insert(lines, string.format("| %s | %s | %s | %s |",
                grp.mainName,
                VM:FormatMoney(grp.totalInValue),
                VM:FormatMoney(grp.totalGoldIn),
                VM:FormatMoney(grp.totalItemsIn)))
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
            row.label:SetText(isLeg and ("|cff808080" .. name .. " (Legacy)|r") or name)

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
-- MAIN FRAME (5 TABS)
--------------------------------------------------------------------------------
function UI:CreateMainFrame()
    mainFrame = CreateFrame("Frame", "VaultManagerMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(800, 560)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    ApplyModernBackdrop(mainFrame, THEME.bg, THEME.border)
    mainFrame:Hide()
    table.insert(UISpecialFrames, "VaultManagerMainFrame")

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
    title:SetText("|cff26a6f2VAULT|r |cffffffffMANAGER|r")

    mainFrame.scanInfo = headerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mainFrame.scanInfo:SetPoint("RIGHT", -42, 0)
    mainFrame.scanInfo:SetTextColor(0.65, 0.70, 0.78)

    local closeBtn = CreateModernButton(headerBar, 24, 24, "X", { 0.85, 0.25, 0.25, 1 })
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function()
        mainFrame:Hide()
        if rosterPickerFrame then rosterPickerFrame:Hide() end
        if exportModalFrame then exportModalFrame:Hide() end
    end)

    local tabNames = { "Vault & Requests", "Requests", "Ledger", "Ranking", "Settings & Mains" }
    mainFrame.navButtons = {}
    for i, name in ipairs(tabNames) do
        local btn = CreateModernButton(mainFrame, 148, 28, name)
        btn:SetPoint("TOPLEFT", 14 + (i - 1) * 156, -48)

        btn.activeBar = btn:CreateTexture(nil, "OVERLAY")
        btn.activeBar:SetHeight(2)
        btn.activeBar:SetPoint("BOTTOMLEFT", 1, 1)
        btn.activeBar:SetPoint("BOTTOMRIGHT", -1, 1)
        btn.activeBar:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        btn.activeBar:Hide()

        btn:SetScript("OnClick", function()
            currentTab = i
            if rosterPickerFrame then rosterPickerFrame:Hide() end
            self:RefreshAll()
        end)
        mainFrame.navButtons[i] = btn
    end

    mainFrame.panels = {}
    for i = 1, 5 do
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
    self:BuildSettingsPanel(mainFrame.panels[5])
end

--------------------------------------------------------------------------------
-- TAB 1: VAULT & REQUESTS
--------------------------------------------------------------------------------
function UI:BuildInventoryPanel(panel)
    panel.bankTabButtons = {}
    for i = 1, 6 do
        local b = CreateModernButton(panel, 82, 24, "Tab " .. i)
        b:SetPoint("TOPLEFT", 10 + (i - 1) * 86, -10)
        b:SetScript("OnClick", function()
            selectedBankTab = i
            self:RefreshInventory()
        end)
        panel.bankTabButtons[i] = b
    end

    local scanBtn = CreateModernButton(panel, 78, 24, "Scan Now", { 0.25, 0.80, 0.45, 1 })
    scanBtn:SetPoint("TOPRIGHT", -156, -10)
    scanBtn:SetScript("OnClick", function()
        if VM.BankScanner and VM.BankScanner.ForceScan then
            VM.BankScanner:ForceScan()
            print("|cff00ccff[Vault Manager]|r Scanning Guild Bank tabs and logs...")
        end
    end)
    panel.scanBtn = scanBtn

    local searchBox = CreateModernEditBox(panel, 140, 24, false)
    searchBox:SetPoint("TOPRIGHT", -10, -10)
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

    panel.ruleBanner = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.ruleBanner:SetPoint("TOPLEFT", 12, -40)

    panel.scroll = CreateScrollArea(panel, -60, 8)
end

function UI:RefreshInventory()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[1] then return end
    local panel = mainFrame.panels[1]
    if not panel or not panel.scroll or not panel.bankTabButtons then return end
    local inv = VM.db and VM.db.inventory
    if not inv or not inv.tabs then return end

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
    if rule.mode == "LOCKED" then
        panel.ruleBanner:SetText("|cffff5555LOCKED TAB|r  |cff999999— Requests disabled|r")
    elseif rule.mode == "PERCENT" then
        panel.ruleBanner:SetText(string.format("|cffffcc33MEMBER PRICE: %d%% OF AUCTION HOUSE|r  |cff999999— Paid upon delivery|r", rule.percent or 50))
    else
        panel.ruleBanner:SetText("|cff44dd77FREE-FOR-ALL|r  |cff999999— Free withdrawal (AH value tracked in ledger)|r")
    end

    local content = panel.scroll.content
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    local tabData = inv.tabs[selectedBankTab]
    if not tabData then return end

    local items = {}
    for _, item in pairs(tabData.items) do
        if searchQuery == "" or (item.name and item.name:lower():find(searchQuery, 1, true)) then
            table.insert(items, item)
        end
    end
    table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)

    local y = 0
    for idx, item in ipairs(items) do
        local row = panel.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 30)
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", 8, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.nameBtn = CreateFrame("Button", nil, row)
            row.nameBtn:SetSize(265, 26)
            row.nameBtn:SetPoint("LEFT", 36, 0)
            row.nameText = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetAllPoints()
            row.nameText:SetJustifyH("LEFT")

            row.stockText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.stockText:SetPoint("LEFT", 310, 0)
            row.stockText:SetWidth(135)
            row.stockText:SetJustifyH("LEFT")

            row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.priceText:SetPoint("LEFT", 450, 0)
            row.priceText:SetWidth(130)
            row.priceText:SetJustifyH("LEFT")

            row.qtyBox = CreateModernEditBox(row, 42, 22, true)
            row.qtyBox:SetPoint("LEFT", 588, 0)
            row.qtyBox:SetText("1")

            row.reqBtn = CreateModernButton(row, 84, 22, "Request", THEME.accent)
            row.reqBtn:SetPoint("LEFT", 638, 0)

            panel.scroll.rows[idx] = row
        end

        local baseBg = (idx % 2 == 0) and THEME.rowEven or THEME.rowOdd
        ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
        row:SetScript("OnEnter", function(selfRow)
            selfRow:SetBackdropColor(THEME.rowHover[1], THEME.rowHover[2], THEME.rowHover[3], THEME.rowHover[4])
        end)
        row:SetScript("OnLeave", function(selfRow)
            selfRow:SetBackdropColor(baseBg[1], baseBg[2], baseBg[3], baseBg[4])
        end)

        row:SetPoint("TOPLEFT", 4, -y)
        row:Show()

        local reserved = VM:GetReservedCount(item.itemID, selectedBankTab)
        local available = math.max(0, item.count - reserved)

        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.nameText:SetText(item.link or item.name)
        row.nameBtn:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            if item.link and item.link:find("item:") then
                GameTooltip:SetHyperlink(item.link)
            else
                GameTooltip:SetText(item.name or "Item")
            end
            GameTooltip:Show()
        end)
        row.nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if reserved > 0 then
            row.stockText:SetText(string.format("Available: |cff44dd77%d|r |cff888888(Res: %d)|r", available, reserved))
        else
            row.stockText:SetText(string.format("In Stock: |cff44dd77%d|r", available))
        end

        if VM:HasPriceAddon() then
            local ah = VM:GetItemAHPrice(item.itemID)
            if ah then
                if rule.mode == "PERCENT" then
                    local memberPrice = math.floor(ah * ((rule.percent or 50) / 100))
                    row.priceText:SetText("Price: " .. VM:FormatMoney(memberPrice))
                else
                    row.priceText:SetText("AH: " .. VM:FormatMoney(ah))
                end
            else
                row.priceText:SetText("|cff777777AH: Unknown|r")
            end
        else
            row.priceText:SetText("")
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

        y = y + 32
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

        local statusColors = {
            PENDING = "|cffffcc33PENDING|r",
            APPROVED = "|cff26a6f2APPROVED|r",
            FULFILLED = "|cff44dd77FULFILLED|r",
            REJECTED = "|cffff5555REJECTED|r"
        }

        local priceNote = ""
        if req.quotedUnitPrice and req.quotedUnitPrice > 0 then
            priceNote = "  |cffaaaaaa(" .. VM:FormatMoney(req.quotedUnitPrice * req.count) .. ")|r"
        end

        row.info:SetText(string.format("[%s]  |cffffffff%s|r  —  %dx %s%s",
            statusColors[req.status] or req.status,
            req.requester, req.count, req.itemLink or req.itemName, priceNote))

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
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local priceToggle = CreateFrame("CheckButton", nil, topBar, "UICheckButtonTemplate")
    priceToggle:SetSize(22, 22)
    priceToggle:SetPoint("LEFT", 0, 0)
    priceToggle:SetChecked(VM.db.uiPrefs.useHistoricalPrices)

    local toggleLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleLabel:SetPoint("LEFT", priceToggle, "RIGHT", 4, 0)
    toggleLabel:SetText("Historical price (otherwise live AH)")

    priceToggle:SetScript("OnClick", function(cb)
        VM.db.uiPrefs.useHistoricalPrices = cb:GetChecked()
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

    local useHist = VM.db.uiPrefs.useHistoricalPrices
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
        ApplyModernBackdrop(header, grp.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or THEME.rowEven, THEME.border)
        header:SetPoint("TOPLEFT", 4, -y)

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
            header.text:SetText(string.format("|cff808080%s [Legacy Member]|r  |cff707070—  Received: %s  |  Donated: %s%s  (%d entries)|r",
                grp.mainName,
                VM:FormatMoney(grp.totalOutValue),
                VM:FormatMoney(grp.totalInValue),
                goldSubNote,
                #grp.transactions))
        else
            header.text:SetText(string.format("|cffffcc33%s|r  —  Received: %s  |  Donated: %s%s  |cff999999(%d entries)|r",
                grp.mainName,
                VM:FormatMoney(grp.totalOutValue),
                VM:FormatMoney(grp.totalInValue),
                goldSubNote,
                #grp.transactions))
        end

        y = y + 30

        if isExpanded then
            for _, tx in ipairs(grp.transactions) do
                local sub = GetRow()
                ApplyModernBackdrop(sub, THEME.rowOdd, { 0, 0, 0, 0 })
                sub:SetPoint("TOPLEFT", 4, -y)
                sub.expandBtn:Hide()
                sub.text:SetPoint("LEFT", 40, 0)
                sub.actionBtn:Hide()

                local isGold = (tx.itemID == 0 or tx.itemLink == "GOLD")
                local dir = (tx.type == "OUT") and (isGold and "|cffff6666GOLD OUT|r" or "|cffff6666OUT|r") or (isGold and "|cffffd700GOLD IN|r" or "|cff44dd77IN|r")
                local val = VM.Ledger:GetTransactionValue(tx, useHist)
                local dateStr = date("%d/%m %H:%M", tx.timestamp or 0)
                local charTag = (tx.player ~= grp.mainName and tx.player ~= "UNATTRIBUTED") and (" (" .. tx.player .. ")") or ""

                if isGold then
                    sub.text:SetText(string.format("|cff999999%s|r [%s]%s: %s",
                        dateStr, dir, charTag, VM:FormatMoney(val)))
                elseif grp.isLegacy then
                    sub.text:SetText(string.format("|cff808080%s [%s]%s: %dx %s — Value: %s|r",
                        dateStr, tx.type == "OUT" and "OUT" or "IN", charTag, tx.count, tx.itemName, VM:FormatMoney(val)))
                else
                    sub.text:SetText(string.format("|cff999999%s|r [%s]%s: %dx %s  —  Value: %s",
                        dateStr, dir, charTag, tx.count, tx.itemLink or tx.itemName, VM:FormatMoney(val)))
                end

                if grp.mainName == "UNATTRIBUTED" and VM:IsOfficer() then
                    sub.actionBtn:Show()
                    sub.actionBtn:SetScript("OnClick", function()
                        UI:OpenRosterPicker(sub.actionBtn, false, function(chosenName)
                            VM.Ledger:AssignUnattributed(tx.id, chosenName)
                        end)
                    end)
                elseif VM:IsOfficer() then
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
-- TAB 4: RANKING (Top Donors: Total / Pure Gold / Mats + Gear)
--------------------------------------------------------------------------------
function UI:BuildRankingPanel(panel)
    local topBar = CreateFrame("Frame", nil, panel)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", 10, -8)
    topBar:SetPoint("TOPRIGHT", -10, -8)

    local filterLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    filterLabel:SetPoint("LEFT", 2, 0)
    filterLabel:SetText("Rank by:")

    panel.sortButtons = {}
    local modes = {
        { key = "TOTAL", label = "Total Value" },
        { key = "GOLD", label = "Pure Gold" },
        { key = "ITEMS", label = "Mats + Gear" },
    }

    for i, m in ipairs(modes) do
        local btn = CreateModernButton(topBar, 110, 24, m.label)
        btn:SetPoint("LEFT", 60 + (i - 1) * 116, 0)
        btn:SetScript("OnClick", function()
            rankingSortMode = m.key
            UI:RefreshRanking()
        end)
        panel.sortButtons[m.key] = btn
    end

    local exportBtn = CreateModernButton(topBar, 76, 24, "Export", THEME.accent)
    exportBtn:SetPoint("RIGHT", 0, 0)
    exportBtn:SetScript("OnClick", function()
        UI:OpenExportModal()
    end)

    -- Column headers
    local colHeader = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    colHeader:SetSize(744, 24)
    colHeader:SetPoint("TOPLEFT", 10, -44)
    ApplyModernBackdrop(colHeader, { 0.06, 0.07, 0.09, 1 }, THEME.border)

    local cRank = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cRank:SetPoint("LEFT", 10, 0)
    cRank:SetText("#")

    local cName = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cName:SetPoint("LEFT", 48, 0)
    cName:SetText("Player (Main)")

    local cGold = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cGold:SetPoint("LEFT", 290, 0)
    cGold:SetText("Pure Gold")

    local cItems = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cItems:SetPoint("LEFT", 435, 0)
    cItems:SetText("Mats + Gear")

    local cTotal = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cTotal:SetPoint("LEFT", 585, 0)
    cTotal:SetText("Total Value")

    panel.scroll = CreateScrollArea(panel, -72, 8)
end

function UI:RefreshRanking()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[4] then return end
    local panel = mainFrame.panels[4]
    if not panel or not panel.scroll or not panel.sortButtons then return end
    local content = panel.scroll.content
    if not content then return end

    for key, btn in pairs(panel.sortButtons) do
        if key == rankingSortMode then
            btn:SetBackdropColor(0.15, 0.28, 0.42, 1)
            btn:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            btn:SetBackdropColor(THEME.btnBg[1], THEME.btnBg[2], THEME.btnBg[3], 1)
            btn:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        end
    end

    local content = panel.scroll.content
    for _, r in ipairs(panel.scroll.rows) do r:Hide() end

    local useHist = VM.db.uiPrefs.useHistoricalPrices
    local ranked = VM.Ledger:GetDonationRanking(rankingSortMode, useHist)

    local y = 0
    for idx, grp in ipairs(ranked) do
        local row = panel.scroll.rows[idx]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(732, 28)

            row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.rankText:SetPoint("LEFT", 10, 0)
            row.rankText:SetWidth(35)
            row.rankText:SetJustifyH("LEFT")

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 48, 0)
            row.nameText:SetWidth(230)
            row.nameText:SetJustifyH("LEFT")

            row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.goldText:SetPoint("LEFT", 286, 0)
            row.goldText:SetWidth(135)
            row.goldText:SetJustifyH("LEFT")

            row.itemsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.itemsText:SetPoint("LEFT", 431, 0)
            row.itemsText:SetWidth(140)
            row.itemsText:SetJustifyH("LEFT")

            row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.totalText:SetPoint("LEFT", 581, 0)
            row.totalText:SetWidth(145)
            row.totalText:SetJustifyH("LEFT")

            panel.scroll.rows[idx] = row
        end

        local baseBg = grp.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or ((idx % 2 == 0) and THEME.rowEven or THEME.rowOdd)
        ApplyModernBackdrop(row, baseBg, { 0, 0, 0, 0 })
        row:SetPoint("TOPLEFT", 6, -y)
        row:Show()

        if grp.isLegacy then
            row.rankText:SetText("|cff808080-|r")
            row.nameText:SetText("|cff808080" .. grp.mainName .. " [Legacy]|r")
            row.goldText:SetText("|cff808080" .. VM:FormatMoney(grp.totalGoldIn) .. "|r")
            row.itemsText:SetText("|cff808080" .. VM:FormatMoney(grp.totalItemsIn) .. "|r")
            row.totalText:SetText("|cff808080" .. VM:FormatMoney(grp.totalInValue) .. "|r")
        else
            local rankBadge = tostring(idx)
            if idx == 1 then rankBadge = "|cffffd700#1|r"
            elseif idx == 2 then rankBadge = "|cffc0c0c0#2|r"
            elseif idx == 3 then rankBadge = "|cffcd7f32#3|r"
            else rankBadge = "|cff888888#" .. idx .. "|r" end

            row.rankText:SetText(rankBadge)
            row.nameText:SetText("|cffffffff" .. grp.mainName .. "|r")
            row.goldText:SetText(VM:FormatMoney(grp.totalGoldIn))
            row.itemsText:SetText(VM:FormatMoney(grp.totalItemsIn))
            row.totalText:SetText("|cff44dd77" .. VM:FormatMoney(grp.totalInValue) .. "|r")
        end

        y = y + 30
    end

    content:SetHeight(math.max(1, y))
end

--------------------------------------------------------------------------------
-- TAB 5: SETTINGS & MAINS (Hierarchical Roster Tree & Bank Tab Rules)
--------------------------------------------------------------------------------
function UI:BuildSettingsPanel(panel)
    local ruleTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleTitle:SetPoint("TOPLEFT", 14, -12)
    ruleTitle:SetText("|cff26a6f2GUILD BANK TAB RULES|r  |cff888888(Officers / GM Only)|r")

    panel.tabRuleRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        r:SetSize(744, 26)
        r:SetPoint("TOPLEFT", 14, -32 - (i - 1) * 28)
        ApplyModernBackdrop(r, (i % 2 == 0) and THEME.rowEven or THEME.rowOdd, { 0, 0, 0, 0 })

        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.label:SetPoint("LEFT", 10, 0)
        r.label:SetWidth(175)
        r.label:SetJustifyH("LEFT")

        r.freeBtn = CreateModernButton(r, 100, 20, "Free-for-All")
        r.freeBtn:SetPoint("LEFT", 195, 0)

        r.pctBtn = CreateModernButton(r, 100, 20, "% of AH")
        r.pctBtn:SetPoint("LEFT", 300, 0)

        r.pctBox = CreateModernEditBox(r, 40, 20, true)
        r.pctBox:SetPoint("LEFT", 405, 0)

        r.lockBtn = CreateModernButton(r, 90, 20, "Locked")
        r.lockBtn:SetPoint("LEFT", 450, 0)

        r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.status:SetPoint("LEFT", 550, 0)

        panel.tabRuleRows[i] = r
    end

    local rosterTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rosterTitle:SetPoint("TOPLEFT", 14, -208)
    rosterTitle:SetText("|cff26a6f2GUILD ROSTER & MAIN/ALT HIERARCHY TREE|r")

    local searchBox = CreateModernEditBox(panel, 180, 22, false)
    searchBox:SetPoint("TOPLEFT", 14, -230)
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchBox.placeholder:SetPoint("LEFT", 8, 0)
    searchBox.placeholder:SetText("Filter character...")
    searchBox:SetScript("OnTextChanged", function(selfBox)
        local txt = selfBox:GetText()
        if txt == "" then selfBox.placeholder:Show() else selfBox.placeholder:Hide() end
        settingsSearchFilter = txt:lower()
        UI:RefreshSettings()
    end)
    panel.searchBox = searchBox

    if VM:IsOfficer() then
        local autoSuggestBtn = CreateModernButton(panel, 130, 22, "Auto-Suggest Alts", THEME.accent)
        autoSuggestBtn:SetPoint("TOPLEFT", 200, -230)
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
            UI:RefreshSettings()
        end)
    end

    panel.treeScroll = CreateScrollArea(panel, -258, 8)
end

function UI:RefreshSettings()
    if not mainFrame or not mainFrame.panels or not mainFrame.panels[5] then return end
    local panel = mainFrame.panels[5]
    if not panel or not panel.tabRuleRows or not panel.treeScroll then return end
    local content = panel.treeScroll.content
    if not content then return end
    local isOff = VM:IsOfficer()

    for i = 1, 6 do
        local r = panel.tabRuleRows[i]
        local tabData = VM.db.inventory.tabs[i]
        if tabData then
            r:Show()
            local rule = VM:GetTabRule(i)
            r.label:SetText(string.format("Tab %d: %s", i, tabData.name or ""))
            r.pctBox:SetText(tostring(rule.percent or 50))

            if rule.mode == "LOCKED" then
                r.status:SetText("|cffff5555Locked|r")
            elseif rule.mode == "PERCENT" then
                r.status:SetText("|cffffcc33" .. (rule.percent or 50) .. "% AH|r")
            else
                r.status:SetText("|cff44dd77Free-for-All|r")
            end

            if isOff then
                r.freeBtn:SetModernEnabled(true)
                r.pctBtn:SetModernEnabled(true)
                r.lockBtn:SetModernEnabled(true)
                r.freeBtn:SetScript("OnClick", function() VM:SetTabRule(i, "FREE", 0) end)
                r.pctBtn:SetScript("OnClick", function()
                    local p = tonumber(r.pctBox:GetText()) or 50
                    VM:SetTabRule(i, "PERCENT", p)
                end)
                r.lockBtn:SetScript("OnClick", function() VM:SetTabRule(i, "LOCKED", 0) end)
            else
                r.freeBtn:SetModernEnabled(false)
                r.pctBtn:SetModernEnabled(false)
                r.lockBtn:SetModernEnabled(false)
            end
        else
            r:Hide()
        end
    end

    local content = panel.treeScroll.content
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

        -- Filter check
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
            local row = GetTreeRow()
            ApplyModernBackdrop(row, mainEntry.isLegacy and { 0.08, 0.08, 0.09, 0.85 } or THEME.rowEven, THEME.border)
            row:SetPoint("TOPLEFT", 4, -y)

            row.expandBtn:SetPoint("LEFT", 4, 0)
            if hasAlts then
                row.expandBtn:Show()
                row.expandBtn:SetText(isExpanded and "-" or "+")
                row.expandBtn:SetScript("OnClick", function()
                    expandedTreeMains[mainName] = not expandedTreeMains[mainName]
                    UI:RefreshSettings()
                end)
            else
                row.expandBtn:Hide()
            end

            row.label:SetPoint("LEFT", hasAlts and 30 or 10, 0)
            if mainEntry.isLegacy then
                row.label:SetText(string.format("|cff808080%s [Legacy]%s|r", mainName, hasAlts and string.format(" (%d alts)", #alts) or ""))
            else
                row.label:SetText(string.format("|cffffcc33%s|r%s", mainName, hasAlts and string.format(" |cff888888(%d alts)|r", #alts) or ""))
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
                        local subRow = GetTreeRow()
                        ApplyModernBackdrop(subRow, THEME.rowOdd, { 0, 0, 0, 0 })
                        subRow:SetPoint("TOPLEFT", 4, -y)

                        subRow.expandBtn:Hide()
                        subRow.label:SetPoint("LEFT", 35, 0)
                        subRow.label:SetText(string.format("|cffaaaaaa└─ %s|r", altName))

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
        row.label:SetText(string.format("|cffffcc33%s|r: %dx %s (Tab %d)",
            req.requester, req.count, req.itemLink or req.itemName, req.tab))

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

function UI:RefreshAll()
    if not mainFrame or not mainFrame:IsShown() then return end
    if not mainFrame.navButtons or not mainFrame.panels or not mainFrame.scanInfo then return end

    if VM.newerVersionAvailable then
        mainFrame.scanInfo:SetText("|cffffcc33Update available|r")
    else
        local inv = VM.db and VM.db.inventory
        if inv and inv.lastScan and inv.lastScan > 0 then
            mainFrame.scanInfo:SetText(string.format("Last scanned: %s by %s",
                date("%d/%m %H:%M", inv.lastScan), inv.scannedBy or "?"))
        else
            mainFrame.scanInfo:SetText("Not scanned yet (Open Guild Bank)")
        end
    end

    for i = 1, 5 do
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

    if currentTab == 1 then self:RefreshInventory()
    elseif currentTab == 2 then self:RefreshRequests()
    elseif currentTab == 3 then self:RefreshLedger()
    elseif currentTab == 4 then self:RefreshRanking()
    elseif currentTab == 5 then self:RefreshSettings()
    end
end
