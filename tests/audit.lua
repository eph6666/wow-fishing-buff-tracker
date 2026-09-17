-- Lua 5.1. Run: lua5.1 tests/audit.lua FishingBuffTracker [test-name-substring]
-- Known defects intentionally fail; this suite does not bless current behavior.
local addonPath = assert(arg[1], "addon path is required")
local scriptDirectory = arg[0]:match("^(.*[/\\])") or ""
local Mock = dofile(scriptDirectory .. "wow_mock.lua")
local reviewData = dofile(scriptDirectory .. "fixtures/review_data.lua")
local tests = {}
local function test(name, callback) tests[#tests + 1] = { name, callback } end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ")
        .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function setup(saved)
    local state = Mock.new(addonPath, saved)
    state:login()
    return state, state.ns
end
local function aura(spellID, expires, stacks)
    return { spellId = spellID, icon = 12345, expirationTime = expires or 200,
        duration = 100, applications = stacks or 1 }
end

test("manifest_load_defaults_and_secure_bindings", function()
    local state, ns = setup()
    equal(#ns:GetEntries(), 8)
    equal(#ns.Bar.buttons, 8)
    equal(ns.Bar.buttons[1].attributes.toy, 202207)
    equal(ns.Bar.buttons[2].attributes.item, "item:241316")
    equal(ns.Bar.buttons[5].attributes.macrotext, "/use item:262651\n/use 28")
    equal(ns.Bar.buttons[2].registeredClicks[1], "AnyDown")
    equal(ns.Bar.buttons[2].registeredClicks[2], "AnyUp")
    equal(ns.Bar.buttons[2].mouseEnabled, true)
    equal(ns.Bar.buttons[2].cooldown.mouseEnabled, false)
    equal(state:secureFrameCount(), 8)
end)

test("mock_rejects_unknown_api_and_protected_mutations", function()
    local state, ns = setup()
    equal(ns.Bar.DoesNotExist, nil)
    state.combat = true
    equal(pcall(function() ns.Bar:Hide() end), false)
    equal(pcall(function() ns.Bar.buttons[1]:SetAttribute("type", "item") end), false)
    equal(pcall(function() ns.Bar.buttons[1]:SetPoint("CENTER") end), false)
end)

test("new_builtins_preserve_user_edits_and_disabled_state", function()
    local _, ns = setup({ entries = {
        { id = "oversized-bobber", label = "我的名称", itemID = 202207,
            spellID = 397827, enabled = false, action = "toy", builtin = true },
    } })
    equal(#ns:GetEntries(), 8)
    equal(ns:GetEntries()[1].label, "我的名称")
    equal(ns:GetEntries()[1].enabled, false)
    ns:GetEntries()[1].label = "changed"
    equal(ns.BUILTIN_ENTRIES[1].label, "可重复使用的巨型鱼漂")
end)

test("aura_icon_stacks_and_countdown", function()
    local state, ns = setup()
    local button = state:button("oversized-bobber")
    equal(button.icon.desaturated, true)
    state.auras = { aura(397827, 200, 3) }
    state:fire("UNIT_AURA", "player")
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.icon.desaturated, false)
    equal(button.icon.texture, 12345)
    equal(button.countText:GetText(), "3")
    equal(button.timeText:GetText(), "2m")
    state.now = 196
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.timeText:GetText(), "4.0")
    state.auras = {}
    state:fire("UNIT_AURA", "player")
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.icon.desaturated, true)
    equal(button.timeText:GetText(), "")
end)

test("lure_visibility_and_unavailable_filter", function()
    local state, ns = setup()
    local lure = state:button("ulatek-lure")
    equal(lure:IsShown(), false)
    state.auras = { aura(1302820) }
    state:fire("UNIT_AURA", "player")
    equal(lure:IsShown(), true)
    ns.db.frame.showUnavailable = false
    ns:Refresh()
    equal(state:button("haranir-phial"):IsShown(), false)
    state.counts[241316] = 2
    state:fire("BAG_UPDATE_DELAYED")
    equal(state:button("haranir-phial"):IsShown(), true)
    equal(state:button("haranir-phial").countText:GetText(), "2")
end)

test("database_contract_crystalline_phial_aura_is_recognized", function()
    local state, ns = setup()
    state.auras = { aura(reviewData.crystallinePhial.auraSpellID) }
    ns:Refresh()
    equal(state:button("crystalline-phial").icon.desaturated, false,
        "database aura 393714 is not recognized by the configured use-spell ID")
end)

-- F02: preserve the old saved definition independently of the corrected defaults.
local function legacyCrystallinePhial()
    return {
        id = "crystalline-phial", label = "晶华感知瓶剂", category = "phial",
        itemID = 191354, spellID = 371454, action = "item", enabled = true, builtin = true,
    }
end

test("crystalline_phial_tracks_aura_not_use_spell_in_bar_tooltip_and_status", function()
    local state, ns = setup()
    local fixture = reviewData.crystallinePhial
    local button = state:button("crystalline-phial")
    equal(button.entry.spellID, fixture.auraSpellID)
    equal(button.entry.useSpellID, fixture.useSpellID)
    equal(button.attributes.type, "item")
    equal(button.attributes.item, "item:" .. fixture.itemID)
    state.auras = { aura(fixture.useSpellID) }
    state:fire("UNIT_AURA", "player")
    equal(button.icon.desaturated, true, "use spell must not activate the tracked Aura")
    equal(ns:ScanAuras()[fixture.useSpellID], nil)

    state.auras[#state.auras + 1] = aura(fixture.auraSpellID)
    state:fire("UNIT_AURA", "player")
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.icon.desaturated, false)
    equal(button.timeText:GetText(), "2m")
    state:script(button, "OnEnter")
    equal(state.env.GameTooltip.spellID, fixture.auraSpellID)
    state:command("status")
    local status
    for _, message in ipairs(state.messages) do
        if message:find(button.entry.label .. ":", 1, true) then status = message end
    end
    assert(status and status:find("ACTIVE", 1, true))
    assert(status:find("SpellID " .. fixture.auraSpellID, 1, true))
    ns:OpenConfig()
    equal(ns.Config.rows[3].spellID:GetText(), tostring(fixture.auraSpellID))
    equal(ns.Config.rows[3].spellID.enabled, true)

    state.auras = { aura(fixture.useSpellID) }
    state:fire("UNIT_AURA", "player")
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.icon.desaturated, true, "removal must not fall back to the use spell")
    equal(button.timeText:GetText(), "")
    state:script(button, "OnEnter")
    equal(state.env.GameTooltip.hyperlink, "item:" .. fixture.itemID)
end)

