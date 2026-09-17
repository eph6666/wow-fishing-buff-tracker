local ADDON_NAME, NS = ...

local PANEL_WIDTH = 760
local PANEL_HEIGHT = 560
local ROW_HEIGHT = 30
local EXPORT_HEADER = "FBT-ENTRIES-1"
local EXPORT_SEPARATOR = ";"
local EXPORT_FIELDS = {
    "id", "label", "category", "itemID", "spellID", "useSpellID",
    "enchantID", "inventorySlot", "action", "macrotext",
    "requiredEquippedItemID", "hideWhenMissing", "enabled", "builtin",
}
local EXPORT_NUMBERS = {
    itemID = { 0 }, spellID = { 0 }, useSpellID = { 1 },
    enchantID = { 1 }, inventorySlot = { 1, 28 },
    requiredEquippedItemID = { 1 },
}
local EXPORT_BOOLEANS = {
    hideWhenMissing = true, enabled = true, builtin = true,
}

-- Headers and rows share the same columns. Only the name takes spare width;
-- numeric fields and action buttons keep their font size and usable hit areas.
local COLUMNS = {
    { "enabled", "启用", 24, 6 },
    { "label", "名称", nil, 8 },
    { "category", "分类", 56, 8 },
    { "itemID", "ItemID", 76, 8 },
    { "spellID", "追踪ID", 76, 8 },
    { "action", "动作", 44, 6 },
    { "lure", "诱饵", 24, 6 },
    { "up", "排序", 24, 4 },
    { "down", "", 24, 4 },
    { "delete", "删除", 28, 4 },
}
local FIXED_COLUMNS_WIDTH = 0
for _, column in ipairs(COLUMNS) do
    FIXED_COLUMNS_WIDTH = FIXED_COLUMNS_WIDTH + (column[3] or 0) + column[4]
end

local function LayoutColumns(frame, width)
    frame:SetWidth(width)
    local x = 0
    for _, column in ipairs(COLUMNS) do
        local control = frame[column[1]]
        local columnWidth = column[3] or math.max(1, width - FIXED_COLUMNS_WIDTH)
        control:SetWidth(columnWidth)
        control:SetPoint("LEFT", frame, "LEFT", x, 0)
        x = x + columnWidth + column[4]
    end
end

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

local function EncodeExportValue(value)
    if value == nil then
        return ""
    end
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    -- Keep UTF-8 names and ordinary punctuation human-readable. Only escape
    -- characters that conflict with the visible, line-based format.
    return tostring(value)
        :gsub("%%", "%%25")
        :gsub(";", "%%3B")
        :gsub("\t", "%%09")
        :gsub("\r", "%%0D")
        :gsub("\n", "%%0A")
end

local function DecodeExportValue(value)
    if value:gsub("%%[%x][%x]", ""):find("%", 1, true) then
        return nil
    end
    local decoded = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

