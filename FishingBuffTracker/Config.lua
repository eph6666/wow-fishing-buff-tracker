local ADDON_NAME, NS = ...

local PANEL_WIDTH = 760
local ROW_HEIGHT = 30

local function CreateText(parent, text, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    label:SetText(text)
    return label
end

local function CreateButton(parent, text, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, 24)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function CreateCheckbox(parent, label, callback)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.text = CreateText(check, label, "GameFontHighlight")
    check.text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check:SetScript("OnClick", function(self)
        callback(self:GetChecked() and true or false)
    end)
    return check
end

local function CreateEditBox(parent, width, numeric)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    box:SetNumeric(numeric and true or false)
    box:SetMaxLetters(numeric and 10 or 60)
    box:SetTextInsets(5, 5, 0, 0)
    return box
end

local function CommitEntryEdit(box)
    local entry = box.entry
    if not entry then
        return
    end

    if box.field == "label" then
        local value = strtrim(box:GetText())
        if value ~= "" then
            entry.label = value
        end
    else
        entry[box.field] = tonumber(box:GetText()) or 0
    end
    NS:RequestRebuild()
end

local function MoveEntry(entry, direction)
    local entries = NS:GetEntries()
    for index, candidate in ipairs(entries) do
        if candidate == entry then
            local target = index + direction
            if target >= 1 and target <= #entries then
                entries[index], entries[target] = entries[target], entries[index]
                NS:RequestRebuild()
            end
            return
        end
    end
end

local function DeleteEntry(entry)
    if entry.builtin then
        entry.enabled = false
        NS:RequestRebuild()
        return
    end

    local entries = NS:GetEntries()
    for index, candidate in ipairs(entries) do
        if candidate == entry then
            table.remove(entries, index)
            NS:RequestRebuild()
            return
        end
    end
end

local function UpdateNumber(field, delta, minimum, maximum)
    local frame = NS.db.frame
    frame[field] = math.max(minimum, math.min(maximum, frame[field] + delta))
    NS:RequestRebuild()
end

local function CreateEntryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PANEL_WIDTH - 55, ROW_HEIGHT)

    row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.enabled:SetSize(24, 24)
    row.enabled:SetPoint("LEFT", 0, 0)

    row.label = CreateEditBox(row, 190, false)
    row.label:SetPoint("LEFT", 30, 0)
    row.label.field = "label"
    row.label:SetScript("OnEnterPressed", function(self)
        CommitEntryEdit(self)
        self:ClearFocus()
    end)
    row.label:SetScript("OnEditFocusLost", CommitEntryEdit)

    row.category = CreateText(row, "", "GameFontHighlightSmall")
    row.category:SetSize(54, 24)
    row.category:SetPoint("LEFT", 226, 0)
    row.category:SetJustifyH("LEFT")

    row.itemID = CreateEditBox(row, 82, true)
    row.itemID:SetPoint("LEFT", 286, 0)
    row.itemID.field = "itemID"
    row.itemID:SetScript("OnEnterPressed", function(self)
        CommitEntryEdit(self)
        self:ClearFocus()
    end)
    row.itemID:SetScript("OnEditFocusLost", CommitEntryEdit)

    row.spellID = CreateEditBox(row, 82, true)
    row.spellID:SetPoint("LEFT", 376, 0)
    row.spellID.field = "spellID"
    row.spellID:SetScript("OnEnterPressed", function(self)
        CommitEntryEdit(self)
        self:ClearFocus()
    end)
    row.spellID:SetScript("OnEditFocusLost", CommitEntryEdit)

    row.action = CreateButton(row, "", 56, function(button)
        local entry = button.entry
        if entry.action == "item" then
            entry.action = "toy"
        elseif entry.action == "toy" then
            entry.action = "item"
        end
        NS:RequestRebuild()
    end)
    row.action:SetPoint("LEFT", 466, 0)

    row.lure = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.lure:SetSize(24, 24)
    row.lure:SetPoint("LEFT", 528, 0)
    row.lure:SetScript("OnClick", function(button)
        local entry = button.entry
        entry.category = button:GetChecked() and "lure" or "custom"
        entry.hideWhenMissing = button:GetChecked() and true or false
        NS:RequestRebuild()
    end)

    row.up = CreateButton(row, "↑", 30, function(button)
        MoveEntry(button.entry, -1)
    end)
    row.up:SetPoint("LEFT", 558, 0)

    row.down = CreateButton(row, "↓", 30, function(button)
        MoveEntry(button.entry, 1)
    end)
    row.down:SetPoint("LEFT", 592, 0)

    row.delete = CreateButton(row, "×", 30, function(button)
        DeleteEntry(button.entry)
    end)
    row.delete:SetPoint("LEFT", 626, 0)

    row.enabled:SetScript("OnClick", function(button)
        button.entry.enabled = button:GetChecked() and true or false
        NS:RequestRebuild()
    end)

    function row:SetEntry(entry)
        self.entry = entry
        self.enabled.entry = entry
        self.label.entry = entry
        self.itemID.entry = entry
        self.spellID.entry = entry
        self.action.entry = entry
        self.lure.entry = entry
        self.up.entry = entry
        self.down.entry = entry
        self.delete.entry = entry

        self.enabled:SetChecked(entry.enabled)
        self.label:SetText(entry.label or "")
        self.itemID:SetText(entry.itemID or "")
        self.spellID:SetText(entry.spellID or "")
        self.category:SetText(NS.CATEGORY_LABELS[entry.category] or entry.category or "自定义")
        self.action:SetText(NS.ACTION_LABELS[entry.action] or entry.action or "物品")
        self.action:SetEnabled(entry.action ~= "macro")
        self.lure:SetChecked(entry.category == "lure")
        self.delete:SetText(entry.builtin and "停" or "×")
    end

    return row
