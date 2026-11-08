-- T-11.10 corrective regressions only. Existing postmatch reducer/START formatter remain unchanged.
-- These cases supplement match_flow_ui.lua and hud_xpbar.lua, never replace their queue/lifecycle coverage.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.JipLib
local function jip() return must(PW.Jip) end

---@class PW.LobbyBodyProbe
---@field team integer
---@field weapons integer
---@field ammo integer
---@field observer integer
---@field spawns integer
---@field bot boolean

---@param bot boolean
---@return Player, PW.LobbyBodyProbe
local function body(bot)
    local state = { team = 1, weapons = 2, ammo = 120, observer = OBS_MODE_NONE, spawns = 0, bot = bot }
    return {
        IsValid = function() return true end,
        IsBot = function() return state.bot end,
        SetTeam = function(_, value) state.team = value end,
        StripWeapons = function() state.weapons = 0 end,
        RemoveAllAmmo = function() state.ammo = 0 end,
        Spectate = function(_, value) state.observer = value end,
        Spawn = function() state.spawns = state.spawns + 1 end
    } --[[@as Player]], state
end

---@param state PW.LobbyBodyProbe
local function expectClean(state)
    assert(state.team == TEAM_UNASSIGNED, "lobby body still has a playable team")
    assert(state.weapons == 0, "lobby body still has weapons")
    assert(state.ammo == 0, "lobby body still has ammo")
    assert(state.observer == OBS_MODE_ROAMING, "lobby body is not a roaming observer")
    assert(state.spawns == 0, "lobby cleanup recursively spawned the player")
end

