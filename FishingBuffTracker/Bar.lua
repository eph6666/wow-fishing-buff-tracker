local ADDON_NAME, NS = ...

local ACTIVE_BORDER = { 0.2, 0.9, 0.35, 1 }
local MISSING_BORDER = { 1, 0.62, 0.15, 1 }
local UNAVAILABLE_BORDER = { 0.5, 0.5, 0.5, 1 }
local EQUIPMENT_BORDER = { 1, 0.2, 0.2, 1 }
local DRAG_AREA_WIDTH = 20
local CLOSE_AREA_WIDTH = 22
local RebuildBar
local RefreshBar

local function SetBorderColor(button, color)
    button.border:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function FormatTime(seconds)
    if seconds >= 3600 then
        return string.format("%dh", math.ceil(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    elseif seconds >= 10 then
        return tostring(math.ceil(seconds))
    elseif seconds > 0 then
        return string.format("%.1f", seconds)
    end
    return ""
end

local function StartMoving()
    if NS.db.frame.locked or InCombatLockdown() then
        return
    end
    NS.Bar:StartMoving()
end

local function StopMoving()
    if not NS.Bar:IsMovable() then
        return
    end

    NS.Bar:StopMovingOrSizing()
    local point, _, relativePoint, x, y = NS.Bar:GetPoint(1)
    NS.db.frame.point = point
    NS.db.frame.relativePoint = relativePoint
    NS.db.frame.x = math.floor(x + 0.5)
    NS.db.frame.y = math.floor(y + 0.5)
end

local function ConfigureSecureAction(button, entry)
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("toy", nil)
    button:SetAttribute("macrotext", nil)

    if entry.action == "toy" then
        button:SetAttribute("type", "toy")
        button:SetAttribute("toy", entry.itemID)
    elseif entry.action == "macro" and entry.macrotext then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.macrotext)
    elseif entry.itemID and entry.itemID > 0 then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. entry.itemID)
    end
end

