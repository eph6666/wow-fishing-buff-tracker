-- Runs the actual Blizzard Lua dispatcher against the addon's configured buttons.
-- This verifies Lua dispatch, not hardware authorization or item effects in WoW.
-- lua5.1 tests/blizzard_contract.lua FishingBuffTracker /path/to/wow-ui-source
local addonPath = assert(arg[1], "addon path is required")
local sourcePath = assert(arg[2], "Blizzard UI source root is required")
local scriptDirectory = arg[0]:match("^(.*[/\\])") or ""
local Mock = dofile(scriptDirectory .. "wow_mock.lua")
local state = Mock.new(addonPath)
state:login()
local env = state.env
local sourceAddons = sourcePath .. "/Interface/AddOns/"

local function loadSource(relativePath, targetEnv)
    local chunk = assert(loadfile(sourceAddons .. relativePath))
    setfenv(chunk, targetEnv or env)
    chunk()
end
env.CopyTable = function(value)
    local copy = {}
    for key, item in pairs(value) do copy[key] = item end
    return copy
end
env.GetFrameMetatable = function()
    return { __index = {
        GetAttribute = function(frame, prefix, name, suffix)
            if not name then return frame.attributes[prefix] end
            local attributes = frame.attributes
            -- Only plain type/item/toy/macrotext attributes are configured here.
            return attributes[prefix .. name .. suffix] or attributes["*" .. name .. suffix]
                or attributes[prefix .. name .. "*"] or attributes[name]
        end,
        GetParent = function(frame) return frame.parent end,
    } }
end
env.C_PaperDollInfo = {
    GetInventorySlotInfo = function(slot) return slot == "MainHandSlot" and 16 or 17 end,
    IsRangedSlotShown = function() return false end,
}
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
env.IsAltKeyDown = function() return false end
env.SpellCanTargetItem = function() return false end
env.SpellCanTargetItemID = function() return false end
local useKeyDown, useHeldSpell = false, false
env.GetCVarBool = function(name)
    if name == "ActionButtonUseKeyDown" then return useKeyDown end
    if name == "ActionButtonUseKeyHeldSpell" then return useHeldSpell end
    error("unexpected CVar: " .. name)
