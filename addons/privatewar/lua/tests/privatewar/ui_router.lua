-- U-3 Router and root (TASKS.md, "Mandatory test cases" U-3; notes/16-frontend-d1-proposal.md Q1). Pure: plain
-- screens, no vgui. PW.Call runs with an isolated failure store so a failing screen does not leak into the game.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIRouterLib
local function router() return must(must(PW.UI).Router) end

---@param id string
---@param tab string
---@param root? boolean
---@return PW.Screen
local function screen(id, tab, root)
    return { ClassName = id, Tab = tab, Root = root, Build = function() return id end }
end

---A screen whose Build raises an error.
---@param id string
---@param tab string
---@param root? boolean
---@return PW.Screen
local function broken(id, tab, root)
    local item = screen(id, tab, root)
    item.Build = function() error("boom " .. id) end
    return item
end

---@param model PW.UIRouterModel
---@return string[]
local function names(model)
    ---@type string[]
    local out = {}
    for index, item in ipairs(model.stacks[model.active]) do out[index] = item.ClassName end
    return out
end

---@return PW.UIRouterModel
local function hub()
    return router().New({
        screen("play_hub", "play", true), screen("play_map", "play"), screen("play_setup", "play"),
        screen("loadout_hub", "loadout", true), screen("loadout_pick", "loadout")
    })
end

local required = { Build = "function", Tab = "string" }

