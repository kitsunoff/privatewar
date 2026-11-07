-- U-6 Map picker (TASKS.md, "Mandatory test cases" U-6, T-8.2; notes/16-frontend-d1-proposal.md §4c; 10-frontend.md
-- d.3). Pure models of the picker (PW.Lobby._Picker* in lobby_ui/sh_picker.lua): the filtered map list, the
-- selection rule, the pager position of the focused row, the thumbnail path and the Q/E mode cycling. The drawing
-- and the keys on the real screen are checkpoint items.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LobbyLib
local function lobby()
    return must(PW.Lobby)
end

-- tdm is offered on every map, ffa on the last two, dom on the last one.
local offered = {
    pwt_tdm = { gm_a = true, gm_b = true, gm_c = true },
    pwt_ffa = { gm_b = true, gm_c = true },
    pwt_dom = { gm_c = true }
}

---@param modeId string
---@param map string
---@return boolean
local function fits(modeId, map)
    local maps = offered[modeId]
    return maps ~= nil and maps[map] == true
end

---@return PW.LobbyState
local function sampleState()
    return {
        map = "gm_a", maps = { "gm_a", "gm_b", "gm_c" },
        modes = {
            { id = "pwt_tdm", name = "Team Deathmatch", groups = {} },
            { id = "pwt_ffa", name = "Free for all", groups = {} },
            { id = "pwt_dom", name = "Domination", groups = {} }
        },
        toggles = {}, canStart = true, canEdit = true, canToggle = true
    }
end

---@return PW.LobbyHubInput
local function input()
    return {
        state = sampleState(), selection = {}, fits = fits, players = {}, maxPlayers = 12, seen = {},
        shortOf = function(id) return id == "pwt_tdm" and "TDM" or nil end
    }
end

---@param list string[]
---@return string
local function joined(list)
    return table.concat(list, ",")
end

