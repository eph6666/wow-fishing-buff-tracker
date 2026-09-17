local ADDON_NAME, NS = ...

local ACTIVE_BORDER = { 0.2, 0.9, 0.35, 1 }
local UNKNOWN_BORDER = { 0.6, 0.73, 1, 1 }
local MISSING_BORDER = { 1, 0.62, 0.15, 1 }
local UNAVAILABLE_BORDER = { 0.5, 0.5, 0.5, 1 }
local EQUIPMENT_BORDER = { 1, 0.2, 0.2, 1 }
local DRAG_AREA_WIDTH = 20
local CLOSE_AREA_WIDTH = 22
local CONTENT_INSET = 4
local VERTICAL_PADDING = 12
local RebuildBar
local RefreshBar

local function SetBorderColor(button, color)
    button.border:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function CreateAlignedBorder(button)
    local border = { edges = {} }

    local function Edge()
        local texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        border.edges[#border.edges + 1] = texture
        return texture
    end

    local top = Edge()
    top:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    top:SetHeight(2)

    local bottom = Edge()
    bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, -1)
    bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    bottom:SetHeight(2)

    local left = Edge()
    left:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, -1)
    left:SetWidth(2)

    local right = Edge()
    right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(2)

    function border:SetVertexColor(red, green, blue, alpha)
        self.vertexColor = { red, green, blue, alpha }
        for _, edge in ipairs(self.edges) do
            edge:SetVertexColor(red, green, blue, alpha)
        end
    end

    return border
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
    if not NS.Bar or NS.barMoving or NS.db.frame.locked or InCombatLockdown() then
        return
    end
    NS.Bar:StartMoving()
    NS.barMoving = true
end

function NS:StopBarMoving()
    local bar = self.Bar
    if not bar or not self.barMoving then
        self.barMoving = nil
        self.barStopPending = nil
        self.pendingDragPosition = nil
        return
    end
    if InCombatLockdown() then
        -- StopMovingOrSizing is protected even if movement began before combat.
        -- Capture the first release position now; otherwise the native moving
        -- frame keeps following the cursor and regen would save the wrong spot.
        if not self.pendingDragPosition then
            local point, _, relativePoint, x, y = bar:GetPoint(1)
            self.pendingDragPosition = {
                point = point,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
        self.barStopPending = true
        return
    end

    local pending = self.pendingDragPosition
    bar:StopMovingOrSizing()
    if pending then
        bar:ClearAllPoints()
        bar:SetPoint(pending.point, UIParent, pending.relativePoint, pending.x, pending.y)
    end
    self.barMoving = nil
    self.barStopPending = nil
    self.pendingDragPosition = nil
    local point, relativePoint, x, y
    if pending then
        point, relativePoint, x, y =
            pending.point, pending.relativePoint, pending.x, pending.y
    else
        local ignored
        point, ignored, relativePoint, x, y = bar:GetPoint(1)
    end
    self.db.frame.point = point
    self.db.frame.relativePoint = relativePoint
    self.db.frame.x = math.floor(x + 0.5)
    self.db.frame.y = math.floor(y + 0.5)
end

local function StopMoving()
    NS:StopBarMoving()
end

local function ResetButton(button)
    if GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
    end
    button:Hide()
    button:ClearAllPoints()
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("toy", nil)
    button:SetAttribute("macro", nil)
    button:SetAttribute("macrotext", nil)

    button.entry = nil
    button.effect = nil
    button.itemCount = nil
    button.icon:SetTexture(nil)
    button.icon:SetDesaturated(false)
    button.icon:SetAlpha(1)
    SetBorderColor(button, UNAVAILABLE_BORDER)
    button.cooldown:Clear()
    button.countText:SetText("")
    button.timeText:SetText("")
    button.warning:Hide()
end

local function ConfigureSecureAction(button, entry)
    if entry.action == "toy" and entry.itemID and entry.itemID > 0 then
        button:SetAttribute("type", "toy")
        button:SetAttribute("toy", entry.itemID)
    elseif entry.action == "macro" and entry.macrotext then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.macrotext)
    elseif entry.action == "item" and entry.itemID and entry.itemID > 0 then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. entry.itemID)
    end
