local ADDON_NAME, NS = ...

NS.ADDON_NAME = ADDON_NAME
NS.DB_VERSION = 2

NS.DEFAULT_FRAME = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    scale = 1,
    iconSize = 40,
    spacing = 4,
    locked = false,
    visible = true,
    showUnavailable = true,
}

NS.BUILTIN_ENTRIES = {
    {
        id = "oversized-bobber",
        label = "可重复使用的巨型鱼漂",
        category = "bobber",
        itemID = 202207,
        spellID = 397827,
        action = "toy",
        enabled = true,
        builtin = true,
    },
    {
        id = "haranir-phial",
        label = "哈籁尼尔感知瓶剂",
        category = "phial",
        itemID = 241316,
        spellID = 1236763,
        action = "item",
        enabled = true,
        builtin = true,
    },
    {
        id = "crystalline-phial",
        label = "晶华感知瓶剂",
        category = "phial",
        itemID = 191354,
        useSpellID = 371454,
        -- Database-backed Aura ID; still needs confirmation after use in a live client.
        spellID = 393714,
        action = "item",
        enabled = true,
        builtin = true,
    },
    {
        id = "sanguithorn-tea",
        label = "血艳蓟茶",
        category = "food",
        itemID = 242299,
        spellID = 1269152,
        action = "item",
        enabled = true,
        builtin = true,
    },
    {
        id = "pointed-spikesnail",
        label = "尖刺钉螺",
        category = "bobber",
        itemID = 262651,
        useSpellID = 1284999,
        enchantID = 8675,
        -- Retail 12.1.0 defines FishingToolSlot as 28. Its enchantment return
        -- and successful item application still need live-client validation.
        inventorySlot = 28,
        action = "macro",
        macrotext = "/use item:262651\n/use 28",
        requiredEquippedItemID = 244790,
        enabled = true,
        builtin = true,
    },
    {
        id = "ulatek-lure",
        label = "乌拉特克蛇头鱼诱饵",
        category = "lure",
        itemID = 277821,
        spellID = 1302820,
        action = "item",
        hideWhenMissing = true,
        enabled = true,
        builtin = true,
    },
    {
        id = "toxic-tlhapi",
        label = "剧毒特拉皮鱼",
        category = "fish",
        itemID = 274588,
        spellID = 1303623,
        action = "item",
        enabled = true,
        builtin = true,
    },
    {
        id = "spotted-killifish",
        label = "斑点鱂鱼",
        category = "fish",
        itemID = 274587,
        spellID = 1303624,
        action = "item",
        enabled = true,
        builtin = true,
    },
}

NS.CATEGORY_LABELS = {
    bobber = "鱼漂",
    phial = "瓶剂",
    food = "食物",
    lure = "诱饵",
    fish = "鱼",
    custom = "自定义",
}

NS.ACTION_LABELS = {
    item = "物品",
    toy = "玩具",
    macro = "宏",
}
