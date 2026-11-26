local _, VM = ...
VM.Minimap = {}
local MM = VM.Minimap

local BUTTON_RADIUS = 80
local VAULT_ICON = "Interface\\Icons\\INV_Box_02"
local minimapBtn

local function UpdatePosition(angleDeg)
    if not minimapBtn then return end
    local rad = math.rad(angleDeg or 220)
    local x = math.cos(rad) * BUTTON_RADIUS
    local y = math.sin(rad) * BUTTON_RADIUS
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CountOpenRequests()
    local pendingCount = 0
    local approvedCount = 0
    if not VM.db or not VM.db.requests or VM.isUnguilded then
        return 0, 0
    end

    local isOff = VM:IsOfficer()
    if isOff then
        for _, req in pairs(VM.db.requests) do
            if req.status == "PENDING" then
                pendingCount = pendingCount + 1
            elseif req.status == "APPROVED" then
                approvedCount = approvedCount + 1
            end
        end
    else
        local myMain = VM:GetMainFor(VM:GetPlayerName())
        for _, req in pairs(VM.db.requests) do
            if req.status == "PENDING" or req.status == "APPROVED" then
                local reqMain = VM:GetMainFor(req.requester or "")
                if reqMain ~= "" and myMain ~= "" and reqMain:lower() == myMain:lower() then
                    if req.status == "PENDING" then
                        pendingCount = pendingCount + 1
                    else
                        approvedCount = approvedCount + 1
                    end
                end
            end
        end
    end

    return pendingCount, approvedCount
end

function MM:GetOpenRequestCounts()
    return CountOpenRequests()
end