end

function NS:CreateConfig()
    local panel = CreateFrame("Frame")
    panel.name = "Fishing Buff Tracker"
    panel:Hide()

    local title = CreateText(panel, "Fishing Buff Tracker", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)

    local subtitle = CreateText(panel, "钓鱼 Buff 状态栏与快捷物品设置", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local showBar = CreateCheckbox(panel, "显示状态栏", function(value)
        NS:SetBarVisible(value)
    end)
    showBar:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    panel.showBar = showBar

    local lock = CreateCheckbox(panel, "锁定状态栏", function(value)
        NS.db.frame.locked = value
        NS:Refresh()
    end)
    lock:SetPoint("LEFT", showBar, "LEFT", 150, 0)
    panel.lock = lock

    local unavailable = CreateCheckbox(panel, "保留无物品的缺失 Buff", function(value)
        NS.db.frame.showUnavailable = value
        NS:RequestRebuild()
    end)
    unavailable:SetPoint("LEFT", lock, "LEFT", 160, 0)
    panel.unavailable = unavailable

    local resetPosition = CreateButton(panel, "重置位置", 90, function()
        NS:ResetFramePosition()
    end)
    resetPosition:SetPoint("LEFT", unavailable, "LEFT", 230, 0)

    local defaults = CreateButton(panel, "恢复内置列表", 110, function()
        NS:ResetEntries()
    end)
    defaults:SetPoint("LEFT", resetPosition, "RIGHT", 8, 0)

    local sizeLabel = CreateText(panel, "", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", showBar, "BOTTOMLEFT", 4, -12)
    panel.sizeLabel = sizeLabel

    local sizeDown = CreateButton(panel, "-", 28, function()
        UpdateNumber("iconSize", -2, 24, 72)
    end)
    sizeDown:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
    local sizeUp = CreateButton(panel, "+", 28, function()
        UpdateNumber("iconSize", 2, 24, 72)
    end)
    sizeUp:SetPoint("LEFT", sizeDown, "RIGHT", 4, 0)

    local spacingLabel = CreateText(panel, "", "GameFontHighlight")
    spacingLabel:SetPoint("LEFT", sizeUp, "RIGHT", 28, 0)
    panel.spacingLabel = spacingLabel
    local spacingDown = CreateButton(panel, "-", 28, function()
        UpdateNumber("spacing", -1, 0, 20)
    end)
    spacingDown:SetPoint("LEFT", spacingLabel, "RIGHT", 8, 0)
    local spacingUp = CreateButton(panel, "+", 28, function()
        UpdateNumber("spacing", 1, 0, 20)
    end)
    spacingUp:SetPoint("LEFT", spacingDown, "RIGHT", 4, 0)

    local scaleLabel = CreateText(panel, "", "GameFontHighlight")
    scaleLabel:SetPoint("LEFT", spacingUp, "RIGHT", 28, 0)
    panel.scaleLabel = scaleLabel
    local scaleDown = CreateButton(panel, "-", 28, function()
        UpdateNumber("scale", -0.05, 0.5, 2)
    end)
    scaleDown:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)
    local scaleUp = CreateButton(panel, "+", 28, function()
        UpdateNumber("scale", 0.05, 0.5, 2)
    end)
    scaleUp:SetPoint("LEFT", scaleDown, "RIGHT", 4, 0)

    local header = CreateFrame("Frame", nil, panel)
    header:SetSize(PANEL_WIDTH - 55, 24)
    header:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -4, -16)
    local headers = {
        { "启用", 0 },
        { "名称", 34 },
        { "分类", 230 },
        { "ItemID", 290 },
        { "SpellID", 380 },
        { "动作", 470 },
        { "诱饵", 530 },
        { "排序", 566 },
        { "删除", 628 },
    }
    for _, info in ipairs(headers) do
        local label = CreateText(header, info[1], "GameFontNormalSmall")
        label:SetPoint("LEFT", info[2], 0)
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 118)
    panel.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH - 55, 1)
    scroll:SetScrollChild(content)
    panel.content = content
    panel.rows = {}

    local addFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    addFrame:SetPoint("BOTTOMLEFT", 16, 18)
    addFrame:SetPoint("BOTTOMRIGHT", -32, 18)
    addFrame:SetHeight(82)
    addFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    addFrame:SetBackdropColor(0.04, 0.05, 0.06, 0.45)
    addFrame:SetBackdropBorderColor(0.25, 0.3, 0.35, 0.8)

    local addTitle = CreateText(addFrame, "添加自定义 Buff", "GameFontNormal")
    addTitle:SetPoint("TOPLEFT", 10, -8)

    local addName = CreateEditBox(addFrame, 220, false)
    addName:SetPoint("TOPLEFT", 10, -38)
    addName:SetText("自定义 Buff")
    local addItem = CreateEditBox(addFrame, 100, true)
    addItem:SetPoint("LEFT", addName, "RIGHT", 12, 0)
    addItem:SetText("0")
    local addSpell = CreateEditBox(addFrame, 100, true)
    addSpell:SetPoint("LEFT", addItem, "RIGHT", 12, 0)
    addSpell:SetText("0")
    local addLure = CreateCheckbox(addFrame, "诱饵", function() end)
    addLure:SetPoint("LEFT", addSpell, "RIGHT", 10, 0)
    local addButton = CreateButton(addFrame, "添加", 70, function()
        local label = strtrim(addName:GetText())
        local itemID = tonumber(addItem:GetText()) or 0
        local spellID = tonumber(addSpell:GetText()) or 0
        if label == "" or spellID <= 0 then
            NS:Print("自定义条目至少需要名称和有效 SpellID。")
            return
        end

        table.insert(NS:GetEntries(), {
            id = "custom-" .. time() .. "-" .. math.random(1000, 9999),
            label = label,
            category = addLure:GetChecked() and "lure" or "custom",
            itemID = itemID,
            spellID = spellID,
            action = "item",
            hideWhenMissing = addLure:GetChecked() and true or false,
            enabled = true,
            builtin = false,
        })
        addName:SetText("自定义 Buff")
        addItem:SetText("0")
        addSpell:SetText("0")
        addLure:SetChecked(false)
        NS:RequestRebuild()
    end)
    addButton:SetPoint("LEFT", addLure, "RIGHT", 58, 0)

    local itemHint = CreateText(addFrame, "ItemID", "GameFontDisableSmall")
    itemHint:SetPoint("BOTTOMLEFT", addItem, "TOPLEFT", 0, 2)
    local spellHint = CreateText(addFrame, "SpellID", "GameFontDisableSmall")
    spellHint:SetPoint("BOTTOMLEFT", addSpell, "TOPLEFT", 0, 2)

    function panel:Refresh()
        if not NS.db then
            return
        end

        self.showBar:SetChecked(NS.db.frame.visible)
        self.lock:SetChecked(NS.db.frame.locked)
        self.unavailable:SetChecked(NS.db.frame.showUnavailable)
        self.sizeLabel:SetText("图标 " .. NS.db.frame.iconSize)
        self.spacingLabel:SetText("间距 " .. NS.db.frame.spacing)
        self.scaleLabel:SetText(string.format("缩放 %.2f", NS.db.frame.scale))

        local entries = NS:GetEntries()
        for index, entry in ipairs(entries) do
            local row = self.rows[index]
            if not row then
                row = CreateEntryRow(self.content)
                self.rows[index] = row
            end
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row:SetEntry(entry)
            row:Show()
        end

        for index = #entries + 1, #self.rows do
            self.rows[index]:Hide()
        end
        self.content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    end

    panel:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Fishing Buff Tracker")
    Settings.RegisterAddOnCategory(category)

    self.Config = panel
    self.ConfigCategory = category
end

function NS:OpenConfig()
    if not self.ConfigCategory then
        return
    end
    Settings.OpenToCategory(self.ConfigCategory:GetID())
end
