local ADDON_NAME, NS = ...

local function FiniteNumber(value)
    if type(value) ~= "number" and type(value) ~= "string" then
        return nil
    end
    local number = tonumber(value)
    if number and number == number and number > -math.huge and number < math.huge then
        return number
    end
end

-- Application ID range: nonnegative signed 32-bit integers. Never round an ID.
-- Empty editor text means zero; absent saved fields remain absent.
function NS:ParseID(value, minimum, maximum)
    local number = FiniteNumber(value)
    if number and number >= (minimum or 0) and number <= (maximum or 2147483647)
        and number == math.floor(number) then
        return number
    end
end

local ENTRY_IDS = {
    itemID = 0, spellID = 0, useSpellID = 1, enchantID = 1,
    requiredEquippedItemID = 1, inventorySlot = 1,
}
local ENTRY_STRINGS = { id = true, label = true, category = true, macrotext = true }
local ENTRY_BOOLEANS = { enabled = true, builtin = true, hideWhenMissing = true }
local SEMANTIC_FIELDS = {
    itemID = true, spellID = true, useSpellID = true, enchantID = true,
    requiredEquippedItemID = true, inventorySlot = true, action = true, macrotext = true,
    builtin = true,
}

local function CopyEntry(entry)
    -- Saved entries are a flat schema. Unknown fields (including nested/cyclic
    -- data) never enter a recursive copier or the applied combat snapshot.
    local copy, malformedSemantics = {}, false
    for key, value in next, entry do
        local normalized
        if ENTRY_IDS[key] ~= nil then
            -- Supported equipment/profession slots: 1..28. The profession
            -- slots are defined in Blizzard_ProfessionsCrafting.xml (20..28);
            -- this is not a claim about every native API inventory position.
            normalized = NS:ParseID(value, ENTRY_IDS[key], key == "inventorySlot" and 28 or nil)
        elseif ENTRY_STRINGS[key] and type(value) == "string" then
            normalized = value
        elseif ENTRY_BOOLEANS[key] and type(value) == "boolean" then
            normalized = value
        elseif key == "action" and (value == "item" or value == "toy" or value == "macro") then
            normalized = value
        end
        copy[key] = normalized
        if normalized == nil and SEMANTIC_FIELDS[key] then
            malformedSemantics = true
        end
    end
    return copy, malformedSemantics
end

local function CreateDefaultEntries()
    local entries = {}
    for index, entry in ipairs(NS.BUILTIN_ENTRIES) do
        entries[index] = CopyEntry(entry)
    end
    return entries
end

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local FRAME_RANGES = { scale = { 0.5, 2 }, iconSize = { 24, 72 }, spacing = { 0, 20 } }

local function NormalizeFrame(frame)
    local normalized = {}
    if type(frame) ~= "table" then frame = {} end
    for key, default in pairs(NS.DEFAULT_FRAME) do
        local value = rawget(frame, key)
        if key == "point" or key == "relativePoint" then
            value = type(value) == "string" and ANCHORS[value] and value or default
        elseif type(default) == "boolean" then
            if type(value) ~= "boolean" then value = default end
        else
            value = FiniteNumber(value) or default
            local range = FRAME_RANGES[key]
            if range then value = math.max(range[1], math.min(range[2], value)) end
        end
        normalized[key] = value
    end
    return normalized
end

local function ValidEntryID(id)
    return type(id) == "string" and id:find("%S") ~= nil
end