local function SplitFields(line, separator)
    local values, start = {}, 1
    while true do
        local position = line:find(separator, start, true)
        if not position then
            values[#values + 1] = line:sub(start)
            return values
        end
        values[#values + 1] = line:sub(start, position - 1)
        start = position + 1
    end
end

function NS:ExportEntries()
    local lines = { EXPORT_HEADER }
    for _, entry in ipairs(self:GetEntries()) do
        local values = {}
        for index, field in ipairs(EXPORT_FIELDS) do
            values[index] = EncodeExportValue(entry[field])
        end
        lines[#lines + 1] = table.concat(values, EXPORT_SEPARATOR)
    end
    return table.concat(lines, "\n")
end

function NS:ImportEntries(text)
    if type(text) ~= "string" then
        return false, "导入内容不是文本。"
    end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end
    if lines[1] ~= EXPORT_HEADER then
        return false, "无法识别配置版本，请确认文本以 " .. EXPORT_HEADER .. " 开头。"
    end

    local entries, ids = {}, {}
    for lineIndex = 2, #lines do
        if lines[lineIndex] ~= "" then
            local encoded = SplitFields(lines[lineIndex], EXPORT_SEPARATOR)
            if #encoded ~= #EXPORT_FIELDS then
                return false, "第 " .. lineIndex .. " 行字段数量不正确。"
            end
            local entry = {}
            for index, field in ipairs(EXPORT_FIELDS) do
                local value = DecodeExportValue(encoded[index])
                if value == nil then
                    return false, "第 " .. lineIndex .. " 行包含无效转义。"
                end
                if EXPORT_NUMBERS[field] then
                    if value ~= "" then
                        local range = EXPORT_NUMBERS[field]
                        value = self:ParseID(value, range[1], range[2])
                        if value == nil then
                            return false, "第 " .. lineIndex .. " 行的 " .. field .. " 无效。"
                        end
                        entry[field] = value
                    end
                elseif EXPORT_BOOLEANS[field] then
                    if value ~= "" and value ~= "0" and value ~= "1" then
                        return false, "第 " .. lineIndex .. " 行的 " .. field .. " 无效。"
                    end
                    if value ~= "" then
                        entry[field] = value == "1"
                    end
                else
                    entry[field] = value ~= "" and value or nil
                end
            end
            if not entry.id or not entry.id:find("%S") or ids[entry.id] then
                return false, "第 " .. lineIndex .. " 行的条目 ID 为空或重复。"
            end
            if not entry.label or not entry.label:find("%S")
                or not entry.category or not entry.category:find("%S") then
                return false, "第 " .. lineIndex .. " 行缺少名称或分类。"
            end
            if entry.action ~= "item" and entry.action ~= "toy" and entry.action ~= "macro" then
                return false, "第 " .. lineIndex .. " 行的动作类型无效。"
            end
            if entry.action == "macro" and not entry.macrotext then
                return false, "第 " .. lineIndex .. " 行的宏内容为空。"
            end
            ids[entry.id] = true
            entries[#entries + 1] = entry
        end
    end
    if #entries == 0 then
        return false, "配置中没有 Buff 条目。"
    end

    if self.Config then
        self.Config:CancelEdits()
    end
    self.db.entries = entries
    self:RequestRebuild()
    return true, "已导入 " .. #entries .. " 个 Buff 条目。"
end

local function EntryReadOnlyReason(box)
    local entry = box.entry
    if not entry then
        return
    end
    if box.field == "itemID" and entry.action == "macro" then
        return "宏条目的 ItemID 为只读，不能单独修改。"
    elseif box.field == "spellID" and entry.enchantID then
        return "临时附魔的追踪 ID 为只读。"
    end
end

local function CanEditEntry(box)
    return box.entry ~= nil and not EntryReadOnlyReason(box)
end

local function HideEntryTooltip(box)
    if GameTooltip:IsOwned(box) then
        GameTooltip:Hide()
    end
end

local function ShowEntryTooltip(box)
    local reason = EntryReadOnlyReason(box)
    if reason then
        GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
        GameTooltip:SetText(reason)
        GameTooltip:Show()
    end
end

local function ResetEntryText(box)
    local entry = box.entry
    local value = entry and (box.field == "spellID" and entry.enchantID or entry[box.field])
    box:SetText(value or "")
    box.syncedText = box:GetText()
end

local function CancelEntryEdit(box, keepTooltip)
    -- Clear focus while still bound to the original entry, without committing
    -- or requesting a refresh from inside another refresh.
    box.cancelingEdit = true
    box:ClearFocus()
    ResetEntryText(box)
    if not keepTooltip then
        HideEntryTooltip(box)
    end
    box.cancelingEdit = nil
end

local function RefreshEntryText(box, rebound)
    local editable = CanEditEntry(box)
    local permissionChanged = box.entryEditable ~= editable
    -- Permission changes also invalidate drafts on the same bound entry,
    -- including text waiting for a delayed focus-loss callback.
    if rebound or permissionChanged or not editable then
        -- Ordinary status updates must leave the hovered read-only reason visible.
        CancelEntryEdit(box, not rebound and not permissionChanged)
    elseif not box:HasFocus() and box:GetText() == box.syncedText then
        ResetEntryText(box)
    end
    if rebound or permissionChanged then
        box.entryEditable = editable
        box:SetEnabled(editable)
        local color = editable and 1 or 0.5
        box:SetTextColor(color, color, color)
    end
end

local function CommitEntryEdit(box)
    local entry = box.entry
    if box.cancelingEdit or not entry then
        return
    end
    -- Hiding a panel/ancestor may deliver focus loss before its OnHide script.
    if not box:IsVisible() then
        CancelEntryEdit(box)
        return
    end
    -- Check the current definition as well as the last displayed permission:
    -- a callback can arrive before the editor has refreshed an action change.
    local editable = CanEditEntry(box)
    if not editable or box.entryEditable ~= editable then
        HideEntryTooltip(box)
        RefreshEntryText(box, false)
        return
    end

    local previous = entry[box.field]
    local value
    if box.field == "label" then
        value = strtrim(box:GetText())
        if value == "" then
            value = previous
        end
    else
        previous = previous or 0
        local text = strtrim(box:GetText())
        value = text == "" and 0 or NS:ParseID(text)
        if value == nil then
            ResetEntryText(box)
            NS:Print("ID 必须是 0 到 2147483647 的整数。")
            return
        end
    end
    local changed = value ~= previous
    if changed then
        entry[box.field] = value
    end
    ResetEntryText(box)
    if changed then
        NS:RequestRebuild()
    end
end

local function FinishEntryEdit(box)
    -- Enter uses the same commit path as ordinary focus loss, exactly once.
    if box:HasFocus() then
        box:ClearFocus()
    else
        CommitEntryEdit(box)
    end
end

local function MoveEntry(entry, direction)
    local entries = NS:GetEntries()
    for index, candidate in ipairs(entries) do
        if candidate == entry then
            local target = index + direction
            if target >= 1 and target <= #entries then
                NS.Config:CancelEdits()
                entries[index], entries[target] = entries[target], entries[index]
                NS:RequestRebuild()
            end
            return
        end
    end
end

local function DeleteEntry(entry)
    NS.Config:CancelEdits()
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
    local value = math.max(minimum, math.min(maximum, frame[field] + delta))
    if value ~= frame[field] then
        frame[field] = value
        NS:Refresh()
    end
end

local function CreateTransferDialog()
    local dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dialog:SetSize(620, 410)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    dialog:Hide()

    local title = CreateText(dialog, "", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetPoint("TOPRIGHT", -44, -18)
    title:SetHeight(24)
    title:SetJustifyH("LEFT")
    dialog.title = title

    local help = CreateText(dialog, "", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    help:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -24, -48)
    help:SetHeight(34)
    help:SetJustifyH("LEFT")
    dialog.help = help

    local closeX = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -5, -5)
    closeX:SetScript("OnClick", function() dialog:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -88)
    scroll:SetPoint("BOTTOMRIGHT", -42, 54)
    dialog.scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll, "InputBoxTemplate")
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetWidth(548)
    edit:SetHeight(1200)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        dialog:Hide()
    end)
    scroll:SetScrollChild(edit)
    dialog.edit = edit

    local close = CreateButton(dialog, "关闭", 80, function()
        dialog:Hide()
    end)
    close:SetPoint("BOTTOMRIGHT", -20, 18)

    local apply = CreateButton(dialog, "导入并应用", 110, function()
        local success, message = NS:ImportEntries(edit:GetText())
        NS:Print(message)
        if success then
            dialog:Hide()
        end
    end)
    apply:SetPoint("RIGHT", close, "LEFT", -8, 0)
    dialog.apply = apply

    function dialog:ShowExport()
        self.title:SetText("导出 Buff 配置")
        self.help:SetText("复制下面的全部文本并妥善保存。该文本只包含 Buff 条目，不包含状态栏位置与外观。")
        self.apply:Hide()
        self.edit:SetText(NS:ExportEntries())
        self:Show()
        self.edit:SetFocus()
        self.edit:HighlightText()
    end

    function dialog:ShowImport()
        self.title:SetText("导入 Buff 配置")
        self.help:SetText("粘贴以 FBT-ENTRIES-1 开头的完整配置文本，然后点击“导入并应用”。")
        self.apply:Show()
        self.edit:SetText("")
        self:Show()
        self.edit:SetFocus()
    end

    return dialog
end

local function CreateEntryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local boundEntry
    row:SetHeight(ROW_HEIGHT)

    row.enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.enabled:SetSize(24, 24)

    row.label = CreateEditBox(row, 1, false)
    row.label.field = "label"
    row.label:SetScript("OnEnterPressed", FinishEntryEdit)
    row.label:SetScript("OnEditFocusLost", CommitEntryEdit)

    row.category = CreateText(row, "", "GameFontHighlightSmall")
    row.category:SetHeight(24)
    row.category:SetJustifyH("LEFT")

    row.itemID = CreateEditBox(row, 76, true)
    row.itemID.field = "itemID"
    row.itemID:SetScript("OnEnterPressed", FinishEntryEdit)
    row.itemID:SetScript("OnEditFocusLost", CommitEntryEdit)
    row.itemID:SetScript("OnEnter", ShowEntryTooltip)
    row.itemID:SetScript("OnLeave", HideEntryTooltip)

    row.spellID = CreateEditBox(row, 76, true)
    row.spellID.field = "spellID"
    row.spellID:SetScript("OnEnterPressed", FinishEntryEdit)
    row.spellID:SetScript("OnEditFocusLost", CommitEntryEdit)
    row.spellID:SetScript("OnEnter", ShowEntryTooltip)
    row.spellID:SetScript("OnLeave", HideEntryTooltip)

    row.action = CreateButton(row, "", 44, function(button)
        local entry = button.entry
        if entry.action == "item" then
            entry.action = "toy"
        elseif entry.action == "toy" or entry.action == nil then
            entry.action = "item"
        end
        NS:RequestRebuild()
    end)

    row.lure = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.lure:SetSize(24, 24)
    row.lure:SetScript("OnClick", function(button)
        local entry = button.entry
        entry.category = button:GetChecked() and "lure" or "custom"
        entry.hideWhenMissing = button:GetChecked() and true or false
        NS:RequestRebuild()
    end)

    row.up = CreateButton(row, "↑", 24, function(button)
        MoveEntry(button.entry, -1)
    end)

    row.down = CreateButton(row, "↓", 24, function(button)
        MoveEntry(button.entry, 1)
    end)

    row.delete = CreateButton(row, "×", 28, function(button)
        DeleteEntry(button.entry)
    end)

    row.enabled:SetScript("OnClick", function(button)
        button.entry.enabled = button:GetChecked() and true or false
        NS:RequestRebuild()
    end)

    function row:CancelEdits()
        if not boundEntry then
            return
        end
        CancelEntryEdit(self.label)
        CancelEntryEdit(self.itemID)
        CancelEntryEdit(self.spellID)
    end

    function row:SetEntry(entry)
        local rebound = boundEntry ~= entry
        if rebound then
            self:CancelEdits()
        end
        boundEntry = entry
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

        RefreshEntryText(self.label, rebound)
        RefreshEntryText(self.itemID, rebound)
        RefreshEntryText(self.spellID, rebound)
        if not entry then
            return
        end
        self.enabled:SetChecked(entry.enabled)
        self.category:SetText(entry.enchantID and "临时附魔"
            or NS.CATEGORY_LABELS[entry.category] or entry.category or "自定义")
        self.action:SetText(NS.ACTION_LABELS[entry.action] or entry.action or "无")
        self.action:SetEnabled(entry.action ~= "macro")
        self.lure:SetChecked(entry.category == "lure")
        self.delete:SetText(entry.builtin and "停" or "×")
    end

    row:SetScript("OnHide", row.CancelEdits)
    return row
end

function NS:CreateConfig()
    local panel = CreateFrame("Frame")
    panel.name = "Fishing Buff Tracker"
    -- A creation size only: Settings DisplayLayout replaces it with SetAllPoints.
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:Hide()

    local title = CreateText(panel, "Fishing Buff Tracker", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetPoint("TOPRIGHT", -36, -16)
    title:SetHeight(22)
    title:SetJustifyH("LEFT")

    local subtitle = CreateText(panel, "钓鱼 Buff 状态栏与快捷物品设置", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 16, -44)
    subtitle:SetPoint("TOPRIGHT", -36, -44)
    subtitle:SetHeight(18)
    subtitle:SetJustifyH("LEFT")

    local showBar = CreateCheckbox(panel, "显示状态栏", function(value)
        NS:SetBarVisible(value)
    end)
    showBar:SetPoint("TOPLEFT", 16, -76)
    showBar.text:SetSize(120, 24)
    showBar.text:SetJustifyH("LEFT")
    panel.showBar = showBar

    local lock = CreateCheckbox(panel, "锁定状态栏", function(value)
        NS.db.frame.locked = value
        NS:Refresh()
    end)
    lock:SetPoint("LEFT", showBar, "LEFT", 150, 0)
    lock.text:SetSize(120, 24)
    lock.text:SetJustifyH("LEFT")
    panel.lock = lock

    local unavailable = CreateCheckbox(panel, "保留无物品的缺失 Buff", function(value)
        NS.db.frame.showUnavailable = value
        NS:Refresh()
    end)
    unavailable:SetPoint("TOPLEFT", showBar, "BOTTOMLEFT", 0, -6)
    unavailable.text:SetSize(212, 24)
    unavailable.text:SetJustifyH("LEFT")
    panel.unavailable = unavailable

    local resetPosition = CreateButton(panel, "重置位置", 90, function()
        NS:ResetFramePosition()
    end)

    local transferDialog = CreateTransferDialog()
    panel.transferDialog = transferDialog
    local exportButton = CreateButton(panel, "导出配置", 90, function()
        transferDialog:ShowExport()
    end)
    panel.exportButton = exportButton
    local importButton = CreateButton(panel, "导入配置", 90, function()
        transferDialog:ShowImport()
    end)
    panel.importButton = importButton

    local defaults = CreateButton(panel, "恢复内置列表", 110, function()
        NS:ResetEntries()
    end)
    defaults:SetPoint("TOPRIGHT", -36, -106)
    resetPosition:SetPoint("RIGHT", defaults, "LEFT", -8, 0)
    importButton:SetPoint("TOPRIGHT", -36, -76)
    exportButton:SetPoint("RIGHT", importButton, "LEFT", -8, 0)

    local numberGroups = {}
    for index = 1, 3 do
        local group = CreateFrame("Frame", nil, panel)
        group:SetHeight(24)
        numberGroups[index] = group
    end

    local sizeLabel = CreateText(numberGroups[1], "", "GameFontHighlight")
    panel.sizeLabel = sizeLabel

    local sizeDown = CreateButton(numberGroups[1], "-", 28, function()
        UpdateNumber("iconSize", -2, 24, 72)
    end)
    local sizeUp = CreateButton(numberGroups[1], "+", 28, function()
        UpdateNumber("iconSize", 2, 24, 72)
    end)

    local spacingLabel = CreateText(numberGroups[2], "", "GameFontHighlight")
    panel.spacingLabel = spacingLabel
    local spacingDown = CreateButton(numberGroups[2], "-", 28, function()
        UpdateNumber("spacing", -1, 0, 20)
    end)
    local spacingUp = CreateButton(numberGroups[2], "+", 28, function()
        UpdateNumber("spacing", 1, 0, 20)
    end)

    local scaleLabel = CreateText(numberGroups[3], "", "GameFontHighlight")
    panel.scaleLabel = scaleLabel
    local scaleDown = CreateButton(numberGroups[3], "-", 28, function()
        UpdateNumber("scale", -0.05, 0.5, 2)
    end)
    local scaleUp = CreateButton(numberGroups[3], "+", 28, function()
        UpdateNumber("scale", 0.05, 0.5, 2)
    end)
    for index, controls in ipairs({
        { sizeLabel, sizeDown, sizeUp },
        { spacingLabel, spacingDown, spacingUp },
        { scaleLabel, scaleDown, scaleUp },
    }) do
        local group = numberGroups[index]
        controls[3]:SetPoint("RIGHT", group, "RIGHT", -8, 0)
        controls[2]:SetPoint("RIGHT", controls[3], "LEFT", -4, 0)
        controls[1]:SetPoint("LEFT", group, "LEFT", 4, 0)
        controls[1]:SetPoint("RIGHT", controls[2], "LEFT", -8, 0)
        controls[1]:SetHeight(24)
        controls[1]:SetJustifyH("LEFT")
    end

    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(24)
    header:SetPoint("TOPLEFT", 16, -180)
    panel.header = header
    for _, column in ipairs(COLUMNS) do
        local label = CreateText(header, column[2], "GameFontNormalSmall")
        label:SetHeight(24)
        label:SetJustifyH("LEFT")
        header[column[1]] = label
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 118)
    panel.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
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

    local addName = CreateEditBox(addFrame, 1, false)
    addName:SetPoint("TOPLEFT", 10, -38)
    addName:SetText("自定义 Buff")
    local addItem = CreateEditBox(addFrame, 88, true)
    addItem:SetText("0")
    local addSpell = CreateEditBox(addFrame, 88, true)
    addSpell:SetText("0")
    local addLure = CreateCheckbox(addFrame, "诱饵", function() end)
    addLure.text:SetSize(28, 24)
    addLure.text:SetJustifyH("LEFT")
    local addButton = CreateButton(addFrame, "添加", 70, function()
        local label = strtrim(addName:GetText())
        local itemText, spellText = strtrim(addItem:GetText()), strtrim(addSpell:GetText())
        local itemID = itemText == "" and 0 or NS:ParseID(itemText)
        local spellID = spellText == "" and 0 or NS:ParseID(spellText)
        if label == "" or itemID == nil or spellID == nil or spellID <= 0 then
            NS:Print("请输入名称和有效整数 ID（0 到 2147483647）；SpellID 必须为正整数，ItemID 可为 0。")
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
    addButton:SetPoint("TOPRIGHT", addFrame, "TOPRIGHT", -10, -38)
    addLure:SetPoint("RIGHT", addButton, "LEFT", -42, 0)
    addSpell:SetPoint("RIGHT", addLure, "LEFT", -10, 0)
    addItem:SetPoint("RIGHT", addSpell, "LEFT", -12, 0)
    addName:SetPoint("RIGHT", addItem, "LEFT", -12, 0)

    local itemHint = CreateText(addFrame, "ItemID", "GameFontDisableSmall")
    itemHint:SetPoint("BOTTOMLEFT", addItem, "TOPLEFT", 0, 2)
    local spellHint = CreateText(addFrame, "SpellID", "GameFontDisableSmall")
    spellHint:SetPoint("BOTTOMLEFT", addSpell, "TOPLEFT", 0, 2)

    function panel:Layout()
        -- Use the canvas rect, including on first show and ancestor resizes.
        -- Do not refresh/rebind/hide controls here: even SetText with the same
        -- string would disturb the caret or an uncommitted F04 draft.
        local width = self:GetWidth() - 16 - 36
        if width <= 0 then
            return
        end
        LayoutColumns(header, width)
        content:SetWidth(width)
        for _, row in ipairs(self.rows) do
            LayoutColumns(row, width)
        end
        for index, group in ipairs(numberGroups) do
            group:SetWidth(width / 3)
            group:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (index - 1) * width / 3, -144)
        end
    end

    function panel:CancelEdits()
        -- Enter/focus loss commits. Structural actions and hiding cancel any
        -- still-pending drafts, including drafts in rows unaffected by a move.
        for _, row in ipairs(self.rows) do
            row:CancelEdits()
        end
    end

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
                LayoutColumns(row, self.content:GetWidth())
            end
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row:SetEntry(entry)
            row:Show()
        end

        for index = #entries + 1, #self.rows do
            self.rows[index]:SetEntry(nil)
            self.rows[index]:Hide()
        end
        self.content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    end

    panel:SetScript("OnShow", function(self)
        self:Layout()
        self:Refresh()
    end)
    panel:SetScript("OnSizeChanged", panel.Layout)
    panel:SetScript("OnHide", panel.CancelEdits)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Fishing Buff Tracker")
    Settings.RegisterAddOnCategory(category)

    self.Config = panel
    self.ConfigCategory = category
end

function NS:OpenConfig()
    if not self.ConfigCategory then
        return
    end
    if InCombatLockdown() then
        if not self.configOpenPending then
            self:Print("设置面板将在战斗结束后打开。")
        end
        self.configOpenPending = true
        return false
    end
    self.configOpenPending = nil
    Settings.OpenToCategory(self.ConfigCategory:GetID())
    return true
end