return {
    groupName = "PW ui map picker",
    cases = {
        {
            name = "The map list is the maps that fit the mode",
            func = function()
                local state = sampleState()
                expect(joined(lobby()._PickerMaps(state, "pwt_tdm", fits))).to.equal("gm_a,gm_b,gm_c")
                expect(joined(lobby()._PickerMaps(state, "pwt_ffa", fits))).to.equal("gm_b,gm_c")
                expect(joined(lobby()._PickerMaps(state, "pwt_dom", fits))).to.equal("gm_c")
                expect(#lobby()._PickerMaps(state, "pwt_unknown", fits)).to.equal(0)
                expect(joined(lobby()._PickerMaps(state, "pwt_ffa", nil))).to.equal("gm_a,gm_b,gm_c")
            end
        },
        {
            name = "The selection is kept when it still fits, else the first fitting map",
            func = function()
                local maps = { "gm_b", "gm_c" }
                expect(lobby()._PickerKeep(maps, "gm_c")).to.equal("gm_c")
                expect(lobby()._PickerKeep(maps, "gm_a")).to.equal("gm_b")
                expect(lobby()._PickerKeep(maps, nil)).to.equal("gm_b")
                expect(lobby()._PickerKeep({}, "gm_a")).to.beNil()
            end
        },
        {
            name = "The model keeps the map across a mode change when it fits and falls back to the first when not",
            func = function()
                local kept = lobby()._Picker(input(), { mode = "pwt_ffa", map = "gm_c" })
                expect(kept.mode).to.equal("pwt_ffa")
                expect(kept.map).to.equal("gm_c")
                expect(kept.focusIndex).to.equal(2)
                local dropped = lobby()._Picker(input(), { mode = "pwt_ffa", map = "gm_a" })
                expect(dropped.map).to.equal("gm_b")
                expect(dropped.focusIndex).to.equal(1)
                expect(#dropped.cards).to.equal(2)
                expect(dropped.summary.mode).to.equal("Free for all")
                expect(dropped.summary.map).to.equal("gm_b")
            end
        },
        {
            name = "The model starts from the lobby selection and marks the current map",
            func = function()
                local view = input()
                view.selection = { mode = "pwt_tdm", map = "gm_b" }
                local model = lobby()._Picker(view, {})
                expect(model.mode).to.equal("pwt_tdm")
                expect(model.map).to.equal("gm_b")
                expect(model.summary.badge).to.equal("TDM")
                expect(model.thumb).to.equal("maps/thumb/gm_b.png")
                expect(model.cards[2].badge).to.equal("CURRENT")
                expect(model.cards[1].badge).to.beNil()
            end
        },
        {
            name = "The pager position follows the focused row: page n of N",
            func = function()
                local first = lobby()._PickerPage(25, 10, 1)
                expect(first.state.page).to.equal(1)
                expect(first.state.pages).to.equal(3)
                expect(first.text).to.equal("1 / 3")
                expect(lobby()._PickerPage(25, 10, 10).state.page).to.equal(1)
                local second = lobby()._PickerPage(25, 10, 11)
                expect(second.state.page).to.equal(2)
                expect(second.state.first).to.equal(11)
                expect(second.text).to.equal("2 / 3")
                local last = lobby()._PickerPage(25, 10, 25)
                expect(last.text).to.equal("3 / 3")
                expect(last.state.atEnd).to.beTrue()
                expect(lobby()._PickerPage(0, 10, 1).text).to.equal("1 / 1")
            end
        },
        {
            name = "The thumbnail path comes from the map name; an unsafe name has none",
            func = function()
                expect(lobby()._ThumbPath("gm_construct")).to.equal("maps/thumb/gm_construct.png")
                expect(lobby()._ThumbPath("cs_office-v2")).to.equal("maps/thumb/cs_office-v2.png")
                expect(lobby()._ThumbPath("../secret")).to.beNil()
                expect(lobby()._ThumbPath("a/b")).to.beNil()
                expect(lobby()._ThumbPath("")).to.beNil()
            end
        },
        {
            name = "Mode cycling: Q goes to the previous mode, E to the next, both wrap",
            func = function()
                local ids = { "pwt_tdm", "pwt_ffa", "pwt_dom" }
                expect(lobby()._PickerCycle(ids, "pwt_tdm", 1)).to.equal("pwt_ffa")
                expect(lobby()._PickerCycle(ids, "pwt_dom", 1)).to.equal("pwt_tdm")
                expect(lobby()._PickerCycle(ids, "pwt_tdm", -1)).to.equal("pwt_dom")
                expect(lobby()._PickerCycle(ids, "pwt_unknown", 1)).to.equal("pwt_tdm")
                expect(lobby()._PickerCycle({}, "pwt_tdm", 1)).to.beNil()
            end
        },
        {
            name = "Q and E on the picker cycle the mode and keep the map by the selection rule",
            func = function()
                local pick = must(lobby()._PickerStep(input(), { mode = "pwt_tdm", map = "gm_a" }, "tab_next"))
                expect(pick.mode).to.equal("pwt_ffa")
                expect(pick.map).to.equal("gm_b")
                local again = must(lobby()._PickerStep(input(), { mode = "pwt_ffa", map = "gm_c" }, "tab_next"))
                expect(again.mode).to.equal("pwt_dom")
                expect(again.map).to.equal("gm_c")
                local back = must(lobby()._PickerStep(input(), { mode = "pwt_ffa", map = "gm_c" }, "tab_prev"))
                expect(back.mode).to.equal("pwt_tdm")
                expect(back.map).to.equal("gm_c")
                expect(lobby()._PickerStep(input(), { mode = "pwt_tdm", map = "gm_a" }, "accept")).to.beNil()
            end
        },
        {
            name = "The model is not ready without a lobby state",
            func = function()
                local view = input()
                view.state = false
                local model = lobby()._Picker(view, {})
                expect(model.ready).to.beFalse()
                expect(#model.cards).to.equal(0)
            end
        },
        {
            name = "A screen that owns the tab keys receives Q and E; the router does not cycle the tabs",
            func = function()
                local router = must(must(PW.UI).Router)
                ---@type PW.Screen
                local root = { ClassName = "u6_root", Tab = "play", Root = true, Build = function() return "root" end }
                ---@type PW.Screen
                local owner = {
                    ClassName = "u6_owner", Tab = "play", OwnsTabKeys = true, Build = function() return "owner" end
                }
                local model = router.New({ root, owner })
                expect(router.Act(model, "tab_next", "LOBBY")).to.equal("stay")
                router.Push(model, "u6_owner")
                expect(router.Act(model, "tab_next", "LOBBY")).to.beNil()
                expect(router.Act(model, "tab_prev", "LOBBY")).to.beNil()
                expect(router.Act(model, "back", "LOBBY")).to.equal("pop")
            end
        }
    }
}
