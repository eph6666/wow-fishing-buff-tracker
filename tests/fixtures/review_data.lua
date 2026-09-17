-- Database-derived test inputs, inspected 2026-09-17; NOT live-client captures.
-- Keep spell usage, actual aura, and temporary enchantment identifiers separate.
-- Sources are recorded in source_manifest.json; validation boundaries in tests/README.md.
return {
    crystallinePhial = {
        itemID = 191354,
        useSpellID = 371454,
        auraSpellID = 393714,
        useSpellSource = "https://www.wowhead.com/spell=371454/crystalline-phial-of-perception",
        auraSource = "https://www.wowhead.com/spell=393714/crystalline-phial-of-perception",
    },
    pointedSpikesnail = {
        itemID = 262651,
        useSpellID = 1284999,
        enchantID = 8675,
        inventorySlot = 28,
        source = "https://www.wowhead.com/spell=1284999/pointed-spikesnail",
    },
    blizzardSource = {
        tag = "12.1.0",
        build = 69814,
        commit = "4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59",
    },
}