local function ShowTooltip(button)
    local entry = button.entry
    local aura = button.aura

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if aura and entry.spellID then
        GameTooltip:SetSpellByID(entry.spellID)
    elseif entry.itemID then
        GameTooltip:SetHyperlink("item:" .. entry.itemID)
    else
        GameTooltip:SetText(entry.label or "Fishing Buff")
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine((NS.CATEGORY_LABELS[entry.category] or entry.category or "自定义")
        .. " · " .. (NS.ACTION_LABELS[entry.action] or entry.action or "物品"), 0.7, 0.8, 1)

    if aura and aura.expirationTime and aura.expirationTime > 0 then
        local remaining = math.max(0, aura.expirationTime - GetTime())
        GameTooltip:AddLine("剩余时间：" .. FormatTime(remaining), 0.2, 1, 0.3)
    elseif entry.hideWhenMissing then
        GameTooltip:AddLine("未激活时按设置隐藏。", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("缺少 Buff，点击使用对应物品。", 1, 0.75, 0.2)
    end

    if entry.requiredEquippedItemID and not NS:IsRequiredEquipmentReady(entry) then
        GameTooltip:AddLine("钓鱼工具栏位 28 未装备指定渔竿。", 1, 0.2, 0.2)
    end
    GameTooltip:AddLine("使用左侧手柄移动状态栏。", 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function CreateButton(parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.border:SetBlendMode("ADD")
    button.border:SetPoint("CENTER")
    button.border:SetSize(70, 70)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetDrawBling(false)

    button.timeText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.timeText:SetPoint("CENTER", 0, 0)
    button.timeText:SetTextColor(1, 1, 1)
    button.timeText:SetShadowOffset(1, -1)

    button.countText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.countText:SetPoint("BOTTOMRIGHT", -2, 2)
    button.countText:SetTextColor(1, 1, 1)
    button.countText:SetShadowOffset(1, -1)

    button.warning = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.warning:SetPoint("TOPLEFT", 2, -1)
    button.warning:SetText("!")
    button.warning:SetTextColor(1, 0.15, 0.15)
    button.warning:Hide()

    return button
end

local function RefreshButton(button, allowProtectedChanges, activeAuras)
    local entry = button.entry
    local aura = activeAuras[entry.spellID]
    local itemCount = NS:GetItemCount(entry)
    local equipmentReady = NS:IsRequiredEquipmentReady(entry)
    local itemIcon = entry.itemID and C_Item.GetItemIconByID(entry.itemID)
    local shouldShow = aura
        or (not entry.hideWhenMissing and (NS.db.frame.showUnavailable or itemCount > 0))

    button.aura = aura
    button.itemCount = itemCount

    if allowProtectedChanges then
        button:SetShown(shouldShow and true or false)
    end

    if not button:IsShown() then
        return false
    end

    button.icon:SetTexture(aura and aura.icon or itemIcon or 134400)
    button.icon:SetDesaturated(not aura)
    if aura then
        button.icon:SetAlpha(1)
    elseif itemCount > 0 then
        button.icon:SetAlpha(0.65)
    else
        button.icon:SetAlpha(0.4)
    end
    button.warning:SetShown(not equipmentReady)

    if aura then
        SetBorderColor(button, ACTIVE_BORDER)
        button.countText:SetText((aura.applications or 0) > 1 and aura.applications or "")
        button.cooldown:Clear()
    else
        if not equipmentReady then
            SetBorderColor(button, EQUIPMENT_BORDER)
        elseif itemCount > 0 then
            SetBorderColor(button, MISSING_BORDER)
        else
            SetBorderColor(button, UNAVAILABLE_BORDER)
        end
        button.countText:SetText(itemCount > 0 and itemCount or "0")

        if entry.itemID then
            local startTime, duration, enable = C_Item.GetItemCooldown(entry.itemID)
            if enable and startTime and duration and duration > 0 then
                button.cooldown:SetCooldown(startTime, duration)
            else
                button.cooldown:Clear()
            end
        end
    end

    return true
end

local function UpdateLayout()
    local config = NS.db.frame
    local visible = {}

    for _, button in ipairs(NS.Bar.buttons) do
        if button:IsShown() then
            table.insert(visible, button)
        end
    end

    local count = #visible
    local width = count > 0 and (count * config.iconSize + (count - 1) * config.spacing) or config.iconSize
    NS.Bar:SetSize(width + 8 + DRAG_AREA_WIDTH + CLOSE_AREA_WIDTH, config.iconSize + 8)

    for index, button in ipairs(visible) do
        button:ClearAllPoints()
        button:SetPoint(
            "LEFT",
            NS.Bar,
            "LEFT",
            DRAG_AREA_WIDTH + 4 + (index - 1) * (config.iconSize + config.spacing),
            0
        )
    end
end

function NS:CreateBar()
    local bar = CreateFrame("Frame", ADDON_NAME .. "Bar", UIParent, "BackdropTemplate")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:SetFrameStrata("MEDIUM")
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    bar:SetBackdropColor(0.04, 0.05, 0.06, 0.78)
    bar:SetBackdropBorderColor(0.3, 0.35, 0.4, 0.9)
    bar.buttons = {}

    local dragHandle = CreateFrame("Button", nil, bar)
    dragHandle:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    dragHandle:SetWidth(DRAG_AREA_WIDTH)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", StartMoving)
    dragHandle:SetScript("OnDragStop", StopMoving)
    dragHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if NS.db.frame.locked then
            GameTooltip:SetText("状态栏已锁定")
            GameTooltip:AddLine("在控制台取消“锁定状态栏”，或输入 /fbt unlock。", 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText("拖动状态栏")
            GameTooltip:AddLine("按住鼠标左键拖动。", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    dragHandle:SetScript("OnLeave", GameTooltip_Hide)

    dragHandle.lines = {}
    for index = 1, 3 do
        local line = dragHandle:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.75, 0.8, 0.85, 1)
        line:SetSize(10, 1)
        line:SetPoint("CENTER", dragHandle, "CENTER", 0, (index - 2) * 4)
        dragHandle.lines[index] = line
    end
    bar.dragHandle = dragHandle

    local closeButton = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    closeButton:SetScript("OnClick", function()
        NS:SetBarVisible(false)
    end)
    bar.closeButton = closeButton

    local config = self.db.frame
    bar:SetScale(config.scale)
    bar:SetPoint(config.point, UIParent, config.relativePoint, config.x, config.y)

    bar:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.1 then
            return
        end
        self.elapsed = 0

        for _, button in ipairs(self.buttons) do
            local aura = button.aura
            if button:IsShown() and aura and aura.expirationTime and aura.expirationTime > 0 then
                local remaining = aura.expirationTime - GetTime()
                button.timeText:SetText(FormatTime(math.max(0, remaining)))
                if remaining <= 0 then
                    NS:Refresh()
                end
            else
                button.timeText:SetText("")
            end
        end
    end)

    bar.Rebuild = RebuildBar
    bar.Refresh = RefreshBar
    self.Bar = bar
    bar:SetShown(config.visible)
end

RebuildBar = function(self)
    if InCombatLockdown() then
        NS.rebuildPending = true
        return
    end

    for _, button in ipairs(self.buttons) do
        button:Hide()
        button:SetParent(nil)
    end
    wipe(self.buttons)

    local config = NS.db.frame
    self:SetScale(config.scale)

    for _, entry in ipairs(NS:GetEntries()) do
        if entry.enabled then
            local button = CreateButton(self)
            button.entry = entry
            button:SetSize(config.iconSize, config.iconSize)
            ConfigureSecureAction(button, entry)
            table.insert(self.buttons, button)
        end
    end

    self:Refresh()
end

RefreshBar = function(self)
    local config = NS.db.frame
    local allowProtectedChanges = not InCombatLockdown()
    local activeAuras = NS:ScanAuras()

    if allowProtectedChanges then
        self:SetShown(config.visible)
        if not config.visible then
            return
        end
        self:SetScale(config.scale)
    end

    for _, button in ipairs(self.buttons) do
        if allowProtectedChanges then
            button:SetSize(config.iconSize, config.iconSize)
        end
        local visible = RefreshButton(button, allowProtectedChanges, activeAuras)
        if not visible then
            button.timeText:SetText("")
        end
    end

    if allowProtectedChanges then
        UpdateLayout()
    end
    self.dragHandle:SetAlpha(config.locked and 0.25 or 0.9)
    self:SetBackdropColor(0.04, 0.05, 0.06, config.locked and 0.45 or 0.78)
end
