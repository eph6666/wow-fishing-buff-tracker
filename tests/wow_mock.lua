-- A deliberately bounded WoW model for local regression tests, not a client emulator.
-- Unknown methods remain nil. Cosmetic methods are explicitly listed below.
local Mock = {}
local unpackValues = unpack or table.unpack

function Mock.new(addonPath, savedVariables)
    local state = {
        frames = {}, regions = {}, messages = {}, auras = {}, counts = {},
        icons = {}, cooldowns = {}, toys = {}, equippedItemID = 244790,
        enchantments = {}, enchantmentQueries = {},
        combat = false, now = 100, auraScans = 0,
    }
    local env = setmetatable({}, { __index = _G })
    local Widget = {}
    Widget.__index = Widget
    state.env = env
    local sizeWatchers, scrollFrames = {}, {}

    -- Solve unscaled rectangular anchors in each axis, including opposing
    -- anchors and SetAllPoints. Font extents are estimates, not raster metrics.
    -- This intentionally excludes XML inheritance, pixel rounding and rendering.
    local function fraction(point, horizontal)
        if point:find(horizontal and "LEFT" or "BOTTOM", 1, true) then return 0 end
        if point:find(horizontal and "RIGHT" or "TOP", 1, true) then return 1 end
        return 0.5
    end
    local function axis(widget, horizontal, resolving)
        if not widget then return 0, 0 end
        resolving = resolving or {}
        assert(not resolving[widget], "cyclic mock anchors")
        resolving[widget] = true
        local size = horizontal and widget.width or widget.height
        if size == 0 and widget.kind == "FontString" then
            if horizontal then
                for char in widget:GetText():gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                    size = size + (#char == 1 and 6 or 12)
                end
            else
                size = 14
            end
        end
        local firstFraction, firstTarget, otherFraction, otherTarget
        for _, anchor in pairs(widget.points) do
            local position, relativeSize = axis(anchor[2], horizontal, resolving)
            local ownFraction = fraction(anchor[1], horizontal)
            local target = position + fraction(anchor[3], horizontal) * relativeSize
                + anchor[horizontal and 4 or 5]
            if not firstFraction then
                firstFraction, firstTarget = ownFraction, target
            elseif ownFraction ~= firstFraction then
                otherFraction, otherTarget = ownFraction, target
            end
        end
        if otherFraction then
            size = math.max(0, (otherTarget - firstTarget) / (otherFraction - firstFraction))
        end
        local position = firstFraction and firstTarget - firstFraction * size or 0
        if not horizontal and widget.scrollOwner then
            -- Positive vertical scroll moves content up (WoW's Y axis is up).
            position = position + widget.scrollOwner:GetVerticalScroll()
        end
        resolving[widget] = nil
        return position, size
    end

    -- Native layout callbacks can be deferred. This model settles them after
    -- mutations; tests also check OnShow after a detached/hidden canvas resizes.
    local layoutRunning, layoutDirty
    local function geometryChanged()
        layoutDirty = true
        if layoutRunning then return end
        layoutRunning = true
        local passes = 0
        while layoutDirty do
            layoutDirty = false
            passes = passes + 1
            assert(passes < 30, "mock layout did not settle")
            for _, widget in ipairs(sizeWatchers) do
                local width, height = widget:GetWidth(), widget:GetHeight()
                if width ~= widget.lastWidth or height ~= widget.lastHeight then
                    widget.lastWidth, widget.lastHeight = width, height
                    local callback = widget.scripts.OnSizeChanged
                    if callback then callback(widget, width, height) end
                end
            end
            for _, scroll in ipairs(scrollFrames) do
                local range = scroll:GetVerticalScrollRange()
                if range ~= scroll.lastRange then
                    scroll.lastRange = range
                    local callback = scroll.scripts.OnScrollRangeChanged
                    if callback then callback(scroll, 0, range) end
                end
            end
        end
        layoutRunning = false
    end

    local function newWidget(kind, parent, template)
        local widget = setmetatable({
            kind = kind, parent = parent, template = template,
            scripts = {}, attributes = {}, events = {}, shown = true,
            points = {}, width = 0, height = 0,
            secure = template == "SecureActionButtonTemplate",
        }, Widget)
        local collection = (kind == "Texture" or kind == "FontString") and state.regions or state.frames
        collection[#collection + 1] = widget
        return widget
    end

    local function isProtected(widget)
        if widget.secure then return true end
        for _, frame in ipairs(state.frames) do
            if frame.secure then
                local parent = frame.parent
                while parent do
                    if parent == widget then return true end
                    parent = parent.parent
                end
            end
        end
        return false
    end

    local function guard(widget, method)
        assert(not state.combat or not isProtected(widget),
            "protected mutation in combat: " .. method)
    end

    function Widget:SetScript(name, callback)
        self.scripts[name] = callback
        if name == "OnSizeChanged" and not self.watchesSize then
            self.watchesSize = true
            self.lastWidth, self.lastHeight = self:GetWidth(), self:GetHeight()
            sizeWatchers[#sizeWatchers + 1] = self
        end
    end
    function Widget:GetScript(name) return self.scripts[name] end
    function Widget:RegisterEvent(name) self.events[name] = true end
    function Widget:UnregisterEvent(name) self.events[name] = nil end
    function Widget:RegisterUnitEvent(name, ...) self.events[name] = { ... } end
    function Widget:SetParent(parent)
        guard(self, "SetParent")
        self.parent = parent
        geometryChanged()
    end
    function Widget:GetParent() return self.parent end
    function Widget:GetName() return self.widgetName end
    function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
        guard(self, "SetPoint")
        if type(relativeTo) == "number" then
            x, y, relativeTo, relativePoint = relativeTo, relativePoint, self.parent, point
        elseif type(relativePoint) == "number" then
            x, y, relativePoint = relativePoint, x, point
        end
        self.point = { point, relativeTo or self.parent, relativePoint or point, x or 0, y or 0 }
        self.points[point] = self.point
        geometryChanged()
    end
    function Widget:GetPoint() return unpackValues(self.point) end
    function Widget:ClearAllPoints()
        guard(self, "ClearAllPoints")
        self.points, self.point, self.allPoints = {}, nil, nil
        geometryChanged()
    end
    function Widget:SetAllPoints(target)
        guard(self, "SetAllPoints")
        self.allPoints = target or self.parent
        self.points = {
            TOPLEFT = { "TOPLEFT", self.allPoints, "TOPLEFT", 0, 0 },
            BOTTOMRIGHT = { "BOTTOMRIGHT", self.allPoints, "BOTTOMRIGHT", 0, 0 },
        }
        self.point = self.points.TOPLEFT
        geometryChanged()
    end
    function Widget:SetSize(width, height)
        guard(self, "SetSize")
        self.width, self.height = width, height
        geometryChanged()
    end
    function Widget:SetWidth(width)
        guard(self, "SetWidth"); self.width = width; geometryChanged()
    end
    function Widget:SetHeight(height)
        guard(self, "SetHeight"); self.height = height; geometryChanged()
    end
    function Widget:GetWidth() local _, size = axis(self, true); return size end
    function Widget:GetHeight() local _, size = axis(self, false); return size end
    function Widget:GetLeft() return (axis(self, true)) end
    function Widget:GetBottom() return (axis(self, false)) end
    function Widget:GetRight() return self:GetLeft() + self:GetWidth() end
    function Widget:GetTop() return self:GetBottom() + self:GetHeight() end
    function Widget:SetScale(value) guard(self, "SetScale"); self.scale = value end
    function Widget:SetShown(value)
        guard(self, "SetShown")
        value = value and true or false
        if self.shown == value then return end
        local wasVisible = {}
        for _, frame in ipairs(state.frames) do
            wasVisible[frame] = frame:IsVisible()
        end
        self.shown = value
        -- Model inherited visibility. Exercise either focus-loss/OnHide order;
        -- this is a lifecycle stress model, not a claim about native ordering.
        local function clearHiddenFocus()
            if state.focus and not state.focus:IsVisible() then state.focus:ClearFocus() end
        end
        if state.hideFocusBeforeScripts then clearHiddenFocus() end
        for _, frame in ipairs(state.frames) do
            local visible = frame:IsVisible()
            if wasVisible[frame] ~= nil and wasVisible[frame] ~= visible then
                local callback = frame.scripts[visible and "OnShow" or "OnHide"]
                if callback then callback(frame) end
            end
        end
        clearHiddenFocus()
    end
    function Widget:Show() self:SetShown(true) end
    function Widget:Hide() self:SetShown(false) end
    function Widget:IsShown() return self.shown end
    function Widget:IsVisible()
        return self.shown and (not self.parent or self.parent:IsVisible())
    end
    function Widget:SetMovable(value) self.movable = value end
    function Widget:IsMovable() return self.movable end
    function Widget:StartMoving() guard(self, "StartMoving"); self.moving = true end
    function Widget:StopMovingOrSizing() guard(self, "StopMovingOrSizing"); self.moving = false end
    function Widget:SetText(value) self.text = tostring(value or "") end
    function Widget:GetText() return self.text or "" end
    function Widget:SetChecked(value) self.checked = value and true or false end
    function Widget:GetChecked() return self.checked end
    function Widget:SetAttribute(key, value)
        guard(self, "SetAttribute")
        self.attributes[key] = value
    end
    function Widget:GetAttribute(key) return self.attributes[key] end
    function Widget:RegisterForClicks(...) self.registeredClicks = { ... } end
    function Widget:RegisterForDrag(...) self.registeredDrags = { ... } end
    function Widget:EnableMouse(value) self.mouseEnabled = value end
    function Widget:SetEnabled(value) self.enabled = value end
    function Widget:Enable() self:SetEnabled(true) end
    function Widget:Disable() self:SetEnabled(false) end
    function Widget:SetDesaturated(value) self.desaturated = value end
    function Widget:SetTexture(value) self.texture = value end
    function Widget:SetVertexColor(...) self.vertexColor = { ... } end
    function Widget:SetAlpha(value) self.alpha = value end
    function Widget:SetCooldown(start, duration) self.cooldown = { start, duration } end
    function Widget:Clear() self.cooldown = nil end
    function Widget:CreateTexture() return newWidget("Texture", self) end
    function Widget:CreateFontString(_, _, template) return newWidget("FontString", self, template) end
    function Widget:SetScrollChild(child)
        self.scrollChild, child.scrollOwner = child, self
        child:SetParent(self)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    end
    function Widget:GetVerticalScroll() return self.verticalScroll or 0 end
    function Widget:GetVerticalScrollRange()
        return math.max(0, (self.scrollChild and self.scrollChild:GetHeight() or 0) - self:GetHeight())
    end
    function Widget:SetVerticalScroll(value)
        if self:GetVerticalScroll() == value then return end
        self.verticalScroll = value
        if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, value) end
    end
    function Widget:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function Widget:GetMinMaxValues() return self.minimum or 0, self.maximum or 0 end
    function Widget:GetValue() return self.value or 0 end
    function Widget:SetValue(value)
        value = math.max(self.minimum or 0, math.min(self.maximum or 0, value))
        if self:GetValue() == value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function Widget:HasFocus() return state.focus == self end
    function Widget:SetFocus()
        if state.focus == self then return end
        if state.focus then state.focus:ClearFocus() end
        state.focus = self
        if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
    end
    function Widget:ClearFocus()
        if state.focus == self then
            state.focus = nil
            if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
    end
    function Widget:SetHyperlink(value) self.hyperlink = value end
    function Widget:SetSpellByID(value) self.spellID = value end
    function Widget:AddLine(value) self.lines[#self.lines + 1] = value end
    function Widget:SetOwner(owner) self.owner, self.lines = owner, {} end
    function Widget:IsOwned(owner) return self.owner == owner end
    function Widget:AddMessage(value) state.messages[#state.messages + 1] = value end

    local cosmeticMethods = {
        "SetTexCoord", "SetBlendMode", "SetDrawEdge", "SetDrawBling",
        "SetTextColor", "SetShadowOffset", "SetClampedToScreen", "SetFrameStrata",
        "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetColorTexture",
        "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetTextInsets", "SetJustifyH",
    }
    for _, method in ipairs(cosmeticMethods) do Widget[method] = function() end end

    env.CreateFrame = function(kind, name, parent, template)
        assert(not state.combat or template ~= "SecureActionButtonTemplate",
            "protected frame creation in combat")
        local frame = newWidget(kind or "Frame", parent, template)
        frame.widgetName = name
        if name then env[name] = frame end
        if template == "UIPanelScrollFrameTemplate" then
            -- Bounded version of SecureScrollTemplates.xml/.lua. The source
            -- contract replaces these callbacks with Blizzard's actual Lua.
            local bar = newWidget("Slider", frame)
            frame.ScrollBar = bar
            bar:SetWidth(16)
            bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, -16)
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 16)
            bar.ScrollUpButton = newWidget("Button", bar)
            bar.ScrollDownButton = newWidget("Button", bar)
            bar.ScrollUpButton:SetSize(16, 16)
            bar.ScrollDownButton:SetSize(16, 16)
            bar.ScrollUpButton:SetPoint("BOTTOM", bar, "TOP", 0, 0)
            bar.ScrollDownButton:SetPoint("TOP", bar, "BOTTOM", 0, 0)
            bar.ThumbTexture = newWidget("Texture", bar)
            bar:SetScript("OnValueChanged", function(_, value) frame:SetVerticalScroll(value) end)
            frame:SetScript("OnScrollRangeChanged", function(_, _, range)
                bar:SetMinMaxValues(0, math.floor(range))
                bar:SetValue(math.min(bar:GetValue(), math.floor(range)))
            end)
            frame:SetScript("OnVerticalScroll", function(_, offset) bar:SetValue(offset) end)
            frame:SetScript("OnMouseWheel", function(_, delta)
                bar:SetValue(bar:GetValue() - (delta > 0 and 1 or -1) * (bar.scrollStep or bar:GetHeight() / 2))
            end)
            scrollFrames[#scrollFrames + 1] = frame
        end
        return frame
    end
    env.UIParent = newWidget("Frame")
    env.UIParent:SetSize(1920, 1080)
    env.DEFAULT_CHAT_FRAME = newWidget("Frame")
    env.GameTooltip = newWidget("Tooltip")
    env.GameTooltip_Hide = function() env.GameTooltip:Hide() end
    env.SlashCmdList = {}
    env.FishingBuffTrackerDB = savedVariables
    env.InCombatLockdown = function() return state.combat end
    env.GetTime = function() return state.now end
    env.time = function() return 1 end
    env.strtrim = function(value) return value:match("^%s*(.-)%s*$") end
    env.wipe = function(value) for key in pairs(value) do value[key] = nil end end
    env.PlayerHasToy = function(itemID) return state.toys[itemID] ~= false end
    env.GetInventoryItemID = function(unit, slot)
        assert(unit == "player" and slot == 28, "unexpected equipment query")
        return state.equippedItemID
    end
    env.AuraUtil = {
        ForEachAura = function(unit, filter, _, callback, packed)
            assert(unit == "player" and filter == "HELPFUL" and packed, "unexpected aura query")
            state.auraScans = state.auraScans + 1
            for _, aura in ipairs(state.auras) do
                if callback(aura) then return end
            end
        end,
    }
    env.C_Item = {
        GetItemCount = function(itemID, bank, uses, reagentBank, accountBank)
            assert(not bank and not uses and not reagentBank and not accountBank,
                "unexpected item count flags")
            return state.counts[itemID] or 0
        end,
        GetItemIconByID = function(itemID) return state.icons[itemID] or 134400 end,
        GetItemCooldown = function(itemID)
            local value = state.cooldowns[itemID]
            if value then return unpackValues(value) end
            return 0, 0, false
        end,
    }
    env.C_PaperDollInfo = {
        GetTemporaryEnchantmentInfo = function(slot)
            assert(type(slot) == "number", "expected an inventory slot")
            state.enchantmentQueries[#state.enchantmentQueries + 1] = slot
            return state.enchantments[slot]
        end,
    }
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel)
            state.categoryPanel = panel
            return { GetID = function() return 1 end }
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function()
            -- Target 12.1.0 SettingsPanelMixin:DisplayLayout uses SetAllPoints.
            local canvas = state.settingsCanvas
            if not canvas then
                canvas = newWidget("Frame")
                canvas:SetSize(665, 601)
                state.settingsCanvas = canvas
            end
            state.categoryPanel:SetParent(canvas)
            state.categoryPanel:ClearAllPoints()
            state.categoryPanel:SetAllPoints(canvas)
            state.categoryPanel:Show()
        end,
    }
    function state:fire(event, ...)
        for _, frame in ipairs(self.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, event, ...)
            end
        end
    end
    function state:script(widget, name, ...)
        return assert(widget:GetScript(name), name .. " is not registered")(widget, ...)
    end
    function state:command(command) self.env.SlashCmdList.FISHINGBUFFTRACKER(command) end
    function state:login()
        self:fire("ADDON_LOADED", "FishingBuffTracker")
        self:fire("PLAYER_LOGIN")
    end
    function state:secureFrameCount()
        local count = 0
        for _, frame in ipairs(self.frames) do if frame.secure then count = count + 1 end end
        return count
    end
    function state:button(id)
        for _, button in ipairs(self.ns.Bar.buttons) do
            if button.entry.id == id then return button end
        end
    end
    state.ns = {}
    -- Use the manifest itself so changes in load order are exercised.
    for line in assert(io.open(addonPath .. "/FishingBuffTracker.toc")):lines() do
        if line:match("%.lua%s*$") then
            local filename = line:match("^%s*(.-)%s*$")
            local chunk = assert(loadfile(addonPath .. "/" .. filename))
            setfenv(chunk, env)
            chunk("FishingBuffTracker", state.ns)
        end
    end
    return state
end

-- F03: strict sentinels/accessor stubs, NOT WoW secret values. Standard Lua
-- cannot trap truthiness or the use of a value as a table key, nor model taint.
-- These stubs reject premature table reads, type checks and common operations;
-- behavioral assertions must also check unknown vs missing and sanitized fields.
function Mock.restrictedAPI(state)
    local records = {}
    local access = { tableChecks = 0, valueChecks = 0, secretChecks = 0 }
    local function reject()
        error("strict restricted-data sentinel used without sanitizing", 2)
    end

    function access:value(secret, readable)
        local value = newproxy(true)
        local mt = getmetatable(value)
        for _, operation in ipairs({
            "__index", "__newindex", "__add", "__sub", "__mul", "__div",
            "__mod", "__pow", "__unm", "__lt", "__le", "__eq", "__concat", "__tostring",
        }) do
            mt[operation] = reject
        end
        records[value] = { secret = secret ~= false, readable = readable == true }
        return value
    end

    function access:table(fields, options)
        options = options or {}
        local record = {
            secret = options.secret == true,
            readable = options.readable ~= false,
            tableReadable = options.tableReadable ~= false,
            reads = {},
        }
        local value = setmetatable({}, {
            __index = function(_, key)
                assert(record.tableChecked, "strict accessor: canaccesstable required before indexing")
                record.tableChecked = false
                assert(record.readable and record.tableReadable and not record.secret,
                    "strict accessor: inaccessible table was indexed")
                assert(not options.allowedFields or options.allowedFields[key],
                    "strict accessor: unrelated field was read: " .. key)
                record.reads[#record.reads + 1] = key
                return fields[key]
            end,
            __newindex = function() error("API table was mutated") end,
        })
        records[value] = record
        return value, record
    end

    state.env.issecretvalue = function(value)
        access.secretChecks = access.secretChecks + 1
        local record = records[value]
        return record ~= nil and record.secret
    end
    state.env.canaccessvalue = function(value)
        access.valueChecks = access.valueChecks + 1
        local record = records[value]
        return record == nil or record.readable
    end
    state.env.canaccesstable = function(value)
        access.tableChecks = access.tableChecks + 1
        local record = records[value]
        if record then
            record.tableChecked = true
            return record.readable and record.tableReadable == true
        end
        return type(value) == "table"
    end
    -- A userdata sentinel would otherwise be silently discarded by a number
    -- type check, concealing a missing access guard in the addon under test.
    state.env.type = function(value)
        local record = records[value]
        if record and (record.secret or not record.readable) then reject() end
        return type(value)
    end
    return access
end

return Mock
