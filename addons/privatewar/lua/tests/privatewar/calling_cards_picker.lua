-- Calling-card picker: exercise the screen's client callbacks through a controlled VGUI boundary.
---@return PW.CallingCardsLib
local function cards()
    return assert(PW.CallingCards)
end

---@param id string
---@return PW.UnlockRequirement
local function requirement(id)
    if id == "level_20" then
        return { unlocked = false, reason = "level", level = 20, lockText = "LV 20", text = "Unlocks at level 20" }
    end
    return { unlocked = true, reason = "default" }
end

---@return PW.UICard[]
local function catalogue()
    local card = assert(cards()._PickerCard, "picker does not build calling-card entries")
    return { card("default", "Recruit", requirement("default")), card("bomb", "Bomb", requirement("bomb")),
        card("level_20", "Veteran", requirement("level_20")) }
end

---@param id string
---@param rows PW.UICard[]
---@param writes { key: string, value: string }[]
---@return boolean
local function selectCard(id, rows, writes)
    local select = assert(cards()._SelectPickerCard, "picker does not implement selection")
    return select(rows, id, function(key, value)
        writes[#writes + 1] = { key = key, value = value }
        return true
    end)
end

local noop = function() end

---@param kind string
---@param parent? any
---@return any
local function fakePanel(kind, parent)
    ---@type any
    local panel = {
        kind = kind, parent = parent, visible = true, x = 0, y = 0, w = 0, h = 0,
        Dock = noop, SetCards = noop, SetVariant = noop, SetTextInset = noop,
        SetTitle = noop, SetRows = noop, SetWarning = noop, SetTooltip = noop, InvalidateLayout = noop,
        SetText = function(self, text) self.text = text end,
        SetLocked = function(self, locked, reason)
            self._locked = locked
            self._pwFocus.locked, self._pwFocus.reason = locked, reason
        end,
        SetPos = function(self, x, y) self.x, self.y = x, y end,
        SetSize = function(self, w, h) self.w, self.h = w, h end,
        SetVisible = function(self, visible) self.visible = visible end,
        IsVisible = function(self) return self.visible end,
        IsEnabled = function() return true end,
        GetParent = function(self) return self.parent end,
        GetCanvas = function(self) return self end,
        GetWide = function(self) return self.w end,
        GetTall = function(self) return self.h end,
        SetTall = function(self, h) self.h = h end
    }
    return panel
end

---@param name string
---@param extensions table<string, any>
---@param root? any
---@return PW.Screen, any[], PW.UIFocusSpec[]
local function compileScreen(name, extensions, root)
    local source = assert(CompileFile("privatewar/screens/" .. name .. ".lua"), name .. " screen is not implemented")
    local screen = { ClassName = name }
    ---@type any[]
    local panels = {}
    ---@type PW.UIFocusSpec[]
    local focusSpecs = {}
    ---@param panel any
    ---@param group string
    ---@param id? string
    ---@return PW.UIFocusSpec
    local function focusable(panel, group, id)
        local spec = { group = group, id = id or tostring(#focusSpecs + 1) }
        panel._pwFocus = spec
        focusSpecs[#focusSpecs + 1] = spec
        return spec
    end
    local ui = setmetatable({
        CurrentRoot = function() return root end,
        Draw = { Px = function(n) return n end },
        Focusable = focusable,
        SetLocked = function(panel, locked, reason)
            panel._pwFocus.locked, panel._pwFocus.reason = locked, reason
        end
    }, { __index = assert(PW.UI) })
    local pw = { UI = ui } --[[@as table<string, any>]]
    for key, value in pairs(extensions) do pw[key] = value end
    local env = setmetatable({
        SCREEN = screen, PW = pw, IsValid = function(value) return istable(value) end,
        LocalPlayer = function() return { Nick = function() return "Local preview name" end } end,
        vgui = { Create = function(kind, parent)
            local panel = fakePanel(kind, parent)
            panels[#panels + 1] = panel
            return panel
        end }
    }, { __index = _G })
    setfenv(source, env)()
    return screen --[[@as PW.Screen]], panels, focusSpecs
end

---@param panels any[]
---@param label string
---@return any
local function button(panels, label)
    for _, item in ipairs(panels) do
        if item.text == label then return item end
    end
    error("missing button " .. label)
end

---@param root any
---@param panels any[]
---@param direction PW.UIDirection
---@return PW.UIFocusModel
local function move(root, panels, direction)
    ---@type PW.UIFocusNode[]
    local nodes = {}
    ---@type table<string, any>
    local byId = {}
    ---@type table<string, PW.UIFocusGroup>
    local groups = {}
    for _, item in ipairs(panels) do
        local spec = item._pwFocus --[[@as PW.UIFocusSpec?]]
        if spec ~= nil and item.visible then
            byId[spec.id] = item
            groups[spec.group] = { axis = spec.axis, wrap = spec.wrap }
            nodes[#nodes + 1] = { id = spec.id, group = spec.group, locked = spec.locked,
                rect = { x = item.x, y = item.y, w = item.w, h = item.h } }
        end
    end
    local focus = assert(assert(PW.UI).Focus)
    local graph = focus.New(nodes, groups)
    local id = focus.Move(graph, root.focused._pwFocus.id, direction)
    root:FocusPanel(byId[id])
    return graph
end

---@param saved string
local function previewFixture(saved)
    local rows = catalogue()
    ---@type { key: string, value: string }[]
    local writes = {}
    ---@type { title: string, name: string, label: string }[]
    local paints = {}
    ---@type any
    local root = {
        FocusPanel = function(self, panel)
            self.focused = assert(panel, "the controller has no focus target")
            if panel.PWOnFocus ~= nil then panel:PWOnFocus() end
        end
    }
    local lib = setmetatable({}, { __index = cards() }) --[[@as PW.CallingCardsLib]]
    lib.LocalChoice = function() return saved end
    lib._PickerCards = function() return rows end
    lib.Choose = function(id) return selectCard(id, rows, writes) end
    lib._PlateFor = function(id)
        for _, row in ipairs(rows) do
            if row.id == id then return { style = "art", title = row.title, rarity = "common" } end
        end
        error("preview requested an unknown card: " .. id)
    end
    lib._FitName = function(name) return name end
    lib._DrawPlate = function(plate, name, label)
        paints[#paints + 1] = { title = plate.title, name = name, label = label }
    end
    lib._PushBanner = function() error("the picker must not write to the live kill banner") end
    local screen, panels = compileScreen("loadout_card", { CallingCards = lib }, root)
    ---@type any
    local view = screen:Build({ root = root, parent = fakePanel("root"), router = {} })
    view:PerformLayout(1160, 600)
    return { root = root, view = view, panels = panels, paints = paints, writes = writes }
end

return {
    groupName = "PW calling card picker",
    cases = {
        {
            name = "Selecting an unlocked calling card writes only its intended client enum value",
            func = function()
                local rows = catalogue()
                ---@type { key: string, value: string }[]
                local writes = {}
                expect(selectCard("bomb", rows, writes)).to.beTrue()
                expect(#writes).to.equal(1)
                expect(writes[1].key).to.equal("calling_cards.selected")
                expect(writes[1].value).to.equal("bomb")
                expect(selectCard("unknown", rows, writes)).to.beFalse()
                expect(selectCard("", rows, writes)).to.beFalse()
                expect(#writes).to.equal(1)
            end
        },
        {
            name = "A locked card stays focusable and shows its requirement without writing a choice",
            func = function()
                local rows = catalogue()
                ---@type { key: string, value: string }[]
                local writes = {}
                local locked = rows[3]
                expect(locked.locked).to.beTrue()
                expect(locked.disabled).toNot.equal(true)
                expect(locked.lockText).to.equal("LV 20")
                expect(locked.reason).to.equal("Unlocks at level 20")
                expect(selectCard(locked.id, rows, writes)).to.beFalse()
                expect(#writes).to.equal(0)
            end
        },
        {
            name = "The saved calling card has initial focus and controller movement changes only the bottom preview",
            func = function()
                local f = previewFixture("bomb")
                expect(f.root.focused.text).to.equal("Bomb")
                f.view.preview:Paint(f.view.preview.w, f.view.preview.h)
                expect(f.paints[1].title).to.equal("Bomb")
                expect(f.paints[1].name).to.equal("Local preview name")
                expect(f.paints[1].label).to.equal("ELIMINATED")
                local graph = move(f.root, f.panels, "right")
                expect(f.root.focused.text).to.equal("Veteran")
                expect(f.root.focused._pwFocus.locked).to.beTrue()
                expect(f.root.focused._pwFocus.reason).to.equal("Unlocks at level 20")
                local focus = assert(assert(PW.UI).Focus)
                local _, action = focus.Apply(graph, f.root.focused._pwFocus.id, "accept")
                expect(action).to.equal("locked")
                f.root.focused:DoClick()
                f.view.preview:Paint(f.view.preview.w, f.view.preview.h)
                expect(f.paints[2].title).to.equal("Veteran")
                expect(f.view.preview.y > f.root.focused.y + f.root.focused.h).to.beTrue()
                expect(#f.writes).to.equal(0)
                move(f.root, f.panels, "left")
                move(f.root, f.panels, "left")
                expect(f.root.focused.text).to.equal("Recruit")
                expect(#f.writes).to.equal(0)
                f.root.focused:DoClick()
                expect(#f.writes).to.equal(1)
                expect(f.writes[1].key).to.equal("calling_cards.selected")
                expect(f.writes[1].value).to.equal("default")
                expect(previewFixture("unknown").root.focused.text).to.equal("Recruit")
            end
        },
        {
            name = "The LOADOUT calling card button opens its child screen and Back returns to Classes",
            func = function()
                local screens = assert(PW.Registries.screens)
                local picker = assert(screens.Get("loadout_card")) --[[@as PW.Screen]]
                local classes = assert(screens.Get("loadout_classes")) --[[@as PW.Screen]]
                local router = assert(assert(PW.UI).Router)
                local model = router.New({ classes, picker }, { "loadout" })
                local push = assert(cards()._PushPicker)
                local screen, panels = compileScreen("loadout_classes", {
                    Loadout = {},
                    CallingCards = { _Active = function() return true end, OpenPicker = function() push(model) end }
                })
                screen:Build({ parent = fakePanel("root") })
                local entry = button(panels, "CALLING CARD")
                expect(entry.visible).to.beTrue()
                expect(entry._pwFocus.group).to.equal(button(panels, "OPERATOR")._pwFocus.group)
                expect(entry._pwFocus.axis).to.equal("horizontal")
                entry:DoClick()
                expect(picker.Tab).to.equal("loadout")
                ---@type table<string, boolean>
                local hints = {}
                for _, hint in ipairs(picker.Hints or {}) do hints[hint.action] = true end
                expect(hints.accept and hints.back).to.beTrue()
                expect(router.Top(model)).to.equal(picker)
                expect(router.Depth(model)).to.equal(2)
                expect(router.Act(model, "back", "LOBBY")).to.equal("pop")
                expect(router.Top(model)).to.equal(classes)
            end
        },
        {
            name = "All stock calling card definitions match the approved art and unlock map",
            func = function()
                local registry = assert(PW.Registries.cards)
                local defaults = {
                    { "default", "Recruit", "common" },
                    { "level_20", "Veteran", "rare", 20 },
                    { "level_40", "Elite", "epic", 40 },
                    { "level_55", "Legend", "legendary", 55 },
                    { "challenge_headshots", "Headhunter", "epic", false },
                    { "challenge_longshots", "Marksman", "rare", false },
                    { "challenge_captures", "Flag Runner", "rare", false },
                    { "challenge_streak_kills", "Air Support", "epic", false },
                    { "challenge_life_kills", "Untouchable", "epic", false },
                    { "challenge_wins", "Champion", "legendary", false }
                }
                for _, row in ipairs(defaults) do
                    local id = row[1] --[[@as string]]
                    local entry = assert(registry.GetStored(id)) --[[@as PW.CallingCard]]
                    expect(entry.Name).to.equal(row[2])
                    expect(entry.Rarity).to.equal(row[3])
                    expect(entry.Material).to.equal("privatewar/cards/" .. id .. ".png")
                    if row[4] == false then
                        local unlock = entry.Unlock --[[@as PW.UnlockSpec]]
                        expect(unlock.level).to.beFalse()
                        expect(unlock.reward).to.equal("challenge")
                    elseif row[4] == nil then
                        expect(entry.Unlock).to.beNil()
                    else
                        expect(entry.Unlock).to.equal(row[4])
                    end
                end
                for _, id in ipairs({ "bomb", "gold_medal", "lightning" }) do
                    local entry = assert(registry.GetStored(id)) --[[@as PW.CallingCard]]
                    expect(entry.Material:sub(1, 7)).to.equal("icon16/")
                    expect((entry.Price or 0) > 0).to.beTrue()
                end
            end
        }
    }
}
