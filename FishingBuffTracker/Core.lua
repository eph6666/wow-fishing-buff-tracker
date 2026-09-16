local ADDON_NAME, NS = ...

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyValue(child)
    end
    return copy
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyValue(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function CreateDefaultEntries()
    return CopyValue(NS.BUILTIN_ENTRIES)
end

local function MergeNewBuiltins(entries)
    local known = {}
    for _, entry in ipairs(entries) do
        known[entry.id] = true
    end

    for _, builtin in ipairs(NS.BUILTIN_ENTRIES) do
        if not known[builtin.id] then
            table.insert(entries, CopyValue(builtin))
        end
    end
end

function NS:InitializeDB()
    if type(FishingBuffTrackerDB) ~= "table" then
        FishingBuffTrackerDB = {}
    end

    local db = FishingBuffTrackerDB
    db.version = NS.DB_VERSION

    if type(db.frame) ~= "table" then
        db.frame = {}
    end
    MergeDefaults(db.frame, NS.DEFAULT_FRAME)

    if type(db.entries) ~= "table" or #db.entries == 0 then
        db.entries = CreateDefaultEntries()
    else
        MergeNewBuiltins(db.entries)
    end

    self.db = db
end

function NS:GetEntries()
    return self.db and self.db.entries or {}
end

function NS:ResetEntries()
    self.db.entries = CreateDefaultEntries()
    self:RequestRebuild()
end

function NS:ResetFramePosition()
    if InCombatLockdown() then
        self.positionResetPending = true
        return
    end

    self.positionResetPending = nil
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

function NS:FindAura(spellID)
    if not spellID or spellID <= 0 then
        return nil
    end

    local found
    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
        if aura.spellId == spellID then
            found = aura
            return true
        end
    end, true)
    return found
end

function NS:ScanAuras()
    local watched = {}
    local active = {}

    for _, entry in ipairs(self:GetEntries()) do
        if entry.enabled and entry.spellID and entry.spellID > 0 then
            watched[entry.spellID] = true
        end
    end

    AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
        if watched[aura.spellId] then
            active[aura.spellId] = aura
        end
    end, true)

    return active
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
    self:Print("当前条目状态：")
    for _, entry in ipairs(self:GetEntries()) do
        if entry.enabled then
            local aura = activeAuras[entry.spellID]
            local state = aura and "|cff33ff66ACTIVE|r" or "|cffffaa33MISSING|r"
            local count = self:GetItemCount(entry)
            local equipment = self:IsRequiredEquipmentReady(entry) and "" or "，渔竿不匹配"
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %s: %s，SpellID %s，物品数量 %d%s",
                entry.label or entry.id,
                state,
                tostring(entry.spellID or 0),
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

    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            NS:Refresh()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
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
        NS:Print("状态栏已解锁，可拖拽图标移动。")
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