end
env.C_Item.IsEquippableItem = function() return false end
env.SecureCmdItemParse = function(item) return item end
local actions = {}
env.SecureCmdUseItem = function(item) actions[#actions + 1] = { "item", item } end
env.UseToy = function(itemID) actions[#actions + 1] = { "toy", itemID } end
env.C_Macro = {
    RunMacroText = function(text) actions[#actions + 1] = { "macro", text } end,
}
loadSource("Blizzard_FrameXML/SecureTemplates.lua")

local cases = {
    { state:button("oversized-bobber"), "toy", 202207 },
    { state:button("haranir-phial"), "item", "item:241316" },
    { state:button("pointed-spikesnail"), "macro", "/use item:262651\n/use 28" },
}
local passed = 0
local function click(button, mouseButton)
    for _, phase in ipairs(button.registeredClicks) do
        env.SecureActionButton_OnClick(button, mouseButton, phase == "AnyDown")
    end
end
for _, down in ipairs({ false, true }) do
    useKeyDown = down
    for _, held in ipairs({ false, true }) do
        useHeldSpell = held
        for _, mouseButton in ipairs({ "LeftButton", "RightButton" }) do
            for _, case in ipairs(cases) do
                actions = {}
                click(case[1], mouseButton)
                assert(#actions == 1, "expected exactly one action per click")
                assert(actions[1][1] == case[2] and actions[1][2] == case[3], "wrong action payload")
                passed = passed + 1
            end
        end
    end
end
print("PASS Blizzard SecureTemplates dispatch: " .. passed .. " click/CVar cases")

-- F07: execute the dispatcher on the same frame as its entry/type changes.
-- Released frames must also be inert, even if a late click reaches the handler.
local reusedButton = state.ns.Bar.buttons[1]
local configuredEntries = state.ns:GetEntries()
local reuseEntry = {
    id = "source-reuse", label = "Reused action", category = "custom",
    itemID = 900001, spellID = 800001, action = "item", enabled = true,
}
state.ns.db.entries = { reuseEntry }
local reusedClicks, releasedClicks = 0, 0
for _, action in ipairs({ "item", "toy", "macro" }) do
    reuseEntry.action, reuseEntry.macrotext = action, "/use item:900001"
    state.ns:RequestRebuild()
    assert(state.ns.Bar.buttons[1] == reusedButton and state:secureFrameCount() == 8)
    for _, down in ipairs({ false, true }) do
        useKeyDown = down
        for _, held in ipairs({ false, true }) do
            useHeldSpell = held
            for _, mouseButton in ipairs({ "LeftButton", "RightButton" }) do
                actions = {}
                click(reusedButton, mouseButton)
                local expected = action == "item" and "item:900001"
                    or action == "toy" and 900001 or reuseEntry.macrotext
                assert(#actions == 1 and actions[1][1] == action and actions[1][2] == expected,
                    "reused button dispatched stale or duplicate action")
                reusedClicks = reusedClicks + 1
            end
        end
    end
end
reuseEntry.enabled = false
state.ns:RequestRebuild()
assert(#state.ns.Bar.buttons == 0 and reusedButton.entry == nil)
for _, down in ipairs({ false, true }) do
    useKeyDown = down
    for _, held in ipairs({ false, true }) do
        useHeldSpell = held
        for _, mouseButton in ipairs({ "LeftButton", "RightButton" }) do
            actions = {}
            click(reusedButton, mouseButton)
            assert(#actions == 0, "released button retained a secure action")
            releasedClicks = releasedClicks + 1
        end
    end
end
state.ns.db.entries = configuredEntries
state.ns:RequestRebuild()
assert(state:secureFrameCount() == 8)
print("PASS Blizzard F07 reused-frame dispatch: " .. reusedClicks .. " click/CVar cases, "
    .. releasedClicks .. " inert released-frame cases")

-- Negative control: reproduce the previous AnyUp-only failure with the same source.
local itemButton = state:button("haranir-phial")
itemButton.registeredClicks = { "AnyUp" }
useKeyDown, useHeldSpell = true, false
actions = {}
click(itemButton, "LeftButton")
assert(#actions == 0, "negative control did not reproduce the old missing click")
print("PASS negative control: AnyUp-only drops the action when useKeyDown=true")

-- Targeted lookup avoids AuraUtil.GetAuraSlots, which taint-fails when player
-- Auras become secret. Verify the consumed fields and make the old path fatal.
local data = {
    [397827] = { spellId = 397827, icon = 2, expirationTime = 300, applications = 1 },
    [1302820] = { spellId = 1302820, icon = 3, expirationTime = 400, applications = 1 },
}
local queries = {}
env.C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID)
        queries[#queries + 1] = spellID
        return data[spellID]
    end,
    GetAuraSlots = function()
        error("targeted addon scan must not call taint-prone GetAuraSlots")
    end,
}
local active = state.ns:ScanAuras()
local function assertAuraFields(actual, expected)
    assert(actual and not actual.unknown, "targeted lookup lost a watched buff")
    for _, field in ipairs({ "spellId", "icon", "expirationTime", "applications" }) do
        assert(actual[field] == expected[field], "aura field changed: " .. field)
    end
end
assertAuraFields(active[397827], data[397827])
assertAuraFields(active[1302820], data[1302820])
queries = {}
assertAuraFields(state.ns:FindAura(397827), data[397827])
assert(#queries == 1 and queries[1] == 397827, "FindAura must issue one targeted lookup")
print("PASS targeted Aura lookup: watched fields, filtering, no GetAuraSlots")

-- Strict accessor stubs cannot emulate client secrets or taint, but verify that
-- targeted results are sanitized before their fields reach display code.
local access = Mock.restrictedAPI(state)
data = {
    [397827] = access:table({
        spellId = 397827, icon = access:value(),
        expirationTime = access:value(), applications = access:value(),
    }),
    [393714] = access:table({
        spellId = 393714, icon = 4, expirationTime = 500, applications = 2,
    }),
    [1302820] = access:table({}, { tableReadable = false }),
}
active = state.ns:ScanAuras()
assert(active[397827].spellId == 397827 and active[393714].spellId == 393714)
assert(active[397827].expirationTime == nil and active[397827].applications == nil
    and active[397827].icon == nil, "restricted fields escaped sanitizing")
assert(active[393714].expirationTime == 500 and active[393714].applications == 2)
assert(active[1236763] == nil, "missing targeted Aura was not reported missing")
assert(active[1302820].unknown, "inaccessible targeted Aura was not reported unknown")
queries = {}
assert(state.ns:FindAura(397827).spellId == 397827)
assert(#queries == 1 and queries[1] == 397827)
assert(state.ns:FindAura(1236763) == nil)
state.ns:Refresh()
assert(state:button("oversized-bobber").timeText:GetText() == "?")
assert(state:button("crystalline-phial").countText:GetText() == "2")
print("PASS targeted Aura lookup: restricted result sanitizing (not client secrets)")

local function documentation(relativePath)
    local result
    env.APIDocumentation = {
        AddDocumentationTable = function(_, value) result = value end,
    }
    loadSource("Blizzard_APIDocumentationGenerated/" .. relativePath)
    return assert(result)
end
local frameScriptDocumentation = documentation("FrameScriptDocumentation.lua")
local accessFunctions = { canaccesstable = true, canaccessvalue = true, issecretvalue = true }
for _, fn in ipairs(frameScriptDocumentation.Functions) do
    if accessFunctions[fn.Name] then
        assert(fn.SecretArguments == "AllowedWhenUntainted")
        assert(#fn.Arguments == 1 and fn.Arguments[1].Type == "LuaValueReference")
        assert(#fn.Returns == 1 and fn.Returns[1].Type == "bool")
        accessFunctions[fn.Name] = nil
    end
end
assert(next(accessFunctions) == nil, "required access predicate missing")
local auraDocumentation = documentation("UnitAuraDocumentation.lua")
local checkedAuraAccess = false
for _, fn in ipairs(auraDocumentation.Functions) do
    if fn.Name == "GetPlayerAuraBySpellID" then
        assert(fn.RequiresNonSecretAura and fn.SecretWhenUnitAuraRestricted)
        assert(fn.SecretArguments == "AllowedWhenTainted")
        assert(#fn.Arguments == 1 and fn.Arguments[1].Type == "SpellIdentifier")
        assert(fn.Returns[1].Type == "AuraData" and fn.Returns[1].Nilable)
        checkedAuraAccess = true
    end
end
assert(checkedAuraAccess, "targeted player Aura access contract missing")
print("PASS Blizzard F03 aura restrictions and access predicate signatures (source contract only)")

-- Generated API documentation: confirm the cooldown enable flag is a boolean.
local itemDocumentation
env.APIDocumentation = {
    AddDocumentationTable = function(_, value) itemDocumentation = value end,
}
loadSource("Blizzard_APIDocumentationGenerated/ItemDocumentation.lua")
local checkedCount, checkedCooldown = false, false
for _, fn in ipairs(itemDocumentation.Functions) do
    if fn.Name == "GetItemCooldown" then
        assert(fn.Returns[3].Type == "bool", "cooldown enable return type changed")
        checkedCooldown = true
    elseif fn.Name == "GetItemCount" then
        assert(#fn.Arguments == 5, "item count parameter contract changed")
        checkedCount = true
    end
end
assert(checkedCount and checkedCooldown, "item APIs missing")
print("PASS Blizzard item API signatures")

-- F01: pin the new slot-based API and the profession slot to this source build.
local paperDollDocumentation
env.APIDocumentation.AddDocumentationTable = function(_, value) paperDollDocumentation = value end
loadSource("Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua")
local checkedEnchantAPI, checkedEnchantInfo = false, false
for _, fn in ipairs(paperDollDocumentation.Functions) do
    if fn.Name == "GetTemporaryEnchantmentInfo" then
        assert(fn.MayReturnNothing, "no-enchantment return contract changed")
        assert(#fn.Arguments == 1 and fn.Arguments[1].Type == "LuaInventorySlot")
        assert(#fn.Returns == 1 and fn.Returns[1].Type == "TemporaryItemEnchantInfo")
        checkedEnchantAPI = true
    end
end
for _, structure in ipairs(paperDollDocumentation.Tables) do
    if structure.Name == "TemporaryItemEnchantInfo" then
        local expected = {
            enchantID = "number", remainingTimeMs = "number",
            chargesRemaining = "number", hasExpirationTime = "bool",
        }
        for _, field in ipairs(structure.Fields) do
            assert(expected[field.Name] == field.Type and field.Nilable == false,
                "temporary enchantment field contract changed: " .. field.Name)
            expected[field.Name] = nil
        end
        assert(next(expected) == nil, "temporary enchantment fields missing")
        checkedEnchantInfo = true
    end
end
assert(checkedEnchantAPI and checkedEnchantInfo, "temporary enchantment API missing")
local xmlFile = assert(io.open(sourceAddons .. "Blizzard_Professions/Blizzard_ProfessionsCrafting.xml"))
local fishingSlot = xmlFile:read("*a"):match('<ItemButton parentKey="FishingToolSlot".-</ItemButton>')
xmlFile:close()
assert(fishingSlot and fishingSlot:find('key="slotID" value="28" type="number"', 1, true),
    "fishing tool inventory slot changed")
print("PASS Blizzard temporary enchantment API and fishing slot 28 (source contract only)")

-- F06: pin the native geometry APIs and size callback used by Config.lua.
env.Enum = {}
for _, filename in ipairs({ "SecretAspectConstantsDocumentation.lua", "ForbiddenAspectConstantsDocumentation.lua" }) do
    for _, enumeration in ipairs(documentation(filename).Tables) do
        local values = {}
        for _, field in ipairs(enumeration.Fields) do values[field.Name] = field.EnumValue end
        env.Enum[enumeration.Name] = values
    end
end

-- F09: the source marks both movement mutations protected. Their native
-- execution and combat/taint propagation are outside this Lua contract test.
local movementAPIs = { StartMoving = true, StopMovingOrSizing = true }
for _, fn in ipairs(documentation("SimpleFrameAPIDocumentation.lua").Functions) do
    if movementAPIs[fn.Name] then
        assert(fn.IsProtectedFunction == true, fn.Name .. " protection contract changed")
        if fn.Name == "StartMoving" then
            assert(#fn.Arguments == 1 and fn.Arguments[1].Name == "alwaysStartFromMouse"
                and fn.Arguments[1].Type == "bool" and fn.Arguments[1].Default == false)
        else
            assert(#fn.Arguments == 0, "StopMovingOrSizing argument contract changed")
        end
        movementAPIs[fn.Name] = nil
    end
end
assert(next(movementAPIs) == nil, "native movement API missing")
print("PASS Blizzard F09 StartMoving/StopMovingOrSizing protected flags (source contract only)")

local geometryAPIs = { GetWidth = true, GetHeight = true, SetWidth = true, SetHeight = true }
for _, filename in ipairs({ "SimpleScriptRegionAPIDocumentation.lua", "SimpleScriptRegionResizingAPIDocumentation.lua" }) do
    for _, fn in ipairs(documentation(filename).Functions) do
        if geometryAPIs[fn.Name] then
            if fn.Name:sub(1, 3) == "Get" then
                assert(#fn.Returns == 1 and fn.Returns[1].Type == "uiUnit")
                assert(fn.Arguments[1].Name == "ignoreRect" and fn.Arguments[1].Default == false)
            else
                assert(#fn.Arguments == 1 and fn.Arguments[1].Type == "uiUnit")
            end
            geometryAPIs[fn.Name] = nil
        end
    end
end
assert(next(geometryAPIs) == nil, "native geometry API missing")
local function sourceText(path)
    local file = assert(io.open(sourceAddons .. path))
    local text = file:read("*a")
    file:close()
    return text
end
assert(sourceText("Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua"):find(
    'target:SetScript("OnSizeChanged", function(target, width, height)', 1, true),
    "native OnSizeChanged callback usage changed")
print("PASS Blizzard F06 geometry API signatures and OnSizeChanged source usage")

-- Execute the actual canvas layout branch, with native frames supplied by our
-- bounded geometry model. This does not execute Settings XML or render a client.
env.tInvert = function(values)
    local inverse = {}
    for key, value in pairs(values) do inverse[value] = key end
    return inverse
end
loadSource("Blizzard_SharedXMLBase/EnumUtil.lua")
local layoutState = Mock.new(addonPath)
layoutState:login()
local layoutEnv, config = layoutState.env, layoutState.ns.Config
layoutEnv.securecallfunction = function(callback, ...) return callback(...) end -- No taint model.
layoutEnv.CreateFromMixins = function(...)
    local result = {}
    for index = 1, select("#", ...) do
        for key, value in pairs(select(index, ...)) do result[key] = value end
    end
    return result
end
layoutEnv.EnumUtil = env.EnumUtil
loadSource("Blizzard_SharedXMLBase/Mixin.lua", layoutEnv)
loadSource("Blizzard_Settings_Shared/Blizzard_SettingsLayouts.lua", layoutEnv)
loadSource("Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua", layoutEnv)
local currentLayout
layoutEnv.SettingsInbound = { SetCurrentLayout = function(layout) currentLayout = layout end }
local canvas = layoutEnv.CreateFrame("Frame")
local list = layoutEnv.CreateFrame("Frame")
local settingsPanel = setmetatable({ Container = { SettingsCanvas = canvas, SettingsList = list } },
    { __index = layoutEnv.SettingsPanelMixin })
local layout = layoutEnv.CreateCanvasLayout(config)
assert(#layout:GetAnchorPoints() == 0)

-- Audit model's 665x601 follows these defaults; this is not an XML interpreter.
local settingsXML = sourceText("Blizzard_Settings_Shared/Blizzard_SettingsPanel.xml")
for _, fragment in ipairs({
    '<Size x="920" y="724"/>', '<Size x="199" y="569"/>',
    '<Anchor point="TOPLEFT" x="18" y="-76"/>',
    '<Anchor point="BOTTOMLEFT" x="178" y="46"/>',
    '<Anchor point="TOPLEFT" relativeKey="$parent.CategoryList" relativePoint="TOPRIGHT" x="16"/>',
    '<Anchor point="BOTTOMLEFT" relativeKey="$parent.CategoryList" relativePoint="BOTTOMRIGHT" x="16" y="1"/>',
    '<Anchor point="RIGHT" x="-22"/>',
    '<Frame parentKey="SettingsCanvas" setAllPoints="true"/>',
}) do
    assert(settingsXML:find(fragment, 1, true), "Settings XML default changed: " .. fragment)
end
local defaultWidth, defaultHeight = 920 - 18 - 199 - 16 - 22, 724 - 76 - 46 - 1
local calls = {}
for _, methodName in ipairs({ "SetParent", "ClearAllPoints", "SetAllPoints" }) do
    local method = config[methodName]
    config[methodName] = function(self, ...)
        calls[#calls + 1] = methodName
        return method(self, ...)
    end
end
local displays, resizes = 0, 0
for _, size in ipairs({ { defaultWidth, defaultHeight }, { 600, 520 }, { 900, 720 } }) do
    config:Hide()
    config:ClearAllPoints()
    config:SetParent(nil)
    config:SetSize(760, 560)
    config:SetPoint("TOPLEFT", layoutEnv.UIParent, "TOPLEFT", 77, -33)
    canvas:Hide()
    canvas:SetSize(unpack(size))
    calls = {}
    settingsPanel:DisplayLayout(layout)
    assert(table.concat(calls, ",") == "SetParent,ClearAllPoints,SetAllPoints")
    assert(currentLayout == layout and config:GetParent() == canvas)
    assert(config:GetWidth() == size[1] and config:GetHeight() == size[2])
    assert(config:GetLeft() == canvas:GetLeft() and config:GetTop() == canvas:GetTop())
    assert(config:IsVisible() and canvas:IsShown() and not list:IsShown())
    assert(config.scroll:GetWidth() == size[1] - 52)
    assert(config.rows[1].delete:GetRight() <= config.scroll:GetRight())
    assert(config.rows[1]:GetWidth() == config.scroll:GetWidth())
    displays = displays + 1
    local box, entry = config.rows[2].label, config.rows[2].entry
    local original = entry.label
    box:SetFocus()
    box:SetText("DisplayLayout resize draft")
    for _, resized in ipairs({ { 600, 520 }, { 900, 720 }, { defaultWidth, defaultHeight } }) do
        canvas:SetSize(unpack(resized))
        assert(config:GetWidth() == resized[1] and config:GetHeight() == resized[2])
        assert(config.scroll:GetWidth() == resized[1] - 52)
        assert(config.rows[1].delete:GetRight() <= config.scroll:GetRight())
        assert(box:HasFocus() and box:GetText() == "DisplayLayout resize draft")
        assert(box.entry == entry and entry.label == original)
        resizes = resizes + 1
    end
end
print("PASS Blizzard F06 DisplayLayout: " .. displays .. " openings, " .. resizes
    .. " ancestor resizes, reparent/clear/SetAllPoints, draft preservation (modeled native frames)")

-- Replace the bounded template callbacks with the supplied Blizzard Lua.
layoutEnv.GetCurrentEnvironment = function() return layoutEnv end
loadSource("Blizzard_SharedXML/SecureScrollTemplates.lua", layoutEnv)
local scroll = config.scroll
scroll.ScrollBar:SetScript("OnValueChanged", layoutEnv.UIPanelScrollBar_OnValueChanged)
scroll:SetScript("OnVerticalScroll", layoutEnv.ScrollFrame_OnVerticalScroll)
scroll:SetScript("OnScrollRangeChanged", layoutEnv.ScrollFrame_OnScrollRangeChanged)
scroll:SetScript("OnMouseWheel", layoutEnv.ScrollFrameTemplate_OnMouseWheel)
layoutEnv.UIPanelScrollFrame_OnLoad(scroll)
local entries = layoutState.ns:GetEntries()
for index = 1, 24 do
    entries[#entries + 1] = {
        id = "source-layout-" .. index, label = "Source scroll row", category = "custom",
        itemID = 123, spellID = 456, action = "item", enabled = true,
    }
end
config:Refresh()
for _, size in ipairs({ { 600, 520 }, { 665, 601 }, { 900, 720 } }) do
    canvas:SetSize(unpack(size))
    for _ = 1, 30 do layoutState:script(scroll, "OnMouseWheel", -1) end
    assert(scroll:GetVerticalScroll() == math.floor(scroll:GetVerticalScrollRange()))
    assert(config.rows[#entries]:GetBottom() == scroll:GetBottom(), "last row is not reachable")
    layoutState:script(scroll, "OnMouseWheel", 1)
    assert(scroll:GetVerticalScroll() < scroll:GetVerticalScrollRange())
end
while #entries > 1 do table.remove(entries) end
config:Refresh()
assert(scroll:GetVerticalScrollRange() == 0 and scroll:GetVerticalScroll() == 0)
assert(scroll.ScrollBar.ScrollUpButton.enabled == false and scroll.ScrollBar.ScrollDownButton.enabled == false)
print("PASS Blizzard F06 scroll template: wheel/range callbacks, 3 sizes, last row reachability, shrink clamp")
