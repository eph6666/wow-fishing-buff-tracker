local addonPath = assert(arg[1], "addon path is required")
local unpackValues = unpack or table.unpack
local frames = {}
local auraList = {}

local Widget = {}
Widget.__index = function(self, key)
    local method = Widget[key]
    if method then
        return method
    end
    return function()
    end
end

function Widget:SetScript(name, callback)
    self.scripts[name] = callback
end

function Widget:GetScript(name)
    return self.scripts[name]
end

-- Creation dimensions only; anchor/resize contracts live in wow_mock + audit.
function Widget:SetSize(width, height)
    self.width, self.height = width, height
end
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height) self.height = height end
function Widget:GetWidth() return rawget(self, "width") or 0 end
function Widget:GetHeight() return rawget(self, "height") or 0 end

function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end

function Widget:GetPoint()
    return unpackValues(self.point or { "CENTER", UIParent, "CENTER", 0, 0 })
end

function Widget:Show()
    self.shown = true
end

function Widget:Hide()
    self.shown = false
end

function Widget:SetShown(value)
    self.shown = value and true or false
end

function Widget:IsShown()
    return self.shown
end

function Widget:IsMovable()
    return true
end

function Widget:StartMoving()
    self.moving = true
end

function Widget:StopMovingOrSizing()
    self.moving = false
end

function Widget:SetText(value)
    self.text = tostring(value or "")
end

function Widget:GetText()
    return self.text or ""
end

function Widget:SetChecked(value)
    self.checked = value and true or false
end

function Widget:GetChecked()
    return self.checked
end

function Widget:SetAttribute(key, value)
    self.attributes[key] = value
end

function Widget:RegisterForClicks(...)
    self.registeredClicks = { ... }
end

function Widget:SetDesaturated(value)
    self.desaturated = value and true or false
end

function Widget:GetID()
    return self.id or 1
end

function Widget:CreateTexture()
    return setmetatable({ scripts = {}, attributes = {}, shown = true }, Widget)
end

function Widget:CreateFontString()
    return setmetatable({ scripts = {}, attributes = {}, shown = true }, Widget)
end

function CreateFrame()
    local frame = setmetatable({
        scripts = {},
        attributes = {},
        shown = true,
    }, Widget)
    table.insert(frames, frame)
    return frame
end

UIParent = CreateFrame()
DEFAULT_CHAT_FRAME = { AddMessage = function()
end }
GameTooltip = CreateFrame()
GameTooltip_Hide = function()
end
AuraUtil = {
    ForEachAura = function(_, _, _, callback)
        for _, aura in ipairs(auraList) do
            if callback(aura) then
                return
            end
        end
    end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID)
        for _, aura in ipairs(auraList) do
            if aura.spellId == spellID then
                return aura
            end
        end
    end,
}
C_Item = {
    GetItemCount = function()
        return 3
    end,
    GetItemIconByID = function()
        return 134400
    end,
    GetItemCooldown = function()
        return 0, 0, false
    end,
}
Settings = {
    RegisterCanvasLayoutCategory = function()
        return setmetatable({ id = 1, scripts = {}, attributes = {}, shown = true }, Widget)
    end,
    RegisterAddOnCategory = function()
    end,
    OpenToCategory = function()
    end,
}
SlashCmdList = {}
InCombatLockdown = function()
    return false
end
PlayerHasToy = function()
    return true
end
GetInventoryItemID = function()
    return 244790
end
GetTime = function()
    return 100
end
strtrim = function(value)
    return value:match("^%s*(.-)%s*$")
end
wipe = function(value)
    for key in pairs(value) do
        value[key] = nil
    end
end
time = function()
    return 1
end

local namespace = {}
for _, filename in ipairs({ "Data.lua", "Core.lua", "Bar.lua", "Config.lua" }) do
    local chunk = assert(loadfile(addonPath .. "/" .. filename))
    chunk("FishingBuffTracker", namespace)
end

local eventFrame
for _, frame in ipairs(frames) do
    if frame:GetScript("OnEvent") then
        eventFrame = frame
        break
    end
end
assert(eventFrame, "event frame was not created")

eventFrame:GetScript("OnEvent")(eventFrame, "ADDON_LOADED", "FishingBuffTracker")
eventFrame:GetScript("OnEvent")(eventFrame, "PLAYER_LOGIN")

assert(namespace.db, "database was not initialized")
assert(namespace.Bar, "bar was not created")
assert(namespace.Config, "config panel was not created")
assert(#namespace.Bar.buttons == #namespace.BUILTIN_ENTRIES, "built-in buttons were not created")
assert(namespace.Bar.buttons[1].attributes.type == "toy", "toy action was not configured")
assert(namespace.Bar.buttons[2].attributes.item == "item:241316", "item action was not configured")
assert(namespace.Bar.buttons[2].registeredClicks[1] == "AnyDown", "item action should receive mouse-down")
assert(namespace.Bar.buttons[2].registeredClicks[2] == "AnyUp", "item action should receive mouse-up")
assert(namespace.Bar.buttons[5].attributes.macrotext:find("/use 28", 1, true), "fishing tool macro is missing")
assert(namespace.Bar.dragHandle, "drag handle was not created")
assert(namespace.Bar.dragHandle:GetScript("OnDragStart"), "drag handle start script is missing")
assert(namespace.Bar.dragHandle:GetScript("OnDragStop"), "drag handle stop script is missing")

namespace.Bar.dragHandle:GetScript("OnDragStart")()
assert(namespace.Bar.moving == true, "drag handle should start moving the bar")
namespace.Bar.dragHandle:GetScript("OnDragStop")()
assert(namespace.Bar.moving == false, "drag handle should stop moving the bar")
assert(namespace.Bar.buttons[1].icon.desaturated == true, "missing buff icon should be desaturated")

auraList = {
    {
        spellId = 397827,
        icon = 12345,
        applications = 1,
        expirationTime = 200,
    },
}
namespace:Refresh()
assert(namespace.Bar.buttons[1].icon.desaturated == false, "active buff icon should be colored")

namespace.Bar.closeButton:GetScript("OnClick")()
assert(namespace.db.frame.visible == false, "close button should persist hidden state")
assert(namespace.Bar:IsShown() == false, "close button should hide the bar")

namespace:PrintStatus()
SlashCmdList.FISHINGBUFFTRACKER("show")
assert(namespace.Bar:IsShown() == true, "show command should display the bar")
SlashCmdList.FISHINGBUFFTRACKER("hide")
assert(namespace.Bar:IsShown() == false, "hide command should hide the bar")
SlashCmdList.FISHINGBUFFTRACKER("config")
SlashCmdList.FISHINGBUFFTRACKER("unlock")
SlashCmdList.FISHINGBUFFTRACKER("lock")
SlashCmdList.FISHINGBUFFTRACKER("reset")

print("PASS addon load and initialization smoke test")
