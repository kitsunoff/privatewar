-- P2 consumer regressions: rejected is not a validated candidate, but an explicit loaded-map recheck is possible.
local function lobby() return assert(PW.Lobby) end

---@param state table<string, any>
---@param explicit boolean
---@return PW.LobbyFits
local function fits(state, explicit)
    return lobby()._Fits(state.registries, explicit and game.GetMap() or nil)
end

return {
    groupName = "PW SND rejected-map consumers",
    beforeEach = function(state)
        state.reason, state.readiness, state.retryable = "S&D plant volume is blocked", "rejected", true
        state.mode = { ClassName = "snd", Name = "Search and Destroy", MapData = true, MapReadiness = true }
        state.registries = { modes = { Get = function(id) return id == "snd" and state.mode or nil end } }
        state.map = game.GetMap()
        state.view = { map = state.map, maps = { state.map, "gm_other_fixture" },
            modes = { { id = "snd", name = "Search and Destroy", groups = {} } }, toggles = {},
            canStart = true, canEdit = true, canToggle = true }
        stub(assert(PW.Map), "ModeFits").with(function(_, map)
            if map ~= state.map then return true end
            return false, state.reason
        end)
        stub(assert(PW.Map), "GetModeAvailability").with(function()
            return { fits = false, readiness = state.readiness, reason = state.reason,
                canRetry = state.retryable == true and state.readiness == "rejected" }
        end)
    end,
    cases = {
        {
            name = "SND rejected cards obey source-owned canRetry instead of inferring it from rejection alone",
            func = function(state)
                state.retryable = false
                local offered, reason, recheck = fits(state, true)("snd", state.map)
                expect(offered).to.beFalse()
                expect(reason).to.equal(state.reason)
                expect(recheck).to.beFalse()
                expect(lobby()._CheckStart({ mode = "snd", map = state.map },
                    { modes = { snd = true }, mapExists = function() return true end,
                        fits = fits(state, true), allowRecheck = true })).to.beFalse()
                local selection = { mode = "snd", map = state.map --[[@as string]] }
                local model = lobby()._Model(state.view, selection, fits(state, true))
                expect(model.map).to.equal(state.map)
                expect(model.canStart).to.beFalse()
                expect(model.blockedReason).to.equal(state.reason)
                expect(model.maps[1].locked).to.beTrue()
            end
        },
        {
            name = "SND lobby fits and start validation preserve the detector rejection reason",
            func = function(state)
                local query = fits(state, false)
                local offered, reason = query("snd", state.map)
                expect(offered).to.beFalse()
                expect(reason).to.equal(state.reason)
                local ok, why = lobby()._CheckStart({ mode = "snd", map = state.map },
                    { modes = { snd = true }, mapExists = function() return true end, fits = query })
                expect(ok).to.beFalse()
                expect(why).to.equal(state.reason)
            end
        },
        {
            name = "SND explicit recheck is separate from strict eligibility and cannot authorize a remote map",
            func = function(state)
                local strict, explicit = fits(state, false), fits(state, true)
                local ok, reason, recheck = explicit("snd", state.map)
                expect(ok).to.beFalse()
                expect(reason).to.equal(state.reason)
                expect(recheck).to.beTrue()
                expect(select(3, strict("snd", state.map))).to.beFalse()
                local facts = { modes = { snd = true }, mapExists = function() return true end,
                    fits = explicit, allowRecheck = true }
                expect(lobby()._CheckStart({ mode = "snd", map = state.map }, facts)).to.beTrue()
                facts.mapExists = function() return false end
                expect(lobby()._CheckStart({ mode = "snd", map = state.map }, facts)).to.beFalse()
                local wrongCurrent = lobby()._Fits(state.registries, "de_not_loaded_fixture")
                expect(select(3, wrongCurrent("snd", state.map))).to.beFalse()
            end
        },
        {
            name = "SND recheck metadata never admits non-SND modes or pending readiness",
            func = function(state)
                state.mode.ClassName = "hardpoint"
                state.retryable = false -- source-owned denial for an unrelated mode
                expect(select(3, fits(state, true)("snd", state.map))).to.beFalse()
                state.mode.ClassName, state.readiness, state.retryable = "snd", "pending", true
                expect(select(3, fits(state, true)("snd", state.map))).to.beFalse()
            end
        },
        {
            name = "SND rejected selection stays visible with its reason and an explicit recheck action",
            func = function(state)
                local query = fits(state, true)
                local selection = { mode = "snd", map = state.map --[[@as string]] }
                local model = lobby()._Model(state.view, selection, query)
                expect(model.map).to.equal(state.map)
                expect(model.retryReason).to.equal(state.reason)
                expect(#model.maps).to.equal(2)
                local input = { state = state.view --[[@as PW.LobbyState]], selection = selection, fits = query,
                    playlists = false, players = {}, maxPlayers = 16, seen = {} }
                local hub = lobby()._Custom(input)
                expect(hub.start.label).to.equal("RECHECK MAP")
                expect(hub.start.locked).to.beFalse()
                expect(hub.start.request.map).to.equal(state.map)
                expect(string.find(hub.start.text, state.reason, 1, true)).to.exist()
                local picker = lobby()._Picker(input, selection)
                expect(picker.map).to.equal(state.map)
                expect(string.find(picker.cards[1].text, state.reason, 1, true)).to.exist()
                local strict = lobby()._PickerMaps(state.view, "snd", fits(state, false))
                expect(strict).to.deepEqual({ "gm_other_fixture" })
            end
        }
    }
}