test("crystalline_phial_migrates_stock_saved_definition_to_tracked_aura", function()
    local legacy = legacyCrystallinePhial()
    local state, ns = setup({ entries = { legacy } })
    equal(ns:GetEntries()[1], legacy, "migration must update in place")
    equal(#ns:GetEntries(), 8)
    equal(legacy.spellID, reviewData.crystallinePhial.auraSpellID)
    equal(legacy.useSpellID, reviewData.crystallinePhial.useSpellID)
    equal(legacy.itemID, 191354)
    equal(legacy.action, "item")
    equal(state:button("crystalline-phial").attributes.item, "item:191354")
    state.auras = { aura(reviewData.crystallinePhial.auraSpellID) }
    state:fire("UNIT_AURA", "player")
    equal(state:button("crystalline-phial").icon.desaturated, false)
end)

test("crystalline_phial_migration_preserves_renamed_disabled_preferences_and_order_on_reload", function()
    local legacy = legacyCrystallinePhial()
    legacy.label, legacy.category = "我的瓶剂", "lure"
    legacy.enabled, legacy.hideWhenMissing = false, true
    local custom = legacyCrystallinePhial()
    custom.id, custom.builtin = "custom-crystalline-phial", false
    local saved = { entries = { custom, legacy } }
    for _ = 1, 2 do
        local state, ns = setup(saved)
        equal(#ns:GetEntries(), 9, "reload must not duplicate built-ins")
        equal(ns:GetEntries()[1], custom)
        equal(ns:GetEntries()[2], legacy)
        equal(legacy.label, "我的瓶剂")
        equal(legacy.category, "lure")
        equal(legacy.enabled, false)
        equal(legacy.hideWhenMissing, true)
        equal(legacy.spellID, reviewData.crystallinePhial.auraSpellID)
        equal(legacy.useSpellID, reviewData.crystallinePhial.useSpellID)
        equal(state:button("crystalline-phial"), nil, "migration must not re-enable a disabled entry")
        equal(custom.spellID, 371454)
        equal(custom.useSpellID, nil)
        equal(ns.BUILTIN_ENTRIES[3].label, "晶华感知瓶剂")
        equal(ns.BUILTIN_ENTRIES[3].enabled, true)
    end
end)

test("crystalline_phial_migration_preserves_custom_ids_and_semantic_overrides", function()
    for _, override in ipairs({
        { "id", "custom-crystalline-phial" }, { "builtin", false }, { "builtin" },
        { "itemID", 123 }, { "itemID" }, { "spellID", 9999 }, { "spellID" },
        { "spellID", 393714 }, { "action", "toy" }, { "action", "macro" }, { "action" },
        { "macrotext", "/use item:123" }, { "requiredEquippedItemID", 244790 },
        { "useSpellID", 123 }, { "useSpellID", 371454 }, { "enchantID", 8675 }, { "inventorySlot", 28 },
    }) do
        local entry = legacyCrystallinePhial()
        entry[override[1]] = override[2]
        local before = {}
        for key, value in pairs(entry) do before[key] = value end
        local saved = { entries = { entry } }
        for _ = 1, 2 do
            local state = Mock.new(addonPath, saved)
            state:fire("ADDON_LOADED", "FishingBuffTracker")
            equal(state.ns:GetEntries()[1], entry)
            for key, value in pairs(before) do equal(entry[key], value, override[1] .. " changed " .. key) end
            for key, value in pairs(entry) do equal(value, before[key], override[1] .. " added " .. key) end
        end
    end
end)

test("crystalline_phial_user_aura_edit_after_migration_survives_reload", function()
    local legacy = legacyCrystallinePhial()
    local state, ns = setup({ entries = { legacy } })
    ns:OpenConfig()
    local box = ns.Config.rows[1].spellID
    box:SetText("9999")
    state:script(box, "OnEditFocusLost")
    local reloaded, reloadedNS = setup(ns.db)
    equal(reloadedNS:GetEntries()[1].spellID, 9999)
    equal(reloadedNS:GetEntries()[1].useSpellID, 371454)
    equal(#reloadedNS:GetEntries(), 8)
    reloaded.auras = { aura(reviewData.crystallinePhial.auraSpellID) }
    reloaded:fire("UNIT_AURA", "player")
    local button = reloaded:button("crystalline-phial")
    equal(button.icon.desaturated, true, "migration must not restore its Aura ID over a later user edit")
    reloaded.auras = { aura(9999) }
    reloaded:fire("UNIT_AURA", "player")
    equal(button.icon.desaturated, false)
    reloaded:script(button, "OnEnter")
    equal(reloaded.env.GameTooltip.spellID, 9999)
end)

test("crystalline_phial_missing_builtin_and_reset_use_corrected_defaults", function()
    local custom = legacyCrystallinePhial()
    custom.id, custom.builtin = "custom-crystalline-phial", false
    local state, ns = setup({ entries = { custom } })
    equal(#ns:GetEntries(), 9)
    equal(custom.spellID, 371454)
    equal(custom.useSpellID, nil)
    local entry
    for _, candidate in ipairs(ns:GetEntries()) do
        if candidate.id == "crystalline-phial" then entry = candidate end
    end
    equal(entry.spellID, reviewData.crystallinePhial.auraSpellID)
    equal(entry.useSpellID, reviewData.crystallinePhial.useSpellID)
    entry.spellID = 9999
    ns:RequestRebuild()
    equal(state:button("crystalline-phial").entry.spellID, 9999)
    state:command("defaults")
    equal(#ns:GetEntries(), 8)
    local reset = state:button("crystalline-phial").entry
    equal(reset.spellID, reviewData.crystallinePhial.auraSpellID)
    equal(reset.useSpellID, reviewData.crystallinePhial.useSpellID)
    equal(reset.enabled, true)
end)

test("database_contract_spikesnail_temporary_enchant_is_recognized", function()
    local state, ns = setup()
    local fixture = reviewData.pointedSpikesnail
    state.env.C_PaperDollInfo = {
        GetTemporaryEnchantmentInfo = function(slot)
            assert(slot == fixture.inventorySlot, "unexpected enchantment slot")
            return { enchantID = fixture.enchantID, remainingTimeMs = 600000,
                chargesRemaining = 0, hasExpirationTime = true }
        end,
    }
    ns:Refresh()
    equal(state:button("pointed-spikesnail").icon.desaturated, false,
        "active temporary enchantment cannot be found by player aura scanning")
end)

-- F01 inputs follow the generated API contract, not live slot-28 captures.
local function spikesnailEnchant(remainingTimeMs, enchantID, hasExpirationTime, chargesRemaining)
    return {
        enchantID = enchantID or reviewData.pointedSpikesnail.enchantID,
        remainingTimeMs = remainingTimeMs or 600000,
        hasExpirationTime = hasExpirationTime ~= false,
        chargesRemaining = chargesRemaining or 0,
    }
end

local function spikesnailStatus(state)
    state.messages = {}
    state:command("status")
    for _, message in ipairs(state.messages) do
        if message:find("尖刺钉螺:", 1, true) then return message end
    end
    error("Spikesnail status missing")
end

local function legacySpikesnail()
    return {
        id = "pointed-spikesnail", label = "尖刺钉螺", category = "bobber",
        itemID = 262651, spellID = 1284999, action = "macro",
        macrotext = "/use item:262651\n/use 28", requiredEquippedItemID = 244790,
        enabled = true, builtin = true,
    }
end

test("spikesnail_use_spell_is_metadata_and_never_aura_fallback", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    local fixture = reviewData.pointedSpikesnail
    equal(button.entry.useSpellID, fixture.useSpellID)
    equal(button.entry.spellID, nil)
    equal(button.entry.enchantID, fixture.enchantID)
    equal(button.entry.inventorySlot, fixture.inventorySlot)
    state.auras = { aura(fixture.useSpellID) }
    state:fire("UNIT_AURA", "player")
    equal(button.icon.desaturated, true, "use spell must not activate an enchantment entry")
    equal(ns:ScanAuras()[fixture.useSpellID], nil)
    for _, slot in ipairs(state.enchantmentQueries) do equal(slot, fixture.inventorySlot) end

    state.env.GetWeaponEnchantInfo = function() error("legacy weapon API must not be used") end
    state.env.C_PaperDollInfo = nil
    ns:Refresh()
    equal(button.icon.desaturated, true)
    state.env.C_PaperDollInfo = {}
    ns:Refresh()
    equal(button.icon.desaturated, true)
end)

test("spikesnail_nil_wrong_and_expired_enchantments_are_missing", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    equal(button.icon.desaturated, true, "nil API return should be missing")
    for _, info in ipairs({
        spikesnailEnchant(600000, 8676),
        spikesnailEnchant(600000, 1284999),
        spikesnailEnchant(0),
        spikesnailEnchant(-1),
    }) do
        state.enchantments[28] = spikesnailEnchant()
        ns:Refresh()
        equal(button.icon.desaturated, false)
        state.enchantments[28] = info
        ns:Refresh()
        equal(button.icon.desaturated, true)
        equal(button.timeText:GetText(), "")
        assert(spikesnailStatus(state):find("MISSING", 1, true))
    end
end)

test("spikesnail_countdown_item_tooltip_and_status_agree", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    state.icons[262651] = 54321
    state.enchantments[28] = spikesnailEnchant()
    ns:Refresh()
    equal(button.icon.desaturated, false)
    equal(button.icon.texture, 54321)
    equal(button.border.vertexColor[2], 0.9)
    equal(button.countText:GetText(), "")
    equal(button.timeText:GetText(), "10m")
    equal(button.effect.expirationTime, 700, "API milliseconds must become GetTime seconds")
    equal(state.enchantments[28].expirationTime, nil, "API result must not be mutated")
    state:script(button, "OnEnter")
    equal(state.env.GameTooltip.hyperlink, "item:262651")
    equal(state.env.GameTooltip.spellID, nil, "use spell must not be used as an Aura tooltip")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("剩余时间：10m", 1, true))
    local status = spikesnailStatus(state)
    assert(status:find("ACTIVE", 1, true))
    assert(status:find("EnchantID 8675", 1, true))
    assert(status:find("栏位 28", 1, true))
    assert(status:find("UseSpellID 1284999", 1, true))

    state.now = 200
    state.enchantments[28].remainingTimeMs = 500000
    state:fire("WEAPON_ENCHANT_CHANGED")
    equal(button.effect.expirationTime, 700, "refresh must not extend the enchantment")
    equal(button.timeText:GetText(), "9m")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("剩余时间：9m", 1, true),
        "open tooltip did not refresh")
end)

test("spikesnail_events_handle_removal_reapplication_and_replacement", function()
    local state = setup()
    local button = state:button("pointed-spikesnail")
    state.counts[262651] = 4
    for _, event in ipairs({
        "WEAPON_ENCHANT_CHANGED", "UNIT_INVENTORY_CHANGED",
        "PROFESSION_EQUIPMENT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    }) do
        state.enchantments[28] = spikesnailEnchant()
        state:fire(event, "player")
        equal(button.icon.desaturated, false, event .. " did not apply the enchantment")
        state:script(button, "OnEnter")
        state.enchantments[28] = nil
        state:fire(event, "player")
        equal(button.icon.desaturated, true, event .. " did not remove the enchantment")
        equal(button.timeText:GetText(), "")
        equal(button.countText:GetText(), "4")
        assert(table.concat(state.env.GameTooltip.lines, "\n"):find("缺少临时附魔", 1, true))
        assert(spikesnailStatus(state):find("MISSING", 1, true))
        state.enchantments[28] = spikesnailEnchant()
        state:fire(event, "player")
        equal(button.icon.desaturated, false)
        state.enchantments[28] = spikesnailEnchant(600000, 8676)
        state:fire(event, "player")
        equal(button.icon.desaturated, true, "a different enchantment must replace the old state")
    end
end)

test("spikesnail_poll_detects_apply_and_remove_without_aura_or_editor_refresh", function()
    local state, ns = setup()
    ns:OpenConfig()
    local box = ns.Config.rows[2].label
    box:SetFocus()
    box:SetText("正在编辑")
    local scans, queries = state.auraScans, #state.enchantmentQueries
    local button = state:button("pointed-spikesnail")
    state.enchantments[28] = spikesnailEnchant()
    state.now = 100.5
    state:script(ns.Bar, "OnUpdate", 0.5)
    equal(#state.enchantmentQueries, queries, "polling should be throttled")
    state.now = 101
    state:script(ns.Bar, "OnUpdate", 0.5)
    equal(#state.enchantmentQueries, queries + 1)
    equal(button.icon.desaturated, false)
    state:script(button, "OnEnter")
    state.enchantments[28] = nil
    state.now = 102
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.icon.desaturated, true)
    equal(button.timeText:GetText(), "")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("缺少临时附魔", 1, true))
    equal(state.auraScans, scans, "enchantment polling must not scan player Auras")
    equal(box:GetText(), "正在编辑", "enchantment polling must not refresh the editor")
end)

test("spikesnail_expiration_clears_state_without_repeated_aura_scans", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    state.enchantments[28] = spikesnailEnchant(500)
    ns:Refresh()
    equal(button.timeText:GetText(), "0.5")
    state:script(button, "OnEnter")
    local scans, queries = state.auraScans, #state.enchantmentQueries
    state.now = 100.6
    state.enchantments[28].remainingTimeMs = 0
    state:script(ns.Bar, "OnUpdate", 0.1)
    equal(button.icon.desaturated, true, "expiry should refresh before the next periodic poll")
    equal(button.timeText:GetText(), "")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("缺少临时附魔", 1, true))
    for _ = 1, 20 do
        state.now = state.now + 0.1
        state:script(ns.Bar, "OnUpdate", 0.1)
    end
    equal(state.auraScans, scans)
    assert(#state.enchantmentQueries - queries <= 3, "expired enchantment triggered repeated retries")
end)

test("spikesnail_nonexpiring_enchantment_stays_active_with_no_missing_tooltip", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    state.enchantments[28] = spikesnailEnchant(0, 8675, false, 3)
    ns:Refresh()
    equal(button.icon.desaturated, false)
    equal(button.timeText:GetText(), "")
    equal(button.countText:GetText(), "3")
    state:script(button, "OnEnter")
    local tooltip = table.concat(state.env.GameTooltip.lines, "\n")
    assert(tooltip:find("临时附魔已激活", 1, true))
    assert(not tooltip:find("缺少", 1, true))
    assert(spikesnailStatus(state):find("ACTIVE", 1, true))
    state.now = 1000
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.icon.desaturated, false)
    equal(button.timeText:GetText(), "")
end)

test("spikesnail_poll_respects_combat_visibility_and_hidden_buttons", function()
    local state, ns = setup()
    local button = state:button("pointed-spikesnail")
    ns.db.frame.showUnavailable = false
    ns:Refresh()
    equal(button:IsShown(), false)
    local width = ns.Bar:GetWidth()
    state.combat = true
    state.enchantments[28] = spikesnailEnchant()
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button:IsShown(), false, "polling must not show a protected button in combat")
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(button:IsShown(), true)
    equal(button.icon.desaturated, false)
    assert(ns.Bar:GetWidth() > width)
    state:script(button, "OnEnter")
    state.combat = true
    state.enchantments[28] = nil
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button:IsShown(), true)
    equal(button.icon.desaturated, true)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(button:IsShown(), false)
    equal(ns.Bar:GetWidth(), width)
    equal(state.env.GameTooltip:IsShown(), false, "hidden button must not retain its tooltip")

    state.enchantments[28] = spikesnailEnchant()
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button:IsShown(), true, "missing hidden buttons must still be polled")
    assert(ns.Bar:GetWidth() > width, "polling did not update layout")
    ns:SetBarVisible(false)
    state.enchantments[28] = nil
    ns:SetBarVisible(true)
    equal(button:IsShown(), false, "showing the bar must read current enchantment state")
end)

test("spikesnail_inventory_events_ignore_other_units", function()
    local state = setup()
    local scans, queries = state.auraScans, #state.enchantmentQueries
    state.enchantments[28] = spikesnailEnchant()
    state:fire("UNIT_INVENTORY_CHANGED", "party1")
    equal(state.auraScans, scans)
    equal(#state.enchantmentQueries, queries)
    equal(state:button("pointed-spikesnail").icon.desaturated, true)
    state:fire("UNIT_INVENTORY_CHANGED", "player")
    equal(state:button("pointed-spikesnail").icon.desaturated, false)
end)

test("spikesnail_migrates_stock_saved_definition_to_active_enchantment", function()
    local legacy = legacySpikesnail()
    local state, ns = setup({ entries = { legacy } })
    equal(#ns:GetEntries(), 8)
    equal(legacy.spellID, nil)
    equal(legacy.useSpellID, 1284999)
    equal(legacy.enchantID, 8675)
    equal(legacy.inventorySlot, 28)
    state.enchantments[28] = spikesnailEnchant()
    state:fire("WEAPON_ENCHANT_CHANGED")
    equal(state:button("pointed-spikesnail").icon.desaturated, false)
end)

test("spikesnail_migration_preserves_renamed_disabled_preferences_and_order_on_reload", function()
    local legacy = legacySpikesnail()
    legacy.label = "我的钉螺"
    legacy.category = "lure"
    legacy.hideWhenMissing = true
    legacy.enabled = false
    local custom = legacySpikesnail()
    custom.id, custom.builtin = "custom-snail", false
    local saved = { entries = { custom, legacy } }
    local _, ns = setup(saved)
    equal(ns:GetEntries()[1], custom)
    equal(ns:GetEntries()[2], legacy, "migration should update in place")
    equal(#ns:GetEntries(), 9)
    equal(legacy.label, "我的钉螺")
    equal(legacy.category, "lure")
    equal(legacy.hideWhenMissing, true)
    equal(legacy.enabled, false)
    equal(legacy.spellID, nil)
    equal(legacy.useSpellID, 1284999)
    equal(legacy.enchantID, 8675)
    equal(legacy.inventorySlot, 28)
    equal(legacy.macrotext, "/use item:262651\n/use 28")
    equal(custom.spellID, 1284999)
    equal(custom.enchantID, nil)
    local _, reloaded = setup(saved)
    equal(#reloaded:GetEntries(), 9, "reload must not duplicate built-ins")
    equal(reloaded:GetEntries()[2], legacy)
    equal(legacy.label, "我的钉螺")
    equal(legacy.category, "lure")
    equal(legacy.hideWhenMissing, true)
    equal(legacy.enabled, false)
    equal(legacy.enchantID, 8675)
    equal(reloaded.BUILTIN_ENTRIES[5].enabled, true)
    equal(reloaded.BUILTIN_ENTRIES[5].spellID, nil)
end)

test("spikesnail_migration_leaves_user_overrides_and_custom_entries_untouched", function()
    for _, override in ipairs({
        { "id", "custom-snail" }, { "builtin", false }, { "builtin" },
        { "itemID", 123 },
        { "spellID", 456 }, { "spellID" }, { "action", "item" },
        { "macrotext", "/use item:123\n/use 28" }, { "macrotext" },
        { "requiredEquippedItemID", 123 }, { "requiredEquippedItemID" },
        { "useSpellID", 1284999 }, { "enchantID", 9000 }, { "inventorySlot", 16 },
    }) do
        local entry = legacySpikesnail()
        entry[override[1]] = override[2]
        local before = {}
        for key, value in pairs(entry) do before[key] = value end
        local state = Mock.new(addonPath, { entries = { entry } })
        state:fire("ADDON_LOADED", "FishingBuffTracker")
        equal(state.ns:GetEntries()[1], entry)
        for key, value in pairs(before) do equal(entry[key], value, override[1] .. " changed " .. key) end
        for key, value in pairs(entry) do equal(value, before[key], override[1] .. " added " .. key) end
    end
end)

test("spikesnail_user_aura_override_still_tracks_the_configured_aura", function()
    local entry = legacySpikesnail()
    entry.spellID = 9999
    local state, ns = setup({ entries = { entry } })
    state.auras = { aura(9999) }
    ns:Refresh()
    local button = state:button("pointed-spikesnail")
    equal(button.icon.desaturated, false)
    equal(#state.enchantmentQueries, 0)
    state:script(button, "OnEnter")
    equal(state.env.GameTooltip.spellID, 9999)
    ns:OpenConfig()
    equal(ns.Config.rows[1].spellID:GetText(), "9999")
    equal(ns.Config.rows[1].spellID.enabled, true)
end)

test("spikesnail_config_shows_readonly_enchant_id_and_reenables_reused_aura_row", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = ns.Config.rows[5]
    local entry = row.entry
    equal(row.spellID:GetText(), "8675")
    equal(row.category:GetText(), "临时附魔")
    equal(row.spellID.enabled, false)
    local frames = state:secureFrameCount()
    row.spellID:SetText("1284999")
    state:script(row.spellID, "OnEditFocusLost")
    equal(entry.spellID, nil, "read-only enchant ID must not be saved as an Aura SpellID")
    equal(entry.enchantID, 8675)
    equal(entry.useSpellID, 1284999)
    equal(state:secureFrameCount(), frames)
    ns.Config:Refresh()
    equal(row.spellID:GetText(), "8675")
    state:script(row.down, "OnClick")
    equal(row.spellID.enabled, true, "a reused Aura row must remain editable")
    equal(row.spellID:GetText(), "1302820")
    equal(ns.Config.rows[6].spellID.enabled, false)
    equal(ns.Config.rows[6].spellID:GetText(), "8675")
end)

test("cooldowns_and_equipment_warning", function()
    local state, ns = setup()
    state.cooldowns[241316] = { 95, 30, true }
    state.equippedItemID = nil
    ns:Refresh()
    equal(state:button("haranir-phial").cooldown.cooldown[2], 30)
    equal(state:button("pointed-spikesnail").warning:IsShown(), true)
    state.cooldowns[241316] = { 95, 30, false }
    state:fire("SPELL_UPDATE_COOLDOWN")
    equal(state:button("haranir-phial").cooldown.cooldown, nil)
end)

test("other_unit_aura_does_not_refresh", function()
    local state = setup()
    local count = state.auraScans
    state:fire("UNIT_AURA", "party1")
    equal(state.auraScans, count)
end)

test("commands_visibility_position_and_lock", function()
    local state, ns = setup()
    state:script(ns.Bar.dragHandle, "OnDragStart")
    equal(ns.Bar.moving, true)
    state:script(ns.Bar.dragHandle, "OnDragStop")
    equal(ns.Bar.moving, false)
    state:command("lock")
    state:script(ns.Bar.dragHandle, "OnDragStart")
    equal(ns.Bar.moving, false)
    state:command("unlock")
    state:script(ns.Bar.closeButton, "OnClick")
    equal(ns.Bar:IsShown(), false)
    equal(ns.db.frame.visible, false)
    state:command("show")
    equal(ns.Bar:IsShown(), true)
    ns.db.frame.x = 222
    state:command("reset")
    equal(ns.db.frame.x, 0)
    state:command("status")
    assert(#state.messages >= 8, "status messages missing")
end)

test("combat_queues_visibility_layout_and_latest_request", function()
    local state, ns = setup()
    state.combat = true
    local count = state:secureFrameCount()
    local width = ns.Bar:GetWidth()
    state:command("hide")
    equal(ns.Bar:IsShown(), true)
    equal(ns.visibilityPending, false)
    state:command("show")
    state:command("hide")
    ns.db.frame.iconSize = 60
    ns:RequestRebuild()
    equal(ns.Bar:GetWidth(), width)
    equal(state:secureFrameCount(), count)
    ns.db.frame.x = 123
    state:command("reset")
    equal(ns.db.frame.x, 123)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(ns.Bar:IsShown(), false)
    equal(ns.db.frame.x, 0)
    equal(ns.rebuildPending, nil)
    equal(ns.visibilityPending, nil)
    equal(ns.Bar.buttons[1].width, 60)
end)

test("combat_lure_layout_updates_on_regen", function()
    local state = setup()
    local lure = state:button("ulatek-lure")
    state.combat = true
    state.auras = { aura(1302820) }
    state:fire("UNIT_AURA", "player")
    equal(lure:IsShown(), false)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(lure:IsShown(), true)
end)

test("custom_add_sort_disable_delete_and_restore", function()
    local state, ns = setup()
    ns:OpenConfig()
    local addButton
    for _, frame in ipairs(state.frames) do
        if frame.kind == "Button" and frame:GetText() == "添加" then addButton = frame end
    end
    assert(addButton, "add button missing")
    local boxes = {}
    for _, frame in ipairs(state.frames) do
        if frame.parent == addButton.parent and frame.kind == "EditBox" then
            boxes[#boxes + 1] = frame
        end
    end
    boxes[1]:SetText("测试鱼")
    boxes[2]:SetText("123")
    boxes[3]:SetText("456")
    state:script(addButton, "OnClick")
    equal(#ns:GetEntries(), 9)
    equal(ns:GetEntries()[9].label, "测试鱼")
    state:script(ns.Config.rows[9].up, "OnClick")
    equal(ns:GetEntries()[8].label, "测试鱼")
    state:script(ns.Config.rows[8].delete, "OnClick")
    equal(#ns:GetEntries(), 8)
    state:script(ns.Config.rows[1].delete, "OnClick")
    equal(ns:GetEntries()[1].enabled, false)
    equal(#ns.Bar.buttons, 7)
    state:command("defaults")
    equal(#ns.Bar.buttons, 8)
end)

test("focused_edit_survives_background_aura_refresh", function()
    local state, ns = setup()
    ns:OpenConfig()
    local box = ns.Config.rows[2].label
    box:SetFocus()
    box:SetText("正在编辑")
    state:fire("UNIT_AURA", "player")
    equal(box:GetText(), "正在编辑", "background refresh discarded draft")
end)

-- F04: Enter/ordinary focus loss commits; structural actions and hiding cancel
-- any still-pending input. Tests cover values/entry identity, not just focus.
local editCases = {
    { field = "label", draft = "  正在编辑  ", value = "正在编辑" },
    { field = "itemID", draft = "000191354", value = 191354 },
    { field = "spellID", draft = "000393714", value = 393714 },
}

local function watchConfigRefresh(ns)
    local counts = { rebuilds = 0, refreshes = 0 }
    local rebuild, refresh = ns.RequestRebuild, ns.Config.Refresh
    local refreshing = false
    ns.RequestRebuild = function(self)
        assert(not refreshing, "draft callback requested a rebuild inside Config:Refresh")
        counts.rebuilds = counts.rebuilds + 1
        return rebuild(self)
    end
    ns.Config.Refresh = function(self)
        assert(not refreshing, "recursive Config:Refresh")
        refreshing = true
        counts.refreshes = counts.refreshes + 1
        refresh(self)
        refreshing = false
    end
    return counts
end

local function clickButtonText(state, text)
    for _, frame in ipairs(state.frames) do
        if frame.kind == "Button" and frame:GetText() == text then
            return state:script(frame, "OnClick")
        end
    end
    error("button missing: " .. text)
end

local function addDraftTestEntry(ns, index)
    local entry = {
        id = "f04-custom", label = "自定义测试", category = "custom",
        itemID = 123, spellID = 456, action = "item", enabled = true, builtin = false,
    }
    table.insert(ns:GetEntries(), index, entry)
    ns:RequestRebuild()
    return entry
end

for _, case in ipairs(editCases) do
    test("f04_" .. case.field .. "_draft_survives_background_events_and_controls", function()
        local state, ns = setup()
        ns:OpenConfig()
        local row = ns.Config.rows[2]
        local entry, box = row.entry, row[case.field]
        local original = entry[case.field]
        box:SetFocus()
        box:SetText(case.draft)
        local textWrites, setText = 0, box.SetText
        box.SetText = function(self, value)
            textWrites = textWrites + 1
            setText(self, value)
        end
        local counts = watchConfigRefresh(ns)
        local function checkDraft()
            equal(box:GetText(), case.draft, "background event replaced draft text")
            equal(entry[case.field], original, "background event committed a draft")
            equal(box.entry, entry)
            equal(textWrites, 0, "even SetText with identical text would reset editing state")
        end

        state.auras = { aura(entry.spellID, 220, 4) }
        state:fire("UNIT_AURA", "player")
        equal(state:button(entry.id).countText:GetText(), "4", "Aura status must still refresh")
        checkDraft()
        state.auras = {}
        state.counts[entry.itemID] = 7
        state:fire("BAG_UPDATE_DELAYED")
        equal(state:button(entry.id).countText:GetText(), "7", "bag count must still refresh")
        checkDraft()
        state.cooldowns[entry.itemID] = { 95, 30, true }
        state:fire("SPELL_UPDATE_COOLDOWN")
        equal(state:button(entry.id).cooldown.cooldown[2], 30)
        checkDraft()
        ns.Config.lock:SetChecked(true)
        state:script(ns.Config.lock, "OnClick")
        equal(ns.Bar.dragHandle.alpha, 0.25)
        checkDraft()
        for _, visible in ipairs({ false, true }) do
            ns.Config.showBar:SetChecked(visible)
            state:script(ns.Config.showBar, "OnClick")
            equal(ns.Bar:IsShown(), visible)
            checkDraft()
        end
        for _, command in ipairs({ "lock", "unlock", "hide", "show" }) do
            state:command(command)
            checkDraft()
        end
        -- A same-entry rebuild is also an ordinary refresh for the editor.
        ns:RequestRebuild()
        checkDraft()
        state.combat = true
        state:command("hide")
        state:fire("UNIT_AURA", "player")
        state:fire("BAG_UPDATE_DELAYED")
        state:fire("SPELL_UPDATE_COOLDOWN")
        ns:RequestRebuild()
        checkDraft()
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(ns.Bar:IsShown(), false)
        checkDraft()
        equal(counts.rebuilds, 3, "refresh events must not rebuild while editing")

        box:ClearFocus()
        equal(entry[case.field], case.value, "preserved draft must remain committable")
        equal(box:GetText(), tostring(case.value))
    end)

    test("f04_" .. case.field .. "_pending_focus_loss_text_survives_refresh", function()
        local state, ns = setup()
        ns:OpenConfig()
        local box = ns.Config.rows[2][case.field]
        local entry, original = box.entry, box.entry[case.field]
        box:SetFocus()
        box:SetText(case.draft)
        -- Deliver a background event between focus removal and its callback.
        state.focus = nil
        for _, event in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN" }) do
            state:fire(event, "player")
            equal(box:GetText(), case.draft)
            equal(entry[case.field], original)
        end
        state:script(box, "OnEditFocusLost")
        equal(entry[case.field], case.value)
        equal(box:GetText(), tostring(case.value))
    end)

    test("f04_" .. case.field .. "_enter_blur_and_focus_transfer_commit_once", function()
        for _, finish in ipairs({ "enter", "blur", "transfer" }) do
            local state, ns = setup()
            ns:OpenConfig()
            local box = ns.Config.rows[2][case.field]
            local entry = box.entry
            box:SetFocus()
            box:SetText(case.draft)
            local counts = watchConfigRefresh(ns)
            if finish == "enter" then
                state:script(box, "OnEnterPressed")
            elseif finish == "blur" then
                box:ClearFocus()
            else
                ns.Config.rows[3].label:SetFocus()
            end
            equal(entry[case.field], case.value)
            equal(box:GetText(), tostring(case.value), "committed text must be normalized")
            equal(counts.rebuilds, 1, finish .. " must commit only once")
            equal(counts.refreshes, 1)
            equal(box:HasFocus(), false)
            state:fire("UNIT_AURA", "player")
            equal(box:GetText(), tostring(case.value))
            if case.field == "itemID" then
                equal(state:button(entry.id).attributes.item, "item:191354")
            elseif case.field == "spellID" then
                state.auras = { aura(case.value) }
                state:fire("UNIT_AURA", "player")
                equal(state:button(entry.id).effect.spellId, case.value)
            end
        end
    end)
end

test("f04_empty_drafts_survive_refresh_and_keep_existing_commit_rules", function()
    for _, case in ipairs(editCases) do
        local state, ns = setup()
        ns:OpenConfig()
        local box = ns.Config.rows[2][case.field]
        local original = box.entry[case.field]
        box:SetFocus()
        box:SetText("")
        state:fire("BAG_UPDATE_DELAYED")
        equal(box:GetText(), "")
        equal(box.entry[case.field], original)
        state:script(box, "OnEnterPressed")
        local expected = case.field == "label" and original or 0
        equal(box.entry[case.field], expected)
        equal(box:GetText(), tostring(expected))
    end
end)

test("f04_committing_one_field_preserves_other_pending_fields", function()
    for _, selected in ipairs(editCases) do
        local state, ns = setup()
        ns:OpenConfig()
        local row = ns.Config.rows[2]
        local original = {}
        for _, case in ipairs(editCases) do
            original[case.field] = row.entry[case.field]
            row[case.field]:SetText(case.draft)
        end
        row[selected.field]:SetFocus()
        state:script(row[selected.field], "OnEnterPressed")
        for _, case in ipairs(editCases) do
            if case ~= selected then
                equal(row[case.field]:GetText(), case.draft, "another commit overwrote pending input")
                equal(row.entry[case.field], original[case.field])
                state:script(row[case.field], "OnEditFocusLost")
            end
        end
        for _, case in ipairs(editCases) do
            equal(row.entry[case.field], case.value)
            equal(row[case.field]:GetText(), tostring(case.value))
        end
    end
end)

test("f04_sort_cancels_pending_drafts_before_rebinding_in_both_directions", function()
    for _, case in ipairs(editCases) do
        for _, direction in ipairs({ "up", "down" }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = ns.Config.rows[2]
            local entry, box = row.entry, row[case.field]
            local original = entry[case.field]
            local target = ns:GetEntries()[direction == "up" and 1 or 3]
            local targetValue = target[case.field]
            local other = ns.Config.rows[4].label
            local otherValue = other.entry.label
            other:SetText("另一行待提交")
            box:SetFocus()
            box:SetText(case.draft)
            local counts = watchConfigRefresh(ns)
            state:script(row[direction], "OnClick")
            equal(entry[case.field], original, "sort must cancel the original draft")
            equal(target[case.field], targetValue, "sort must not write into a neighbor")
            equal(row.entry, target)
            equal(box:GetText(), tostring(targetValue))
            equal(other:GetText(), otherValue, "sort cancels pending input in unaffected rows too")
            equal(other.entry.label, otherValue)
            equal(counts.rebuilds, 1)
            equal(counts.refreshes, 1)
            box:ClearFocus()
            equal(target[case.field], targetValue)
            equal(counts.rebuilds, 1, "canceled focus must not later commit into a rebound row")
            box:SetFocus()
            box:SetText(case.draft)
            state:script(box, "OnEnterPressed")
            equal(target[case.field], case.value, "next edit must target the newly bound entry")
            equal(entry[case.field], original)
        end
    end
end)

test("f04_delete_builtin_cancels_draft_even_when_row_binding_is_unchanged", function()
    for _, case in ipairs(editCases) do
        local state, ns = setup()
        ns:OpenConfig()
        local row = ns.Config.rows[2]
        local original = row.entry[case.field]
        row[case.field]:SetFocus()
        row[case.field]:SetText(case.draft)
        local counts = watchConfigRefresh(ns)
        state:script(row.delete, "OnClick")
        equal(row.entry.enabled, false)
        equal(row.entry[case.field], original)
        equal(row[case.field]:GetText(), tostring(original))
        row[case.field]:ClearFocus()
        equal(counts.rebuilds, 1)
        equal(counts.refreshes, 1)
    end
end)

test("f04_delete_custom_cancels_drafts_and_unbinds_surplus_rows", function()
    for _, case in ipairs(editCases) do
        for _, index in ipairs({ 2, 9 }) do
            local state, ns = setup()
            local entry = addDraftTestEntry(ns, index)
            ns:OpenConfig()
            local row = ns.Config.rows[index]
            local box, original = row[case.field], entry[case.field]
            local following = ns:GetEntries()[index + 1]
            local followingValue = following and following[case.field]
            box:SetFocus()
            box:SetText(case.draft)
            local counts = watchConfigRefresh(ns)
            state:script(row.delete, "OnClick")
            equal(#ns:GetEntries(), 8)
            equal(entry[case.field], original, "removed entry must not receive a canceled draft")
            if following then
                equal(row.entry, following)
                equal(following[case.field], followingValue)
                equal(box:GetText(), tostring(followingValue))
            end
            local surplus = ns.Config.rows[9]
            equal(surplus:IsShown(), false)
            equal(surplus.entry, nil)
            for _, field in ipairs({ "label", "itemID", "spellID" }) do
                equal(surplus[field].entry, nil, "hidden editors must release old entry bindings")
                equal(surplus[field]:GetText(), "")
                state:script(surplus[field], "OnEditFocusLost")
            end
            box:ClearFocus()
            equal(counts.rebuilds, 1)
            equal(counts.refreshes, 1)
            local replacement = addDraftTestEntry(ns, 9)
            equal(surplus.entry, replacement)
            equal(surplus[case.field]:GetText(), tostring(replacement[case.field]))
            equal(entry[case.field], original)
        end
    end
end)

test("f04_defaults_cancel_pending_builtin_and_custom_drafts_in_and_out_of_combat", function()
    for _, case in ipairs(editCases) do
        for _, mode in ipairs({ "button", "command", "direct" }) do
            for _, combat in ipairs({ false, true }) do
                local state, ns = setup()
                local custom = addDraftTestEntry(ns, 9)
                ns:OpenConfig()
                local row = ns.Config.rows[2]
                local entry, original = row.entry, row.entry[case.field]
                ns.Config.rows[9][case.field]:SetText(case.draft)
                row[case.field]:SetFocus()
                row[case.field]:SetText(case.draft)
                local customValue = custom[case.field]
                local counts = watchConfigRefresh(ns)
                state.combat = combat
                if mode == "button" then
                    clickButtonText(state, "恢复内置列表")
                elseif mode == "command" then
                    state:command("defaults")
                else
                    ns:ResetEntries()
                end
                equal(entry[case.field], original)
                equal(custom[case.field], customValue)
                equal(#ns:GetEntries(), 8)
                assert(row.entry ~= entry, "defaults must replace old entry objects")
                equal(row.entry[case.field], ns.BUILTIN_ENTRIES[2][case.field])
                equal(row[case.field]:GetText(), tostring(ns.BUILTIN_ENTRIES[2][case.field]))
                equal(ns.Config.rows[9].entry, nil)
                equal(ns.Config.rows[5].spellID.enabled, false)
                equal(ns.Config.rows[5].spellID:GetText(), "8675")
                equal(counts.rebuilds, 1)
                equal(counts.refreshes, 1)
                row[case.field]:ClearFocus()
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                equal(row.entry[case.field], ns.BUILTIN_ENTRIES[2][case.field])
            end
        end
    end
end)

test("f04_external_reorder_or_same_id_replacement_cancels_without_recursive_refresh", function()
    for _, case in ipairs(editCases) do
        for _, replace in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = ns.Config.rows[2]
            local entry, original = row.entry, row.entry[case.field]
            row[case.field]:SetFocus()
            row[case.field]:SetText(case.draft)
            local entries = ns:GetEntries()
            if replace then
                local replacement = {}
                for key, value in pairs(entry) do replacement[key] = value end
                entries[2] = replacement
            else
                entries[2], entries[3] = entries[3], entries[2]
            end
            local targetValue = entries[2][case.field]
            local counts = watchConfigRefresh(ns)
            ns.Config:Refresh()
            equal(entry[case.field], original)
            equal(row.entry, entries[2])
            equal(row.entry[case.field], targetValue)
            equal(row[case.field]:GetText(), tostring(targetValue))
            row[case.field]:ClearFocus()
            equal(counts.rebuilds, 0, "rebinding must suppress focus-loss commits")
            equal(counts.refreshes, 1)
        end
    end
end)

test("f04_aura_to_enchant_rebind_cancels_spell_draft_and_preserves_readonly_tracking", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = ns.Config.rows[6]
    local entry, original = row.entry, row.entry.spellID
    row.spellID:SetFocus()
    row.spellID:SetText("9999")
    local entries = ns:GetEntries()
    entries[5], entries[6] = entries[6], entries[5]
    local counts = watchConfigRefresh(ns)
    ns.Config:Refresh()
    equal(counts.rebuilds, 0)
    equal(entry.spellID, original)
    equal(row.spellID.enabled, false)
    equal(row.spellID:GetText(), "8675")
    row.spellID:SetText("1234")
    state:script(row.spellID, "OnEditFocusLost")
    equal(row.entry.spellID, nil)
    equal(row.entry.enchantID, 8675)
    equal(row.entry.useSpellID, 1284999)
    state:fire("UNIT_AURA", "player")
    equal(row.spellID:GetText(), "8675")
    entries[5], entries[6] = entries[6], entries[5]
    ns.Config:Refresh()
    equal(row.spellID.enabled, true)
    row.spellID:SetFocus()
    row.spellID:SetText("9999")
    state:script(row.spellID, "OnEnterPressed")
    equal(entry.spellID, 9999)
end)

test("f04_panel_or_ancestor_hide_cancels_with_either_focus_callback_order", function()
    for _, case in ipairs(editCases) do
        for _, ancestor in ipairs({ false, true }) do
            for _, focusFirst in ipairs({ false, true }) do
                for _, combat in ipairs({ false, true }) do
                    local state, ns = setup()
                    ns:OpenConfig()
                    state.hideFocusBeforeScripts = focusFirst
                    local panel = ns.Config
                    local box = panel.rows[2][case.field]
                    local entry, original = box.entry, box.entry[case.field]
                    local other = panel.rows[3].label
                    local otherValue = other.entry.label
                    other:SetText("待提交")
                    box:SetFocus()
                    box:SetText(case.draft)
                    local counts = watchConfigRefresh(ns)
                    state.combat = combat
                    local hidden = ancestor and panel:GetParent() or panel
                    hidden:Hide()
                    equal(entry[case.field], original, "hiding must cancel pending input")
                    equal(box:GetText(), tostring(original))
                    equal(other.entry.label, otherValue)
                    equal(other:GetText(), otherValue)
                    equal(box:HasFocus(), false)
                    equal(counts.rebuilds, 0, "OnHide/focus loss must not rebuild")
                    equal(counts.refreshes, 0)
                    state:fire("BAG_UPDATE_DELAYED")
                    hidden:Show()
                    equal(box:GetText(), tostring(original))
                    equal(box.entry, entry)
                    state.combat = false
                    box:SetFocus()
                    box:SetText(case.draft)
                    state:script(box, "OnEnterPressed")
                    equal(entry[case.field], case.value, "reopened panel must accept fresh edits")
                    equal(counts.rebuilds, 1)
                end
            end
        end
    end
end)

test("f04_focus_loss_before_structural_click_commits_only_the_original_entry", function()
    for _, case in ipairs(editCases) do
        for _, action in ipairs({ "sort", "delete", "defaults" }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = ns.Config.rows[2]
            local entry, neighbor = row.entry, ns:GetEntries()[3]
            local neighborValue = neighbor[case.field]
            row[case.field]:SetFocus()
            row[case.field]:SetText(case.draft)
            row[case.field]:ClearFocus()
            equal(entry[case.field], case.value)
            if action == "sort" then
                state:script(row.down, "OnClick")
            elseif action == "delete" then
                state:script(row.delete, "OnClick")
            else
                state:command("defaults")
                equal(row.entry[case.field], ns.BUILTIN_ENTRIES[2][case.field])
            end
            equal(entry[case.field], case.value, "already-committed edits belong to the old entry")
            equal(neighbor[case.field], neighborValue)
        end
    end
end)

test("combat_edit_keeps_display_and_secure_action_consistent", function()
    local state, ns = setup()
    ns:OpenConfig()
    local button = state:button("haranir-phial")
    state.combat = true
    local box = ns.Config.rows[2].itemID
    box:SetText("191354")
    state:script(box, "OnEditFocusLost")
    equal(button.attributes.item, "item:" .. button.entry.itemID,
        "displayed item differs from item that a hardware click would use")
end)

-- F05: settings remain editable, while actions, watch lists and status all use
-- the last applied entries. Live game data still refreshes against those IDs.
local function configRow(ns, id)
    for _, row in ipairs(ns.Config.rows) do
        if row.entry and row.entry.id == id then return row end
    end
    error("configuration row missing: " .. id)
end

local function editConfigField(state, row, field, value)
    row[field]:SetFocus()
    row[field]:SetText(tostring(value))
    state:script(row[field], "OnEnterPressed")
end

local function readStatus(state)
    state.messages = {}
    state:command("status")
    return table.concat(state.messages, "\n")
end

local function assertAction(button, action, payload)
    equal(button.attributes.type, action)
    equal(button.attributes.item, action == "item" and "item:" .. payload or nil)
    equal(button.attributes.toy, action == "toy" and payload or nil)
    equal(button.attributes.macrotext, action == "macro" and payload or nil)
end

local function f05CustomEntry()
    return {
        id = "f05-custom", label = "自定义已应用", category = "custom",
        itemID = 910100, spellID = 810100, action = "item", enabled = true, builtin = false,
    }
end

test("f05_noncombat_edits_apply_detached_entries_only_on_rebuild", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "haranir-phial")
    local desired = row.entry
    local applied = state:button(desired.id).entry
    assert(applied ~= desired, "runtime entry must be detached from editable settings")
    editConfigField(state, row, "label", "已应用新名称")
    editConfigField(state, row, "itemID", 910001)
    editConfigField(state, row, "spellID", 810001)
    local button = state:button(desired.id)
    assert(button.entry ~= desired)
    equal(button.entry.label, "已应用新名称")
    equal(button.entry.spellID, 810001)
    assertAction(button, "item", 910001)
    equal(applied.label, ns.BUILTIN_ENTRIES[2].label)
    equal(applied.itemID, 241316, "a later rebuild must not mutate an older snapshot")
    equal(row.entry, desired, "the editor must keep editing desired settings")

    -- Even out of combat, an ordinary refresh must not partly apply settings.
    desired.itemID, desired.spellID = 910002, 810002
    state.auras = { aura(810001), aura(810002) }
    ns:Refresh()
    assertAction(button, "item", 910001)
    equal(button.effect.spellId, 810001)
    equal(ns:ScanAuras()[810002], nil)
    ns:RequestRebuild()
    button = state:button(desired.id)
    assertAction(button, "item", 910002)
    equal(button.effect.spellId, 810002)
    equal(ns:ScanAuras()[810001], nil)
end)

local actionCases = {
    { id = "haranir-phial", action = "item", itemID = 241316, newItemID = 910011 },
    { id = "oversized-bobber", action = "toy", itemID = 202207, newItemID = 910012 },
    { id = "pointed-spikesnail", action = "macro", itemID = 262651, newItemID = 910013,
        macrotext = "/use item:262651\n/use 28" },
}

for _, case in ipairs(actionCases) do
    test("f05_" .. case.action .. "_combat_metadata_and_live_queries_keep_applied_ids", function()
        local state, ns = setup()
        ns:OpenConfig()
        local row = configRow(ns, case.id)
        local button = state:button(case.id)
        local applied = button.entry
        local oldPayload = case.macrotext or case.itemID
        local newPayload = case.action == "macro" and "/use item:" .. case.newItemID .. "\n/use 28"
            or case.newItemID
        state.icons[case.itemID], state.icons[case.newItemID] = 111, 222
        state.counts[case.itemID], state.counts[case.newItemID] = 4, 13
        state.cooldowns[case.itemID] = { 95, 30, true }
        state.cooldowns[case.newItemID] = { 90, 80, true }
        ns:Refresh()
        state:script(button, "OnEnter")
        local allocated = state:secureFrameCount()
        state.combat = true
        editConfigField(state, row, "label", "排队的新名称")
        if case.action == "macro" then
            -- F08 makes macro ItemID read-only. This F05 test still simulates
            -- a complete external definition update, with identical assertions.
            row.entry.itemID, row.entry.macrotext = case.newItemID, newPayload
        else
            editConfigField(state, row, "itemID", case.newItemID)
        end
        row.entry.category = "custom"
        ns:RequestRebuild()
        ns.Bar:Rebuild() -- The direct rebuild guard must retain the same snapshot too.
        equal(button.entry, applied)
        equal(applied.itemID, case.itemID)
        assert(applied ~= row.entry)
        assertAction(button, case.action, oldPayload)
        equal(button.icon.texture, 111)
        equal(button.countText:GetText(), case.action == "toy" and "1" or "4")
        equal(button.cooldown.cooldown[2], 30)
        equal(state.env.GameTooltip.hyperlink, "item:" .. case.itemID)
        equal(state.env.GameTooltip.lines[2],
            ns.CATEGORY_LABELS[applied.category] .. " · " .. ns.ACTION_LABELS[case.action])
        local status = readStatus(state)
        assert(status:find(applied.label .. ":", 1, true))
        assert(not status:find("排队的新名称:", 1, true))
        assert(status:find("已应用", 1, true) and status:find("战斗结束后应用", 1, true))

        state.counts[case.itemID] = 7
        state.toys[case.itemID] = false
        state.toys[case.newItemID] = true
        state.icons[case.itemID] = 333
        state.cooldowns[case.itemID] = { 98, 40, true }
        for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN", "UNIT_AURA" }) do
            state:fire(event, "player")
            equal(button.icon.texture, 333, "applied item icons must still refresh live")
            equal(button.countText:GetText(), case.action == "toy" and "0" or "7")
            equal(button.cooldown.cooldown[2], 40)
            equal(state.env.GameTooltip.hyperlink, "item:" .. case.itemID)
            assertAction(button, case.action, oldPayload)
        end
        equal(state:secureFrameCount(), allocated, "combat edits must not allocate secure buttons")
        equal(ns.rebuildPending, true)
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(ns.rebuildPending, nil)
        equal(state.env.GameTooltip:IsShown(), false, "retired action tooltip must close on apply")
        button = state:button(case.id)
        assert(button.entry ~= applied and button.entry ~= row.entry)
        assertAction(button, case.action, newPayload)
        equal(button.entry.label, "排队的新名称")
        equal(button.entry.category, "custom")
        equal(button.icon.texture, 222)
        equal(button.countText:GetText(), case.action == "toy" and "1" or "13")
        equal(button.cooldown.cooldown[2], 80)
        state:script(button, "OnEnter")
        equal(state.env.GameTooltip.hyperlink, "item:" .. case.newItemID)
        equal(state.env.GameTooltip.lines[2], "自定义 · " .. ns.ACTION_LABELS[case.action])
        status = readStatus(state)
        assert(status:find("排队的新名称:", 1, true))
        assert(not status:find("战斗结束后应用", 1, true))
    end)
end

test("f05_action_type_changes_switch_item_toy_and_macro_attributes_on_regen", function()
    for _, case in ipairs(actionCases) do
        for _, action in ipairs({ "item", "toy", "macro" }) do
            if action ~= case.action then
                local state, ns = setup()
                ns:OpenConfig()
                local desired = configRow(ns, case.id).entry
                local button = state:button(case.id)
                state.combat = true
                desired.action, desired.itemID = action, 920001
                desired.macrotext = action == "macro" and "/use item:920001" or nil
                ns:RequestRebuild()
                assertAction(button, case.action, case.macrotext or case.itemID)
                equal(button.entry.action, case.action)
                equal(button.entry.itemID, case.itemID)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                button = state:button(case.id)
                assertAction(button, action, desired.macrotext or desired.itemID)
                equal(button.entry.action, action)
                equal(button.entry.itemID, 920001)
            end
        end
    end
end)

test("f05_spell_edit_tracks_old_aura_removal_and_reapplication_until_regen", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "haranir-phial")
    local button = state:button(row.entry.id)
    local oldID, newID = row.entry.spellID, 820001
    local oldAura, newAura = aura(oldID, 220, 3), aura(newID, 500, 8)
    oldAura.icon, newAura.icon = 111, 222
    state.auras = { oldAura }
    ns:Refresh()
    state:script(button, "OnEnter")
    state.combat = true
    editConfigField(state, row, "spellID", newID)
    equal(row.entry.spellID, newID)
    state.auras = { oldAura, newAura }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.spellId, oldID)
    equal(button.icon.texture, 111)
    equal(button.countText:GetText(), "3")
    equal(ns:ScanAuras()[newID], nil, "desired spell must not enter the applied watch list")
    equal(ns:GetEntryEffect(button.entry).spellId, oldID)
    equal(state.env.GameTooltip.spellID, oldID)
    assert(readStatus(state):find("SpellID " .. oldID, 1, true))
    assert(not readStatus(state):find("SpellID " .. newID, 1, true))

    state.auras = { newAura }
    state:fire("UNIT_AURA", "player")
    equal(button.effect, nil, "new Aura must not stand in for a removed applied Aura")
    equal(button.timeText:GetText(), "")
    equal(state.env.GameTooltip.hyperlink, "item:241316")
    state.auras = { newAura, oldAura }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.spellId, oldID, "reapplication must still find the applied spell")
    equal(button.timeText:GetText(), "2m")

    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    button = state:button(row.entry.id)
    equal(button.entry.spellID, newID)
    equal(button.effect.spellId, newID)
    equal(button.icon.texture, 222)
    equal(button.countText:GetText(), "8")
    equal(ns:ScanAuras()[oldID], nil)
    state:script(button, "OnEnter")
    equal(state.env.GameTooltip.spellID, newID)
    state.auras = { oldAura }
    state:fire("UNIT_AURA", "player")
    equal(button.effect, nil)
    state.auras = { newAura }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.spellId, newID)
end)

test("f05_disable_and_delete_keep_applied_watch_list_and_status_until_regen", function()
    for _, mode in ipairs({ "disable", "builtin-delete", "custom-delete" }) do
        local state, ns = setup(mode == "custom-delete" and { entries = { f05CustomEntry() } } or nil)
        ns:OpenConfig()
        local id = mode == "custom-delete" and "f05-custom" or "haranir-phial"
        local row = configRow(ns, id)
        local button = state:button(id)
        local applied, count = button.entry, #ns.Bar.buttons
        state.auras = { aura(applied.spellID) }
        ns:Refresh()
        state.combat = true
        if mode == "disable" then
            row.enabled:SetChecked(false)
            state:script(row.enabled, "OnClick")
        else
            state:script(row.delete, "OnClick")
        end
        equal(#ns.Bar.buttons, count)
        equal(state:button(id), button)
        equal(button.entry.enabled, true)
        equal(button.effect.spellId, applied.spellID)
        equal(ns:ScanAuras()[applied.spellID].spellId, applied.spellID)
        assert(readStatus(state):find(applied.label .. ":", 1, true))
        state.auras = {}
        state:fire("UNIT_AURA", "player")
        equal(button.effect, nil)
        state.auras = { aura(applied.spellID, 300, 5) }
        state:fire("UNIT_AURA", "player")
        equal(button.countText:GetText(), "5", "deleted/disabled desired entries must remain watched")
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(state:button(id), nil)
        equal(#ns.Bar.buttons, count - 1)
        equal(ns:ScanAuras()[applied.spellID], nil)
        assert(not readStatus(state):find(applied.label .. ":", 1, true))
    end
end)

test("f05_defaults_keep_custom_and_overridden_applied_spells_until_regen", function()
    local state, ns = setup({ entries = { f05CustomEntry() } })
    ns:OpenConfig()
    local row = configRow(ns, "haranir-phial")
    editConfigField(state, row, "label", "旧瓶剂设置")
    editConfigField(state, row, "itemID", 930001)
    editConfigField(state, row, "spellID", 830001)
    local phial, custom = state:button("haranir-phial"), state:button("f05-custom")
    state.auras = { aura(830001, 220, 3), aura(1236763, 500, 8), aura(810100, 300, 4) }
    ns:Refresh()
    state.combat = true
    state:command("defaults")
    equal(#ns:GetEntries(), 8)
    equal(#ns.Bar.buttons, 9)
    equal(phial.entry.label, "旧瓶剂设置")
    assertAction(phial, "item", 930001)
    state:fire("UNIT_AURA", "player")
    equal(phial.effect.spellId, 830001)
    equal(custom.effect.spellId, 810100)
    equal(ns:ScanAuras()[1236763], nil)
    local status = readStatus(state)
    assert(status:find("旧瓶剂设置:", 1, true))
    assert(status:find("自定义已应用:", 1, true))
    assert(not status:find(ns.BUILTIN_ENTRIES[2].label .. ":", 1, true))
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    phial = state:button("haranir-phial")
    equal(#ns.Bar.buttons, 8)
    equal(state:button("f05-custom"), nil)
    assertAction(phial, "item", 241316)
    equal(phial.effect.spellId, 1236763)
    equal(ns:ScanAuras()[830001], nil)
    equal(ns:ScanAuras()[810100], nil)
    assert(not readStatus(state):find("自定义已应用:", 1, true))
end)

test("f05_reorder_hide_and_lure_settings_keep_applied_order_and_tracking", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "haranir-phial")
    local original = {}
    for index, button in ipairs(ns.Bar.buttons) do original[index] = button end
    state.auras = { aura(1236763), aura(397827) }
    ns:Refresh()
    state.combat = true
    row.lure:SetChecked(true)
    state:script(row.lure, "OnClick")
    state:script(row.up, "OnClick")
    state:command("hide")
    state:command("show")
    state:command("hide")
    equal(ns.Bar:IsShown(), true)
    equal(ns.visibilityPending, false)
    for index, button in ipairs(original) do equal(ns.Bar.buttons[index], button) end
    equal(original[2].entry.category, "phial")
    equal(original[2].entry.hideWhenMissing, nil)
    state:fire("UNIT_AURA", "player")
    equal(original[2].effect.spellId, 1236763)
    local status = readStatus(state)
    assert(status:find(original[1].entry.label .. ":", 1, true)
        < status:find(original[2].entry.label .. ":", 1, true))
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(ns.Bar:IsShown(), false)
    equal(ns.visibilityPending, nil)
    equal(ns.Bar.buttons[1].entry.id, "haranir-phial")
    equal(ns.Bar.buttons[1].entry.hideWhenMissing, true)
    equal(ns.Bar.buttons[1].entry.category, "lure")
    state:command("show")
    equal(state:button("haranir-phial").effect.spellId, 1236763)
    state.auras = {}
    state:fire("UNIT_AURA", "player")
    equal(state:button("haranir-phial"):IsShown(), false)
end)

test("f05_empty_applied_list_excludes_pending_enables_and_additions", function()
    local state, ns = setup()
    for _, entry in ipairs(ns:GetEntries()) do entry.enabled = false end
    ns:RequestRebuild()
    ns:OpenConfig()
    equal(#ns.Bar.buttons, 0)
    state.combat = true
    local row = configRow(ns, "haranir-phial")
    row.enabled:SetChecked(true)
    state:script(row.enabled, "OnClick")
    table.insert(ns:GetEntries(), f05CustomEntry())
    ns:RequestRebuild()
    state.auras = { aura(1236763), aura(810100) }
    state:fire("UNIT_AURA", "player")
    equal(#ns.Bar.buttons, 0)
    equal(next(ns:ScanAuras()), nil, "empty applied list must not fall back to desired settings")
    local status = readStatus(state)
    assert(not status:find(row.entry.label .. ":", 1, true))
    assert(not status:find("自定义已应用:", 1, true))
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(#ns.Bar.buttons, 2)
    equal(state:button("haranir-phial").effect.spellId, 1236763)
    equal(state:button("f05-custom").effect.spellId, 810100)
    assertAction(state:button("f05-custom"), "item", 910100)
end)

test("f05_latest_edits_after_defaults_and_reorder_apply_on_each_regen", function()
    local state, ns = setup()
    ns:OpenConfig()
    local button = state:button("haranir-phial")
    local original = button.entry
    state.combat = true
    local row = configRow(ns, original.id)
    editConfigField(state, row, "itemID", 940001)
    editConfigField(state, row, "spellID", 840001)
    state:script(row.action, "OnClick")
    state:script(row.down, "OnClick")
    state:command("defaults")
    row = configRow(ns, original.id)
    editConfigField(state, row, "label", "最终设置")
    editConfigField(state, row, "itemID", 940002)
    editConfigField(state, row, "spellID", 840002)
    state:script(row.action, "OnClick")
    state:script(row.up, "OnClick")
    state:script(configRow(ns, "oversized-bobber").delete, "OnClick")
    state.auras = { aura(original.spellID, 200, 2), aura(840001, 300, 3), aura(840002, 400, 4) }
    state:fire("UNIT_AURA", "player")
    assertAction(button, "item", 241316)
    equal(button.entry, original)
    equal(button.effect.spellId, original.spellID)
    equal(ns:ScanAuras()[840001], nil)
    equal(ns:ScanAuras()[840002], nil)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    button = state:button(original.id)
    equal(ns.Bar.buttons[1], button)
    equal(#ns.Bar.buttons, 7)
    equal(state:button("oversized-bobber"), nil)
    equal(button.entry.label, "最终设置")
    assertAction(button, "toy", 940002)
    equal(button.effect.spellId, 840002)
    equal(button.countText:GetText(), "4")
    equal(ns:ScanAuras()[840001], nil)
    equal(ns:ScanAuras()[original.spellID], nil)
    state.combat = true
    editConfigField(state, configRow(ns, original.id), "itemID", 940003)
    assertAction(button, "toy", 940002)
    equal(button.entry.itemID, 940002)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    assertAction(state:button(original.id), "toy", 940003)
    equal(original.itemID, 241316)
end)

test("f05_enchantment_poll_and_equipment_checks_keep_applied_slot_and_ids", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "pointed-spikesnail")
    local desired, button = row.entry, state:button(row.entry.id)
    state.enchantments[28] = spikesnailEnchant(120000)
    ns:Refresh()
    state:script(button, "OnEnter")
    state.combat = true
    desired.enchantID, desired.inventorySlot = 8999, 16
    desired.useSpellID, desired.requiredEquippedItemID = 850001, 950001
    state.enchantments[16] = spikesnailEnchant(600000, 8999)
    state.enchantmentQueries = {}
    ns:RequestRebuild()
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.entry.inventorySlot, 28)
    equal(button.entry.requiredEquippedItemID, 244790)
    equal(button.effect.enchantID, 8675)
    equal(button.timeText:GetText(), "2m")
    equal(button.warning:IsShown(), false)
    for _, slot in ipairs(state.enchantmentQueries) do equal(slot, 28) end
    local status = readStatus(state)
    assert(status:find("EnchantID 8675", 1, true) and status:find("栏位 28", 1, true))
    assert(status:find("UseSpellID 1284999", 1, true))
    assert(not status:find("EnchantID 8999", 1, true))
    state.equippedItemID = 950001
    state:fire("PLAYER_EQUIPMENT_CHANGED")
    equal(button.warning:IsShown(), true, "queued equipment ID must not suppress the old requirement")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("未装备指定渔竿", 1, true))
    state.enchantments[28] = nil
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.effect, nil, "queued enchantment in another slot must not activate the old action")
    state.enchantments[28] = spikesnailEnchant(180000)
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.effect.enchantID, 8675)
    equal(button.timeText:GetText(), "3m")
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    button = state:button(desired.id)
    equal(button.entry.inventorySlot, 16)
    equal(button.effect.enchantID, 8999)
    equal(button.timeText:GetText(), "10m")
    equal(button.warning:IsShown(), false)
    status = readStatus(state)
    assert(status:find("EnchantID 8999", 1, true) and status:find("栏位 16", 1, true))
    assert(status:find("UseSpellID 850001", 1, true))
end)

test("f05_tracking_kind_changes_keep_applied_aura_or_enchantment_until_regen", function()
    for _, toEnchant in ipairs({ true, false }) do
        local state, ns = setup()
        ns:OpenConfig()
        local id = toEnchant and "haranir-phial" or "pointed-spikesnail"
        local desired = configRow(ns, id).entry
        local button = state:button(id)
        local oldSpell = 1236763
        state.auras = { aura(oldSpell), aura(860001) }
        state.enchantments[28] = spikesnailEnchant()
        ns:Refresh()
        state.combat = true
        if toEnchant then
            desired.spellID = nil
            desired.enchantID, desired.inventorySlot = 8675, 28
        else
            desired.spellID = 860001
            desired.enchantID, desired.inventorySlot = nil, nil
        end
        ns:RequestRebuild()
        state:fire("UNIT_AURA", "player")
        state:script(ns.Bar, "OnUpdate", 1)
        if toEnchant then
            equal(button.effect.spellId, oldSpell)
            equal(button.effect.enchantID, nil)
        else
            equal(button.effect.enchantID, 8675)
            equal(ns:ScanAuras()[860001], nil)
        end
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        button = state:button(id)
        if toEnchant then
            equal(button.effect.enchantID, 8675)
            equal(ns:ScanAuras()[oldSpell], nil)
        else
            equal(button.effect.spellId, 860001)
            equal(button.effect.enchantID, nil)
        end
    end
end)

test("f05_partial_aura_scans_sanitize_fields_and_mark_only_applied_spells_unknown", function()
    local state, ns = setup()
    ns:OpenConfig()
    local access = Mock.restrictedAPI(state)
    local row = configRow(ns, "haranir-phial")
    local button = state:button(row.entry.id)
    local oldID = button.entry.spellID
    state.combat = true
    editConfigField(state, row, "spellID", 870001)
    state.auras = {
        access:table({}, { tableReadable = false }),
        access:table({
            spellId = oldID, icon = access:value(),
            applications = access:value(), expirationTime = access:value(),
        }),
        access:table({ spellId = 870001 }, { allowedFields = { spellId = true } }),
    }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.spellId, oldID)
    equal(button.effect.icon, nil)
    equal(button.effect.applications, nil)
    equal(button.effect.expirationTime, nil)
    equal(button.timeText:GetText(), "?")
    equal(button.countText:GetText(), "?")
    equal(ns:ScanAuras()[870001], nil)
    state.auras = { access:table({}, { tableReadable = false }) }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.unknown, true)
    equal(ns:ScanAuras()[oldID].unknown, true)
    equal(ns:ScanAuras()[870001], nil)
    state:script(button, "OnEnter")
    assert(table.concat(state.env.GameTooltip.lines, "\n"):find("状态未知", 1, true))
    assert(readStatus(state):find(button.entry.label .. ": |cff99bbffUNKNOWN", 1, true))
    state.auras = { access:table(aura(870001, 300, 6)) }
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    button = state:button(row.entry.id)
    equal(button.effect.spellId, 870001)
    equal(button.countText:GetText(), "6")
    equal(ns:ScanAuras()[oldID], nil)
end)

test("f05_applying_committed_changes_on_regen_preserves_f04_uncommitted_drafts", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "haranir-phial")
    local originalLabel = row.entry.label
    state.combat = true
    editConfigField(state, row, "itemID", 980001)
    editConfigField(state, row, "spellID", 880001)
    row.label:SetFocus()
    row.label:SetText("  仍在编辑  ")
    for _, event in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN" }) do
        state:fire(event, "player")
        equal(row.label:GetText(), "  仍在编辑  ")
        equal(state:button(row.entry.id).entry.label, originalLabel)
        assertAction(state:button(row.entry.id), "item", 241316)
    end
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(row.label:GetText(), "  仍在编辑  ")
    equal(row.entry.label, originalLabel)
    local button = state:button(row.entry.id)
    equal(button.entry.label, originalLabel)
    equal(button.entry.spellID, 880001)
    assertAction(button, "item", 980001)
    row.label:ClearFocus()
    equal(row.entry.label, "仍在编辑")
    equal(state:button(row.entry.id).entry.label, "仍在编辑")
end)

test("rebuild_reuses_existing_secure_frames", function()
    local state, ns = setup()
    local before = state:secureFrameCount()
    for _ = 1, 50 do ns:RequestRebuild() end
    equal(state:secureFrameCount(), before, "50 rebuilds grew permanent secure frame allocation")
end)

-- F07: count permanent frames/regions as well as rebuild requests. Reusing a
-- button alone could otherwise conceal redundant edit commits and action writes.
local function watchActionWork(state, ns)
    local work = { copies = 0, rebuilds = 0, attributes = 0 }
    local copy, rebuild = ns.CopyEntries, ns.Bar.Rebuild
    ns.CopyEntries = function(self)
        work.copies = work.copies + 1
        return copy(self)
    end
    ns.Bar.Rebuild = function(self)
        work.rebuilds = work.rebuilds + 1
        return rebuild(self)
    end
    for _, frame in ipairs(state.frames) do
        if frame.secure then
            local setAttribute = frame.SetAttribute
            frame.SetAttribute = function(self, ...)
                work.attributes = work.attributes + 1
                return setAttribute(self, ...)
            end
        end
    end
    return work
end

local function f07Entry(index)
    return {
        id = "f07-" .. index, label = "Pool " .. index, category = "custom",
        itemID = 900000 + index, spellID = 800000 + index,
        action = "item", enabled = true,
    }
end

local function numberControl(state, label, text)
    for _, frame in ipairs(state.frames) do
        if frame.parent == label.parent and frame.kind == "Button" and frame:GetText() == text then
            return frame
        end
    end
    error("number control missing")
end

test("f07_repeated_rebuilds_retain_buttons_cooldowns_and_regions", function()
    local state, ns = setup()
    ns:OpenConfig()
    local frames, regions = #state.frames, #state.regions
    local original = {}
    for index, button in ipairs(ns.Bar.buttons) do original[index] = button end
    for _ = 1, 50 do
        ns:RequestRebuild()
        for index, button in ipairs(ns.Bar.buttons) do
            equal(button, original[index])
            equal(button:GetParent(), ns.Bar)
            assert(button.entry ~= ns:GetEntries()[index], "reuse must still detach applied entries")
        end
    end
    equal(#state.frames, frames, "rebuild allocated child frames")
    equal(#state.regions, regions, "rebuild allocated textures or text")
end)

test("f07_pool_grows_only_with_peak_enabled_count_across_replacements_and_defaults", function()
    local state, ns = setup()
    local peak = 8
    for cycle, count in ipairs({ 3, 0, 5, 11, 2, 11, 0, 8 }) do
        local previous = ns:GetAppliedEntries()
        local firstID = previous[1] and previous[1].id
        local entries = {}
        for index = 1, count + 6 do
            local entry = f07Entry(cycle * 100 + index)
            entry.enabled = index <= count
            entry.hideWhenMissing = true
            entries[index] = entry
        end
        ns.db.entries = entries
        ns:RequestRebuild()
        peak = math.max(peak, count)
        equal(state:secureFrameCount(), peak, "disabled entries or new IDs grew the pool")
        equal(#ns.Bar.buttons, count)
        local cooldowns = 0
        for _, frame in ipairs(state.frames) do
            if frame.kind == "Cooldown" and frame.parent.secure then cooldowns = cooldowns + 1 end
        end
        equal(cooldowns, peak)
        for index, button in ipairs(ns.Bar.buttons) do
            equal(button.entry.id, entries[index].id)
            equal(button:IsShown(), false, "missing effects must stay hidden on reused slots")
            assertAction(button, "item", entries[index].itemID)
        end
        equal(previous[1] and previous[1].id, firstID, "reuse mutated a retired snapshot")
    end
    ns:ResetEntries()
    equal(state:secureFrameCount(), peak)
    equal(#ns.Bar.buttons, 8)
    assertAction(state:button("oversized-bobber"), "toy", 202207)
    assertAction(state:button("pointed-spikesnail"), "macro", "/use item:262651\n/use 28")
end)

test("f07_same_frame_switches_all_action_types_and_clears_empty_actions", function()
    local state, ns = setup()
    local button = ns.Bar.buttons[1]
    ns.db.entries = { f07Entry(1) }
    local entry = ns:GetEntries()[1]
    for _, from in ipairs({ "item", "toy", "macro" }) do
        for _, to in ipairs({ "item", "toy", "macro", "empty" }) do
            entry.action, entry.itemID, entry.macrotext = from, 900001, "/use item:900001"
            ns:RequestRebuild()
            assertAction(button, from, from == "macro" and entry.macrotext or entry.itemID)
            entry.action = to == "empty" and "item" or to
            entry.itemID = to == "empty" and 0 or 900002
            entry.macrotext = to == "macro" and "/use item:900002" or nil
            ns:RequestRebuild()
            equal(ns.Bar.buttons[1], button, "type switching abandoned the original frame")
            assertAction(button, to ~= "empty" and to or nil,
                to == "macro" and entry.macrotext or entry.itemID)
            equal(button.attributes.macro, nil)
            equal(state:secureFrameCount(), 8)
        end
    end
end)

test("f07_release_and_hidden_reuse_clear_effect_cooldown_text_warning_and_tooltip", function()
    for _, mode in ipairs({ "aura", "cooldown", "unknown", "enchant" }) do
        local state, ns = setup()
        local entry = f07Entry(1)
        entry.requiredEquippedItemID = 244790
        if mode == "enchant" then
            entry.spellID, entry.enchantID, entry.inventorySlot = nil, 8675, 28
            entry.action, entry.macrotext = "macro", "/use item:900001\n/use 28"
            state.enchantments[28] = spikesnailEnchant(120000)
        elseif mode == "aura" then
            state.auras = { aura(entry.spellID, 220, 4) }
        elseif mode == "unknown" then
            state.auras = { {} } -- An unreadable identity leaves the watch list unknown.
        end
        state.equippedItemID = nil
        state.counts[entry.itemID] = 9
        state.cooldowns[entry.itemID] = { 95, 40, true }
        ns.db.entries = { entry }
        ns:RequestRebuild()
        local button = ns.Bar.buttons[1]
        local applied = button.entry
        equal(button.warning:IsShown(), true)
        if mode == "cooldown" then
            equal(button.cooldown.cooldown[2], 40)
            equal(button.countText:GetText(), "9")
        else
            assert(button.effect)
            assert(button.timeText:GetText() ~= "")
        end
        state:script(button, "OnEnter")
        ns:SetBarVisible(false)
        ns.db.entries = {}
        ns:RequestRebuild()
        equal(#ns.Bar.buttons, 0)
        equal(button:GetParent(), ns.Bar, "released frames must stay owned by the bar")
        equal(button:IsShown(), false)
        equal(next(button.attributes), nil)
        equal(next(button.points), nil)
        equal(button.entry, nil)
        equal(button.effect, nil)
        equal(button.itemCount, nil)
        equal(button.icon.texture, nil)
        equal(button.icon.desaturated, false)
        equal(button.icon.alpha, 1)
        equal(button.cooldown.cooldown, nil)
        equal(button.countText:GetText(), "")
        equal(button.timeText:GetText(), "")
        equal(button.warning:IsShown(), false)
        equal(state.env.GameTooltip:IsShown(), false)
        state:script(button, "OnEnter") -- A late callback cannot display a retired entry.
        equal(state.env.GameTooltip:IsShown(), false)
        state.combat = true
        state:script(ns.Bar, "OnUpdate", 1)
        state.combat = false

        local replacement = f07Entry(2)
        replacement.itemID, replacement.hideWhenMissing = nil, true
        state.auras, state.enchantments = {}, {}
        ns.db.entries = { replacement }
        ns:RequestRebuild()
        equal(ns.Bar.buttons[1], button)
        equal(button:IsShown(), false)
        equal(button.effect, nil)
        equal(button.cooldown.cooldown, nil)
        equal(button.countText:GetText(), "")
        equal(button.timeText:GetText(), "")
        equal(button.warning:IsShown(), false)
        equal(next(button.attributes), nil)
        ns:SetBarVisible(true)
        equal(button:IsShown(), false)
        state.auras = { aura(replacement.spellID, 300, 2) }
        ns:Refresh()
        equal(button:IsShown(), true)
        equal(button.effect.spellId, replacement.spellID)
        equal(button.countText:GetText(), "2")
        equal(button.timeText:GetText(), "4m")
        state:script(button, "OnEnter")
        equal(state.env.GameTooltip.spellID, replacement.spellID)
        equal(applied.id, entry.id)
        equal(ns:ScanAuras()[entry.spellID or 0], nil)
        equal(state:secureFrameCount(), 8)
    end
end)

test("f07_reorder_disable_delete_and_defaults_reuse_slots_with_current_actions", function()
    local state, ns = setup()
    ns:OpenConfig()
    local slots = {}
    for index, button in ipairs(ns.Bar.buttons) do slots[index] = button end
    state:script(configRow(ns, "pointed-spikesnail").up, "OnClick")
    equal(state:button("pointed-spikesnail"), slots[4])
    assertAction(slots[4], "macro", "/use item:262651\n/use 28")
    local row = configRow(ns, "oversized-bobber")
    row.enabled:SetChecked(false)
    state:script(row.enabled, "OnClick")
    equal(state:button("oversized-bobber"), nil)
    assertAction(slots[1], "item", 241316)
    local custom = f07Entry(1)
    table.insert(ns:GetEntries(), custom)
    ns:RequestRebuild()
    equal(state:button(custom.id), slots[8])
    state:script(configRow(ns, custom.id).delete, "OnClick")
    equal(state:button(custom.id), nil)
    equal(slots[8].entry, nil)
    equal(next(slots[8].attributes), nil)
    state:command("defaults")
    for index, button in ipairs(ns.Bar.buttons) do
        equal(button, slots[index])
        equal(button.entry.id, ns.BUILTIN_ENTRIES[index].id)
    end
    equal(state:secureFrameCount(), 8)
end)

test("f07_combat_defers_pool_release_growth_and_applies_only_latest_entries", function()
    for _, initialCount in ipairs({ 0, 3, 8 }) do
        local state, ns = setup()
        for index, entry in ipairs(ns:GetEntries()) do entry.enabled = index <= initialCount end
        ns:RequestRebuild()
        local applied, buttons = ns:GetAppliedEntries(), {}
        for index, button in ipairs(ns.Bar.buttons) do buttons[index] = button end
        local work = watchActionWork(state, ns)
        state.combat = true
        ns.db.entries = {}
        ns:RequestRebuild()
        for index = 1, 15 do ns:GetEntries()[index] = f07Entry(index) end
        ns:RequestRebuild()
        ns.Bar:Rebuild()
        ns.db.entries = { f07Entry(100), f07Entry(101) }
        ns:RequestRebuild()
        equal(ns:GetAppliedEntries(), applied)
        equal(#ns.Bar.buttons, initialCount)
        for index, button in ipairs(buttons) do equal(ns.Bar.buttons[index], button) end
        equal(state:secureFrameCount(), 8)
        equal(work.attributes, 0)
        equal(work.copies, 0)
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(ns.rebuildPending, nil)
        equal(#ns.Bar.buttons, 2)
        equal(state:secureFrameCount(), 8, "intermediate combat lists must never allocate")
        assertAction(ns.Bar.buttons[1], "item", 900100)
        assertAction(ns.Bar.buttons[2], "item", 900101)

        state.combat = true
        for index = 3, 10 do ns:GetEntries()[index] = f07Entry(index) end
        ns:RequestRebuild()
        equal(state:secureFrameCount(), 8)
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(state:secureFrameCount(), 10)
        equal(#ns.Bar.buttons, 10)
    end
end)

for _, case in ipairs(editCases) do
    test("f07_" .. case.field .. "_normalized_noops_and_duplicate_callbacks_do_no_action_work", function()
        for _, combat in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = configRow(ns, "haranir-phial")
            local box, original = row[case.field], row.entry[case.field]
            local applied = ns:GetAppliedEntries()
            local counts, work = watchConfigRefresh(ns), watchActionWork(state, ns)
            local normalized = case.field == "label" and "  " .. original .. "  " or "000" .. original
            state.combat = combat
            for _, text in ipairs({ tostring(original), normalized,
                case.field == "label" and "   " or tostring(original) }) do
                for _, finish in ipairs({ "blur", "enter", "delayed" }) do
                    box:SetFocus()
                    box:SetText(text)
                    if finish == "blur" then
                        box:ClearFocus()
                    elseif finish == "enter" then
                        state:script(box, "OnEnterPressed")
                    else
                        state.focus = nil
                        state:script(box, "OnEditFocusLost")
                    end
                    state:script(box, "OnEditFocusLost")
                    state:script(box, "OnEnterPressed")
                    equal(row.entry[case.field], original)
                    equal(box:GetText(), tostring(original))
                end
            end
            equal(counts.rebuilds, 0)
            equal(counts.refreshes, 0)
            equal(work.copies, 0)
            equal(work.rebuilds, 0)
            equal(work.attributes, 0)
            equal(ns:GetAppliedEntries(), applied)
            equal(ns.rebuildPending, nil)
            equal(state:secureFrameCount(), 8)
        end
    end)
end

test("f07_zero_and_absent_numeric_fields_normalize_without_rebuilding", function()
    for _, field in ipairs({ "itemID", "spellID" }) do
        for _, absent in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = configRow(ns, "haranir-phial")
            local expected
            if not absent then expected = 0 end
            row.entry[field] = expected
            ns:RequestRebuild()
            local counts = watchConfigRefresh(ns)
            for _, text in ipairs({ "", "0", "0000" }) do
                editConfigField(state, row, field, text)
                state:script(row[field], "OnEditFocusLost")
                equal(row.entry[field], expected)
            end
            equal(counts.rebuilds, 0)
        end
    end
end)

test("f07_changed_commits_rebuild_once_despite_late_focus_callbacks", function()
    for _, case in ipairs(editCases) do
        for _, combat in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = configRow(ns, "haranir-phial")
            local counts, work = watchConfigRefresh(ns), watchActionWork(state, ns)
            state.combat = combat
            editConfigField(state, row, case.field, case.draft)
            for _ = 1, 3 do
                state:script(row[case.field], "OnEditFocusLost")
                state:script(row[case.field], "OnEnterPressed")
            end
            equal(row.entry[case.field], case.value)
            equal(counts.rebuilds, 1)
            equal(work.copies, combat and 0 or 1)
            equal(work.rebuilds, combat and 0 or 1)
            if combat then
                equal(work.attributes, 0)
                equal(ns.rebuildPending, true)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                equal(work.rebuilds, 1)
            end
            equal(state:button(row.entry.id).entry[case.field], case.value)
            equal(state:secureFrameCount(), 8)
        end
    end
end)

test("f07_layout_controls_preserve_actions_snapshots_tooltip_and_f04_drafts", function()
    for _, combat in ipairs({ false, true }) do
        local state, ns = setup()
        ns:OpenConfig()
        local button = state:button("haranir-phial")
        state.counts[241316] = 4
        ns:Refresh()
        state:script(button, "OnEnter")
        local row = configRow(ns, "haranir-phial")
        row.label:SetFocus()
        row.label:SetText("  仍在编辑  ")
        local counts, work = watchConfigRefresh(ns), watchActionWork(state, ns)
        local applied, width, scale = ns:GetAppliedEntries(), ns.Bar:GetWidth(), ns.Bar.scale
        local size = button:GetWidth()
        state.combat = combat
        for _, label in ipairs({ ns.Config.sizeLabel, ns.Config.spacingLabel, ns.Config.scaleLabel }) do
            state:script(numberControl(state, label, "+"), "OnClick")
        end
        ns.Config.unavailable:SetChecked(false)
        state:script(ns.Config.unavailable, "OnClick")
        equal(row.label:HasFocus(), true)
        equal(row.label:GetText(), "  仍在编辑  ")
        equal(ns:GetAppliedEntries(), applied)
        equal(state.env.GameTooltip:IsShown(), true)
        equal(state.env.GameTooltip.hyperlink, "item:241316")
        if combat then
            equal(button:GetWidth(), size)
            equal(ns.Bar:GetWidth(), width)
            equal(ns.Bar.scale, scale)
            state.combat = false
            state:fire("PLAYER_REGEN_ENABLED")
        end
        equal(button:GetWidth(), size + 2)
        equal(ns.Bar.scale, scale + 0.05)
        equal(state:button("crystalline-phial"):IsShown(), false)
        equal(button:IsShown(), true)
        equal(ns.Bar:GetWidth(), 2 * (size + 2) + ns.db.frame.spacing + 50)
        equal(counts.rebuilds, 0)
        equal(work.rebuilds, 0)
        equal(work.copies, 0)
        equal(work.attributes, 0)
        equal(ns.rebuildPending, nil)
        equal(ns:GetAppliedEntries(), applied)
        equal(state:secureFrameCount(), 8)
        row.label:ClearFocus()
        equal(state:button(row.entry.id).entry.label, "仍在编辑")
    end
end)

test("f07_layout_controls_at_limits_do_not_refresh_or_rebuild", function()
    local state, ns = setup()
    ns:OpenConfig()
    for _, case in ipairs({
        { "iconSize", ns.Config.sizeLabel, 24, 72 },
        { "spacing", ns.Config.spacingLabel, 0, 20 },
        { "scale", ns.Config.scaleLabel, 0.5, 2 },
    }) do
        for _, upper in ipairs({ false, true }) do
            ns.db.frame[case[1]] = upper and case[4] or case[3]
            ns:Refresh()
            local counts = watchConfigRefresh(ns)
            state:script(numberControl(state, case[2], upper and "+" or "-"), "OnClick")
            equal(counts.rebuilds, 0)
            equal(counts.refreshes, 0)
        end
    end
end)

test("macro_item_edit_updates_action_or_is_disabled", function()
    local state, ns = setup()
    ns:OpenConfig()
    local box = ns.Config.rows[5].itemID
    if box.enabled == false then return end
    box:SetText("241316")
    state:script(box, "OnEditFocusLost")
    local button = state:button("pointed-spikesnail")
    assert(button.attributes.macrotext:find("/use item:" .. button.entry.itemID, 1, true),
        "item editor changes display/count while macro still uses item:262651")
end)

-- F08: disabled controls are also exercised through direct/delayed callbacks.
-- The mock permits these calls deliberately; this tests the commit boundary,
-- not a claim that native disabled EditBoxes accept hardware keyboard input.
local function f08Macro()
    return {
        id = "f08-macro", label = "自定义宏", category = "custom",
        itemID = 910008, spellID = 810008, enabled = true, action = "macro",
        macrotext = "#showtooltip\n/use [mod:shift] item:111111; item:222222\n/say keep this text",
    }
end

local function finishF08Edit(state, box, finish)
    if finish == "enter" or finish == "unfocused-enter" then
        state:script(box, "OnEnterPressed")
    elseif finish == "blur" then
        box:ClearFocus()
    else
        state.focus = nil
        state:script(box, "OnEditFocusLost")
    end
end

test("f08_macro_item_and_enchant_id_present_readonly_with_editable_aura_fields", function()
    local state = Mock.new(addonPath, { entries = { f08Macro() } })
    -- Record this presentation API instead of expanding the cosmetic mock.
    local create = state.env.CreateFrame
    state.env.CreateFrame = function(kind, ...)
        local frame = create(kind, ...)
        if kind == "EditBox" then
            frame.SetTextColor = function(self, ...) self.textColor = { ... } end
        end
        return frame
    end
    state:login()
    local ns = state.ns
    ns:OpenConfig()
    for _, id in ipairs({ "f08-macro", "pointed-spikesnail" }) do
        local row = configRow(ns, id)
        equal(row.itemID.enabled, false)
        equal(row.itemID:GetText(), tostring(row.entry.itemID))
        equal(row.itemID.textColor[1], 0.5)
        equal(row.itemID.textColor[2], 0.5)
        equal(row.itemID.textColor[3], 0.5)
        equal(row.label.enabled, true)
        equal(row.label.textColor[1], 1)
        equal(row.action.enabled, false)
        state:script(row.itemID, "OnEnter")
        equal(state.env.GameTooltip.owner, row.itemID)
        assert(state.env.GameTooltip:GetText():find("ItemID 为只读", 1, true))
        state:script(row.itemID, "OnLeave")
        equal(state.env.GameTooltip:IsShown(), false)
    end
    local enchant = configRow(ns, "pointed-spikesnail").spellID
    equal(enchant.enabled, false)
    equal(enchant:GetText(), "8675")
    equal(enchant.textColor[1], 0.5)
    state:script(enchant, "OnEnter")
    assert(state.env.GameTooltip:GetText():find("追踪 ID 为只读", 1, true))
    equal(configRow(ns, "f08-macro").spellID.enabled, true)
    for _, id in ipairs({ "haranir-phial", "oversized-bobber" }) do
        local row = configRow(ns, id)
        equal(row.itemID.enabled, true)
        equal(row.itemID.textColor[1], 1)
        equal(row.itemID.textColor[2], 1)
        equal(row.itemID.textColor[3], 1)
    end
    local row = configRow(ns, "pointed-spikesnail")
    state:script(row.down, "OnClick")
    equal(row.itemID.enabled, true)
    equal(row.itemID.textColor[1], 1, "reused item fields must regain editable styling")
    equal(row.spellID.enabled, true)
    equal(row.spellID.textColor[1], 1)
end)

test("f08_readonly_enter_and_focus_loss_restore_text_without_writes_or_rebuilds", function()
    for _, case in ipairs({
        { "pointed-spikesnail", "itemID", "262651" },
        { "pointed-spikesnail", "spellID", "8675" },
        { "f08-macro", "itemID", "910008" },
    }) do
        for _, combat in ipairs({ false, true }) do
            for _, finish in ipairs({ "enter", "unfocused-enter", "blur", "delayed" }) do
                local state, ns = setup({ entries = { f08Macro() } })
                ns:OpenConfig()
                local row = configRow(ns, case[1])
                local entry, box = row.entry, row[case[2]]
                local itemID, spellID, enchantID, macro = entry.itemID, entry.spellID,
                    entry.enchantID, entry.macrotext
                local applied, frames = ns:GetAppliedEntries(), state:secureFrameCount()
                local counts, work = watchConfigRefresh(ns), watchActionWork(state, ns)
                state.combat = combat
                if finish ~= "unfocused-enter" then box:SetFocus() end
                box:SetText("000123456")
                finishF08Edit(state, box, finish)
                state:script(box, "OnEditFocusLost")
                state:script(box, "OnEnterPressed")
                equal(box:GetText(), case[3], "blocked drafts must normalize immediately")
                equal(box:HasFocus(), false)
                equal(box.enabled, false)
                equal(entry.itemID, itemID)
                equal(entry.spellID, spellID)
                equal(entry.enchantID, enchantID)
                equal(entry.macrotext, macro)
                equal(ns:GetAppliedEntries(), applied)
                assertAction(state:button(entry.id), "macro", macro)
                equal(counts.rebuilds, 0)
                equal(counts.refreshes, 0)
                equal(work.attributes, 0)
                equal(work.copies, 0)
                equal(state:secureFrameCount(), frames)
                equal(ns.rebuildPending, nil)
            end
        end
    end
end)

test("f08_same_entry_item_to_macro_refresh_cancels_only_the_locked_draft", function()
    for _, id in ipairs({ "haranir-phial", "oversized-bobber" }) do
        for _, combat in ipairs({ false, true }) do
            for _, focused in ipairs({ false, true }) do
                local state, ns = setup()
                ns:OpenConfig()
                local row = configRow(ns, id)
                local entry, original = row.entry, row.entry.itemID
                row.itemID:SetFocus()
                row.itemID:SetText("000123456")
                if not focused then state.focus = nil end
                row.label:SetText("  名称草稿  ")
                row.spellID:SetText("000810009")
                local counts = watchConfigRefresh(ns)
                state.combat = combat
                entry.action, entry.macrotext = "macro", f08Macro().macrotext
                state:fire("UNIT_AURA", "player")
                equal(row.entry, entry)
                equal(row.itemID:GetText(), tostring(original))
                equal(row.itemID:HasFocus(), false)
                equal(row.itemID.enabled, false)
                equal(row.label:GetText(), "  名称草稿  ")
                equal(row.spellID:GetText(), "000810009")
                equal(row.spellID.enabled, true)
                state:script(row.itemID, "OnEditFocusLost")
                equal(entry.itemID, original)
                equal(counts.rebuilds, 0)
                -- Valid drafts in unrelated fields remain committable.
                state:script(row.label, "OnEditFocusLost")
                state:script(row.spellID, "OnEditFocusLost")
                equal(entry.label, "名称草稿")
                equal(entry.spellID, 810009)
                equal(counts.rebuilds, 2)
                equal(entry.macrotext, f08Macro().macrotext)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                assertAction(state:button(id), "macro", entry.macrotext)
                equal(state:button(id).entry.itemID, original)
            end
        end
    end
end)

test("f08_permission_changes_before_callbacks_cancel_stale_drafts_in_both_directions", function()
    for _, startMacro in ipairs({ false, true }) do
        for _, combat in ipairs({ false, true }) do
            for _, finish in ipairs({ "enter", "unfocused-enter", "blur", "delayed" }) do
                local state, ns = setup()
                ns:OpenConfig()
                local row = configRow(ns, "haranir-phial")
                local entry, original = row.entry, row.entry.itemID
                if startMacro then
                    entry.action, entry.macrotext = "macro", f08Macro().macrotext
                    ns:RequestRebuild()
                end
                if finish ~= "unfocused-enter" then row.itemID:SetFocus() end
                row.itemID:SetText("000123456")
                -- No Config refresh before the callback: its permission may be stale.
                entry.action = startMacro and "item" or "macro"
                entry.macrotext = f08Macro().macrotext
                local counts = watchConfigRefresh(ns)
                state.combat = combat
                finishF08Edit(state, row.itemID, finish)
                state:script(row.itemID, "OnEditFocusLost")
                equal(entry.itemID, original)
                equal(row.itemID:GetText(), tostring(original))
                equal(row.itemID:HasFocus(), false)
                equal(row.itemID.enabled, startMacro)
                equal(entry.macrotext, f08Macro().macrotext)
                equal(counts.rebuilds, 0)
                equal(counts.refreshes, 0)
                equal(ns.rebuildPending, nil)
                -- A fresh edit after reenabling is valid, and duplicates are no-ops.
                entry.action = "item"
                ns.Config:Refresh()
                editConfigField(state, row, "itemID", "000910009")
                state:script(row.itemID, "OnEditFocusLost")
                equal(entry.itemID, 910009)
                equal(counts.rebuilds, 1)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                assertAction(state:button(entry.id), "item", 910009)
            end
        end
    end
end)

test("f08_same_entry_macro_to_item_refresh_discards_readonly_period_drafts", function()
    for _, action in ipairs({ "item", "toy" }) do
        local state, ns = setup({ entries = { f08Macro() } })
        ns:OpenConfig()
        local row = configRow(ns, "f08-macro")
        local entry = row.entry
        row.itemID:SetFocus()
        row.itemID:SetText("123456")
        entry.action = action
        local counts = watchConfigRefresh(ns)
        ns.Config:Refresh()
        equal(row.itemID.enabled, true)
        equal(row.itemID:HasFocus(), false)
        equal(row.itemID:GetText(), "910008")
        state:script(row.itemID, "OnEditFocusLost")
        equal(entry.itemID, 910008)
        equal(counts.rebuilds, 0)
        editConfigField(state, row, "itemID", 910010)
        equal(counts.rebuilds, 1)
        assertAction(state:button(entry.id), action, 910010)
        equal(entry.macrotext, f08Macro().macrotext, "changing type must not rewrite stored macro text")
    end
end)

test("f08_row_reuse_macro_to_item_or_toy_and_back_cancels_old_drafts", function()
    for _, target in ipairs({ { 1, "toy" }, { 2, "item" } }) do
        local state, ns = setup()
        ns:OpenConfig()
        local row, entries = ns.Config.rows[5], ns:GetEntries()
        local macro, other = row.entry, entries[target[1]]
        local macroText, originalItem = macro.macrotext, macro.itemID
        row.itemID:SetFocus()
        row.itemID:SetText("123456")
        entries[5], entries[target[1]] = entries[target[1]], entries[5]
        local counts = watchConfigRefresh(ns)
        ns.Config:Refresh()
        equal(row.entry, other)
        equal(row.itemID.enabled, true)
        equal(row.spellID.enabled, true)
        equal(row.itemID:HasFocus(), false)
        equal(row.itemID:GetText(), tostring(other.itemID))
        equal(macro.itemID, originalItem)
        equal(counts.rebuilds, 0)
        editConfigField(state, row, "itemID", 910011)
        assertAction(state:button(other.id), target[2], 910011)
        row.itemID:SetFocus()
        row.itemID:SetText("910012")
        entries[5], entries[target[1]] = entries[target[1]], entries[5]
        ns.Config:Refresh()
        equal(row.entry, macro)
        equal(row.itemID.enabled, false)
        equal(row.spellID.enabled, false)
        equal(row.itemID:GetText(), tostring(originalItem))
        equal(row.spellID:GetText(), "8675")
        state:script(row.itemID, "OnEditFocusLost")
        equal(other.itemID, 910011)
        equal(macro.itemID, originalItem)
        equal(macro.macrotext, macroText)
        equal(counts.rebuilds, 1)
        equal(state:secureFrameCount(), 8)
    end
end)

test("f08_deleted_macro_row_and_same_id_replacement_reenable_without_stale_commits", function()
    for _, removeFirst in ipairs({ false, true }) do
        local state, ns = setup()
        local macro = f08Macro()
        table.insert(ns:GetEntries(), macro)
        ns:RequestRebuild()
        ns:OpenConfig()
        local row = ns.Config.rows[9]
        row.itemID:SetFocus()
        row.itemID:SetText("123456")
        local counts = watchConfigRefresh(ns)
        if removeFirst then
            state:script(row.delete, "OnClick")
            equal(row.entry, nil)
            equal(row:IsShown(), false)
            equal(row.itemID.enabled, false)
            equal(row.itemID:GetText(), "")
            state:script(row.itemID, "OnEditFocusLost")
            equal(macro.itemID, 910008)
        end
        local replacement = f08Macro()
        replacement.action, replacement.itemID = "item", 910012
        ns:GetEntries()[9] = replacement
        ns:RequestRebuild()
        equal(ns.Config.rows[9], row)
        equal(row.entry, replacement)
        equal(row.itemID.enabled, true)
        equal(row.spellID.enabled, true)
        equal(row.itemID:GetText(), "910012")
        state:script(row.itemID, "OnEditFocusLost")
        equal(replacement.itemID, 910012)
        equal(macro.itemID, 910008)
        equal(counts.rebuilds, removeFirst and 2 or 1)
        editConfigField(state, row, "itemID", 910013)
        assertAction(state:button(replacement.id), "item", 910013)
        equal(state:secureFrameCount(), 9)
    end
end)

test("f08_custom_and_overridden_macro_definitions_survive_callbacks_refresh_and_reload_verbatim", function()
    for _, text in ipairs({ f08Macro().macrotext, "", "/use [@mouseover] 28\n/cast Fishing" }) do
        for _, builtin in ipairs({ false, true }) do
            local entry = f08Macro()
            entry.id = builtin and "pointed-spikesnail" or entry.id
            entry.builtin, entry.macrotext = builtin, text
            local state, ns = setup({ entries = { entry } })
            ns:OpenConfig()
            local row = configRow(ns, entry.id)
            editConfigField(state, row, "itemID", 123456)
            state:script(row.itemID, "OnEditFocusLost")
            state:fire("BAG_UPDATE_DELAYED")
            state:script(row.down, "OnClick")
            ns.Config:Hide()
            ns:OpenConfig()
            equal(entry.itemID, 910008)
            equal(entry.spellID, 810008)
            equal(entry.macrotext, text)
            equal(entry.action, "macro")
            local reloaded, loaded = setup(ns.db)
            loaded:OpenConfig()
            local saved = configRow(loaded, entry.id).entry
            equal(saved.itemID, 910008)
            equal(saved.spellID, 810008)
            equal(saved.macrotext, text)
            equal(saved.action, "macro")
            equal(configRow(loaded, entry.id).itemID.enabled, false)
            assertAction(reloaded:button(entry.id), "macro", text)
        end
    end
    -- Even a custom macro with no text stays read-only; F08 does not infer an action.
    local entry = f08Macro()
    entry.macrotext = nil
    local state, ns = setup({ entries = { entry } })
    ns:OpenConfig()
    editConfigField(state, configRow(ns, entry.id), "itemID", 123456)
    equal(entry.itemID, 910008)
    equal(entry.macrotext, nil)
    equal(entry.action, "macro")
end)

test("f08_macro_label_and_aura_edits_preserve_macro_action_and_f05_combat_snapshot", function()
    for _, combat in ipairs({ false, true }) do
        local state, ns = setup({ entries = { f08Macro() } })
        ns:OpenConfig()
        local row = configRow(ns, "f08-macro")
        local button = state:button(row.entry.id)
        local applied = button.entry
        local counts = watchConfigRefresh(ns)
        state.combat = combat
        editConfigField(state, row, "label", "  改名宏  ")
        editConfigField(state, row, "spellID", "000810009")
        editConfigField(state, row, "itemID", 123456)
        state:script(row.spellID, "OnEditFocusLost")
        equal(counts.rebuilds, 2, "only the label and aura edits may rebuild")
        equal(row.entry.label, "改名宏")
        equal(row.entry.spellID, 810009)
        equal(row.entry.itemID, 910008)
        equal(row.entry.macrotext, f08Macro().macrotext)
        state.auras = { aura(810008), aura(810009) }
        state:fire("UNIT_AURA", "player")
        if combat then
            equal(button.entry, applied)
            equal(button.effect.spellId, 810008)
            equal(ns:ScanAuras()[810009], nil)
            equal(ns.rebuildPending, true, "blocked item callbacks must retain pending valid edits")
        end
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(button.entry.label, "改名宏")
        equal(button.effect.spellId, 810009)
        equal(ns:ScanAuras()[810008], nil)
        assertAction(button, "macro", f08Macro().macrotext)
        equal(state:secureFrameCount(), 9)
    end
end)

test("f08_item_toy_transitions_keep_valid_drafts_and_commit_once", function()
    for _, id in ipairs({ "haranir-phial", "oversized-bobber" }) do
        for _, combat in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = configRow(ns, id)
            local before, applied = row.entry.itemID, state:button(id).entry
            row.itemID:SetFocus()
            row.itemID:SetText("000910014")
            local counts = watchConfigRefresh(ns)
            state.combat = combat
            state:script(row.action, "OnClick")
            equal(row.itemID.enabled, true)
            equal(row.itemID:GetText(), "000910014")
            equal(row.itemID:HasFocus(), true)
            equal(row.entry.itemID, before)
            state:script(row.itemID, "OnEnterPressed")
            state:script(row.itemID, "OnEditFocusLost")
            equal(row.entry.itemID, 910014)
            equal(counts.rebuilds, 2, "one action toggle and one item commit")
            if combat then equal(state:button(id).entry, applied) end
            state.combat = false
            state:fire("PLAYER_REGEN_ENABLED")
            assertAction(state:button(id), row.entry.action, 910014)
            equal(state:secureFrameCount(), 8)
        end
    end
end)

test("f08_enchant_tracking_permission_changes_cancel_stale_spell_drafts", function()
    local state, ns = setup({ entries = { f08Macro() } })
    ns:OpenConfig()
    local row = configRow(ns, "f08-macro")
    local entry = row.entry
    row.spellID:SetFocus()
    row.spellID:SetText("123456")
    entry.spellID, entry.enchantID, entry.inventorySlot = nil, 8675, 28
    local counts = watchConfigRefresh(ns)
    ns.Config:Refresh()
    equal(row.spellID:GetText(), "8675")
    equal(row.spellID:HasFocus(), false)
    equal(row.spellID.enabled, false)
    equal(row.itemID.enabled, false)
    editConfigField(state, row, "spellID", 123456)
    equal(row.spellID:GetText(), "8675")
    equal(entry.spellID, nil)
    equal(entry.enchantID, 8675)
    equal(counts.rebuilds, 0)
    row.spellID:SetText("999999")
    entry.enchantID, entry.inventorySlot, entry.spellID = nil, nil, 810009
    ns.Config:Refresh()
    equal(row.spellID.enabled, true)
    equal(row.spellID:GetText(), "810009")
    equal(row.itemID.enabled, false)
    state:script(row.spellID, "OnEditFocusLost")
    equal(counts.rebuilds, 0)
    editConfigField(state, row, "spellID", 810010)
    equal(entry.spellID, 810010)
    equal(entry.macrotext, f08Macro().macrotext)
    equal(counts.rebuilds, 1)
end)

test("f08_readonly_tooltip_survives_status_refresh_and_closes_on_rebind_or_hide", function()
    local state, ns = setup()
    ns:OpenConfig()
    local row = configRow(ns, "pointed-spikesnail")
    state:script(row.itemID, "OnEnter")
    local reason = state.env.GameTooltip:GetText()
    for _, event in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN" }) do
        state:fire(event, "player")
        equal(state.env.GameTooltip:IsShown(), true)
        equal(state.env.GameTooltip.owner, row.itemID)
        equal(state.env.GameTooltip:GetText(), reason)
    end
    row.entry.action = "item"
    ns.Config:Refresh()
    equal(state.env.GameTooltip:IsShown(), false, "permission changes must close the old reason")
    row.entry.action = "macro"
    ns.Config:Refresh()
    state:script(row.itemID, "OnEnter")
    ns.Config:CancelEdits()
    equal(state.env.GameTooltip:IsShown(), false, "explicit cancellation must close the reason")
    state:script(row.itemID, "OnEnter")
    row.itemID:SetText("123456")
    state:script(row.itemID, "OnEditFocusLost")
    equal(state.env.GameTooltip:IsShown(), false, "a blocked commit cancels its tooltip")
    equal(row.itemID:GetText(), "262651")
    state:script(row.itemID, "OnEnter")
    state:script(row.down, "OnClick")
    equal(state.env.GameTooltip:IsShown(), false)
    state:script(row.itemID, "OnEnter")
    equal(state.env.GameTooltip:IsShown(), false, "editable item fields have no read-only tooltip")
    local box = configRow(ns, "pointed-spikesnail").itemID
    state:script(box, "OnEnter")
    ns.Config:Hide()
    equal(state.env.GameTooltip:IsShown(), false)
end)

test("settings_add_button_fits_actual_canvas", function()
    local state, ns = setup()
    ns:OpenConfig()
    local addButton
    for _, frame in ipairs(state.frames) do
        if frame.kind == "Button" and frame:GetText() == "添加" then addButton = frame end
    end
    -- Resolve both anchor ends; the add form now grows its name field between
    -- the left inset and the fixed controls anchored from the right.
    local right = addButton:GetRight() - addButton.parent:GetLeft()
    local available = ns.Config:GetWidth() - 16 - 32
    equal(addButton.parent:GetWidth(), available)
    assert(right <= available, "add button right=" .. right .. ", parent width=" .. available)
end)

test("settings_row_actions_fit_actual_scroll_viewport", function()
    local _, ns = setup()
    ns:OpenConfig()
    local row = ns.Config.rows[1]
    local right = row.delete:GetRight() - ns.Config.scroll:GetLeft()
    -- The scroll area starts 16px from the panel left and ends 36px from its right.
    local available = ns.Config:GetWidth() - 16 - 36
    equal(ns.Config.scroll:GetWidth(), available)
    assert(right <= available, "delete button right=" .. right .. ", viewport width=" .. available)
    equal(row:GetWidth(), available)
end)

local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001,
        "geometry differs: expected " .. expected .. ", got " .. actual)
end

local function inside(widget, container)
    assert(widget:GetLeft() >= container:GetLeft() and widget:GetRight() <= container:GetRight(),
        widget.kind .. " exceeds horizontal bounds: " .. widget:GetLeft() .. ".." .. widget:GetRight()
            .. " outside " .. container:GetLeft() .. ".." .. container:GetRight())
    assert(widget:GetBottom() >= container:GetBottom() and widget:GetTop() <= container:GetTop(),
        widget.kind .. " exceeds vertical bounds")
end

local function addControls(state)
    local button
    for _, frame in ipairs(state.frames) do
        if frame.kind == "Button" and frame:GetText() == "添加" then button = frame end
    end
    local boxes, lure = {}, nil
    for _, frame in ipairs(state.frames) do
        if frame.parent == button.parent then
            if frame.kind == "EditBox" then boxes[#boxes + 1] = frame end
            if frame.kind == "CheckButton" then lure = frame end
        end
    end
    return button, boxes, lure
end

local function checkConfigGeometry(state, ns, width, height)
    local panel, scroll = ns.Config, ns.Config.scroll
    local addButton, boxes, lure = addControls(state)
    equal(panel:GetWidth(), width)
    equal(panel:GetHeight(), height)
    equal(scroll:GetWidth(), width - 52)
    equal(scroll:GetHeight(), height - 326)
    equal(panel.header:GetWidth(), scroll:GetWidth())
    equal(panel.content:GetWidth(), scroll:GetWidth())
    equal(scroll:GetLeft(), panel:GetLeft() + 16)
    equal(scroll:GetRight(), panel:GetRight() - 36)
    equal(addButton.parent:GetWidth(), width - 48)
    assert(scroll:GetBottom() > addButton.parent:GetTop(), "list overlaps add form")
    inside(scroll, panel)
    inside(scroll.ScrollBar, panel)
    inside(scroll.ScrollBar.ScrollUpButton, panel)
    inside(scroll.ScrollBar.ScrollDownButton, panel)
    inside(addButton.parent, panel)
    inside(addButton, addButton.parent)
    assert(boxes[1]:GetWidth() >= 180, "add name is too narrow")
    for index, box in ipairs(boxes) do
        inside(box, addButton.parent)
        if index > 1 then
            assert(box:GetLeft() - boxes[index - 1]:GetRight() >= 12, "add fields overlap")
            equal(box:GetWidth(), 88)
        end
    end
    inside(lure, addButton.parent)
    inside(lure.text, addButton.parent)
    assert(lure:GetLeft() - boxes[3]:GetRight() >= 10)
    assert(addButton:GetLeft() - lure.text:GetRight() >= 12, "add lure label overlaps button")

    -- Check the top-level controls, labels, number groups and footer labels.
    -- Row content is clipped by the scroll frame and checked in row coordinates.
    local topControls = {}
    for _, collection in ipairs({ state.frames, state.regions }) do
        for _, widget in ipairs(collection) do
            local parent = widget.parent
            if parent == panel then
                topControls[#topControls + 1] = {
                    left = widget:GetLeft(),
                    right = widget.kind == "CheckButton" and widget.text:GetRight() or widget:GetRight(),
                    bottom = widget:GetBottom(), top = widget:GetTop(),
                }
            end
            if parent == panel and widget ~= scroll then inside(widget, panel) end
            if parent and parent.parent == panel and parent ~= scroll and parent ~= panel.header then
                inside(widget, panel)
            end
            if parent == addButton.parent then inside(widget, parent) end
            while parent and parent ~= panel do parent = parent.parent end
            if parent == panel then assert(widget.scale == nil or widget.scale == 1, "control was scaled") end
        end
    end
    assert(panel.scale == nil or panel.scale == 1, "canvas was scaled")
    for index, rect in ipairs(topControls) do
        for otherIndex = index + 1, #topControls do
            local other = topControls[otherIndex]
            assert(rect.right <= other.left or other.right <= rect.left
                or rect.top <= other.bottom or other.top <= rect.bottom, "top-level controls overlap")
        end
    end
    for _, label in ipairs({ panel.sizeLabel, panel.spacingLabel, panel.scaleLabel }) do
        assert(label:GetWidth() >= 90, "top number label was squeezed")
        inside(label, label.parent)
        local buttons = {}
        for _, frame in ipairs(state.frames) do
            if frame.parent == label.parent and frame.kind == "Button" then
                inside(frame, label.parent)
                buttons[#buttons + 1] = frame
            end
        end
        equal(#buttons, 2)
        assert(buttons[1]:GetLeft() - label:GetRight() >= 8)
        assert(buttons[2]:GetLeft() - buttons[1]:GetRight() >= 4)
    end

    local fields = { "enabled", "label", "category", "itemID", "spellID", "action", "lure", "up", "down", "delete" }
    local count = #ns:GetEntries()
    equal(panel.content:GetHeight(), math.max(1, count * 30))
    for index, row in ipairs(panel.rows) do
        if index <= count then
            equal(row.entry, ns:GetEntries()[index])
            equal(row:IsShown(), true)
            equal(row:GetWidth(), scroll:GetWidth())
            equal(row:GetHeight(), 30)
            equal(row:GetTop(), panel.content:GetTop() - (index - 1) * 30)
            assert(row.label:GetWidth() >= 100, "row name is too narrow")
            local previous
            for _, field in ipairs(fields) do
                local control, heading = row[field], panel.header[field]
                inside(control, row)
                inside(heading, panel.header)
                near(control:GetLeft(), heading:GetLeft())
                equal(control:GetWidth(), heading:GetWidth())
                if previous then assert(control:GetLeft() > previous:GetRight(), "columns overlap") end
                previous = control
            end
            equal(row.itemID:GetWidth(), 76)
            equal(row.spellID:GetWidth(), 76)
            equal(row.category:GetWidth(), 56)
            assert(row.delete:GetRight() <= scroll:GetRight())
        else
            equal(row:IsShown(), false)
            equal(row.entry, nil)
        end
    end
end

test("f06_mock_solves_opposing_anchors_reparenting_and_resize_notifications", function()
    local state = setup()
    local canvas = state.env.CreateFrame("Frame")
    canvas:SetSize(665, 601)
    local panel = state.env.CreateFrame("Frame")
    panel:SetSize(760, 560)
    local calls = 0
    panel:SetScript("OnSizeChanged", function(_, width, height)
        calls = calls + 1
        equal(width, canvas:GetWidth())
        equal(height, canvas:GetHeight())
    end)
    panel:SetParent(canvas)
    panel:SetAllPoints(canvas)
    equal(calls, 1)
    canvas:SetSize(600, 520)
    equal(calls, 2)
    equal(panel:GetWidth(), 600)
    equal(panel:GetHeight(), 520)
    local child = state.env.CreateFrame("Frame", nil, panel)
    child:SetSize(999, 999)
    child:SetPoint("TOPLEFT", 16, -208)
    child:SetPoint("BOTTOMRIGHT", -36, 118)
    equal(child:GetWidth(), 548)
    equal(child:GetHeight(), 194)
    panel:SetScript("OnSizeChanged", nil)
    panel:ClearAllPoints()
    panel:SetParent(nil)
    equal(panel:GetWidth(), 760, "cleared SetAllPoints must not retain old canvas size")
end)

test("f06_first_open_and_resize_fit_canvas_with_empty_default_and_long_lists", function()
    for _, count in ipairs({ 0, 1, 8, 40 }) do
        local state, ns = setup()
        local entries = ns:GetEntries()
        while #entries > count do table.remove(entries) end
        while #entries < count do
            entries[#entries + 1] = {
                id = "layout-" .. #entries, label = "足够长的钓鱼测试名称", category = "custom",
                itemID = 1234567890, spellID = 1234567890, action = "item", enabled = true,
            }
        end
        -- First show at each size, including the default, must use the host's
        -- dimensions rather than the creation size or a previous opening.
        for _, size in ipairs({ { 665, 601 }, { 600, 520 }, { 900, 720 } }) do
            ns.Config:Hide()
            local canvas = state.env.CreateFrame("Frame")
            canvas:SetSize(unpack(size))
            state.settingsCanvas = canvas
            ns:OpenConfig()
            checkConfigGeometry(state, ns, unpack(size))
            for _, resized in ipairs({ { 600, 520 }, { 900, 720 }, { 665, 601 } }) do
                canvas:SetSize(unpack(resized))
                checkConfigGeometry(state, ns, unpack(resized))
            end
        end
    end
end)

test("f06_resize_preserves_row_and_add_drafts_focus_bindings_and_commit_behavior", function()
    for _, case in ipairs(editCases) do
        for _, focused in ipairs({ true, false }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = ns.Config.rows[2]
            local box, entry = row[case.field], row.entry
            local original = entry[case.field]
            if focused then box:SetFocus() end
            box:SetText(case.draft)
            local addButton, boxes, lure = addControls(state)
            for index, addBox in ipairs(boxes) do addBox:SetText("00" .. index) end
            lure:SetChecked(true)
            local writes, setText = 0, box.SetText
            for _, control in ipairs({ box, boxes[1], boxes[2], boxes[3] }) do
                control.SetText = function(self, value)
                    writes = writes + 1
                    setText(self, value)
                end
            end
            local counts, frames = watchConfigRefresh(ns), #state.frames
            for _, size in ipairs({ { 600, 520 }, { 900, 720 }, { 665, 601 } }) do
                state.combat = true -- Settings is unprotected; resizing needs no rebuild.
                state.settingsCanvas:SetSize(unpack(size))
                checkConfigGeometry(state, ns, unpack(size))
                equal(ns.Config.rows[2], row)
                equal(box.entry, entry)
                equal(box:GetText(), case.draft)
                equal(box:HasFocus(), focused)
                equal(entry[case.field], original)
                equal(lure:GetChecked(), true)
                for index, addBox in ipairs(boxes) do equal(addBox:GetText(), "00" .. index) end
            end
            state.combat = false
            equal(writes, 0, "resize must not even rewrite identical text")
            equal(#state.frames, frames, "resize recreated controls")
            equal(counts.refreshes, 0)
            equal(counts.rebuilds, 0)
            if focused then box:ClearFocus() else state:script(box, "OnEditFocusLost") end
            equal(entry[case.field], case.value)
            equal(counts.rebuilds, 1)
            -- The add input itself also keeps focus across a resize.
            boxes[1]:SetFocus()
            local before = writes
            state.settingsCanvas:SetSize(600, 520)
            equal(boxes[1]:HasFocus(), true)
            equal(boxes[1]:GetText(), "001")
            equal(writes, before)
            equal(addButton:IsVisible(), true)
        end
    end
end)

test("f06_scroll_reaches_last_row_and_clamps_after_resize_and_delete", function()
    local state, ns = setup()
    ns:OpenConfig()
    local button, boxes = addControls(state)
    for index = 1, 20 do
        boxes[1]:SetText("滚动 " .. index)
        boxes[2]:SetText("123")
        boxes[3]:SetText("456")
        state:script(button, "OnClick")
    end
    local scroll = ns.Config.scroll
    for _, size in ipairs({ { 600, 520 }, { 900, 720 }, { 665, 601 } }) do
        state.settingsCanvas:SetSize(unpack(size))
        checkConfigGeometry(state, ns, unpack(size))
        for _ = 1, 30 do state:script(scroll, "OnMouseWheel", -1) end
        equal(scroll:GetVerticalScroll(), math.floor(scroll:GetVerticalScrollRange()))
        local lastRow = ns.Config.rows[#ns:GetEntries()]
        inside(lastRow, scroll)
        near(lastRow:GetBottom(), scroll:GetBottom())
        -- Both sort directions and field edits still act on the visible entry.
        local entry = lastRow.entry
        state:script(lastRow.up, "OnClick")
        equal(ns:GetEntries()[#ns:GetEntries() - 1], entry)
        state:script(ns.Config.rows[#ns:GetEntries() - 1].down, "OnClick")
        equal(lastRow.entry, entry)
        lastRow.itemID:SetFocus()
        lastRow.itemID:SetText("789")
        state:script(lastRow.itemID, "OnEnterPressed")
        equal(entry.itemID, 789)
        state:script(lastRow.action, "OnClick")
        equal(entry.action, "toy")
        lastRow.lure:SetChecked(true)
        state:script(lastRow.lure, "OnClick")
        equal(entry.category, "lure")
        state:script(lastRow.delete, "OnClick")
        equal(ns.Config.rows[#ns:GetEntries() + 1]:IsShown(), false)
        equal(scroll:GetVerticalScroll(), math.floor(scroll:GetVerticalScrollRange()))
    end
    while #ns:GetEntries() > 8 do state:script(ns.Config.rows[#ns:GetEntries()].delete, "OnClick") end
    state.settingsCanvas:SetSize(900, 720)
    equal(scroll:GetVerticalScrollRange(), 0)
    equal(scroll:GetVerticalScroll(), 0)
    checkConfigGeometry(state, ns, 900, 720)
end)

test("f06_top_controls_work_at_small_width_and_keep_header_separate", function()
    local state, ns = setup()
    ns:OpenConfig()
    state.settingsCanvas:SetSize(600, 520)
    for _, label in ipairs({ ns.Config.sizeLabel, ns.Config.spacingLabel, ns.Config.scaleLabel }) do
        local field = label == ns.Config.sizeLabel and "iconSize"
            or label == ns.Config.spacingLabel and "spacing" or "scale"
        local old = ns.db.frame[field]
        local minus, plus
        for _, frame in ipairs(state.frames) do
            if frame.parent == label.parent and frame.kind == "Button" then
                if frame:GetText() == "+" then plus = frame else minus = frame end
            end
        end
        state:script(plus, "OnClick")
        assert(ns.db.frame[field] > old)
        state:script(minus, "OnClick")
        near(ns.db.frame[field], old)
    end
    ns.Config.showBar:SetChecked(false)
    state:script(ns.Config.showBar, "OnClick")
    equal(ns.db.frame.visible, false)
    ns.Config.lock:SetChecked(true)
    state:script(ns.Config.lock, "OnClick")
    equal(ns.db.frame.locked, true)
    ns.Config.unavailable:SetChecked(false)
    state:script(ns.Config.unavailable, "OnClick")
    equal(ns.db.frame.showUnavailable, false)
    clickButtonText(state, "重置位置")
    clickButtonText(state, "恢复内置列表")
    equal(#ns:GetEntries(), 8)
    checkConfigGeometry(state, ns, 600, 520)
end)

test("drag_release_after_combat_starts_avoids_protected_call", function()
    local state, ns = setup()
    state:script(ns.Bar.dragHandle, "OnDragStart")
    state.combat = true
    state:script(ns.Bar.dragHandle, "OnDragStop")
end)

-- F09: model the native stop re-anchoring the frame, then observe stop/save
-- order. This does not emulate cursor movement or native combat/taint behavior.
do
    local function dragSetup()
        local state, ns = setup({ frame = {
            point = "BOTTOMLEFT", relativePoint = "BOTTOMRIGHT", x = 12, y = -24,
        } })
        local bar = ns.Bar
        local trace = { starts = 0, stops = 0, reads = 0, events = {} }
        local start, stop, getPoint = bar.StartMoving, bar.StopMovingOrSizing, bar.GetPoint
        bar.StartMoving = function(self)
            start(self)
            trace.starts = trace.starts + 1
        end
        bar.StopMovingOrSizing = function(self)
            stop(self) -- Retain the mock's protected-call guard.
            trace.stops = trace.stops + 1
            trace.events[#trace.events + 1] = "stop"
            if trace.finalPoint then
                self:ClearAllPoints()
                self:SetPoint(unpack(trace.finalPoint))
            end
        end
        bar.GetPoint = function(self, ...)
            assert(not state.combat, "drag position must not be sampled in combat")
            equal(self.moving, false, "save must sample the anchor after the native stop")
            trace.reads = trace.reads + 1
            trace.events[#trace.events + 1] = "save"
            return getPoint(self, ...)
        end
        trace.finalPoint = { "TOPRIGHT", state.env.UIParent, "TOPLEFT", -43.6, 71.7 }
        return state, ns, bar, trace
    end

    local function savedPosition(ns, point, relativePoint, x, y)
        equal(ns.db.frame.point, point)
        equal(ns.db.frame.relativePoint, relativePoint)
        equal(ns.db.frame.x, x)
        equal(ns.db.frame.y, y)
    end

    local function finished(ns, bar, trace, count)
        equal(bar.moving, false)
        equal(ns.barMoving, nil)
        equal(ns.barStopPending, nil)
        equal(trace.stops, count)
        equal(trace.reads, count)
    end

    test("f09_drag_normal_release_saves_final_anchor_once_and_allows_next_drag", function()
        local state, ns, bar, trace = dragSetup()
        for index, position in ipairs({
            { "TOPRIGHT", state.env.UIParent, "TOPLEFT", -43.6, 71.7 },
            { "BOTTOM", state.env.UIParent, "CENTER", 18.4, -29.2 },
        }) do
            trace.finalPoint = position
            state:script(bar.dragHandle, "OnDragStart")
            state:script(bar.dragHandle, "OnDragStart")
            equal(trace.starts, index, "duplicate starts must retain one movement session")
            equal(bar.moving, true)
            equal(ns.barMoving, true)
            equal(ns.barStopPending, nil)
            equal(trace.reads, index - 1)
            state:script(bar.dragHandle, "OnDragStop")
            finished(ns, bar, trace, index)
            savedPosition(ns, position[1], position[3],
                math.floor(position[4] + 0.5), math.floor(position[5] + 0.5))
            state:script(bar.dragHandle, "OnDragStop")
            state:fire("PLAYER_REGEN_ENABLED")
            finished(ns, bar, trace, index)
        end
        equal(table.concat(trace.events, ","), "stop,save,stop,save")
    end)

    test("f09_drag_combat_release_defers_stop_and_save_until_safe_regen", function()
        local state, ns, bar, trace = dragSetup()
        state:script(bar.dragHandle, "OnDragStart")
        state.combat = true
        for _ = 1, 2 do
            state:script(bar.dragHandle, "OnDragStop")
            state:script(bar.dragHandle, "OnDragStart")
            ns:Refresh()
            -- Even a premature event must not bypass InCombatLockdown.
            state:fire("PLAYER_REGEN_ENABLED")
            equal(bar.moving, true)
            equal(ns.barMoving, true)
            equal(ns.barStopPending, true)
            equal(trace.starts, 1)
            equal(trace.stops, 0)
            equal(trace.reads, 0)
            savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
        end
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        finished(ns, bar, trace, 1)
        savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
        state:script(bar.dragHandle, "OnDragStop")
        state:fire("PLAYER_REGEN_ENABLED")
        finished(ns, bar, trace, 1)
        state:script(bar.dragHandle, "OnDragStart")
        state:script(bar.dragHandle, "OnDragStop")
        finished(ns, bar, trace, 2)
    end)

    test("f09_drag_release_without_start_does_not_stop_or_save_a_movable_bar", function()
        for _, locked in ipairs({ false, true }) do
            for _, combat in ipairs({ false, true }) do
                local state, ns, bar, trace = dragSetup()
                ns.db.frame.locked, state.combat = locked, combat
                equal(bar:IsMovable(), true)
                state:script(bar.dragHandle, "OnDragStop")
                state:script(bar.dragHandle, "OnDragStop")
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                equal(trace.starts, 0)
                equal(trace.stops, 0)
                equal(trace.reads, 0)
                equal(ns.barMoving, nil)
                equal(ns.barStopPending, nil)
                savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
            end
        end
    end)

    test("f09_drag_locked_or_combat_start_never_creates_a_movement_session", function()
        for _, mode in ipairs({ { true, false }, { false, true }, { true, true } }) do
            local state, ns, bar, trace = dragSetup()
            ns.db.frame.locked, state.combat = mode[1], mode[2]
            equal(bar:IsMovable(), true, "locking is a DB setting, not SetMovable")
            state:script(bar.dragHandle, "OnDragStart")
            state:script(bar.dragHandle, "OnDragStop")
            state.combat = false
            state:fire("PLAYER_REGEN_ENABLED")
            equal(trace.starts, 0)
            equal(trace.stops, 0)
            equal(trace.reads, 0)
            equal(ns.barMoving, nil)
            equal(ns.barStopPending, nil)
            savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
            state:command("unlock")
            state:script(bar.dragHandle, "OnDragStart")
            state:script(bar.dragHandle, "OnDragStop")
            finished(ns, bar, trace, 1)
        end
    end)

    test("f09_drag_failed_native_start_does_not_authorize_a_later_stop", function()
        local state, ns, bar, trace = dragSetup()
        bar.StartMoving = function() error("native start failed") end
        equal(pcall(function() state:script(bar.dragHandle, "OnDragStart") end), false)
        state:script(bar.dragHandle, "OnDragStop")
        equal(ns.barMoving, nil)
        equal(ns.barStopPending, nil)
        equal(trace.stops, 0)
        equal(trace.reads, 0)
        savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
    end)

    test("f09_drag_held_through_combat_keeps_moving_until_release", function()
        local state, ns, bar, trace = dragSetup()
        state:script(bar.dragHandle, "OnDragStart")
        state.combat = true
        ns:Refresh()
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(bar.moving, true)
        equal(ns.barMoving, true)
        equal(ns.barStopPending, nil)
        equal(trace.stops, 0)
        equal(trace.reads, 0)
        state:script(bar.dragHandle, "OnDragStop")
        finished(ns, bar, trace, 1)
    end)

    test("f09_drag_safe_duplicate_release_finishes_pending_stop_before_regen", function()
        local state, ns, bar, trace = dragSetup()
        state:script(bar.dragHandle, "OnDragStart")
        state.combat = true
        state:script(bar.dragHandle, "OnDragStop")
        state.combat = false
        state:script(bar.dragHandle, "OnDragStop")
        finished(ns, bar, trace, 1)
        savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
        state.combat = true
        state:script(bar.dragHandle, "OnDragStop")
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        finished(ns, bar, trace, 1)
    end)

    test("f09_drag_recovery_saves_before_queued_reset_visibility_and_rebuild", function()
        for _, reset in ipairs({ false, true }) do
            for _, visible in ipairs({ false, true }) do
                local state, ns, bar, trace = dragSetup()
                local applied, button = bar.appliedEntries, bar.buttons[2]
                local frames = state:secureFrameCount()
                state:script(bar.dragHandle, "OnDragStart")
                state.combat = true
                state:script(bar.dragHandle, "OnDragStop")
                if reset then
                    ns:ResetFramePosition()
                    ns:ResetFramePosition()
                end
                ns:SetBarVisible(false)
                if visible then ns:SetBarVisible(true) end
                ns.db.frame.iconSize = 60
                ns.db.frame.scale = 1.2
                ns.db.entries[2].itemID = 900009
                ns:RequestRebuild()
                equal(bar.appliedEntries, applied)
                equal(button.attributes.item, "item:241316")
                equal(trace.stops, 0)
                equal(trace.reads, 0)
                savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
                local function expectedPosition()
                    if reset then
                        local defaults = ns.DEFAULT_FRAME
                        savedPosition(ns, defaults.point, defaults.relativePoint, defaults.x, defaults.y)
                    else
                        savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
                    end
                end
                for _, name in ipairs({ "ResetFramePosition", "SetBarVisible", "RequestRebuild" }) do
                    local methodName, method = name, ns[name]
                    ns[methodName] = function(self, ...)
                        finished(ns, bar, trace, 1)
                        if methodName == "ResetFramePosition" then
                            savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
                        else
                            expectedPosition()
                        end
                        trace.events[#trace.events + 1] = methodName
                        return method(self, ...)
                    end
                end
                for _, name in ipairs({ "SetShown", "SetScale", "SetSize" }) do
                    local method = bar[name]
                    bar[name] = function(self, ...)
                        finished(ns, bar, trace, 1)
                        expectedPosition()
                        return method(self, ...)
                    end
                end
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
                equal(table.concat(trace.events, ","), "stop,save,"
                    .. (reset and "ResetFramePosition," or "") .. "SetBarVisible,RequestRebuild")
                expectedPosition()
                equal(ns.positionResetPending, nil)
                equal(ns.visibilityPending, nil)
                equal(ns.rebuildPending, nil)
                equal(bar:IsShown(), visible)
                equal(bar.buttons[2], button)
                equal(state:secureFrameCount(), frames)
                equal(button.attributes.item, "item:900009")
                equal(button.entry.itemID, 900009)
                equal(applied[2].itemID, 241316, "recovery must preserve the old detached snapshot")
                equal(button.width, 60)
                state:script(bar.dragHandle, "OnDragStop")
                state:fire("PLAYER_REGEN_ENABLED")
                finished(ns, bar, trace, 1)
                expectedPosition()
                if reset then
                    equal(bar.point[1], ns.DEFAULT_FRAME.point)
                    equal(bar.point[3], ns.DEFAULT_FRAME.relativePoint)
                    equal(bar.point[4], ns.DEFAULT_FRAME.x)
                    equal(bar.point[5], ns.DEFAULT_FRAME.y)
                end
            end
        end
    end)

    test("f09_drag_reset_while_held_stops_before_reset_and_ignores_late_release", function()
        for _, combat in ipairs({ false, true }) do
            local state, ns, bar, trace = dragSetup()
            state:script(bar.dragHandle, "OnDragStart")
            state.combat = combat
            ns:ResetFramePosition()
            if combat then
                equal(trace.stops, 0)
                equal(trace.reads, 0)
                equal(ns.positionResetPending, true)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
            end
            finished(ns, bar, trace, 1)
            local defaults = ns.DEFAULT_FRAME
            savedPosition(ns, defaults.point, defaults.relativePoint, defaults.x, defaults.y)
            equal(bar.point[4], defaults.x)
            equal(bar.point[5], defaults.y)
            state.combat = true
            state:script(bar.dragHandle, "OnDragStop")
            state.combat = false
            state:script(bar.dragHandle, "OnDragStop")
            state:fire("PLAYER_REGEN_ENABLED")
            finished(ns, bar, trace, 1)
            savedPosition(ns, defaults.point, defaults.relativePoint, defaults.x, defaults.y)
        end
    end)

    test("f09_drag_lock_command_and_checkbox_stop_or_defer_once", function()
        for _, control in ipairs({ "command", "checkbox" }) do
            for _, combat in ipairs({ false, true }) do
                local state, ns, bar, trace = dragSetup()
                ns:OpenConfig()
                state:script(bar.dragHandle, "OnDragStart")
                state.combat = combat
                if control == "command" then
                    state:command("lock")
                else
                    ns.Config.lock:SetChecked(true)
                    state:script(ns.Config.lock, "OnClick")
                end
                equal(ns.db.frame.locked, true)
                equal(bar:IsMovable(), true)
                if combat then
                    equal(trace.stops, 0)
                    equal(trace.reads, 0)
                    equal(ns.barStopPending, true)
                    savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
                    state.combat = false
                    state:fire("PLAYER_REGEN_ENABLED")
                end
                finished(ns, bar, trace, 1)
                savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
                state:command("lock")
                state:script(bar.dragHandle, "OnDragStart")
                state:script(bar.dragHandle, "OnDragStop")
                equal(trace.starts, 1)
                finished(ns, bar, trace, 1)
                state:command("unlock")
                state:script(bar.dragHandle, "OnDragStart")
                state:script(bar.dragHandle, "OnDragStop")
                finished(ns, bar, trace, 2)
            end
        end
    end)

    test("f09_drag_hide_request_finishes_without_release_even_if_shown_again", function()
        for _, combat in ipairs({ false, true }) do
            for _, showAgain in ipairs({ false, true }) do
                local state, ns, bar, trace = dragSetup()
                state:script(bar.dragHandle, "OnDragStart")
                state.combat = combat
                ns:SetBarVisible(false)
                if showAgain then ns:SetBarVisible(true) end
                if combat then
                    equal(bar:IsShown(), true)
                    equal(trace.stops, 0)
                    equal(trace.reads, 0)
                    equal(ns.barStopPending, true)
                    savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
                    state.combat = false
                    state:fire("PLAYER_REGEN_ENABLED")
                end
                finished(ns, bar, trace, 1)
                equal(bar:IsShown(), showAgain)
                equal(ns.visibilityPending, nil)
                savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
                state:script(bar.dragHandle, "OnDragStop")
                finished(ns, bar, trace, 1)
            end
        end
    end)

    test("f09_drag_hide_callback_handles_bar_ancestor_and_native_combat_hide", function()
        for _, mode in ipairs({ "bar", "ancestor", "combat" }) do
            local state, ns, bar, trace = dragSetup()
            state:script(bar.dragHandle, "OnDragStart")
            if mode == "combat" then
                state.combat = true
                -- Deliver a native lifecycle callback without calling protected Hide.
                state:script(bar, "OnHide")
                equal(trace.stops, 0)
                equal(trace.reads, 0)
                equal(ns.barStopPending, true)
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
            elseif mode == "bar" then
                bar:Hide()
            else
                state.env.UIParent:Hide()
            end
            finished(ns, bar, trace, 1)
            savedPosition(ns, "TOPRIGHT", "TOPLEFT", -44, 72)
            state:script(bar, "OnHide")
            state:script(bar.dragHandle, "OnDragStop")
            finished(ns, bar, trace, 1)
        end
    end)

    test("f09_drag_nil_bar_clears_pending_state_without_stopping_or_saving", function()
        local beforeLogin = Mock.new(addonPath)
        beforeLogin:fire("PLAYER_REGEN_ENABLED")
        beforeLogin.ns:StopBarMoving()
        for _, cleanup in ipairs({ "release", "regen" }) do
            local state, ns, bar, trace = dragSetup()
            state:script(bar.dragHandle, "OnDragStart")
            state.combat = true
            state:script(bar.dragHandle, "OnDragStop")
            equal(ns.barStopPending, true)
            ns.Bar = nil
            if cleanup == "release" then
                state:script(bar.dragHandle, "OnDragStop")
            else
                state.combat = false
                state:fire("PLAYER_REGEN_ENABLED")
            end
            equal(ns.barMoving, nil)
            equal(ns.barStopPending, nil)
            state:script(bar.dragHandle, "OnDragStart")
            state.combat = false
            state:script(bar.dragHandle, "OnDragStart")
            state:fire("PLAYER_REGEN_ENABLED")
            equal(trace.starts, 1)
            equal(trace.stops, 0)
            equal(trace.reads, 0)
            savedPosition(ns, "BOTTOMLEFT", "BOTTOMRIGHT", 12, -24)
        end
    end)
end

test("unchanged_focus_loss_does_not_allocate_more_frames", function()
    local state, ns = setup()
    ns:OpenConfig()
    local before = state:secureFrameCount()
    local box = ns.Config.rows[2].label
    box:SetFocus()
    box:ClearFocus()
    equal(state:secureFrameCount(), before, "unchanged edit caused a rebuild")
end)

test("malformed_saved_entry_does_not_abort_initialization", function()
    local _, ns = setup({ entries = {
        { label = "缺少 id", spellID = 456, itemID = 123, enabled = true, action = "item" },
    } })
    assert(ns.Bar, "malformed entry prevented addon initialization")
end)

test("malformed_saved_frame_numbers_are_sanitized", function()
    local _, ns = setup({ frame = { iconSize = "bad", scale = -1, spacing = false } })
    assert(type(ns.db.frame.iconSize) == "number", "invalid icon size survived initialization")
    assert(ns.db.frame.scale > 0, "invalid scale survived initialization")
end)

-- F10: damaged saves are recovered field by field. These fixtures exercise
-- login, actual action/tooltip consumers, reloads and editor writes.
local function f10Entry(id)
    return {
        id = id, label = "保留我的名称", category = "custom",
        itemID = 123, spellID = 456, action = "item", enabled = true, builtin = false,
    }
end

local function sameScalars(actual, expected)
    for key, value in pairs(expected) do equal(actual[key], value, "changed " .. key) end
    for key, value in pairs(actual) do equal(value, expected[key], "added " .. key) end
end

test("f10_sparse_mixed_entries_keep_order_custom_data_disabled_builtins_and_reload_identity", function()
    local first, orphan, duplicate = f10Entry("custom-f10"), f10Entry(), f10Entry("custom-f10")
    duplicate.builtin = true
    first.action, first.macrotext = "macro", "  /use [mod:shift] item:123\n/run print('unchanged')\n"
    local reserved, stock, tail = f10Entry("recovered-1"), f10Entry("oversized-bobber"), f10Entry("tail")
    stock.enabled, stock.builtin, stock.hideWhenMissing = false, true, true
    stock.category = "个人分类"
    local saved = {
        version = 1, extra = "unrelated root setting",
        frame = { visible = false, locked = true, showUnavailable = false,
            point = "TOPRIGHT", relativePoint = "BOTTOMLEFT", x = "12.5", y = "-83",
            scale = "1.25", iconSize = "52", spacing = "7" },
        entries = { [1] = first, [2] = false, [4] = "broken", [7] = orphan, [9] = duplicate,
            [20] = reserved, [30] = stock, [1000000] = tail,
            [-1] = f10Entry("negative"), [0] = f10Entry("zero-index"),
            [1.5] = f10Entry("fractional"), ["35"] = f10Entry("string-index") },
    }
    local expectedOrder = { first, orphan, duplicate, reserved, stock, tail }
    local snapshot, frameSnapshot
    for reload = 1, 3 do
        local state, ns = setup(saved)
        equal(ns.db, saved, "recovery replaced the whole database")
        equal(saved.extra, "unrelated root setting")
        equal(#ns:GetEntries(), 13)
        equal(ns.db.version, ns.DB_VERSION)
        for index, original in ipairs(expectedOrder) do equal(ns:GetEntries()[index], original) end
        local ids = {}
        for index, entry in ipairs(ns:GetEntries()) do
            assert(type(entry.id) == "string" and entry.id:find("%S"))
            assert(not ids[entry.id], "duplicate identity after recovery")
            ids[entry.id] = true
            if snapshot then sameScalars(entry, snapshot[index]) end
        end
        equal(first.id, "custom-f10")
        equal(reserved.id, "recovered-1", "generated ID stole a later valid identity")
        assert(orphan.id ~= duplicate.id and duplicate.id ~= first.id)
        equal(duplicate.builtin, false)
        equal(stock.label, "保留我的名称")
        equal(stock.category, "个人分类")
        equal(stock.hideWhenMissing, true)
        equal(state:button(stock.id), nil)
        equal(state:button(first.id).attributes.macrotext, first.macrotext)
        equal(ns.Bar:IsShown(), false)
        equal(saved.frame.locked, true)
        equal(saved.frame.showUnavailable, false)
        equal(saved.frame.point, "TOPRIGHT")
        equal(saved.frame.relativePoint, "BOTTOMLEFT")
        equal(saved.frame.x, 12.5)
        equal(saved.frame.y, -83)
        equal(saved.frame.scale, 1.25)
        equal(saved.frame.iconSize, 52)
        equal(saved.frame.spacing, 7)
        ns:OpenConfig()
        equal(ns.Config.rows[1].label:GetText(), first.label)
        snapshot = ns:CopyEntries()
        if frameSnapshot then sameScalars(saved.frame, frameSnapshot) end
        frameSnapshot = {}
        for key, value in pairs(saved.frame) do frameSnapshot[key] = value end
    end
end)

test("f10_bad_identity_types_and_repeated_table_references_get_independent_stable_ids", function()
    local shared = f10Entry("shared")
    local entries = { shared, shared }
    for _, id in ipairs({ "", "  \t", 17, false, {}, function() end }) do
        entries[#entries + 1] = f10Entry(id)
    end
    local saved = { entries = entries }
    local _, ns = setup(saved)
    equal(ns:GetEntries()[1], shared)
    equal(shared.id, "shared")
    assert(ns:GetEntries()[2] ~= shared)
    local snapshot, ids = ns:CopyEntries(), {}
    for _, entry in ipairs(ns:GetEntries()) do
        assert(type(entry.id) == "string" and not ids[entry.id])
        ids[entry.id] = true
    end
    local _, reloaded = setup(saved)
    for index, entry in ipairs(reloaded:GetEntries()) do sameScalars(entry, snapshot[index]) end
end)

test("f10_cyclic_containers_and_nested_fields_never_reach_applied_snapshots", function()
    local custom, saved, frame, source = f10Entry("cycle"), { extra = "keep" }, {}, {}
    saved.frame, saved.entries = frame, source
    frame.spacing, frame.unknown = frame, saved
    custom.label, custom.itemID, custom.unknown = custom, saved, source
    source[1], source[3], source[5], source[7] = saved, frame, source, custom
    custom[custom] = custom
    local state, ns = setup(saved)
    equal(ns.db, saved)
    equal(saved.extra, "keep")
    equal(saved.frame.spacing, 4)
    equal(custom.label, nil)
    equal(custom.itemID, nil)
    equal(custom.spellID, 456)
    equal(custom.unknown, nil)
    equal(custom[custom], nil)
    equal(saved.frame.unknown, nil)
    local function assertFlat(entries)
        for _, entry in ipairs(entries) do
            for key, value in pairs(entry) do
                equal(type(key), "string")
                assert(type(value) ~= "table" and type(value) ~= "function")
            end
        end
    end
    assertFlat(ns:GetEntries())
    assertFlat(ns:GetAppliedEntries())
    -- Even corruption introduced after load cannot enter the snapshot copier.
    custom.unknown, custom.macrotext = custom, custom
    local copied = ns:CopyEntries()
    assertFlat(copied)
    equal(copied[4].macrotext, nil)
    equal(custom.unknown, custom, "copying must not mutate desired entries")
    ns:RequestRebuild()
    state:command("status")
    local _, reloaded = setup(saved)
    assertFlat(reloaded:GetEntries())
    assertFlat(reloaded:GetAppliedEntries())
end)

test("f10_non_table_database_or_entries_recover_without_discarding_valid_frame_preferences", function()
    for _, broken in ipairs({ false, 17, "broken", function() end }) do
        local _, ns = setup(broken)
        equal(#ns:GetEntries(), 8)
        local saved = { entries = broken, frame = { visible = false, scale = 1.7, x = 51, y = 82 } }
        local _, recovered = setup(saved)
        equal(#recovered:GetEntries(), 8)
        equal(recovered.db.frame.visible, false)
        equal(recovered.db.frame.scale, 1.7)
        equal(recovered.db.frame.x, 51)
        equal(recovered.db.frame.y, 82)
    end
end)

local f10InvalidNumbers = { "bad", "", false, true, {}, function() end, 0 / 0, math.huge, -math.huge, "1e309" }
for _, spec in ipairs({
    { "scale", 1, 0.5, 2 }, { "iconSize", 40, 24, 72 }, { "spacing", 4, 0, 20 },
    { "x", 0 }, { "y", -180 },
}) do
    test("f10_frame_" .. spec[1] .. "_numeric_boundaries_and_field_local_fallback", function()
        local cases = {}
        for _, value in ipairs(f10InvalidNumbers) do cases[#cases + 1] = { value, spec[2] } end
        if spec[3] then
            cases[#cases + 1] = { spec[3], spec[3] }
            cases[#cases + 1] = { spec[4], spec[4] }
            cases[#cases + 1] = { spec[3] - 0.25, spec[3] }
            cases[#cases + 1] = { spec[4] + 0.25, spec[4] }
            cases[#cases + 1] = { tostring((spec[3] + spec[4]) / 2), (spec[3] + spec[4]) / 2 }
        else
            cases[#cases + 1] = { "-250.5", -250.5 }
            cases[#cases + 1] = { 12345, 12345 }
        end
        for _, case in ipairs(cases) do
            local saved = { frame = { [spec[1]] = case[1], locked = true, visible = false } }
            local _, ns = setup(saved)
            equal(ns.db.frame[spec[1]], case[2], spec[1])
            equal(ns.db.frame.locked, true)
            equal(ns.db.frame.visible, false)
        end
    end)
end

test("f10_frame_anchors_accept_all_nine_points_and_fallback_independently", function()
    for _, field in ipairs({ "point", "relativePoint" }) do
        for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
            "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "", "middle", "center", 1, false, {} }) do
            local valid = type(point) == "string" and point ~= "" and point ~= "middle" and point ~= "center"
            local other = field == "point" and "relativePoint" or "point"
            local _, ns = setup({ frame = { [field] = point, [other] = "TOPRIGHT", x = 12, y = -21 } })
            equal(ns.db.frame[field], valid and point or "CENTER")
            equal(ns.db.frame[other], "TOPRIGHT")
            equal(ns.db.frame.x, 12)
            equal(ns.db.frame.y, -21)
        end
    end
end)

test("f10_booleans_do_not_treat_strings_numbers_or_tables_as_true", function()
    for _, value in ipairs({ false, true, "false", "true", 0, 1, {}, function() end }) do
        local entry = f10Entry("boolean")
        entry.enabled, entry.builtin, entry.hideWhenMissing = value, value, value
        local _, ns = setup({ entries = { entry },
            frame = { locked = value, visible = value, showUnavailable = value } })
        for _, field in ipairs({ "enabled", "builtin", "hideWhenMissing" }) do
            local expected
            if type(value) == "boolean" then expected = value end
            equal(entry[field], expected)
        end
        for _, field in ipairs({ "locked", "visible", "showUnavailable" }) do
            local expected = ns.DEFAULT_FRAME[field]
            if type(value) == "boolean" then expected = value end
            equal(ns.db.frame[field], expected)
        end
    end
end)

test("f10_missing_fields_stay_absent_until_the_user_explicitly_enables_and_selects_an_action", function()
    local entry = { id = "missing-fields", itemID = 123, spellID = 456 }
    local state, ns = setup({ entries = { entry } })
    sameScalars(entry, { id = "missing-fields", itemID = 123, spellID = 456 })
    equal(state:button(entry.id), nil, "missing enabled must not enable an entry")
    ns:OpenConfig()
    local row = configRow(ns, entry.id)
    equal(row.action:GetText(), "无")
    row.enabled:SetChecked(true)
    state:script(row.enabled, "OnClick")
    local button = state:button(entry.id)
    equal(next(button.attributes), nil, "missing action must not silently become an item click")
    state:script(row.action, "OnClick")
    assertAction(button, "item", 123)
    equal(entry.label, nil)
    equal(entry.category, nil)
    equal(entry.builtin, nil)
    equal(entry.hideWhenMissing, nil)
end)

for _, field in ipairs({ "itemID", "spellID", "useSpellID", "enchantID", "requiredEquippedItemID", "inventorySlot" }) do
    test("f10_" .. field .. "_accepts_only_supported_finite_integers", function()
        local cases = {
            { 1, 1 }, { "00028", 28 }, { "16.0", 16 }, { -1 }, { 1.5 }, { "3.5" },
            { 2147483648 }, { 9007199254740992 }, { "1e100" },
        }
        for _, value in ipairs(f10InvalidNumbers) do cases[#cases + 1] = { value } end
        cases[#cases + 1] = { 0, (field == "itemID" or field == "spellID") and 0 or nil }
        cases[#cases + 1] = { "0", (field == "itemID" or field == "spellID") and 0 or nil }
        cases[#cases + 1] = { 2147483647, field ~= "inventorySlot" and 2147483647 or nil }
        if field == "inventorySlot" then cases[#cases + 1] = { 29 } end
        for _, case in ipairs(cases) do
            local entry = f10Entry("numeric")
            entry[field] = case[1]
            local state, ns = setup({ entries = { entry } })
            equal(entry[field], case[2], field)
            equal(entry.label, "保留我的名称")
            state:command("status")
            state:script(state:button(entry.id), "OnEnter")
            if field == "inventorySlot" and case[2] == 28 then
                entry.enchantID = 8675
                state.enchantments[28] = spikesnailEnchant()
                ns:RequestRebuild()
                equal(state:button(entry.id).effect.enchantID, 8675)
            elseif field == "enchantID" and case[2] then
                equal(state:button(entry.id).effect.unknown, true, "missing slot must not call native API")
                local queries = #state.enchantmentQueries
                ns:GetEntryEffect(state:button(entry.id).entry)
                equal(#state.enchantmentQueries, queries, "missing slot reached the native API")
            end
        end
    end)
end

test("f10_actions_and_macro_types_never_fallback_to_an_unintended_item_click", function()
    for _, action in ipairs({ "macro", "unknown", false, 1, {}, function() end }) do
        for _, text in ipairs({ false, 1, {}, function() end, "", " \n/use [mod] item:123\n/run print('原文')\n" }) do
            local entry = f10Entry("action")
            entry.action, entry.macrotext = action, text
            local state, ns = setup({ entries = { entry } })
            local button = state:button(entry.id)
            if action == "macro" and type(text) == "string" then
                assertAction(button, "macro", text)
                equal(entry.macrotext, text, "macro text was rewritten")
            else
                equal(next(button.attributes), nil, "invalid action fell through to item")
            end
            if type(text) == "string" then equal(entry.macrotext, text) else equal(entry.macrotext, nil) end
            ns:OpenConfig()
            if entry.action == nil then
                state:script(configRow(ns, entry.id).action, "OnClick")
                assertAction(button, "item", 123)
            end
        end
    end
end)

test("f10_zero_ids_skip_item_apis_clicks_and_tooltips_but_keep_aura_tracking", function()
    for _, action in ipairs({ "item", "toy", "macro" }) do
        local entry = f10Entry("zero")
        entry.itemID, entry.action = 0, action
        entry.macrotext = action == "macro" and "/cast Fishing" or nil
        local state = Mock.new(addonPath, { entries = { entry } })
        for _, api in ipairs({ "GetItemCount", "GetItemIconByID", "GetItemCooldown" }) do
            local original = state.env.C_Item[api]
            state.env.C_Item[api] = function(id, ...)
                assert(id > 0, "zero passed to " .. api)
                return original(id, ...)
            end
        end
        local originalToy, tooltip = state.env.PlayerHasToy, state.env.GameTooltip
        state.env.PlayerHasToy = function(id) assert(id > 0); return originalToy(id) end
        local originalLink = tooltip.SetHyperlink
        tooltip.SetHyperlink = function(self, link)
            assert(link ~= "item:0", "zero item tooltip")
            return originalLink(self, link)
        end
        state:login()
        local ns, button = state.ns, state:button("zero")
        assertAction(button, action == "macro" and "macro" or nil, entry.macrotext)
        state:script(button, "OnEnter")
        equal(tooltip:GetText(), entry.label)
        state.auras = { aura(456) }
        ns:Refresh()
        equal(button.effect.spellId, 456)
        state:script(button, "OnEnter")
        equal(tooltip.spellID, 456)
        entry.spellID = 0
        ns:RequestRebuild()
        equal(button.effect, nil)
        equal(ns:ScanAuras()[0], nil)
        equal(ns:FindAura(0), nil)
    end
end)

test("f10_numeric_string_legacy_migrations_preserve_preferences_and_are_idempotent", function()
    for _, version in ipairs({ 0, 1, "1", false, "broken", math.huge }) do
        local snail, phial = legacySpikesnail(), legacyCrystallinePhial()
        for _, entry in ipairs({ snail, phial }) do
            for key, value in pairs(entry) do
                if type(value) == "number" then entry[key] = "00" .. value end
            end
            entry.label, entry.category = "我的旧条目", "个人分类"
            entry.enabled, entry.hideWhenMissing = false, true
        end
        local saved = { version = version, entries = { phial, f10Entry("between"), snail },
            frame = { locked = true, visible = false, scale = "1.4", x = "75", y = "-50" } }
        local snapshot
        for _ = 1, 3 do
            local _, ns = setup(saved)
            equal(ns:GetEntries()[1], phial)
            equal(ns:GetEntries()[3], snail)
            equal(phial.spellID, 393714)
            equal(phial.useSpellID, 371454)
            equal(snail.spellID, nil)
            equal(snail.useSpellID, 1284999)
            equal(snail.enchantID, 8675)
            equal(snail.inventorySlot, 28)
            for _, entry in ipairs({ snail, phial }) do
                equal(entry.label, "我的旧条目")
                equal(entry.category, "个人分类")
                equal(entry.enabled, false)
                equal(entry.hideWhenMissing, true)
            end
            equal(saved.frame.scale, 1.4)
            equal(saved.frame.x, 75)
            equal(saved.frame.y, -50)
            equal(saved.frame.visible, false)
            equal(saved.frame.locked, true)
            if snapshot then
                for index, entry in ipairs(ns:GetEntries()) do sameScalars(entry, snapshot[index]) end
            end
            snapshot = ns:CopyEntries()
        end
    end
end)

test("f10_malformed_semantic_overrides_do_not_become_stock_migration_matches_on_reload", function()
    for _, factory in ipairs({ legacySpikesnail, legacyCrystallinePhial }) do
        for _, override in ipairs({
            { "useSpellID", 0 }, { "useSpellID", {} }, { "enchantID", -1 },
            { "inventorySlot", "bad" }, { "builtin", "true" }, { "macrotext", false },
            { "action", {} }, { "spellID", "9999" }, { "itemID", "0" },
        }) do
            local entry = factory()
            entry[override[1]] = override[2]
            local originalSpell = entry.spellID
            local saved, snapshot = { version = 1, entries = { entry } }, nil
            for _ = 1, 3 do
                local _, ns = setup(saved)
                equal(entry.spellID, tonumber(originalSpell))
                equal(entry.useSpellID, nil)
                equal(entry.enchantID, nil)
                if snapshot then sameScalars(entry, snapshot) end
                snapshot = ns:CopyEntries()[1]
            end
        end
    end
end)

test("f10_version_is_written_after_recovery_and_migration_and_current_versions_keep_overrides", function()
    local phial = legacyCrystallinePhial()
    phial.spellID = "371454"
    local saved = setmetatable({ entries = { phial }, frame = { scale = -1, iconSize = "bad" } }, {
        __newindex = function(db, key, value)
            if key == "version" then
                equal(db.entries[1].spellID, 393714, "version written before migration")
                equal(db.entries[1].useSpellID, 371454)
                equal(db.frame.scale, 0.5, "version written before frame recovery")
                equal(db.frame.iconSize, 40)
                equal(#db.entries, 8, "version written before builtin merge")
            end
            rawset(db, key, value)
        end,
    })
    local _, ns = setup(saved)
    equal(saved.version, ns.DB_VERSION)
    for _, version in ipairs({ ns.DB_VERSION, tostring(ns.DB_VERSION), ns.DB_VERSION + 1 }) do
        local entry = legacyCrystallinePhial()
        local current = { version = version, entries = { entry } }
        setup(current)
        equal(entry.spellID, 371454, "current-version user definition was remigrated")
        equal(entry.useSpellID, nil)
    end
end)

for _, field in ipairs({ "itemID", "spellID" }) do
    test("f10_ui_rejects_invalid_" .. field .. "_without_rebuild_or_combat_snapshot_changes", function()
        for _, combat in ipairs({ false, true }) do
            local state, ns = setup()
            ns:OpenConfig()
            local row = configRow(ns, "haranir-phial")
            local original, applied = row.entry[field], ns:GetAppliedEntries()
            local work = watchActionWork(state, ns)
            state.combat = combat
            for _, text in ipairs({ "-1", "1.5", "nan", "inf", "1e309", "2147483648", "bad" }) do
                editConfigField(state, row, field, text)
                state:script(row[field], "OnEditFocusLost")
                equal(row.entry[field], original)
                equal(row[field]:GetText(), tostring(original))
                equal(ns:GetAppliedEntries(), applied)
            end
            equal(work.rebuilds, 0)
            equal(work.copies, 0)
            equal(work.attributes, 0)
            equal(ns.rebuildPending, nil)
        end
    end)
end

test("f10_ui_add_requires_positive_spell_id_and_keeps_invalid_drafts", function()
    local state, ns = setup()
    ns:OpenConfig()
    local button, boxes = addControls(state)
    for _, pair in ipairs({
        { "-1", "456" }, { "123", "-1" }, { "1.5", "456" }, { "123", "2.5" },
        { "bad", "456" }, { "123", "bad" }, { "1e309", "456" }, { "123", "1e309" },
        { "2147483648", "456" }, { "123", "2147483648" }, { "0", "0" },
        { "123", "0" }, { "123", "0000" }, { "123", "" }, { "123", " " },
    }) do
        boxes[1]:SetText("我的草稿")
        boxes[2]:SetText(pair[1])
        boxes[3]:SetText(pair[2])
        state:script(button, "OnClick")
        equal(#ns:GetEntries(), 8)
        equal(boxes[1]:GetText(), "我的草稿")
        equal(boxes[2]:GetText(), pair[1])
        equal(boxes[3]:GetText(), pair[2])
    end
    for index, pair in ipairs({ { "0", "456" }, { "123", "1" }, { "00123", "00456" } }) do
        boxes[1]:SetText("有效条目 " .. index)
        boxes[2]:SetText(pair[1])
        boxes[3]:SetText(pair[2])
        state:script(button, "OnClick")
        local entry = ns:GetEntries()[8 + index]
        equal(entry.itemID, tonumber(pair[1]))
        equal(entry.spellID, tonumber(pair[2]))
        assertAction(state:button(entry.id), entry.itemID > 0 and "item" or nil, entry.itemID)
    end
end)

test("f10_recovered_frame_controls_remain_within_display_ranges", function()
    local state, ns = setup({ frame = { scale = "bad", iconSize = math.huge, spacing = false } })
    ns:OpenConfig()
    for _, spec in ipairs({
        { "scale", ns.Config.scaleLabel, 0.5, 2 },
        { "iconSize", ns.Config.sizeLabel, 24, 72 },
        { "spacing", ns.Config.spacingLabel, 0, 20 },
    }) do
        for _, text in ipairs({ "+", "-" }) do
            local button = numberControl(state, spec[2], text)
            for _ = 1, 40 do state:script(button, "OnClick") end
            near(ns.db.frame[spec[1]], text == "+" and spec[4] or spec[3])
        end
    end
end)

test("expired_aura_retry_scans_are_bounded", function()
    local state, ns = setup()
    for _, entry in ipairs(ns:GetEntries()) do state.auras[#state.auras + 1] = aura(entry.spellID, 99) end
    ns:Refresh()
    local before = state.auraScans
    state:script(ns.Bar, "OnUpdate", 0.1)
    assert(state.auraScans - before <= 1,
        "one timer tick rescanned all auras " .. (state.auraScans - before) .. " times")
end)

-- F11: advance GetTime and elapsed together. Hidden frames do not receive native
-- OnUpdate calls; individual tests can still invoke a late callback explicitly.
do
    local function ticks(state, ns, count, elapsed)
        elapsed = elapsed or 0.1
        local start = state.now
        for index = 1, count do
            state.now = start + index * elapsed
            if ns.Bar:IsVisible() then state:script(ns.Bar, "OnUpdate", elapsed) end
        end
    end

    local function watchRefreshes(ns)
        local counts = watchConfigRefresh(ns)
        local refresh = ns.Bar.Refresh
        counts.bar = 0
        ns.Bar.Refresh = function(self)
            counts.bar = counts.bar + 1
            return refresh(self)
        end
        return counts
    end

    local function expiredAuras(state, ns)
        for _, entry in ipairs(ns:GetAppliedEntries()) do
            if entry.enabled and not entry.enchantID and entry.spellID then
                state.auras[#state.auras + 1] = aura(entry.spellID, 99)
            end
        end
        ns:Refresh()
    end

    test("f11_simultaneous_expirations_scan_once_and_only_refresh_the_bar", function()
        local state, ns = setup()
        ns:OpenConfig()
        expiredAuras(state, ns)
        equal(#state.auras, 7)
        local counts, scans = watchRefreshes(ns), state.auraScans
        ticks(state, ns, 1)
        equal(state.auraScans - scans, 1)
        equal(counts.bar, 1)
        equal(counts.refreshes, 0)
        equal(counts.rebuilds, 0)
        for _, button in ipairs(ns.Bar.buttons) do
            equal(button.timeText:GetText(), "")
        end
    end)

    test("f11_persistent_remnants_are_bounded_for_seconds_without_catchup_bursts", function()
        local state, ns = setup()
        ns:OpenConfig()
        expiredAuras(state, ns)
        local counts, scans = watchRefreshes(ns), state.auraScans
        local scanTimes, scan = {}, ns.ScanAuras
        ns.ScanAuras = function(self)
            scanTimes[#scanTimes + 1] = state.now
            return scan(self)
        end
        ticks(state, ns, 50)
        equal(state.auraScans - scans, 5, "50 countdown ticks must perform only five retries")
        for index = 2, #scanTimes do
            assert(scanTimes[index] - scanTimes[index - 1] >= 1, "retries were less than one second apart")
        end
        ticks(state, ns, 1, 30)
        equal(state.auraScans - scans, 6, "a stalled frame must not replay missed retries")
        ticks(state, ns, 9)
        equal(state.auraScans - scans, 6)
        ticks(state, ns, 1)
        equal(state.auraScans - scans, 7)
        equal(counts.bar, 7)
        equal(counts.refreshes, 0)
    end)

    test("f11_no_expiration_keeps_tenth_second_countdowns_without_full_refreshes", function()
        local state, ns = setup()
        local access = Mock.restrictedAPI(state)
        ns:GetEntries()[8].enabled = false
        ns:RequestRebuild()
        local unknownTime = aura(393714)
        unknownTime.expirationTime = access:value()
        state.auras = {
            aura(397827, 108), aura(1236763, 0), access:table(unknownTime),
            access:table({}, { tableReadable = false }), aura(ns:GetEntries()[8].spellID, 99),
        }
        ns:Refresh()
        ns:OpenConfig()
        local counts, scans = watchRefreshes(ns), state.auraScans
        ticks(state, ns, 1)
        equal(state:button("oversized-bobber").timeText:GetText(), "7.9")
        ticks(state, ns, 1)
        equal(state:button("oversized-bobber").timeText:GetText(), "7.8")
        ticks(state, ns, 28)
        equal(state:button("oversized-bobber").timeText:GetText(), "5.0")
        equal(state:button("haranir-phial").timeText:GetText(), "")
        equal(state:button("crystalline-phial").timeText:GetText(), "?")
        equal(state:button("ulatek-lure").effect.unknown, true)
        equal(state.auraScans, scans)
        equal(counts.bar, 0)
        equal(counts.refreshes, 0)
    end)

    test("f11_events_bypass_retry_throttle_and_recover_immediately", function()
        local state, ns = setup()
        ns:OpenConfig()
        state.auras = { aura(397827, 99) }
        ns:Refresh()
        ticks(state, ns, 1)
        local button = state:button("oversized-bobber")
        local counts, scans = watchRefreshes(ns), state.auraScans
        for index, event in ipairs({ "UNIT_AURA", "BAG_UPDATE_DELAYED", "SPELL_UPDATE_COOLDOWN" }) do
            state.auras = { aura(397827, 110, index + 1) }
            state:fire(event, "player")
            equal(state.auraScans - scans, index)
            equal(button.countText:GetText(), tostring(index + 1))
            equal(button.effect.expirationTime, 110)
        end
        state.auras = {}
        state:fire("UNIT_AURA", "player")
        equal(button.effect, nil)
        equal(state.auraScans - scans, 4)
        state.auras = { aura(397827, 99, 5) }
        state:fire("UNIT_AURA", "player")
        equal(button.countText:GetText(), "5")
        equal(state.auraScans - scans, 5)
        ticks(state, ns, 5)
        equal(state.auraScans - scans, 5, "events must not reopen the automatic retry budget")
        equal(counts.bar, 5)
        equal(counts.refreshes, 5, "event refresh behavior must remain intact")
    end)

    test("f11_silent_recovery_stops_retries_and_new_expirations_share_the_budget", function()
        for _, recovery in ipairs({ "missing", "extended" }) do
            local state, ns = setup()
            ns:OpenConfig()
            local button = state:button("oversized-bobber")
            state.auras = { aura(397827, 99) }
            ns:Refresh()
            local counts, scans = watchRefreshes(ns), state.auraScans
            ticks(state, ns, 1)
            state.auras = recovery == "missing" and {} or { aura(397827, 110) }
            ticks(state, ns, 9)
            equal(state.auraScans - scans, 1)
            ticks(state, ns, 1)
            equal(state.auraScans - scans, 2)
            if recovery == "missing" then
                equal(button.effect, nil)
            else
                equal(button.effect.expirationTime, 110)
                equal(button.timeText:GetText(), "8.9")
            end

            -- An event introduces a different Aura that expires inside the
            -- existing interval. It must get a retry by the next deadline.
            state.auras = { aura(1236763, 101.3) }
            state:fire("UNIT_AURA", "player")
            local newButton = state:button("haranir-phial")
            scans = state.auraScans
            ticks(state, ns, 5)
            equal(newButton.timeText:GetText(), "")
            equal(state.auraScans, scans)
            state.auras = {}
            ticks(state, ns, 5)
            equal(state.auraScans - scans, 1)
            equal(newButton.effect, nil)
            scans = state.auraScans
            ticks(state, ns, 30)
            equal(state.auraScans, scans, "recovered data must stop automatic scans")
            equal(counts.refreshes, 1, "only the explicit event may refresh Config")
        end
    end)

    test("f11_expired_data_becoming_unknown_stops_retries_until_an_event_recovers_it", function()
        for _, unknownKind in ipairs({ "identity", "time" }) do
            local state, ns = setup()
            ns:OpenConfig()
            local access = Mock.restrictedAPI(state)
            state.auras = { aura(397827, 99) }
            ns:Refresh()
            ticks(state, ns, 1)
            local fields = aura(397827)
            fields[unknownKind == "identity" and "spellId" or "expirationTime"] = access:value()
            state.auras = { access:table(fields) }
            ticks(state, ns, 10)
            local button = state:button("oversized-bobber")
            equal(button.effect.expirationTime, nil)
            equal(button.timeText:GetText(), "?")
            local counts, scans = watchRefreshes(ns), state.auraScans
            ticks(state, ns, 30)
            equal(state.auraScans, scans)
            equal(counts.bar, 0)
            state.auras = { aura(397827, state.now + 0.2) }
            state:fire("UNIT_AURA", "player")
            equal(state.auraScans - scans, 1)
            equal(button.effect.unknown, nil)
            state.auras = {}
            ticks(state, ns, 3)
            equal(state.auraScans - scans, 2)
            equal(button.effect, nil)
            equal(counts.refreshes, 1)
        end
    end)

    test("f11_enchant_only_poll_and_known_expiry_never_refresh_auras_or_config", function()
        local state, ns = setup()
        ns:OpenConfig()
        local button = state:button("pointed-spikesnail")
        local counts, scans, queries = watchRefreshes(ns), state.auraScans, #state.enchantmentQueries
        state.enchantments[28] = spikesnailEnchant(200)
        ticks(state, ns, 1, 1)
        equal(#state.enchantmentQueries - queries, 1)
        equal(button.effect.expirationTime, 101.2)
        ticks(state, ns, 1)
        equal(button.timeText:GetText(), "0.1")
        state.enchantments[28].remainingTimeMs = 0
        ticks(state, ns, 2)
        equal(button.effect, nil, "known expiration must be checked before the one-second poll")
        equal(#state.enchantmentQueries - queries, 2)
        ticks(state, ns, 20)
        assert(#state.enchantmentQueries - queries <= 4)
        equal(state.auraScans, scans)
        equal(counts.bar, 0)
        equal(counts.refreshes, 0)
        state.enchantments[28] = spikesnailEnchant(600000)
        ticks(state, ns, 1, 1)
        equal(button.effect.enchantID, 8675)
        equal(state.auraScans, scans)
        equal(counts.refreshes, 0)
    end)

    test("f11_aura_retry_throttle_does_not_delay_known_enchant_expiry", function()
        local state, ns = setup()
        ns:OpenConfig()
        state.auras = { aura(397827, 99) }
        state.enchantments[28] = spikesnailEnchant(400)
        ns:Refresh()
        ticks(state, ns, 1)
        local counts, scans, queries = watchRefreshes(ns), state.auraScans, #state.enchantmentQueries
        state.enchantments[28].remainingTimeMs = 0
        ticks(state, ns, 4)
        equal(state:button("pointed-spikesnail").effect, nil)
        equal(#state.enchantmentQueries - queries, 1)
        equal(state.auraScans, scans)
        equal(counts.bar, 0)
        equal(counts.refreshes, 0)
    end)

    test("f11_hidden_bar_pauses_retries_and_show_reads_current_data_immediately", function()
        for _, hiddenFor in ipairs({ 0.2, 5 }) do
            local state, ns = setup()
            ns:OpenConfig()
            state.auras = { aura(397827, 99) }
            ns:Refresh()
            ticks(state, ns, 1)
            ns:SetBarVisible(false)
            local counts, scans, queries = watchRefreshes(ns), state.auraScans, #state.enchantmentQueries
            ticks(state, ns, 1, hiddenFor)
            state:script(ns.Bar, "OnUpdate", 1) -- A late callback must also be harmless.
            equal(state.auraScans, scans)
            equal(#state.enchantmentQueries, queries)
            equal(counts.refreshes, 0)
            state.auras = hiddenFor < 1 and { aura(397827, 99) } or {}
            ns:SetBarVisible(true)
            equal(state.auraScans - scans, 1, "show must bypass the old retry deadline")
            scans = state.auraScans
            local configRefreshes = counts.refreshes
            ticks(state, ns, 1)
            equal(state.auraScans, scans, "show must not reset the retry budget or keep removed data")
            equal(counts.refreshes, configRefreshes)
            if hiddenFor > 1 then
                equal(state:button("oversized-bobber").effect, nil)
                state.auras = { aura(397827, state.now + 0.2) }
                state:fire("UNIT_AURA", "player")
                scans = state.auraScans
                state.auras = {}
                ticks(state, ns, 3)
                equal(state.auraScans - scans, 1, "new expiry after a long hide must not retain stale delay")
            end
        end
    end)

    test("f11_combat_retries_keep_drafts_actions_snapshots_and_pending_visibility", function()
        local state, ns = setup()
        ns:OpenConfig()
        expiredAuras(state, ns)
        local row = configRow(ns, "haranir-phial")
        local button = state:button(row.entry.id)
        local applied, entries = button.entry, ns:GetAppliedEntries()
        local oldSpell, oldLabel = applied.spellID, applied.label
        state:script(button, "OnEnter")
        state:script(ns.Bar.dragHandle, "OnDragStart")
        state.combat = true
        state:script(ns.Bar.dragHandle, "OnDragStop")
        editConfigField(state, row, "itemID", 910011)
        editConfigField(state, row, "spellID", 810011)
        row.label:SetFocus()
        row.label:SetText("  重试时保留草稿  ")
        ns:SetBarVisible(false)
        local counts, work, scans = watchRefreshes(ns), watchActionWork(state, ns), state.auraScans
        ticks(state, ns, 30)
        equal(state.auraScans - scans, 3)
        equal(counts.bar, 3)
        equal(counts.refreshes, 0)
        equal(work.copies, 0)
        equal(work.rebuilds, 0)
        equal(work.attributes, 0)
        equal(ns:GetAppliedEntries(), entries)
        equal(button.entry, applied)
        equal(button.effect.spellId, oldSpell)
        equal(button.entry.label, oldLabel)
        assertAction(button, "item", 241316)
        equal(row.label:GetText(), "  重试时保留草稿  ")
        equal(state.focus, row.label)
        equal(ns.Bar:IsShown(), true)
        equal(ns.barStopPending, true)
        equal(ns.rebuildPending, true)

        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(ns.Bar:IsShown(), false)
        equal(ns.barMoving, nil)
        equal(ns.barStopPending, nil)
        equal(ns.rebuildPending, nil)
        equal(state:button(row.entry.id), button)
        equal(button.entry.spellID, 810011)
        assertAction(button, "item", 910011)
        equal(applied.spellID, oldSpell)
        equal(applied.itemID, 241316)
        equal(row.label:GetText(), "  重试时保留草稿  ")
        state.auras = { aura(810011, 200) }
        ns:SetBarVisible(true)
        equal(button.effect.spellId, 810011)
        equal(row.label:GetText(), "  重试时保留草稿  ")
    end)

    test("f11_combat_hidden_buttons_retry_effects_without_protected_layout_changes", function()
        local state, ns = setup()
        local button = state:button("ulatek-lure")
        equal(button:IsShown(), false)
        local width = ns.Bar:GetWidth()
        state.combat = true
        state.auras = { aura(1302820, 99) }
        state:fire("UNIT_AURA", "player")
        equal(button:IsShown(), false)
        local counts, scans = watchRefreshes(ns), state.auraScans
        ticks(state, ns, 1)
        equal(state.auraScans - scans, 1)
        state.auras = {}
        ticks(state, ns, 10)
        equal(state.auraScans - scans, 2)
        equal(button.effect, nil)
        equal(button:IsShown(), false)
        equal(ns.Bar:GetWidth(), width)
        equal(counts.refreshes, 0)
        state.auras = { aura(1302820, 200) }
        state:fire("UNIT_AURA", "player")
        equal(button.effect.expirationTime, 200)
        equal(button:IsShown(), false)
        state.combat = false
        state:fire("PLAYER_REGEN_ENABLED")
        equal(button:IsShown(), true)
        assert(ns.Bar:GetWidth() > width)
    end)

    test("f11_rebuild_and_pool_reuse_preserve_retry_bound_and_replace_expired_tracking", function()
        local state, ns = setup()
        state.auras = { aura(397827, 99) }
        ns:Refresh()
        ticks(state, ns, 1)
        local button, applied = ns.Bar.buttons[1], ns.Bar.buttons[1].entry
        local frames = state:secureFrameCount()
        local replacement = f07Entry(11)
        state.auras = { aura(replacement.spellID, 99) }
        ns.db.entries = { replacement }
        for _ = 1, 3 do
            ns:RequestRebuild()
            local scans = state.auraScans
            ticks(state, ns, 1)
            equal(state.auraScans, scans, "rebuild must not reopen the timer retry budget")
            equal(ns.Bar.buttons[1], button)
        end
        local counts, scans = watchRefreshes(ns), state.auraScans
        state.auras = {}
        ticks(state, ns, 8)
        equal(state.auraScans - scans, 1)
        equal(button.effect, nil)
        equal(button.entry.spellID, replacement.spellID)
        equal(applied.spellID, 397827)
        assertAction(button, "item", replacement.itemID)
        equal(counts.refreshes, 0)
        ns.db.entries = {}
        ns:RequestRebuild()
        scans = state.auraScans
        ticks(state, ns, 30)
        equal(state.auraScans, scans)
        equal(button.entry, nil)
        equal(button.effect, nil)
        ns.db.entries = { replacement }
        ns:RequestRebuild()
        equal(ns.Bar.buttons[1], button)
        equal(button.effect, nil)
        equal(state:secureFrameCount(), frames)
    end)
end

-- F03: these are strict sentinel/accessor contracts, not real client secrets.
local function restrictedSetup()
    local state, ns = setup()
    return state, ns, Mock.restrictedAPI(state)
end

local function entryStatus(state, button)
    state.messages = {}
    state:command("status")
    for _, message in ipairs(state.messages) do
        if message:find(button.entry.label .. ":", 1, true) then return message end
    end
    error("entry status missing")
end

local function tooltipText(state)
    return table.concat(state.env.GameTooltip.lines, "\n")
end

test("f03_strict_model_rejects_unguarded_reads_and_sentinel_operations", function()
    local state = setup()
    local access = Mock.restrictedAPI(state)
    local raw = access:table(aura(397827))
    equal(pcall(function() return raw.spellId end), false)
    equal(state.env.canaccesstable(raw), true)
    equal(raw.spellId, 397827)
    local opaque = access:table({}, { tableReadable = false })
    equal(state.env.canaccessvalue(opaque), true, "table contents have separate permissions")
    equal(state.env.canaccesstable(opaque), false)
    equal(pcall(function() return opaque.spellId end), false)
    local secret = access:value()
    equal(pcall(function() return secret - 100 end), false)
    equal(pcall(function() return secret > 1 end), false)
    equal(pcall(function() return tostring(secret) end), false)
    equal(pcall(function() return state.env.type(secret) end), false)
end)

test("f03_readable_aura_snapshots_preserve_observable_fields", function()
    local state, ns, access = restrictedSetup()
    local fields = aura(397827, 240, 3)
    fields.name = access:value() -- Unused fields must not be copied or inspected.
    state.auras = { access:table(fields) }
    local snapshot = ns:ScanAuras()[397827]
    equal(snapshot.spellId, 397827)
    equal(snapshot.expirationTime, 240)
    equal(snapshot.applications, 3)
    equal(snapshot.icon, 12345)
    equal(snapshot.name, nil)
    fields.expirationTime = 220
    equal(snapshot.expirationTime, 240, "snapshot retained the mutable API table")
    equal(ns:FindAura(397827).expirationTime, 220)
    ns:Refresh()
    local button = state:button("oversized-bobber")
    equal(button.icon.texture, 12345)
    equal(button.countText:GetText(), "3")
    equal(button.timeText:GetText(), "2m")
    state:script(button, "OnEnter")
    assert(tooltipText(state):find("剩余时间：2m", 1, true))
    assert(entryStatus(state, button):find("ACTIVE", 1, true))
    assert(access.tableChecks > 0 and access.valueChecks > 0 and access.secretChecks > 0)
end)

test("f03_inaccessible_whole_aura_is_unknown_without_indexing", function()
    for _, options in ipairs({
        { tableReadable = false }, { readable = false }, { secret = true },
    }) do
        local state = Mock.new(addonPath)
        local access = Mock.restrictedAPI(state)
        local raw, record = access:table(aura(397827), options)
        state.auras = { raw }
        state:login() -- Also exercise the first refresh with restricted data.
        local ns = state.ns
        local button = state:button("oversized-bobber")
        equal(ns:FindAura(397827).unknown, true)
        equal(ns:ScanAuras()[397827].unknown, true)
        equal(ns:GetEntryEffect(button.entry).unknown, true)
        equal(button.effect.unknown, true)
        equal(#record.reads, 0)
        equal(button.icon.desaturated, true)
        equal(button.border.vertexColor[3], 1)
        equal(button.timeText:GetText(), "?")
        equal(button.countText:GetText(), "")
        state:script(button, "OnEnter")
        assert(tooltipText(state):find("状态未知", 1, true))
        assert(not tooltipText(state):find("缺少", 1, true))
        assert(entryStatus(state, button):find("UNKNOWN", 1, true))
        equal(state:button("pointed-spikesnail").effect, nil,
            "partial aura scans must not make slot enchantments unknown")
    end
end)

test("f03_secret_or_inaccessible_spell_id_cannot_be_compared_or_used_as_key", function()
    for _, flags in ipairs({ { true, false }, { false, false }, { true, true } }) do
        local state, ns, access = restrictedSetup()
        local fields = aura(397827)
        fields.spellId = access:value(unpack(flags))
        local raw, record = access:table(fields, { allowedFields = { spellId = true } })
        state.auras = { raw }
        local active = ns:ScanAuras()
        equal(active[397827].unknown, true, "unreadable ID incorrectly treated as absence")
        equal(active[fields.spellId], nil, "sentinel leaked into the result's keys")
        equal(ns:FindAura(397827).unknown, true)
        ns:Refresh()
        equal(state:button("oversized-bobber").timeText:GetText(), "?")
        for _, field in ipairs(record.reads) do equal(field, "spellId") end
    end
end)

test("f03_secret_expiration_stacks_and_icon_are_independently_sanitized", function()
    for _, field in ipairs({ "expirationTime", "applications", "icon" }) do
        for _, flags in ipairs({ { true, false }, { false, false }, { true, true } }) do
            local state, ns, access = restrictedSetup()
            local fields = aura(397827, 200, 3)
            fields[field] = access:value(unpack(flags))
            state.auras = { access:table(fields) }
            state.icons[202207] = 54321
            ns:Refresh()
            local button = state:button("oversized-bobber")
            equal(button.effect[field], nil)
            equal(button.effect.spellId, 397827)
            equal(button.icon.desaturated, false)
            equal(button.icon.texture, field == "icon" and 54321 or 12345)
            equal(button.timeText:GetText(), field == "expirationTime" and "?" or "2m")
            equal(button.countText:GetText(), field == "applications" and "?" or "3")
            equal(ns:FindAura(397827)[field], nil)
            state:script(button, "OnEnter")
            assert(not tooltipText(state):find("缺少", 1, true))
            if field == "expirationTime" then
                assert(tooltipText(state):find("剩余时间未知", 1, true))
            elseif field == "applications" then
                assert(tooltipText(state):find("层数未知", 1, true))
            end
            assert(entryStatus(state, button):find("ACTIVE", 1, true))
            local scans = state.auraScans
            state:script(ns.Bar, "OnUpdate", 0.1)
            equal(state.auraScans, scans)
        end
    end
end)

test("f03_all_payload_fields_restricted_still_confirm_presence", function()
    local state, ns, access = restrictedSetup()
    state.auras = { access:table({
        spellId = 397827, expirationTime = access:value(),
        applications = access:value(), icon = access:value(),
    }) }
    ns:Refresh()
    local button = state:button("oversized-bobber")
    equal(button.effect.spellId, 397827)
    equal(button.effect.unknown, nil)
    equal(button.timeText:GetText(), "?")
    equal(button.countText:GetText(), "?")
    equal(button.icon.texture, 134400)
    equal(button.border.vertexColor[2], 0.9)
    state:script(button, "OnEnter")
    assert(tooltipText(state):find("剩余时间未知", 1, true))
    local scans = state.auraScans
    state.now = 1000
    for _ = 1, 20 do state:script(ns.Bar, "OnUpdate", 0.1) end
    equal(state.auraScans, scans, "unknown duration triggered expiry retries")
end)

test("f03_mixed_partial_scans_keep_readable_matches_in_either_order", function()
    for _, opaqueFirst in ipairs({ true, false }) do
        local state, ns, access = restrictedSetup()
        local opaque = access:table({}, { tableReadable = false })
        local secretID = access:table({ spellId = access:value() })
        local bobber = access:table(aura(397827, 250, 4))
        local phial = access:table(aura(393714, 400, 2))
        state.auras = opaqueFirst and { opaque, secretID, bobber, phial }
            or { bobber, phial, secretID, opaque }
        ns:Refresh()
        local active = ns:ScanAuras()
        equal(active[397827].expirationTime, 250)
        equal(active[393714].expirationTime, 400)
        equal(active[1236763].unknown, true)
        equal(ns:FindAura(397827).applications, 4)
        equal(ns:FindAura(393714).applications, 2)
        equal(ns:FindAura(1236763).unknown, true)
        equal(state:button("oversized-bobber").countText:GetText(), "4")
        assert(entryStatus(state, state:button("crystalline-phial")):find("ACTIVE", 1, true))
        assert(entryStatus(state, state:button("haranir-phial")):find("UNKNOWN", 1, true))
        ns.db.frame.showUnavailable = false
        ns:Refresh()
        equal(state:button("ulatek-lure"):IsShown(), true,
            "hideWhenMissing must not hide an unknown effect")
    end
end)

test("f03_readable_unrelated_id_with_secret_payload_does_not_make_scan_partial", function()
    local state, ns, access = restrictedSetup()
    local raw, record = access:table({
        spellId = 999999, expirationTime = access:value(),
        applications = access:value(), icon = access:value(),
    }, { allowedFields = { spellId = true } })
    state.auras = { raw }
    equal(ns:FindAura(397827), nil)
    equal(ns:ScanAuras()[397827], nil)
    ns:Refresh()
    equal(state:button("ulatek-lure"):IsShown(), false)
    assert(entryStatus(state, state:button("oversized-bobber")):find("MISSING", 1, true))
    for _, field in ipairs(record.reads) do equal(field, "spellId") end
end)

test("f03_active_unknown_readable_and_missing_transitions_clear_stale_ui", function()
    local state, ns, access = restrictedSetup()
    local button = state:button("oversized-bobber")
    state.auras = { access:table(aura(397827, 200, 3)) }
    ns:Refresh()
    state:script(button, "OnEnter")
    equal(button.timeText:GetText(), "2m")
    state.auras = { access:table({}, { tableReadable = false }) }
    state:fire("UNIT_AURA", "player")
    equal(button.timeText:GetText(), "?")
    equal(button.countText:GetText(), "")
    equal(button.icon.texture, 134400)
    assert(tooltipText(state):find("状态未知", 1, true), "open tooltip retained stale duration")
    assert(entryStatus(state, button):find("UNKNOWN", 1, true))
    state.auras = { access:table(aura(397827, 0, 1)) }
    state:fire("UNIT_AURA", "player")
    equal(button.effect.unknown, nil)
    equal(button.timeText:GetText(), "")
    equal(button.countText:GetText(), "")
    assert(tooltipText(state):find("Buff 已激活", 1, true))
    assert(not tooltipText(state):find("缺少", 1, true))
    state.auras = {}
    state:fire("UNIT_AURA", "player")
    equal(button.effect, nil)
    equal(button.timeText:GetText(), "")
    assert(tooltipText(state):find("缺少 Buff", 1, true))
    assert(entryStatus(state, button):find("MISSING", 1, true))
end)

test("f03_unknown_visibility_respects_combat_and_recovers_after_regen", function()
    local state, ns, access = restrictedSetup()
    local lure = state:button("ulatek-lure")
    equal(lure:IsShown(), false)
    state.combat = true
    state.auras = { access:table({}, { tableReadable = false }) }
    state:fire("UNIT_AURA", "player")
    equal(lure.effect.unknown, true)
    equal(lure:IsShown(), false)
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(lure:IsShown(), true)
    equal(lure.timeText:GetText(), "?")
    state:script(lure, "OnEnter")
    state.combat = true
    state.auras = {}
    state:fire("UNIT_AURA", "player")
    equal(lure:IsShown(), true)
    equal(lure.effect, nil)
    equal(lure.timeText:GetText(), "")
    state.combat = false
    state:fire("PLAYER_REGEN_ENABLED")
    equal(lure:IsShown(), false)
    equal(state.env.GameTooltip:IsShown(), false)
end)

test("f03_readable_data_works_without_restriction_apis", function()
    local state, ns = setup()
    equal(state.env.issecretvalue, nil)
    equal(state.env.canaccessvalue, nil)
    equal(state.env.canaccesstable, nil)
    state.auras = { aura(397827, 200, 2) }
    state.enchantments[28] = spikesnailEnchant()
    ns:Refresh()
    equal(ns:FindAura(397827).spellId, 397827)
    equal(ns:FindAura(393714), nil)
    equal(state:button("oversized-bobber").countText:GetText(), "2")
    equal(state:button("pointed-spikesnail").timeText:GetText(), "10m")
    assert(entryStatus(state, state:button("oversized-bobber")):find("ACTIVE", 1, true))
    state.auras = {}
    ns:Refresh()
    equal(state:button("oversized-bobber").effect, nil)
end)

test("f03_individual_access_api_fallbacks", function()
    for _, removed in ipairs({ "issecretvalue", "canaccessvalue", "canaccesstable" }) do
        local state, ns, access = restrictedSetup()
        state.env[removed] = nil
        local fields = aura(397827)
        fields.expirationTime = access:value()
        -- With no table checker, use an ordinary accessible table; with no value
        -- checker, issecretvalue still rejects the sentinel, and vice versa.
        state.auras = { removed == "canaccesstable" and fields or access:table(fields) }
        ns:Refresh()
        equal(state:button("oversized-bobber").timeText:GetText(), "?")
        equal(ns:FindAura(397827).spellId, 397827)
    end
end)

test("f03_find_aura_guards_query_values_and_keeps_early_exit", function()
    local state, ns, access = restrictedSetup()
    local scans = state.auraScans
    equal(ns:FindAura(access:value()).unknown, true)
    equal(ns:FindAura(0), nil)
    equal(ns:FindAura(-1), nil)
    equal(ns:FindAura("397827"), nil)
    equal(ns:FindAura(nil), nil)
    equal(state.auraScans, scans)
    local later, record = access:table(aura(393714))
    state.auras = { access:table(aura(397827)), later }
    equal(ns:FindAura(397827).spellId, 397827)
    equal(#record.reads, 0, "FindAura did not stop after the readable match")
end)

test("f03_enchantment_identity_restrictions_are_unknown_not_missing", function()
    for _, mode in ipairs({ "table", "value", "secret", "id" }) do
        local state, ns, access = restrictedSetup()
        local fields = spikesnailEnchant()
        if mode == "id" then fields.enchantID = access:value() end
        state.enchantments[28] = access:table(fields, {
            tableReadable = mode ~= "table", readable = mode ~= "value", secret = mode == "secret",
        })
        state.auras = { access:table(aura(397827)) }
        ns:Refresh()
        local button = state:button("pointed-spikesnail")
        equal(button.effect.unknown, true)
        equal(button.timeText:GetText(), "?")
        equal(button.countText:GetText(), "")
        equal(state:button("oversized-bobber").effect.spellId, 397827)
        state:script(button, "OnEnter")
        equal(state.env.GameTooltip.hyperlink, "item:262651")
        assert(tooltipText(state):find("状态未知", 1, true))
        assert(entryStatus(state, button):find("UNKNOWN", 1, true))
        state:script(ns.Bar, "OnUpdate", 1)
        equal(button.effect.unknown, true)
    end
end)

test("f03_enchantment_fields_are_guarded_before_branching_or_arithmetic", function()
    for _, field in ipairs({ "hasExpirationTime", "remainingTimeMs", "chargesRemaining" }) do
        local state, ns, access = restrictedSetup()
        local fields = spikesnailEnchant(600000, 8675, true, 3)
        fields[field] = access:value()
        state.enchantments[28] = access:table(fields)
        ns:Refresh()
        local button = state:button("pointed-spikesnail")
        equal(button.effect.enchantID, 8675)
        equal(button.effect.unknown, nil)
        equal(button.timeText:GetText(), field == "chargesRemaining" and "10m" or "?")
        equal(button.countText:GetText(), field == "chargesRemaining" and "?" or "3")
        state:script(button, "OnEnter")
        assert(not tooltipText(state):find("缺少", 1, true))
        assert(entryStatus(state, button):find("ACTIVE", 1, true))
        state:script(ns.Bar, "OnUpdate", 1)
        equal(button.effect.enchantID, 8675)
    end
end)

test("f03_enchantment_ignores_irrelevant_restricted_fields_and_handles_absent_api", function()
    local state, ns, access = restrictedSetup()
    local button = state:button("pointed-spikesnail")
    state.enchantments[28] = access:table({
        enchantID = 8676, hasExpirationTime = access:value(), remainingTimeMs = access:value(),
    }, { allowedFields = { enchantID = true } })
    ns:Refresh()
    equal(button.effect, nil, "readable wrong enchantment confirms absence")
    state.enchantments[28] = access:table({
        enchantID = 8675, hasExpirationTime = false, remainingTimeMs = access:value(), chargesRemaining = 0,
    }, { allowedFields = { enchantID = true, hasExpirationTime = true, chargesRemaining = true } })
    ns:Refresh()
    equal(button.effect.expirationTime, 0)
    equal(button.timeText:GetText(), "")
    state.env.C_PaperDollInfo = nil
    ns:Refresh()
    equal(button.effect.unknown, true, "absent API cannot confirm missing enchantment")
    assert(entryStatus(state, button):find("UNKNOWN", 1, true))
end)

test("f03_enchantment_poll_transitions_refresh_tooltip_without_aura_scans", function()
    local state, ns, access = restrictedSetup()
    local button = state:button("pointed-spikesnail")
    state.enchantments[28] = access:table(spikesnailEnchant())
    ns:Refresh()
    state:script(button, "OnEnter")
    local scans = state.auraScans
    state.enchantments[28] = access:table({}, { tableReadable = false })
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.timeText:GetText(), "?")
    assert(tooltipText(state):find("状态未知", 1, true))
    state.enchantments[28] = access:table(spikesnailEnchant(120000))
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.timeText:GetText(), "2m")
    assert(tooltipText(state):find("剩余时间：2m", 1, true))
    state.enchantments[28] = nil
    state:script(ns.Bar, "OnUpdate", 1)
    equal(button.effect, nil)
    equal(button.timeText:GetText(), "")
    assert(tooltipText(state):find("缺少临时附魔", 1, true))
    equal(state.auraScans, scans)
end)

local passed, failed = 0, 0
for _, entry in ipairs(tests) do
    if not arg[2] or entry[1]:find(arg[2], 1, true) then
        local ok, err = pcall(entry[2])
        if ok then
            passed = passed + 1
            print("PASS " .. entry[1])
        else
            failed = failed + 1
            print("FAIL " .. entry[1] .. "\n  " .. tostring(err))
        end
    end
end
print(string.format("RESULT %d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