local function NormalizeEntries(source, db)
    local entries, candidates, indices = {}, {}, {}
    if type(source) ~= "table" then return entries, {} end
    for key, value in next, source do
        if type(key) == "number" and FiniteNumber(key) and key >= 1 and key == math.floor(key)
            and type(value) == "table" then
            indices[#indices + 1] = key
        end
    end
    table.sort(indices)

    -- Reserve all original IDs before generating replacements, including IDs
    -- later in a sparse list and built-ins that will be appended below.
    local reserved, used, seenTables, migrationBlocked = {}, {}, {}, {}
    for _, builtin in ipairs(NS.BUILTIN_ENTRIES) do reserved[builtin.id] = true end
    for _, index in ipairs(indices) do
        local entry = rawget(source, index)
        local copy, malformed = CopyEntry(entry)
        candidates[#candidates + 1] = { original = entry, copy = copy, malformed = malformed }
        if ValidEntryID(copy.id) then reserved[copy.id] = true end
    end

    local serial = 0
    for _, candidate in ipairs(candidates) do
        local copy, original = candidate.copy, candidate.original
        if not ValidEntryID(copy.id) or used[copy.id] then
            repeat
                serial = serial + 1
                copy.id = "recovered-" .. serial
            until not reserved[copy.id]
            reserved[copy.id] = true
            -- A recovered identity cannot claim to be a stock definition.
            copy.builtin = false
        end
        used[copy.id] = true
        -- Keep valid entry identity for editors/migrations. Shared references
        -- and references to the DB containers must become independent entries.
        local entry = copy
        if not seenTables[original] and original ~= source and original ~= db
            and original ~= db.frame then
            for key in next, original do rawset(original, key, nil) end
            for key, value in pairs(copy) do rawset(original, key, value) end
            entry = original
        end
        seenTables[original] = true
        migrationBlocked[entry] = candidate.malformed
        entries[#entries + 1] = entry
    end
    return entries, migrationBlocked
end

local function MigrateLegacySpikesnail(entry)
    -- Correct only the stock tracking/action definition. Keep display
    -- preferences, enabled state and ordering; leave semantic overrides alone.
    if entry.id == "pointed-spikesnail" and entry.builtin == true
        and entry.itemID == 262651 and entry.spellID == 1284999
        and entry.action == "macro" and entry.macrotext == "/use item:262651\n/use 28"
        and entry.requiredEquippedItemID == 244790
        and entry.useSpellID == nil and entry.enchantID == nil and entry.inventorySlot == nil then
        entry.spellID = nil
        entry.useSpellID = 1284999
        entry.enchantID = 8675
        entry.inventorySlot = 28
    end
end

local function MigrateLegacyCrystallinePhial(entry)
    -- Match the stock tracking/action definition without changing display preferences.
    if entry.id == "crystalline-phial" and entry.builtin == true
        and entry.itemID == 191354 and entry.spellID == 371454 and entry.action == "item"
        and entry.macrotext == nil and entry.requiredEquippedItemID == nil
        and entry.useSpellID == nil and entry.enchantID == nil and entry.inventorySlot == nil then
        entry.spellID = 393714
        entry.useSpellID = 371454
    end
end

local function MergeNewBuiltins(entries, migrateLegacy, migrationBlocked)
    local known = {}
    for _, entry in ipairs(entries) do
        if migrateLegacy and not migrationBlocked[entry] then
            MigrateLegacySpikesnail(entry)
            MigrateLegacyCrystallinePhial(entry)
        end
        known[entry.id] = true
    end

    for _, builtin in ipairs(NS.BUILTIN_ENTRIES) do
        if not known[builtin.id] then
            entries[#entries + 1] = CopyEntry(builtin)
        end
    end
end

function NS:InitializeDB()
    if type(FishingBuffTrackerDB) ~= "table" then
        FishingBuffTrackerDB = {}
    end

    local db = FishingBuffTrackerDB
    local previousVersion = self:ParseID(db.version) or 0
    local frame = NormalizeFrame(db.frame)
    local entries, migrationBlocked = NormalizeEntries(db.entries, db)
    -- Normalizing malformed optional fields to nil must not accidentally turn
    -- an override into a stock migration match, now or on the next reload.
    MergeNewBuiltins(entries, previousVersion < 2, migrationBlocked)
    db.frame = frame
    db.entries = entries
    db.version = NS.DB_VERSION
    self.db = db
end

function NS:GetEntries()
    return self.db and self.db.entries or {}
end

function NS:CopyEntries()
    local entries = {}
    for _, entry in ipairs(self:GetEntries()) do
        if type(entry) == "table" then
            entries[#entries + 1] = CopyEntry(entry)
        end
    end
    return entries
end

function NS:GetAppliedEntries()
    -- Runtime tracking/status follows the same detached entries as the buttons.
    -- Before the bar exists, status can still inspect the initialized settings.
    return self.Bar and self.Bar.appliedEntries or self:GetEntries()
end

function NS:ResetEntries()
    if self.Config then
        self.Config:CancelEdits()
    end
    self.db.entries = CreateDefaultEntries()
    self:RequestRebuild()
end

function NS:ResetFramePosition()
    if InCombatLockdown() then
        self.positionResetPending = true
        return
    end

    self.positionResetPending = nil
    self:StopBarMoving()
    local frame = self.db.frame
    frame.point = NS.DEFAULT_FRAME.point
    frame.relativePoint = NS.DEFAULT_FRAME.relativePoint
    frame.x = NS.DEFAULT_FRAME.x
    frame.y = NS.DEFAULT_FRAME.y

    if self.Bar then
        self.Bar:ClearAllPoints()
        self.Bar:SetPoint(frame.point, UIParent, frame.relativePoint, frame.x, frame.y)
    end
end

function NS:SetBarVisible(visible)
    visible = visible and true or false
    self.db.frame.visible = visible

    if not visible then
        self:StopBarMoving()
    end
    if InCombatLockdown() then
        self.visibilityPending = visible
        self:Print("状态栏显隐将在战斗结束后更新。")
        return false
    end

    self.visibilityPending = nil
    if self.Bar then
        self.Bar:SetShown(visible)
        if visible then
            self:Refresh()
        end
    end

    if self.Config and self.Config.Refresh and self.Config:IsShown() then
        self.Config:Refresh()
    end
    return true
end

-- Check API values before even testing their truthiness or type. Table access
-- and field access are separate permissions in Retail; neither implies the other.
local function CanReadValue(value)
    if issecretvalue and issecretvalue(value) then
        return false
    end
    if canaccessvalue and not canaccessvalue(value) then
        return false
    end
    return true
end

local function ReadField(data, key, expectedType, alternateType)
    if not CanReadValue(data) or type(data) ~= "table" then
        return nil
    end
    if canaccesstable and not canaccesstable(data) then
        return nil
    end
    local value = data[key]
    if not CanReadValue(value) then
        return nil
    end
    local valueType = type(value)
    if valueType == expectedType or valueType == alternateType then
        return value
    end
end

-- Result contract: nil = missing, unknown = unconfirmed presence. A matched
-- snapshot stays active even when individual display fields are nil (unknown).
local function ScanWatchedAuras(watched, stopOnMatch)
    local active = {}
    local incomplete = false

    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
        local spellID = ReadField(aura, "spellId", "number")
        if not spellID then
            incomplete = true
        elseif watched[spellID] then
            -- Only these checked scalars reach UI/timer consumers. Never retain
            -- the API table: an unrelated secret field must not poison a match.
            active[spellID] = {
                spellId = spellID,
                icon = ReadField(aura, "icon", "number", "string"),
                expirationTime = ReadField(aura, "expirationTime", "number"),
                applications = ReadField(aura, "applications", "number"),
            }
            return stopOnMatch
        end
    end, true)

    -- An unidentified aura could be any unseen tracked spell. Keep readable
    -- matches, but do not infer absence from a partial scan.
    if incomplete then
        for spellID in pairs(watched) do
            if not active[spellID] then
                active[spellID] = { unknown = true }
            end
        end
    end
    return active
end

function NS:FindAura(spellID)
    if not CanReadValue(spellID) then
        return { unknown = true }
    end
    if type(spellID) ~= "number" or spellID <= 0 then
        return nil
    end
    return ScanWatchedAuras({ [spellID] = true }, true)[spellID]
end

function NS:ScanAuras()
    local watched = {}

    for _, entry in ipairs(self:GetAppliedEntries()) do
        if entry.enabled and not entry.enchantID and entry.spellID and entry.spellID > 0 then
            watched[entry.spellID] = true
        end
    end

    return ScanWatchedAuras(watched)
end

function NS:GetEntryEffect(entry, activeAuras)
    if not entry.enchantID then
        return (activeAuras or self:ScanAuras())[entry.spellID]
    end

    if not entry.inventorySlot or not C_PaperDollInfo or not C_PaperDollInfo.GetTemporaryEnchantmentInfo then
        return { unknown = true }
    end
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(entry.inventorySlot)
    if not CanReadValue(info) then
        return { unknown = true }
    end
    if info == nil then
        return nil
    end
    local enchantID = ReadField(info, "enchantID", "number")
    if not enchantID then
        return { unknown = true }
    end
    if enchantID ~= entry.enchantID then
        return nil
    end

    local expirationTime
    local hasExpirationTime = ReadField(info, "hasExpirationTime", "boolean")
    if hasExpirationTime == false then
        expirationTime = 0
    elseif hasExpirationTime then
        local remainingTimeMs = ReadField(info, "remainingTimeMs", "number")
        if remainingTimeMs and remainingTimeMs <= 0 then
            return nil
        end
        if remainingTimeMs then
            expirationTime = GetTime() + remainingTimeMs / 1000
        end
    end
    return {
        enchantID = enchantID,
        expirationTime = expirationTime,
        chargesRemaining = ReadField(info, "chargesRemaining", "number"),
    }
end

function NS:GetItemCount(entry)
    if entry.action == "toy" then
        return entry.itemID and entry.itemID > 0 and PlayerHasToy(entry.itemID) and 1 or 0
    end

    if not entry.itemID or entry.itemID <= 0 then
        return 0
    end
    return C_Item.GetItemCount(entry.itemID, false, false, false, false)
end

function NS:IsRequiredEquipmentReady(entry)
    if not entry.requiredEquippedItemID then
        return true
    end
    return GetInventoryItemID("player", 28) == entry.requiredEquippedItemID
end

function NS:Refresh()
    if self.Bar and self.Bar.Refresh then
        self.Bar:Refresh()
    end
    if self.Config and self.Config.Refresh and self.Config:IsShown() then
        self.Config:Refresh()
    end
end

function NS:RequestRebuild()
    if InCombatLockdown() then
        self.rebuildPending = true
        self:Refresh()
        return
    end

    self.rebuildPending = nil
    if self.Bar and self.Bar.Rebuild then
        self.Bar:Rebuild()
    end
    if self.Config and self.Config.Refresh then
        self.Config:Refresh()
    end
end

function NS:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffFishing Buff Tracker:|r " .. tostring(message))
end

function NS:PrintStatus()
    local activeAuras = self:ScanAuras()
    self:Print("当前已应用条目状态：")
    if self.rebuildPending then
        self:Print("设置更改将在战斗结束后应用。")
    end
    for _, entry in ipairs(self:GetAppliedEntries()) do
        if entry.enabled then
            local effect = self:GetEntryEffect(entry, activeAuras)
            local state = effect and (effect.unknown and "|cff99bbffUNKNOWN|r" or "|cff33ff66ACTIVE|r")
                or "|cffffaa33MISSING|r"
            local count = self:GetItemCount(entry)
            local equipment = self:IsRequiredEquipmentReady(entry) and "" or "，渔竿不匹配"
            local tracking = entry.enchantID
                and string.format("EnchantID %s，栏位 %s，UseSpellID %s",
                    tostring(entry.enchantID), tostring(entry.inventorySlot), tostring(entry.useSpellID or 0))
                or "SpellID " .. tostring(entry.spellID or 0)
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %s: %s，%s，物品数量 %d%s",
                entry.label or entry.id,
                state,
                tracking,
                count,
                equipment
            ))
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PROFESSION_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then
            return
        end
        NS:InitializeDB()
        return
    end

    if event == "PLAYER_LOGIN" then
        NS:CreateBar()
        NS:CreateConfig()
        NS:RequestRebuild()
        return
    end

    if event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then
            NS:Refresh()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Save the completed drag before queued changes; an explicit reset wins.
        if NS.barStopPending then
            NS:StopBarMoving()
        end
        if NS.positionResetPending then
            NS:ResetFramePosition()
        end
        if NS.visibilityPending ~= nil then
            NS:SetBarVisible(NS.visibilityPending)
        end
        if NS.rebuildPending then
            NS:RequestRebuild()
        else
            NS:Refresh()
        end
        return
    end

    NS:Refresh()
end)

SLASH_FISHINGBUFFTRACKER1 = "/fbt"
SLASH_FISHINGBUFFTRACKER2 = "/钓鱼buff"
SLASH_FISHINGBUFFTRACKER3 = "/fishingbuff"
SlashCmdList.FISHINGBUFFTRACKER = function(input)
    local command = strtrim(input or ""):lower()

    if command == "" or command == "config" then
        NS:OpenConfig()
    elseif command == "show" then
        if NS:SetBarVisible(true) then
            NS:Print("状态栏已显示。")
        end
    elseif command == "hide" then
        if NS:SetBarVisible(false) then
            NS:Print("状态栏已隐藏，可使用 /fbt show 或控制台重新打开。")
        end
    elseif command == "reset" then
        NS:ResetFramePosition()
        NS:Print("状态栏位置已重置。")
    elseif command == "lock" then
        NS.db.frame.locked = true
        NS:Refresh()
        NS:Print("状态栏已锁定。")
    elseif command == "unlock" then
        NS.db.frame.locked = false
        NS:Refresh()
        NS:Print("状态栏已解锁，可拖动左侧手柄移动。")
    elseif command == "defaults" then
        NS:ResetEntries()
        NS:Print("内置 Buff 列表已恢复。")
    elseif command == "status" then
        NS:PrintStatus()
    else
        NS:Print("命令：/fbt config、show、hide、lock、unlock、reset、defaults、status")
        NS:OpenConfig()
    end
end
