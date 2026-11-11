-- Exercise the real core dependency checker and enable snapshots, not a second dependency algorithm.
local function lib() return assert(PW.Playlist) end

---@param kind string
---@return PW.Registry
local function registry(kind)
    return PW.Registry.New(kind, { preRegister = function() end, log = function() end })
end

---@return PW.RotationFacts
local function content()
    local facts = lib()._RotationFacts()
    facts.maps = { "gm_construct" }
    return facts
end

return {
    groupName = "PW playlist dependency admission",
    beforeEach = function(state)
        state.registries, state.enable, state.call = PW.Registries, PW._Enable, PW._Call
        state.modules, state.modes = registry("modules"), registry("modes")
        state.actions = registry("objective_actions")
        PW.Registries = { modules = state.modules, modes = state.modes, objective_actions = state.actions }
        PW._Call = { log = function() end, failed = {}, profile = {} }
        state.disabled = false
        PW._Enable = assert(PW.Enable)._NewStore({ registries = function() return PW.Registries end,
            read = function(name) return not (state.disabled and name == "pw_module_bots_objectives_enabled") end,
            exists = function() return true end })
        state.modules.Register({ Dependencies = { modules = { "not_a_transitive_requirement" } } }, "bots_objectives")
        state.actions.Register({}, "capture")
        state.actions.Register({}, "hold")
        state.modes.Register({ Name = "DOM", Dependencies = {
            modules = { "bots_objectives" }, objective_actions = { "capture" } } }, "dom")
        state.modes.Register({ Name = "HP", Dependencies = {
            modules = { "bots_objectives" }, objective_actions = { "hold" } } }, "hardpoint")
        state.modes.Register({ Name = "TDM" }, "tdm")
        state.modes.Register({ Name = "FFA" }, "ffa")
        state.modules.ResolveAll() state.actions.ResolveAll() state.modes.ResolveAll()
    end,
    afterEach = function(state)
        PW.Registries, PW._Enable, PW._Call = state.registries, state.enable, state.call
        state.modules._Release() state.actions._Release() state.modes._Release()
    end,
    cases = {
        {
            name = "Initially disabled required module rejects Objective Chaos while unrelated TDM and FFA survive",
            func = function(state)
                state.disabled = true
                assert(PW.Enable)._NewMatch()
                expect(lib()._BuildRotation("objective_chaos", content())).to.equal(nil)
                expect(lib()._BuildRotation("ground_war", content()) ~= nil).to.beTrue()
                expect(lib()._BuildRotation("ffa_frenzy", content()) ~= nil).to.beTrue()
                state.disabled = false
                assert(PW.Enable)._NewMatch()
                expect(lib()._BuildRotation("objective_chaos", content()) ~= nil).to.beTrue()
            end
        },
        {
            name = "Resolved playlist predicate follows applied disable and re-enable without changing its pool",
            func = function(state)
                local data = assert(lib()._BuildRotation("objective_chaos", content()))
                local source = assert(assert(PW.Playlists).GetStored("objective_chaos"))
                local definition = { _RotationData = data, IsActive = source.IsActive }
                local now = 1794355200
                expect(lib()._Evaluate(definition, now).active).to.beTrue()
                state.disabled = true
                -- Pending ConVars are not applied mid-match; use the same boundary as core.
                expect(lib()._Evaluate(definition, now).active).to.beTrue()
                assert(PW.Enable)._NewMatch()
                expect(lib()._Evaluate(definition, now)).to.deepEqual({ active = false, valid = true })
                state.disabled = false
                assert(PW.Enable)._NewMatch()
                expect(lib()._Evaluate(definition, now).active).to.beTrue()
                expect(data.Modes).to.deepEqual({ dom = 1, hardpoint = 1 })
            end
        },
        {
            name = "Hard failures survive soft re-enable and fresh replacement repairs admission through core",
            func = function(state)
                local data = assert(lib()._BuildRotation("objective_chaos", content()))
                state.modules._Disable("bots_objectives", "runtime failure")
                assert(PW.Enable)._NewMatch()
                expect(lib()._RotationContentActive("objective_chaos", data, 1794355200, content())).to.beFalse()
                local failed = assert(state.modules.Get("bots_objectives"))
                PW._Call.failed[failed] = true
                state.modules._Enable("bots_objectives")
                expect(lib()._BuildRotation("objective_chaos", content())).to.equal(nil)
                state.modules.Register({}, "bots_objectives")
                state.modules.ResolveAll()
                expect(lib()._BuildRotation("objective_chaos", content()) ~= nil).to.beTrue()
            end
        },
        {
            name = "Action dependencies filter modes independently and keep core nonrecursive declaration semantics",
            func = function(state)
                -- Nested module Dependencies are intentionally not traversed by the core checker.
                local mode = assert(state.modes.Get("dom"))
                expect(assert(PW.Match)._CheckDependencies(mode, PW.Registries) ~= nil).to.beTrue()
                state.actions._Disable("hold", "missing implementation")
                expect(assert(lib()._BuildRotation("objective_chaos", content())).Modes).to.deepEqual({ dom = 1 })
                state.actions._Disable("capture", "missing implementation")
                expect(lib()._BuildRotation("objective_chaos", content())).to.equal(nil)
                state.actions._Enable("hold")
                expect(assert(lib()._BuildRotation("objective_chaos", content())).Modes)
                    .to.deepEqual({ hardpoint = 1 })
            end
        },
        {
            name = "Resolved Base dependencies and malformed nested declarations follow core validation",
            func = function(state)
                state.modes.Register({ Dependencies = { modules = { "missing_parent_requirement" } } }, "parent")
                state.modes.Register({ Name = "HP", Base = "parent" }, "hardpoint")
                state.modes.ResolveAll()
                expect(assert(lib()._BuildRotation("objective_chaos", content())).Modes).to.deepEqual({ dom = 1 })
                state.modules.Register({}, "missing_parent_requirement")
                state.modules.ResolveAll()
                expect(assert(lib()._BuildRotation("objective_chaos", content())).Modes)
                    .to.deepEqual({ dom = 1, hardpoint = 1 })
                state.modes.Register({ Name = "HP", Dependencies = { modules = { { "not_an_id" } } } }, "hardpoint")
                state.modes.ResolveAll()
                expect(assert(lib()._BuildRotation("objective_chaos", content())).Modes).to.deepEqual({ dom = 1 })
            end
        }
    }
}
