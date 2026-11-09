-- Mode dependencies are checked even with no bots; unrelated disabled modules remain optional.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "dependency contract absent") return value end

---@return PW.MatchLib
local function match() return must(PW.Match) end

---@return table<string, any>
local function api() return match() --[[@as table<string, any>]] end

return {
    groupName = "PW objective mode dependencies",
    beforeEach = function(state)
        state.match, state.mode, state.enable, state.settings = PW._Match, PW.ActiveMode, PW._Enable, PW._Settings
        state.registries, state.call = PW.Registries, PW._Call
        PW.ActiveMode = nil
        PW._Match = match()._NewStore({ log = function() end, players = function() return {} end })
        PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
        PW._Settings = must(PW.Settings)._NewStore()
        PW._Call = { log = function() end, failed = {}, profile = {} }
        local reg = PW.Registry.New("objective_actions", { preRegister = function() end, log = function() end })
        reg.Register({ Update = function() return must(PW.BotBrain).Continue() end }, "test_required")
        reg.ResolveAll()
        PW.Registries = { objective_actions = reg }
        state.reg = reg
        state.starts, state.ends = 0, 0
        state.definition = { ClassName = "dependency_test", Teams = 0,
            Dependencies = { objective_actions = { "test_required" } },
            Start = function() state.starts = state.starts + 1 end,
            Cleanup = function() state.ends = state.ends + 1 end }
    end,
    afterEach = function(state)
        PW._Match, PW.ActiveMode, PW._Enable, PW._Settings = state.match, state.mode, state.enable, state.settings
        PW.Registries, PW._Call = state.registries, state.call
        state.reg._Release()
    end,
    cases = {
        {
            name = "Dependencies: built-in required action lists follow actual emitted actions",
            func = function(state)
                local expected = { dom = { "capture", "defend" }, kc = { "collect", "deny" },
                    hardpoint = { "hold" }, snd = { "collect", "hold", "plant", "defuse" } }
                for id, ids in pairs(expected) do
                    local mode = must(state.registries.modes.Get(id)) --[[@as table<string, any>]]
                    expect(mode.Dependencies.objective_actions).to.deepEqual(ids)
                end
            end
        },
        {
            name = "Dependencies: missing or disabled mandatory action aborts human-only PREMATCH before Start",
            func = function(state)
                state.reg._Disable("test_required", "disabled")
                match().Start(state.definition)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.starts).to.equal(0)
                expect(match().GetAbortReason()).to.exist()
                state.definition.Dependencies.objective_actions = { "missing" }
                match().Start(state.definition)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.starts).to.equal(0)
            end
        },
        {
            name = "Dependencies: runtime failure stops the mode immediately, cleanup once and no later Think",
            func = function(state)
                local required = state.reg.Get("test_required") --[[@as PW.Entity]]
                required.Update = function() error("required failed") end
                match().Start(state.definition)
                match()._SetPhase("LIVE")
                expect(state.starts).to.equal(1)
                PW.Call(state.reg.Get("test_required"), "Update")
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(state.ends).to.equal(1)
                match()._Tick()
                expect(state.ends).to.equal(1)
            end
        },
        {
            name = "Dependencies: unrelated optional disable does not abort and failed entry cannot silently run",
            func = function(state)
                state.reg.Register({ Update = function() end }, "optional")
                match().Start(state.definition)
                match()._SetPhase("LIVE")
                state.reg._Disable("optional", "optional disabled")
                expect(match().GetPhase()).to.equal("LIVE")
                state.reg._Disable("test_required", "required disabled")
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "Dependencies: current match pins old definitions across reload; next match uses replacements",
            func = function(state)
                match().Start(state.definition)
                local pinned = api().Dependency("objective_actions", "test_required") --[[@as PW.Entity]]
                local replacement = PW.Registry.New("objective_actions", { log = function() end })
                replacement.Register({ Update = function() end }, "test_required")
                replacement.ResolveAll()
                local keep = PW.Loader._KeepFor(PW.Registries, api()._DependencyEntities())
                state.reg._Release(keep.objective_actions)
                PW.Registries.objective_actions = replacement
                expect(api().Dependency("objective_actions", "test_required")).to.equal(pinned)
                expect(pinned:IsValid()).to.beTrue()
                match().Abort("test restart")
                match().Start(state.definition)
                local nextDefinition = api().Dependency("objective_actions", "test_required") --[[@as PW.Entity]]
                expect(nextDefinition).to.equal(replacement.Get("test_required"))
                replacement._Release()
            end
        }
    }
}
