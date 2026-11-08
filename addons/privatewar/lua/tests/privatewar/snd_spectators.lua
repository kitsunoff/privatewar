-- Generic owner policy, with pure decision and recording engine boundaries. Never creates or teleports a bot.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil, "expected spectator policy owner") return value end
---@return PW.JipLib
local function lib() return must(PW.Jip) end

---@class PW.TestSpectatorActor: Player
---@field id integer
---@field team integer
---@field alive boolean
---@field mode integer
---@field target Entity
---@field events integer[]

---@class PW.TestSpectatorState
---@field viewer PW.TestSpectatorActor
---@field friend PW.TestSpectatorActor
---@field enemy PW.TestSpectatorActor
---@field policy PW.SpectatorPolicy

---@param id integer
---@param team integer
---@param alive boolean
---@return PW.TestSpectatorActor
local function actor(id, team, alive)
    ---@type table<string, any>
    local p = { id = id, team = team, alive = alive, mode = OBS_MODE_NONE, target = NULL, events = {} }
    p.IsValid, p.IsPlayer, p.IsBot = function() return true end, function() return true end, function() return true end
    p.UserID = function() return id end
    p.Team = function(self) return self.team end
    p.Alive = function(self) return self.alive end
    p.GetObserverMode = function(self) return self.mode end
    p.GetObserverTarget = function(self) return self.target end
    p.SetTeam = function(self, value) self.team = value end
    p.StripWeapons, p.SetNoTarget = function() end, function() end
    p.Spectate = function(self, mode)
        self.mode = mode
        local events = self.events --[[@as any[] ]]
        events[#events + 1] = mode
    end
    p.SpectateEntity = function(self, target) self.target = target end
    return p --[[@as PW.TestSpectatorActor]]
end

---@param name string
---@param ... any
local function engine(name, ...)
    local module = must(PW.Modules.Get("lobby"))
    must(must(module._EngineHooks)[name])(module, ...)
end

return { groupName = "PW SND spectator privacy",
    beforeEach = function(state)
        ---@cast state PW.TestSpectatorState
        state.viewer, state.friend, state.enemy = actor(1, 1, false), actor(2, 1, true), actor(3, 2, true)
        state.policy = { restricted = true, eligible = { [2] = true } }
        stub(player, "GetAll").with(function() return { state.viewer, state.friend, state.enemy } end)
        stub(PW, "Ask").with(function(name)
            expect(name).to.equal("PW_SpectatorPolicy")
            return state.policy
        end)
    end,
    cases = {
        { name = "Spectator policy: nil preserves roaming; malformed restrictions fail closed fixed", func = function()
            local choose = must(lib().SpectatorChoice)
            expect(choose(nil, {})).to.equal("roaming")
            for _, bad in ipairs({ false, "all", {}, { restricted = true },
                { restricted = true, eligible = "all" } }) do
                expect(choose(bad, { { id = 2, alive = true } })).to.equal("fixed")
            end
            expect(choose({ restricted = true, eligible = {} }, { { id = 2, alive = true } })).to.equal("fixed")
        end },
        { name = "Spectator policy: choose only living allowed UserIDs; forged enemy target cannot bypass it",
            func = function(state)
                ---@cast state PW.TestSpectatorState
                local policy = { restricted = true, eligible = { [2] = true }, target = state.enemy }
                local mode, target = must(lib().SpectatorChoice)(policy,
                    { { id = 3, alive = true }, { id = 2, alive = true } }, 3)
                expect(mode).to.equal("follow")
                expect(target).to.equal(2)
                expect(must(lib().SpectatorChoice)(policy, { { id = 2, alive = false } }, 2)).to.equal("fixed")
            end },
        { name = "Spectator policy: engine parking applies restriction synchronously without any roaming exposure",
            func = function(state)
                ---@cast state PW.TestSpectatorState
                local store = lib()._NewStore()
                store.park(state.viewer)
                expect(state.viewer.mode).to.equal(OBS_MODE_IN_EYE)
                expect(state.viewer.target).to.equal(state.friend)
                for _, mode in ipairs(state.viewer.events --[[@as integer[] ]]) do
                    expect(mode == OBS_MODE_ROAMING).to.beFalse()
                end
            end },
        { name = "Spectator policy: no eligible target is fixed with no enemy entity attached", func = function(state)
            ---@cast state PW.TestSpectatorState
            state.friend.alive = false
            state.viewer.target, state.viewer.mode = state.enemy, OBS_MODE_IN_EYE
            must(lib().RefreshSpectator)(state.viewer)
            expect(state.viewer.mode).to.equal(OBS_MODE_FIXED)
            expect(IsValid(state.viewer.target)).to.beFalse()
        end },
        { name = "Spectator policy: death disconnect and forged visibility target refresh through the owner",
            func = function(state)
                ---@cast state PW.TestSpectatorState
                must(lib().RefreshSpectator)(state.viewer)
                state.viewer.target = state.enemy
                engine("SetupPlayerVisibility", state.viewer)
                expect(state.viewer.target).to.equal(state.friend)
                state.friend.alive = false
                engine("PlayerDeath", state.friend)
                expect(state.viewer.mode).to.equal(OBS_MODE_FIXED)
                state.friend.alive = true
                must(lib().RefreshSpectator)(state.viewer)
                engine("PlayerDisconnected", state.friend)
                expect(state.viewer.mode).to.equal(OBS_MODE_FIXED)
                expect(IsValid(state.viewer.target)).to.beFalse()
            end },
        { name = "Spectator policy: team and round invalidations cannot keep a now-ineligible target",
            func = function(state)
                ---@cast state PW.TestSpectatorState
                must(lib().RefreshSpectator)(state.viewer)
                state.policy.eligible = {}
                local module = must(PW.Modules.Get("lobby"))
                for _, event in ipairs({ "PW_PlayerTeamChanging", "PW_PlayerTeamChanged",
                    "PW_RoundPreparing", "PW_RoundPrepared" }) do
                    state.viewer.mode, state.viewer.target = OBS_MODE_IN_EYE, state.enemy
                    PW.Call(module, event, state.enemy, 2, 1, "test")
                    expect(state.viewer.mode).to.equal(OBS_MODE_FIXED)
                    expect(IsValid(state.viewer.target)).to.beFalse()
                end
            end },
        { name = "SND spectator policy: only current own-team roster lives are eligible; JIP is fixed",
            func = function(state)
                ---@cast state PW.TestSpectatorState
                local roster = {
                    ["bot:1"] = { userId = 1, team = 1, alive = false, connected = true, spawned = true },
                    ["bot:2"] = { userId = 2, team = 1, alive = true, connected = true, spawned = true },
                    ["bot:3"] = { userId = 3, team = 2, alive = true, connected = true, spawned = true }
                }
                local definition = must(PW.Modes.Get("snd"))
                local mode = setmetatable({ _SND = { roster = roster } }, { __index = definition }) --[[@as PW.SNDMode]]
                local own = must(mode:PW_SpectatorPolicy(state.viewer))
                expect(own.eligible).to.deepEqual({ [2] = true })
                state.friend.team = 2
                expect(must(mode:PW_SpectatorPolicy(state.viewer)).eligible).to.deepEqual({})
                expect(must(mode:PW_SpectatorPolicy(actor(99, TEAM_SPECTATOR, false) --[[@as Player]])).eligible)
                    .to.deepEqual({})
            end }
    }
}