return {
    groupName = "PW UI router",
    beforeEach = function(state)
        state.previousStore = PW._Call
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Call = {
            log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }),
            profile = {}
        }
    end,
    afterEach = function(state)
        PW._Call = state.previousStore
    end,
    cases = {
        {
            name = "The screens kind is declared and requires Build and Tab",
            func = function()
                expect(must(PW.Registries["screens"])).to.exist()
                expect(PW.Registry.ValidateRequired({ Tab = "play" }, required)).to.beFalse()
                expect(PW.Registry.ValidateRequired(screen("a", "play"), required)).to.beTrue()
            end
        },
        {
            name = "Tabs come in the fixed order; a tab without a root is locked; the first open tab is active",
            func = function()
                local model = hub()
                ---@type string[]
                local out = {}
                for _, tab in ipairs(model.tabs) do out[#out + 1] = tab.id .. (tab.locked and ":locked" or "") end
                expect(out).to.deepEqual({ "play", "loadout", "progress:locked", "store:locked" })
                expect(model.active).to.equal("play")
                expect(names(model)).to.deepEqual({ "play_hub" })
            end
        },
        {
            name = "Root choice: the lowest Order among Root screens of the tab",
            func = function()
                local late, early = screen("late", "play", true), screen("early", "play", true)
                late.Order, early.Order = 50, 10
                local model = router().New({ late, early })
                expect(names(model)).to.deepEqual({ "early" })
            end
        },
        {
            name = "Push, Pop and Replace work on the active tab's stack",
            func = function()
                local model = hub()
                expect(router().Push(model, "play_map")).to.beTrue()
                expect(router().Push(model, "play_setup")).to.beTrue()
                expect(names(model)).to.deepEqual({ "play_hub", "play_map", "play_setup" })
                expect(router().Replace(model, "play_map")).to.beTrue()
                expect(names(model)).to.deepEqual({ "play_hub", "play_map", "play_map" })
                expect(router().Pop(model)).to.beTrue()
                expect(router().Pop(model)).to.beTrue()
                expect(names(model)).to.deepEqual({ "play_hub" })
                expect(router().Pop(model)).to.beFalse()
                expect(router().Push(model, "no_such_screen")).to.beFalse()
                expect(router().Depth(model)).to.equal(1)
            end
        },
        {
            name = "Back at a tab root in LOBBY stays; above the root it pops; outside LOBBY a root asks to close",
            func = function()
                local model = hub()
                expect(router().Back(model, "LOBBY")).to.equal("stay")
                expect(names(model)).to.deepEqual({ "play_hub" })
                router().Push(model, "play_map")
                expect(router().Back(model, "LOBBY")).to.equal("pop")
                expect(names(model)).to.deepEqual({ "play_hub" })
                expect(router().Back(model, "LOBBY")).to.equal("stay")
                expect(router().Back(model, "VOTE")).to.equal("close")
                expect(router().Act(model, "back", "LOBBY")).to.equal("stay")
            end
        },
        {
            name = "A tab switch keeps each tab's stack",
            func = function()
                local model = hub()
                router().Push(model, "play_map")
                expect(router().SwitchTab(model, "loadout")).to.beTrue()
                expect(names(model)).to.deepEqual({ "loadout_hub" })
                router().Push(model, "loadout_pick")
                expect(router().SwitchTab(model, "play")).to.beTrue()
                expect(names(model)).to.deepEqual({ "play_hub", "play_map" })
                expect(router().SwitchTab(model, "loadout")).to.beTrue()
                expect(names(model)).to.deepEqual({ "loadout_hub", "loadout_pick" })
            end
        },
        {
            name = "A locked tab cannot be entered, by id or by cycling; unlocking enters it",
            func = function()
                local model = hub()
                expect(router().SwitchTab(model, "store")).to.beFalse()
                expect(model.active).to.equal("play")
                expect(router().Cycle(model, 1)).to.beTrue()
                expect(model.active).to.equal("loadout")
                expect(router().Cycle(model, 1)).to.beTrue()
                expect(model.active).to.equal("play")
                expect(router().Cycle(model, -1)).to.beTrue()
                expect(model.active).to.equal("loadout")
                router().SetLocked(model, "loadout", true, "later")
                expect(model.active).to.equal("play")
                expect(router().SwitchTab(model, "loadout")).to.beFalse()
                expect(router().SwitchTab(model, "unknown")).to.beFalse()
                router().SetLocked(model, "loadout", false)
                expect(router().SwitchTab(model, "loadout")).to.beTrue()
            end
        },
        {
            name = "Input actions: tab_prev and tab_next switch tabs, back pops, others are not the router's",
            func = function()
                local model = hub()
                expect(router().Act(model, "tab_next", "LOBBY")).to.equal("tab")
                expect(model.active).to.equal("loadout")
                expect(router().Act(model, "tab_prev", "LOBBY")).to.equal("tab")
                expect(model.active).to.equal("play")
                router().Push(model, "play_map")
                expect(router().Act(model, "back", "LOBBY")).to.equal("pop")
                expect(router().Act(model, "accept", "LOBBY")).to.beNil()
            end
        },
        {
            name = "A screen whose Build errors is skipped through PW.Call and the others work",
            func = function(state)
                local model = router().New({ screen("play_hub", "play", true), broken("play_bad", "play") })
                router().Push(model, "play_bad")
                local view, built = router().Build(model, {})
                expect(view).to.equal("play_hub")
                expect(must(built).ClassName).to.equal("play_hub")
                expect(names(model)).to.deepEqual({ "play_hub" })
                local logged = state.logged --[[@as string[] ]]
                expect(#logged).to.equal(1)
            end
        },
        {
            name = "A root whose Build errors locks its tab and the router moves to the next tab",
            func = function()
                local model = router().New({ broken("play_hub", "play", true), screen("loadout_hub", "loadout", true) })
                local view = router().Build(model, {})
                expect(view).to.equal("loadout_hub")
                expect(model.active).to.equal("loadout")
                expect(model.tabById["play"].locked).to.beTrue()
                expect(router().SwitchTab(model, "play")).to.beFalse()
            end
        },
        {
            name = "With every screen broken Build returns nothing",
            func = function()
                local model = router().New({ broken("play_hub", "play", true) })
                expect(router().Build(model, {})).to.beNil()
            end
        }
    }
}
