# WoW Fishing Buff Tracker - Technical Research

Research snapshot: 2026-09-16

Target: World of Warcraft Retail 12.1.0 (build 69814 source snapshot)

## Conclusion

The requested addon is feasible with the standard WoW AddOn API.

The main bar should be built from `SecureActionButtonTemplate` buttons so a
hardware click can use an item or toy. Buff state should be detected by
enumerating the player's helpful auras and comparing `aura.spellId`, rather
than comparing localized aura names.

Most entries can use one-click item or toy actions. Pointed Spikesnail is the
only special case: it starts an item-targeting action and then must be applied
to fishing profession equipment slot 28. A secure macro may be able to perform
both steps, but this exact interaction must be validated in the live client.

## Recommended Stack

- Lua and WoW XML/Frame API
- `.toc` manifest with `SavedVariables`
- `C_UnitAuras` and `AuraUtil.ForEachAura`
- `SecureActionButtonTemplate`
- `C_Item` for item metadata, counts, cooldowns, and item spells
- `C_ToyBox` plus secure action type `toy`
- `Settings` API for an Interface Options category
- Slash commands for quick access, such as `/fbt` and `/fbt reset`

No external Lua library is required for the first version.

## Aura Detection

Listen to:

- `PLAYER_LOGIN`
- `UNIT_AURA`, filtered to `unitTarget == "player"`
- `BAG_UPDATE_DELAYED`
- `SPELL_UPDATE_COOLDOWN`
- `PLAYER_REGEN_ENABLED`
- `PROFESSION_EQUIPMENT_CHANGED`

Use:

```lua
AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
    if watchedSpellIDs[aura.spellId] then
        activeAuras[aura.spellId] = aura
    end
end, true)
```

Relevant `AuraData` fields include:

- `spellId`
- `icon`
- `applications`
- `duration`
- `expirationTime`
- `auraInstanceID`

Do not use aura names as the primary key. Blizzard's own `AuraUtil` comments
warn that aura names are localized and not unique.

## Clickable Buttons

Create every actionable entry with:

```lua
CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
```

Normal consumable:

```lua
button:SetAttribute("type", "item")
button:SetAttribute("item", "item:241316")
```

Toy:

```lua
button:SetAttribute("type", "toy")
button:SetAttribute("toy", 202207)
```

Pointed Spikesnail candidate:

```lua
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "/use item:262651\n/use 28")
```

Slot 28 is `FishingToolSlot` in the current Blizzard Professions UI source.
This macro is a candidate, not yet a live-client-verified result.

Secure attributes must not be changed during combat. Queue configuration or
button-action updates until `PLAYER_REGEN_ENABLED`.

## Built-in Data

| Category | Display item | Item ID | Aura Spell ID | Action | Status |
|---|---|---:|---:|---|---|
| Bobber | Reusable Oversized Bobber | 202207 | 397827 | Toy | Verified |
| Phial | Haranir Phial of Perception | 241316 | 1236763 | Item | Verified |
| Phial | Crystalline Phial of Perception | 191354 | 371454 | Item | Missing SpellID resolved |
| Food | Sanguithorn Tea | 242299 | 1269152 | Item/channel | Verified; buff appears after drinking for 10 seconds |
| Bobber | Pointed Spikesnail | 262651 | 1284999 | Item targeting fishing tool | Missing SpellID resolved; click flow needs live test |
| Lure | Ula'tek Snakehead Lure | 277821 | 1302820 | Item | Missing SpellID resolved |
| Fish | Toxic Tlhapi | 274588 | 1303623 | Item | Verified |
| Fish | Spotted Killifish | 274587 | 1303624 | Item | Verified |

Additional findings:

- Reusable Oversized Bobber is toy ItemID `202207`.
- Ula'tek spell `1302819` is the crafting recipe spell.
- Ula'tek buff `1302820` is the 30-minute catch-chance aura.
- Pointed Spikesnail item effect and expected aura are spell `1284999`.
- Crystalline Phial uses `371454`; spell `396962` is the generic Phial
  duration behavior and should not be the primary watched aura.
- Fishing profession equipment tool slot is currently inventory slot `28`.
- The user supplied `244790` for The Coiled Huntress; the addon can check
  `GetInventoryItemID("player", 28)` before presenting the Spikesnail action.

## Display Behavior

Recommended state model for each entry:

1. Active aura: show aura icon, remaining duration, and stack count.
2. Missing aura and usable item available: show item icon and bag count.
3. Missing aura and no item: show desaturated item icon and `0`.
4. Disabled entry: hide it.
5. Lure group: show the active selected lure; if none is active, show no
   warning state, as requested.

The frame should:

- Lay entries out horizontally.
- Be movable by dragging an unlocked background or drag handle.
- Save anchor point, X/Y offset, icon size, spacing, scale, and lock state.
- Show standard GameTooltip data on hover.
- Use the cooldown spiral for item cooldowns and a numeric aura countdown.

## Configuration Model

Use account-wide `FishingBuffTrackerDB` with a profile-like structure:

```lua
FishingBuffTrackerDB = {
    version = 1,
    frame = {
        point = "CENTER",
        x = 0,
        y = -180,
        scale = 1,
        iconSize = 40,
        spacing = 4,
        locked = false,
    },
    entries = {},
    lureSelection = {},
}
```

The control panel should support:

- Enable/disable and reorder entries.
- Add a custom entry with label, category, ItemID, SpellID, and action type.
- Edit ItemID or SpellID.
- Select one or more lure definitions.
- Choose whether missing, unavailable items remain visible.
- Lock/unlock, reset position, icon size, spacing, and scale.

For the first version, a custom canvas under WoW's `Settings` panel is simpler
and more flexible than forcing the dynamic entry editor into standard option
templates.

## Suggested File Layout

```text
wow-fishing-buff-tracker/
└── FishingBuffTracker/
    ├── FishingBuffTracker.toc
    ├── Core.lua
    ├── Data.lua
    ├── AuraScanner.lua
    ├── Bar.lua
    ├── Config.lua
    └── Locale.lua
```

## Risks Requiring Live Client Validation

1. Confirm `/use item:262651` followed by `/use 28` applies Pointed Spikesnail
   to the profession fishing tool in one secure click.
2. Capture `/dump C_UnitAuras.GetAuraDataByIndex(...)` after using each item to
   ensure the observed live aura IDs match the database.
3. Confirm whether the 12.1.0 client exposes any of these player auras as
   restricted/secret in the relevant gameplay state.

## Sources

- Blizzard UI source mirror, live tag `12.1.0`:
  https://github.com/Gethe/wow-ui-source/tree/12.1.0
- Secure action implementation:
  https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua
- Aura utility implementation:
  https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua
- Generated Unit Aura API:
  https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
- Blizzard profession equipment slot definitions:
  https://github.com/Gethe/wow-ui-source/blob/12.1.0/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsCrafting.xml
- Item and spell validation:
  https://www.wowhead.com/
