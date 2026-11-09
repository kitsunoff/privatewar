-- Mode dependencies are checked even with no bots; unrelated disabled modules remain optional.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "dependency contract absent") return value end

---@return PW.MatchLib
local function match() return must(PW.Match) end

---@return table<string, any>
local function api() return match() --[[@as table<string, any>]] end

local resources = include("privatewar_fixtures/resource_lifecycle.lua") --[[@as PW.TestFixtureResources]]

local group = {
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
        hook.Remove("PW_MatchEnd", "PW.Test.ObjectiveDependencyStop")
        PW._Match, PW.ActiveMode, PW._Enable, PW._Settings = state.match, state.mode, state.enable, state.settings
        PW.Registries, PW._Call = state.registries, state.call
        state.reg._Release()
        resources.Yield(timer.Simple)
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
            name = "Dependencies: enable edits wait for next match; required modules are explicit",
            func = function(state)
                local enabled = true
                PW._Enable = must(PW.Enable)._NewStore({ registries = function() return PW.Registries end,
                    read = function() return enabled end, exists = function() return true end })
                match().Start(state.definition)
                match()._SetPhase("LIVE")
                enabled = false
                match()._Tick()
                expect(match().GetPhase()).to.equal("LIVE")
                expect(state.reg.Get("test_required"):IsValid()).to.beTrue()
                match().Abort("test next match")
                match().Start(state.definition)
                expect(match().GetPhase()).to.equal("LOBBY")
                state.definition.Dependencies = { modules = { "missing_runner" } }
                match().Start(state.definition)
                expect(match().GetPhase()).to.equal("LOBBY")
            end
        },
        {
            name = "Dependencies: synchronous abort during objective Update cannot apply to an already-stopped stack",
            func = function(state)
                local brain = must(PW.BotBrain)
                local stack = brain.NewState()
                local board = { bot = "fixture" --[[@as any]], intent = { buttons = 0 } }
                local env = { bot = board.bot, board = board, behaviors = {}, mode = "test",
                    random = function() return 0 end }
                local def = { ClassName = "abort_fixture", Rank = function() return "objective" end,
                    Weight = function() return 1 end,
                    Update = function()
                        state.reg._Disable("test_required", "test failure")
                        brain.Stop(stack, env, 0, "synchronous match end")
                        return brain.Done("aborted")
                    end }
                env.behaviors = { def }
                match().Start(state.definition)
                match()._SetPhase("LIVE")
                brain.Think(stack, env, 0)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(#stack.stack).to.equal(0)
                expect(PW._Call.failed[def]).to.beNil()
            end
        },
        {
            name = "Dependencies: cleanup failure during suspension cannot start a new behavior after abort",
            func = function(state)
                local brain = must(PW.BotBrain)
                local running = brain.NewState()
                local bot = { IsValid = function() return true end, Alive = function() return true end,
                    UserID = function() return 7 end } --[[@as Player]]
                ---@type PW.BotBoard
                local board = { bot = bot, intent = { buttons = 0 } }
                local target = { id = "visit", action = "test_required", pos = Vector(), radius = 10,
                    weight = 1, want = 1 }
                local combat = false
                local fight = { ClassName = "combat_fixture", Rank = function() return combat and "combat" or false end,
                    Weight = function() return 1 end, Update = function() return brain.Continue() end }
                local facade = must(must(PW.BotBehaviors).Get("objective")) --[[@as PW.BotBehavior]]
                local env = { bot = bot, board = board, behaviors = { facade, fight }, mode = "test",
                    random = function() return 0 end, api = { clearGoal = function() board.goal = nil end,
                        facts = function() return { pos = Vector(), objectives = { target }, mates = {}, deaths = {},
                            candidates = {}, stationary = false, teamwork = 1 } end } }
                local required = state.reg.Get("test_required") --[[@as PW.Entity]]
                required.OnEnd = function() error("cleanup failed during suspension") end
                hook.Add("PW_MatchEnd", "PW.Test.ObjectiveDependencyStop", function()
                    brain.Stop(running, env, 1, "match ended")
                end)
                match().Start(state.definition)
                match()._SetPhase("LIVE")
                brain.Think(running, env, 0)
                expect(must(running.stack[1]).id).to.equal("objective")
                combat = true
                brain.Think(running, env, 1)
                expect(match().GetPhase()).to.equal("LOBBY")
                expect(#running.stack).to.equal(0)
                expect(must(facade):IsValid()).to.beTrue()
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
                local target = { id = "visit", action = "test_required", pos = Vector(), radius = 10,
                    weight = 1, want = 1 }
                local ctx = must(PW.BotBrain).NewState().ctx
                local bot = { IsValid = function() return false end } --[[@as Player]]
                ctx.bot, ctx.board, ctx.state = bot, { bot = bot }, {}
                -- This is a pure dispatch fixture, not an engine player for the gatherer to inspect.
                ctx._api.facts = function()
                    return { pos = Vector(), objectives = { target }, authoritative = true, mates = {}, deaths = {},
                        candidates = {}, stationary = false, teamwork = 1 }
                end
                expect(must(PW.BotObjectives).RunAction(ctx, target).kind).to.equal("continue")
                expect(#must(PW.BotCommander).Sanitize({ target })).to.equal(1)
                must(PW.BotObjectives).EndAction(ctx)
                match().Abort("test restart")
                match().Start(state.definition)
                local nextDefinition = api().Dependency("objective_actions", "test_required") --[[@as PW.Entity]]
                expect(nextDefinition).to.equal(replacement.Get("test_required"))
                replacement._Release()
            end
        }
    }
}

-- The resource boundary runs in each case's coroutine, as in the core phase-machine fixtures.
for _, case in ipairs(group.cases) do case.coroutine = true end
return group