end

local function ShowTooltip(button)
    local entry = button.entry
    if not entry then
        return
    end
    local effect = button.effect

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if effect and not effect.unknown and not entry.enchantID and entry.spellID and entry.spellID > 0 then
        GameTooltip:SetSpellByID(entry.spellID)
    elseif entry.itemID and entry.itemID > 0 then
        GameTooltip:SetHyperlink("item:" .. entry.itemID)
    else
        GameTooltip:SetText(entry.label or "Fishing Buff")
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine((NS.CATEGORY_LABELS[entry.category] or entry.category or "自定义")
        .. " · " .. (NS.ACTION_LABELS[entry.action] or entry.action or "无动作"), 0.7, 0.8, 1)

    -- Effects contain only Core's checked scalars, never raw API Aura/enchant data.
    if effect and effect.unknown then
        GameTooltip:AddLine("状态未知：效果数据暂不可读取。", 0.6, 0.73, 1)
    elseif effect then
        if effect.expirationTime == nil then
            GameTooltip:AddLine("已激活，剩余时间未知。", 0.6, 0.73, 1)
        elseif effect.expirationTime > 0 then
            local remaining = math.max(0, effect.expirationTime - GetTime())
            GameTooltip:AddLine("剩余时间：" .. FormatTime(remaining), 0.2, 1, 0.3)
        else
            GameTooltip:AddLine(entry.enchantID and "临时附魔已激活。" or "Buff 已激活。", 0.2, 1, 0.3)
        end
        if effect.chargesRemaining == nil and effect.applications == nil then
            GameTooltip:AddLine(entry.enchantID and "剩余次数未知。" or "层数未知。", 0.6, 0.73, 1)
        end
    elseif entry.hideWhenMissing then
        GameTooltip:AddLine("未激活时按设置隐藏。", 0.7, 0.7, 0.7)
    elseif entry.enchantID then
        GameTooltip:AddLine("缺少临时附魔，点击使用对应物品。", 1, 0.75, 0.2)
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
    -- Secure actions must receive both phases: the ActionButtonUseKeyDown CVar
    -- decides whether the client executes the action on mouse-down or mouse-up.
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:EnableMouse(true)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Four explicit edges share the button's exact bounds. Blizzard's
    -- UI-ActionButton-Border is oversized, rounded and optically offset, which
    -- does not align with these square item icons at custom sizes.
    button.border = CreateAlignedBorder(button)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:EnableMouse(false)
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
    local effect = NS:GetEntryEffect(entry, activeAuras)
    local itemCount = NS:GetItemCount(entry)
    local equipmentReady = NS:IsRequiredEquipmentReady(entry)
    local itemIcon = entry.itemID and entry.itemID > 0 and C_Item.GetItemIconByID(entry.itemID)
    local shouldShow = effect
        or (not entry.hideWhenMissing and (NS.db.frame.showUnavailable or itemCount > 0))

    button.effect = effect
    button.itemCount = itemCount
    local refreshTooltip = GameTooltip:IsShown() and GameTooltip:IsOwned(button)

    if allowProtectedChanges then
        button:SetShown(shouldShow and true or false)
    end

    if not button:IsShown() then
        if refreshTooltip then
            GameTooltip:Hide()
        end
        return false
    end

    button.icon:SetTexture(effect and effect.icon or itemIcon or 134400)
    button.icon:SetDesaturated(not effect or effect.unknown == true)
    if effect then
        button.icon:SetAlpha(1)
    elseif itemCount > 0 then
        button.icon:SetAlpha(0.65)
    else
        button.icon:SetAlpha(0.4)
    end
    button.warning:SetShown(not equipmentReady)

    if effect and effect.unknown then
        SetBorderColor(button, UNKNOWN_BORDER)
        button.countText:SetText("")
        button.cooldown:Clear()
    elseif effect then
        SetBorderColor(button, ACTIVE_BORDER)
        local count = effect.chargesRemaining or effect.applications
        button.countText:SetText(count == nil and "?" or (count > 1 and count or ""))
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

        if entry.itemID and entry.itemID > 0 then
            local startTime, duration, enable = C_Item.GetItemCooldown(entry.itemID)
            if enable and startTime and duration and duration > 0 then
                button.cooldown:SetCooldown(startTime, duration)
            else
                button.cooldown:Clear()
            end
        end
    end

    if effect and effect.expirationTime == nil then
        button.timeText:SetText("?")
    else
        local remaining = effect and effect.expirationTime > 0 and effect.expirationTime - GetTime() or 0
        button.timeText:SetText(FormatTime(math.max(0, remaining)))
    end
    if refreshTooltip then
        ShowTooltip(button)
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
    local leftAreaWidth = config.locked
        and CONTENT_INSET
        or DRAG_AREA_WIDTH + CONTENT_INSET
    NS.Bar:SetSize(
        width + leftAreaWidth + CONTENT_INSET + CLOSE_AREA_WIDTH,
        config.iconSize + VERTICAL_PADDING
    )

    for index, button in ipairs(visible) do
        button:ClearAllPoints()
        button:SetPoint(
            "LEFT",
            NS.Bar,
            "LEFT",
            leftAreaWidth + (index - 1) * (config.iconSize + config.spacing),
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
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0.04, 0.05, 0.06, 0.78)
    bar:SetBackdropBorderColor(0.38, 0.43, 0.48, 0.9)
    bar.buttons = {}
    bar.buttonPool = {}
    bar.appliedEntries = {}
    bar:SetScript("OnHide", StopMoving)

    local dragHandle = CreateFrame("Button", nil, bar)
    dragHandle:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    -- Include the gap before the first icon in the handle's visual region so
    -- its glyph is centered between the outer border and the first icon.
    dragHandle:SetWidth(DRAG_AREA_WIDTH + CONTENT_INSET)
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

    local dragGlyph = CreateFrame("Frame", nil, dragHandle)
    dragGlyph:SetSize(12, 12)
    dragGlyph:SetPoint("CENTER", dragHandle, "CENTER", 0, 0)
    dragHandle.glyph = dragGlyph
    dragHandle.lines = {}
    for index = 1, 3 do
        local line = dragGlyph:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.75, 0.8, 0.85, 1)
        line:SetSize(12, 1)
        line:SetPoint("CENTER", dragGlyph, "CENTER", 0, (index - 2) * 4)
        dragHandle.lines[index] = line
    end
    bar.dragHandle = dragHandle

    local closeButton = CreateFrame("Button", nil, bar)
    closeButton:SetSize(26, 26)
    -- The right visual region includes CLOSE_AREA_WIDTH plus CONTENT_INSET.
    closeButton:SetPoint(
        "CENTER",
        bar,
        "RIGHT",
        -(CLOSE_AREA_WIDTH + CONTENT_INSET) / 2,
        0
    )

    local closeNormal = closeButton:CreateTexture(nil, "ARTWORK")
    closeNormal:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeNormal:SetSize(24, 24)
    closeNormal:SetPoint("CENTER")
    closeButton.normalTexture = closeNormal

    local closePushed = closeButton:CreateTexture(nil, "ARTWORK")
    closePushed:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closePushed:SetSize(24, 24)
    closePushed:SetPoint("CENTER")
    closePushed:Hide()
    closeButton.pushedTexture = closePushed

    local closeHighlight = closeButton:CreateTexture(nil, "HIGHLIGHT")
    closeHighlight:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeHighlight:SetBlendMode("ADD")
    closeHighlight:SetSize(26, 26)
    closeHighlight:SetPoint("CENTER")
    closeButton.highlightTexture = closeHighlight

    closeButton:SetScript("OnMouseDown", function(self)
        self.normalTexture:Hide()
        self.pushedTexture:Show()
    end)
    closeButton:SetScript("OnMouseUp", function(self)
        self.pushedTexture:Hide()
        self.normalTexture:Show()
    end)
    closeButton:SetScript("OnClick", function()
        NS:SetBarVisible(false)
    end)
    bar.closeButton = closeButton

    local config = self.db.frame
    bar:SetScale(config.scale)
    bar:SetPoint(config.point, UIParent, config.relativePoint, config.x, config.y)

    bar:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then
            return
        end
        self.enchantElapsed = (self.enchantElapsed or 0) + elapsed
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.1 then
            return
        end
        self.elapsed = 0
        local now = GetTime()

        -- Slot 28 may change without a player Aura event. Poll only enchantment
        -- buttons, including missing ones, without refreshing the settings editor.
        local pollEnchantments = self.enchantElapsed >= 1
        if pollEnchantments then
            self.enchantElapsed = 0
        end
        local layoutChanged = false
        local expiredAura = false
        for _, button in ipairs(self.buttons) do
            local effect = button.effect
            if button.entry.enchantID and (pollEnchantments
                or (effect and effect.expirationTime and effect.expirationTime > 0
                    and effect.expirationTime <= now)) then
                local wasShown = button:IsShown()
                RefreshButton(button, not InCombatLockdown())
                layoutChanged = layoutChanged or wasShown ~= button:IsShown()
                effect = button.effect
            end
            local remaining = effect and effect.expirationTime and effect.expirationTime > 0
                and effect.expirationTime - now
            if remaining and remaining <= 0 and not button.entry.enchantID then
                expiredAura = true
            end
            if button:IsShown() and effect and effect.expirationTime == nil then
                button.timeText:SetText("?")
            elseif button:IsShown() and remaining then
                button.timeText:SetText(FormatTime(math.max(0, remaining)))
            else
                button.timeText:SetText("")
            end
        end
        -- API remnants share one retry per second, using the same absolute
        -- clock as Aura expiration. Keep this deadline across rebuilds/hides;
        -- new expirations share the remaining delay, while events/show still
        -- refresh immediately. Timer retries never refresh the settings editor.
        if expiredAura and (not self.nextAuraRetryAt or now >= self.nextAuraRetryAt) then
            self.nextAuraRetryAt = now + 1
            self:Refresh()
        elseif layoutChanged then
            UpdateLayout()
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

    -- Only an allowed rebuild applies settings to actions, display and tracking.
    local appliedEntries = NS:CopyEntries()
    wipe(self.buttons)

    local config = NS.db.frame

    -- Reuse slots, including buttons currently hidden by a missing effect.
    -- The pool grows only with the largest applied enabled list, never by ID.
    for _, entry in ipairs(appliedEntries) do
        if entry.enabled then
            local index = #self.buttons + 1
            local button = self.buttonPool[index]
            if not button then
                button = CreateButton(self)
                self.buttonPool[index] = button
            end
            ResetButton(button)
            button.entry = entry
            button:SetSize(config.iconSize, config.iconSize)
            ConfigureSecureAction(button, entry)
            table.insert(self.buttons, button)
        end
    end
    for index = #self.buttons + 1, #self.buttonPool do
        local button = self.buttonPool[index]
        if button.entry then
            ResetButton(button)
        end
    end

    self.appliedEntries = appliedEntries
    self:Refresh()
end

RefreshBar = function(self)
    local config = NS.db.frame
    if config.locked or not config.visible then
        NS:StopBarMoving()
    end
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
        self.dragHandle:SetShown(not config.locked)
    end
    self.dragHandle:SetAlpha(0.9)
    self:SetBackdropColor(0.04, 0.05, 0.06, config.locked and 0.45 or 0.78)
end