return {
    groupName = "PW match flow corrective regressions",
    cases = {
        {
            name = "Button countdown: PREMATCH and pending map change share ceil and zero clamp without the old text",
            func = function()
                local lobby = must(PW.Lobby)
                for _, now in ipairs({ 100, 102.9, 103, 103.1, 110 }) do
                    local expected = math.max(0, math.ceil(103 - now))
                    local start = must(lobby._StartButton({ phase = "PREMATCH", phaseEnd = 103,
                        changeAt = -1, now = now }))
                    local change = must(lobby._StartButton({ phase = "LOBBY", phaseEnd = -1,
                        changeAt = 103, now = now }))
                    expect(start.seconds).to.equal(expected)
                    expect(change.seconds).to.equal(expected)
                    expect(start.label).to.equal(string.format(lobby.FlowText.starting, expected))
                    expect(change.label).to.equal(string.format(lobby.FlowText.changing, expected))
                    expect(string.find(string.lower(start.label), "match starts from", 1, true)).to.beNil()
                    expect(string.find(string.lower(change.label), "match starts from", 1, true)).to.beNil()
                end
            end
        },
        {
            name = "Map change: zero and negative delays announce the same clamped positive deadline",
            func = function(state)
                local change = must(PW.MapChange)
                state.previous = PW._MapChange
                local now, begun = 1000, 0
                local announcedAt, announcedMap, announcedMode = -1, "", ""
                stub(change, "_Begin").with(function(mode, map)
                    expect(mode.ClassName).to.equal("pwt_flow")
                    expect(map).to.equal("gm_flow_there")
                    expect(now).to.equal(announcedAt)
                    begun = begun + 1
                    return true
                end)
                for _, delay in ipairs({ 0, -5, 0.25, 1, 5 }) do
                    now, begun = 1000, 0
                    announcedAt, announcedMap, announcedMode = -1, "", ""
                    PW._MapChange = change._NewStore({
                        clock = function() return now end,
                        delay = function() return delay end,
                        log = function() end,
                        announce = function(map, mode, at)
                            announcedMap, announcedMode, announcedAt = map, mode, at
                        end
                    })
                    expect(change.Schedule({ ClassName = "pwt_flow" }, "gm_flow_there")).to.beTrue()
                    expect(announcedAt).to.equal(1000 + math.max(1, delay))
                    expect(announcedMap).to.equal("gm_flow_there")
                    expect(announcedMode).to.equal("pwt_flow")
                    expect(change.IsChanging()).to.beTrue()
                    expect(begun).to.equal(0)
                    now = announcedAt - 0.001
                    change._Tick()
                    expect(begun).to.equal(0)
                    now = announcedAt
                    change._Tick()
                    expect(begun).to.equal(1)
                    change._Tick()
                    expect(begun).to.equal(1)
                end
            end,
            cleanup = function(state)
                if state.previous ~= nil then PW._MapChange = state.previous end
            end
        },
        {
            name = "Map popup: visible before deadline and absent at or after deadline",
            func = function()
                local lobby = must(PW.Lobby)
                local facts = { changeAt = 105, now = 104.999, map = "gm_construct", mapName = "Construct Night",
                    modeName = "Team Deathmatch" }
                local popup = must(lobby._MapChangePopup(facts))
                expect(popup.map).to.equal("CONSTRUCT NIGHT")
                expect(popup.mode).to.equal("TEAM DEATHMATCH")
                expect(popup.seconds).to.equal(1)
                for _, now in ipairs({ 105, 105.001, 1000 }) do
                    facts.now = now
                    expect(lobby._MapChangePopup(facts)).to.beNil()
                    local start = must(lobby._StartButton({ phase = "LOBBY", phaseEnd = -1,
                        changeAt = facts.changeAt, now = now }))
                    expect(start.seconds).to.equal(0)
                    expect(start.label).to.equal(string.format(lobby.FlowText.changing, 0))
                end
            end
        },
        {
            name = "Lobby entry: initial and postmatch humans and bots use the same body cleanup path",
            func = function()
                local lib = jip()
                local human, humanState = body(false)
                local bot, botState = body(true)
                ---@type fun()[]
                local deferred = {}
                local phase = "LOBBY"
                local store = must(lib._NewStore)({
                    phase = function() return phase end,
                    players = function() return { human, bot } end,
                    defer = function(fn) deferred[#deferred + 1] = fn end
                })
                -- First PlayerSpawn, including bots created after the initial phase notification.
                -- The return value still reports only JIP parking, not lobby presentation cleanup.
                expect(must(lib._OnSpawn)(store, human)).to.beFalse()
                expect(must(lib._OnSpawn)(store, bot)).to.beFalse()
                for _, fn in ipairs(deferred) do fn() end
                expectClean(humanState)
                expectClean(botState)
                -- Actual returning phase path uses that exact store.unspawn function for both actors.
                deferred = {}
                humanState.team, humanState.weapons, humanState.ammo, humanState.observer = 2, 3, 200, OBS_MODE_NONE
                botState.team, botState.weapons, botState.ammo, botState.observer = 1, 1, 30, OBS_MODE_NONE
                expect(must(lib._OnLobby)(store, "LOBBY", "POSTMATCH")).to.equal(2)
                for _, fn in ipairs(deferred) do fn() end
                expectClean(humanState)
                expectClean(botState)
                expect(must(PW.Lobby)._ShouldShow("LOBBY", true, true)).to.beTrue()
                expect(must(PW.Lobby)._ScreenFor("LOBBY")).to.equal("lobby")
                phase = "LIVE"
                expect(must(lib._OnSpawn)(store, human)).to.beFalse()
            end
        },
        {
            name = "Lobby entry: deferred cleanup cannot unspawn a match that already started",
            func = function()
                local lib = jip()
                local ply, state = body(false)
                ---@type fun()[]
                local deferred = {}
                local phase = "LOBBY"
                local store = must(lib._NewStore)({
                    phase = function() return phase end,
                    players = function() return { ply } end,
                    defer = function(fn) deferred[#deferred + 1] = fn end
                })
                must(lib._OnSpawn)(store, ply)
                must(lib._OnLobby)(store, "LOBBY", "POSTMATCH")
                phase = "LIVE"
                for _, fn in ipairs(deferred) do fn() end
                expect(state.team).to.equal(1)
                expect(state.weapons).to.equal(2)
                expect(state.observer).to.equal(OBS_MODE_NONE)
            end
        }
    }
}
