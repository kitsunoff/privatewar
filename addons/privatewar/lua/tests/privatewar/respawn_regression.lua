-- Regression: bots never respawned in LIVE (FFA on the Deck, 2026-11-07). The engine runs no command for a dead
-- player bot (no StartCommand, no PlayerPostThink, so no PlayerDeathThink), so the PlayerDeathThink glue of
-- match_rules never set the respawn time of a bot and every bot stayed dead after its first death. The module's
-- Tick hook drives the same death think for dead bots. Player stand-ins and a stubbed player.Iterator: no bot is
-- created and no real player dies. Every case restores the store, PW.ActiveMode, PW.Match.GetPhase,
-- player.Iterator and its hooks.

local listenerId = "PW_Test_RespawnRegression"
local hookNames = { "PW_CanRespawn", "PW_RespawnDelay" }

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---Calls one engine hook the match_rules module added through PW.HookFor.
---@param name string
---@param ... any
---@return any
local function engineHook(name, ...)
    local entity = must(must(PW.Modules).Get("match_rules")) --[[@as PW.Module]]
    local fn = must(must(entity._EngineHooks)[name])
    return fn(entity, ...)
end

---A player stand-in with the methods the death think reads.
---@param bot boolean
---@param alive boolean
---@return Player
local function fakePlayer(bot, alive)
    ---@type table<string, any>
    local fake = { spawns = 0, alive = alive }
    fake.IsValid = function() return true end
    fake.IsPlayer = function() return true end
    fake.IsBot = function() return bot end
    fake.Alive = function(self) return self.alive end
    fake.Team = function() return 1 end
    fake.Spawn = function(self)
        self.spawns = self.spawns + 1
        self.alive = true
    end
    return fake --[[@as Player]]
end

---@param ply Player
---@return integer
local function spawnsOf(ply)
    return (ply --[[@as table<string, any>]]).spawns
end

---Replaces player.Iterator with one over list; afterEach puts the real one back. GLuaTest's stub is only in the
---environment of a case function, not of a file-level helper.
---@param list Player[]
local function stubPlayers(list)
    rawset(player, "Iterator", function() return ipairs(list) end)
end

return {
    groupName = "PW respawn regression",
    beforeEach = function(state)
        state.store = PW._MatchRules
        state.activeMode = PW.ActiveMode
        state.getPhase = match().GetPhase
        state.iterator = player.Iterator
        state.phase = "LIVE"
        PW._MatchRules = must(PW.MatchRules)._NewStore()
        match().GetPhase = function() return state.phase end
        PW.ActiveMode = PW.Modes.Get("ffa")
        hook.Add("PW_RespawnDelay", listenerId, function() return 0 end)
    end,
    afterEach = function(state)
        for _, name in ipairs(hookNames) do hook.Remove(name, listenerId) end
        match().GetPhase = state.getPhase --[[@as fun(): PW.PhaseName]]
        rawset(player, "Iterator", state.iterator)
        PW._MatchRules = state.store
        PW.ActiveMode = state.activeMode
    end,
    cases = {
        {
            name = "A dead bot respawns in LIVE without any PlayerDeathThink call (the engine thinks no dead bot)",
            func = function()
                local deadBot, aliveBot, deadHuman = fakePlayer(true, false), fakePlayer(true, true),
                    fakePlayer(false, false)
                stubPlayers({ deadBot, aliveBot, deadHuman })
                engineHook("Tick")
                expect(spawnsOf(deadBot)).to.equal(1)
                expect(spawnsOf(aliveBot)).to.equal(0)
                -- A human's client sends commands while dead: the engine's PlayerDeathThink respawns them.
                expect(spawnsOf(deadHuman)).to.equal(0)
                engineHook("Tick")
                expect(spawnsOf(deadBot)).to.equal(1)
            end
        },
        {
            name = "A dead bot waits for PW_RespawnDelay and for PW_CanRespawn, like a player",
            func = function()
                hook.Remove("PW_RespawnDelay", listenerId)
                hook.Add("PW_RespawnDelay", listenerId, function() return 30 end)
                local slow = fakePlayer(true, false)
                stubPlayers({ slow })
                engineHook("Tick")
                expect(PW._MatchRules.respawnAt[slow]).to.equal(CurTime() + 30)
                expect(spawnsOf(slow)).to.equal(0)
                hook.Remove("PW_RespawnDelay", listenerId)
                hook.Add("PW_RespawnDelay", listenerId, function() return 0 end)
                local blocked = fakePlayer(true, false)
                hook.Add("PW_CanRespawn", listenerId, function() return false end)
                stubPlayers({ blocked })
                engineHook("Tick")
                expect(spawnsOf(blocked)).to.equal(0)
            end
        },
        {
            name = "Outside LIVE the Tick hook respawns no bot",
            func = function(state)
                state.phase = "POSTMATCH"
                local bot = fakePlayer(true, false)
                stubPlayers({ bot })
                engineHook("Tick")
                expect(spawnsOf(bot)).to.equal(0)
                expect(PW._MatchRules.respawnAt[bot]).to.beNil()
            end
        }
    }
}