function MM:UpdateBadge()
    if not minimapBtn or not VM.db then return end
    if VM.isUnguilded then
        minimapBtn.badge:Hide()
        return
    end

    local pendingCount, approvedCount = CountOpenRequests()
    local total = pendingCount + approvedCount

    if total > 0 then
        local isOff = VM:IsOfficer()
        if isOff then
            if pendingCount > 0 then
                minimapBtn.badge:SetBackdropColor(0.85, 0.18, 0.18, 1) -- Red: needs approval
            else
                minimapBtn.badge:SetBackdropColor(0.15, 0.55, 0.90, 1) -- Blue: approved ready for delivery
            end
        else
            if approvedCount > 0 then
                minimapBtn.badge:SetBackdropColor(0.20, 0.72, 0.35, 1) -- Green: own request approved
            else
                minimapBtn.badge:SetBackdropColor(0.85, 0.65, 0.15, 1) -- Yellow: own request pending
            end
        end

        local label = (total > 99) and "99+" or tostring(total)
        minimapBtn.badge:SetWidth((#label >= 2) and 20 or 16)
        minimapBtn.badgeText:SetText(label)
        minimapBtn.badge:Show()
    else
        minimapBtn.badge:Hide()
    end
end

-- Supports both MM:SetHidden(hide) and MM.SetHidden(hide)
function MM:SetHidden(hideArg)
    local hide
    if self == MM then
        hide = hideArg and true or false
    else
        hide = self and true or false
    end

    if VM.db then
        VM.db.minimap = VM.db.minimap or { angle = 220, hide = false }
        VM.db.minimap.hide = hide
        if VM.db.uiPrefs then
            VM.db.uiPrefs.showMinimap = not hide
        end
    end

    if minimapBtn then
        if hide then
            minimapBtn:Hide()
        else
            minimapBtn:Show()
            MM:UpdateBadge()
        end
    end
end

function MM:Create()
    if minimapBtn then
        self:UpdateBadge()
        return
    end

    VM.db = VM.db or {}
    VM.db.minimap = VM.db.minimap or { angle = 220, hide = false }
    local shouldHide = VM.db.minimap.hide == true
    if VM.db.uiPrefs and VM.db.uiPrefs.showMinimap == false then
        shouldHide = true
    end

    minimapBtn = CreateFrame("Button", "VaultManagerMinimapButton", Minimap)
    minimapBtn:SetSize(31, 31)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:EnableMouse(true)
    minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapBtn:RegisterForDrag("LeftButton")

    if shouldHide then
        minimapBtn:Hide()
    else
        minimapBtn:Show()
    end

    -- Standard circular minimap border
    local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER", 0, 0)

    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(VAULT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER", 0, 0)
    minimapBtn.icon = icon

    local highlight = minimapBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("CENTER", 0, 0)

    -- Notification badge (open requests count)
    local badge = CreateFrame("Frame", nil, minimapBtn, "BackdropTemplate")
    badge:SetSize(16, 16)
    badge:SetPoint("BOTTOMRIGHT", 2, -2)
    if not badge.SetBackdrop then Mixin(badge, BackdropTemplateMixin) end
    badge:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
    })
    badge:SetBackdropColor(0.85, 0.18, 0.18, 1)
    badge:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    badge:Hide()
    minimapBtn.badge = badge

    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badgeText:SetPoint("CENTER", 0, 0)
    badgeText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    minimapBtn.badgeText = badgeText

    -- Drag around the minimap
    minimapBtn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if VM.db then
                VM.db.minimap = VM.db.minimap or {}
                VM.db.minimap.angle = angle
            end
            UpdatePosition(angle)
        end)
    end)

    minimapBtn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Click actions
    minimapBtn:SetScript("OnClick", function(self, button)
        if self.isDragging then return end
        if not VM.UI then return end
        if button == "LeftButton" then
            VM.UI:Toggle()
        elseif button == "RightButton" then
            local f = _G["VaultManagerMainFrame"]
            if not f or not f:IsShown() then
                VM.UI:Toggle()
            end
            if VM.UI.SelectTab then
                VM.UI:SelectTab(2)
            end
        end
    end)

    -- Status tooltip
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local ver = VM.GetAddonVersion and VM:GetAddonVersion() or "1.4.3"
        GameTooltip:AddLine(string.format("|cff26a6f2Vault Manager|r |cff8899aa(v%s)|r", ver))

        if VM.isUnguilded then
            GameTooltip:AddLine("Not in a guild", 0.65, 0.65, 0.65)
        else
            if VM.newerVersionAvailable then
                GameTooltip:AddLine("A newer version is available on CurseForge!", 1, 0.8, 0.2)
            end

            local pendingCount, approvedCount = CountOpenRequests()
            local isOff = VM:IsOfficer()
            if pendingCount > 0 or approvedCount > 0 then
                GameTooltip:AddLine(" ")
                local reqHeader = isOff and "Open Guild Requests:" or "Your Open Requests:"
                GameTooltip:AddLine(reqHeader, 0.9, 0.9, 0.9)
                if pendingCount > 0 then
                    GameTooltip:AddLine(string.format("  |cffffcc33%d Pending|r", pendingCount))
                end
                if approvedCount > 0 then
                    GameTooltip:AddLine(string.format("  |cff26a6f2%d Approved|r", approvedCount))
                end
            else
                GameTooltip:AddLine("No open requests", 0.6, 0.6, 0.6)
            end

            local inv = VM.db and VM.db.inventory
            local lastScan = inv and inv.lastScan or 0
            if lastScan > 0 then
                local diff = math.max(0, time() - lastScan)
                local hours = math.floor(diff / 3600)
                local mins = math.floor((diff % 3600) / 60)
                local timeAgo = hours > 0 and string.format("%dh %dm", hours, mins) or string.format("%dm", mins)
                local scanBy = inv.lastScanBy or inv.scannedBy or "?"
                GameTooltip:AddLine(string.format("Last scan: |cffffffff%s ago|r by %s", timeAgo, scanBy), 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Last scan: Never", 0.6, 0.6, 0.6)
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffffLeft-click:|r Open / close window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffRight-click:|r Open Requests tab", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag:|r Move button around minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition(VM.db.minimap.angle)
    self:UpdateBadge()
end

-- Event-driven creation and badge refresh (no polling ticker)
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() MM:Create() end)
        else
            MM:Create()
        end
    else
        if minimapBtn then
            MM:UpdateBadge()
        end
    end
end)
