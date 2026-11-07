-- Match end and lobby flow (Phase 11, match flow fixes; 00-core.md d.5, d.9; 08-lobby.md d.3; 10-frontend.md d.1):
-- the postmatch screen stays for POSTMATCH's duration (the test gate restores the match ConVars that test files
-- shorten), the START button shows the start and map change countdowns, a map change is announced and runs after a
-- delay, and the post-match lobby unspawns every player like the first lobby. Pure rules and fake stores only; the
-- real machine stays in LOBBY.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LobbyLib
local function lobby() return must(PW.Lobby) end

---@return PW.JipLib
local function jip() return must(PW.Jip) end

---@return PW.MapChangeLib
local function changer() return must(PW.MapChange) end

---@type string a backup of this test only, never the real one
local backupProbe = "privatewar_dev/match_flow_backup_probe.json"

---@class PW.MatchFlowGate
---@field Backup fun(path: string, names: string[], get: fun(name: string): string?): boolean
---@field Finish fun(path: string, set: fun(name: string, value: string)): integer?
---@field Guarded string[]

---@return PW.MatchFlowGate
local function gate()
    local found = rawget(PW, "_DevTestGate") --[[@as table?]]
    assert(found ~= nil, "PW._DevTestGate is missing: the dev addon is not loaded")
    return found --[[@as PW.MatchFlowGate]]
end

---@param state table<string, any>
---@param delay number
local function installChanger(state, delay)
    state.previousChange = PW._MapChange
    state.changelevels, state.announced = {}, {}
    PW._MapChange = changer()._NewStore({
        path = "privatewar_dev/match_flow_pending_probe.json",
        log = function() end,
        clock = function() return state.now end,
        map = function() return "gm_flow_here" end,
        delay = function() return delay end,
        changelevel = function(map)
            local calls = state.changelevels --[[@as string[] ]]
            calls[#calls + 1] = map
        end,
        announce = function(map, mode, at)
            local calls = state.announced --[[@as table[] ]]
            calls[#calls + 1] = { map = map, mode = mode, at = at }
        end
    })
end

---@param state table<string, any>
local function restoreChanger(state)
    if state.previousChange ~= nil then PW._MapChange = state.previousChange end
    if file.Exists("privatewar_dev/match_flow_pending_probe.json", "DATA") then
        file.Delete("privatewar_dev/match_flow_pending_probe.json")
    end
end

---A player stand-in that records SetTeam and Spawn.
---@param log string[]
---@return Player
local function fakePlayer(log)
    return {
        IsValid = function() return true end,
        SetTeam = function(_, team) log[#log + 1] = "team:" .. tostring(team) end,
        Spawn = function() log[#log + 1] = "spawn" end
    } --[[@as Player]]
end

return {
    groupName = "PW match flow and lobby",
    cases = {
        {
            name = "Postmatch stays for its duration: POSTMATCH until pw_postmatch_time has passed, then the lobby",
            func = function()
                local settings = { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
                local state = { phase = "POSTMATCH", endsAt = 1015, countdown = false }
                expect(PW.Phase._Next(state, 1000, false, settings)).to.beNil()
                expect(PW.Phase._Next(state, 1014.9, false, settings)).to.beNil()
                expect(must(PW.Phase._Next(state, 1015, false, settings)).phase).to.equal("LOBBY")
                settings.afterMatch = "rotation"
                expect(must(PW.Phase._Next(state, 1015, false, settings)).phase).to.equal("VOTE")
                -- The client: the postmatch screen for POSTMATCH, the lobby never over it.
                expect(lobby()._ScreenFor("POSTMATCH")).to.equal("postmatch")
                expect(lobby()._ShouldShow("POSTMATCH", true, true)).to.beFalse()
                expect(lobby()._ShouldShow("VOTE", true, true)).to.beFalse()
                local decide = must(must(PW.UI).Postmatch).Decide
                local facts = { phase = "POSTMATCH", enabled = true, open = true, otherRoot = false, dismissed = false }
                expect(decide("tick", facts)).to.beNil()
            end
        },
        {
            name = "Postmatch duration: the real pw_postmatch_time is not a test leftover (at least 5 s)",
            func = function()
                expect(must(PW.Match)._ReadSettings().postmatch >= 5).to.beTrue()
            end
        },
        {
            name = "Test gate: the end of a run restores the shortened match ConVars from the backup",
            func = function()
                local values = { pw_postmatch_time = "15", pw_countdown = "10" }
                expect(gate().Backup(backupProbe, { "pw_postmatch_time", "pw_countdown" },
                    function(name) return values[name] end)).to.beTrue()
                -- A test shortened them and its own restore never ran (an async timeout).
                values.pw_postmatch_time, values.pw_countdown = "0.5", "0"
                local count = gate().Finish(backupProbe, function(name, value) values[name] = value end)
                expect(count).to.equal(2)
                expect(values.pw_postmatch_time).to.equal("15")
                expect(values.pw_countdown).to.equal("10")
                expect(file.Exists(backupProbe, "DATA")).to.beFalse()
                -- Every match ConVar a test file sets is guarded.
                ---@type table<string, true>
                local guarded = {}
                for _, name in ipairs(gate().Guarded) do guarded[name] = true end
                for _, name in ipairs({ "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch",
                    "pw_vote_time" }) do
                    expect(guarded[name], name).to.beTrue()
                end
            end,
            cleanup = function()
                if file.Exists(backupProbe, "DATA") then file.Delete(backupProbe) end
            end
        },
        {
            name = "Screens by phase: the lobby in LOBBY and PREMATCH, the summary in POSTMATCH, the vote in VOTE",
            func = function()
                expect(lobby()._ScreenFor("LOBBY")).to.equal("lobby")
                expect(lobby()._ScreenFor("PREMATCH")).to.equal("lobby")
                expect(lobby()._ScreenFor("LIVE")).to.beNil()
                expect(lobby()._ScreenFor("VOTE")).to.equal("vote")
                expect(lobby()._ShouldShow("PREMATCH", true, true)).to.beTrue()
                expect(lobby()._ShouldShow("LIVE", true, true)).to.beFalse()
            end
        },
        {
            name = "Button countdown: START MATCH in LOBBY, STARTING N in PREMATCH, MAP CHANGE N while a change waits",
            func = function()
                local text = lobby().FlowText
                expect(lobby()._StartButton({ phase = "LOBBY", phaseEnd = -1, now = 100, changeAt = -1 })).to.beNil()
                local starting = must(lobby()._StartButton({ phase = "PREMATCH", phaseEnd = 104.2, now = 100,
                    changeAt = -1 }))
                expect(starting.label).to.equal(string.format(text.starting, 5))
                expect(starting.seconds).to.equal(5)
                expect(starting.reason).to.equal(text.startingReason)
                local changing = must(lobby()._StartButton({ phase = "LOBBY", phaseEnd = -1, now = 100,
                    changeAt = 103 }))
                expect(changing.label).to.equal(string.format(text.changing, 3))
                expect(changing.reason).to.equal(text.changingReason)
                -- A pending change wins over the phase (a rotation waits in VOTE), and the count never goes negative.
                local late = must(lobby()._StartButton({ phase = "VOTE", phaseEnd = -1, now = 110, changeAt = 103 }))
                expect(late.seconds).to.equal(0)
            end
        },
        {
            name = "Button countdown on the hub: locked, the countdown label, the countdown style; untouched otherwise",
            func = function()
                ---@type PW.LobbyAction
                local start = { id = "start", title = "Start match", locked = false, label = "START MATCH" }
                expect(lobby()._ApplyFlow(start, nil)).to.equal(start)
                expect(start.countdown).to.beNil()
                lobby()._ApplyFlow(start, { phase = "LOBBY", phaseEnd = -1, now = 0, changeAt = -1 })
                expect(start.label).to.equal("START MATCH")
                expect(start.locked).to.beFalse()
                lobby()._ApplyFlow(start, { phase = "PREMATCH", phaseEnd = 9.5, now = 0, changeAt = -1 })
                expect(start.label).to.equal(string.format(lobby().FlowText.starting, 10))
                expect(start.title).to.equal(start.label)
                expect(start.locked).to.beTrue()
                expect(start.countdown).to.beTrue()
                -- Countdown style: accent ink on a dark fill (PW.UI.Style tokens).
                local colours = lobby().CountdownColours
                expect(colours.ink).to.equal("accent")
                expect(colours.fill).to.equal("bg_raised")
            end
        },
        {
            name = "Map change popup: title, nice map name, upper-case mode and the seconds left; nil without a change",
            func = function()
                expect(lobby()._MapChangePopup({ changeAt = -1, now = 0, map = "gm_x", modeName = "TDM" })).to.beNil()
                local popup = must(lobby()._MapChangePopup({ changeAt = 104.5, now = 100, map = "de_dust2_classic",
                    modeName = "Team Deathmatch" }))
                expect(popup.title).to.equal(lobby().FlowText.popupTitle)
                expect(popup.map).to.equal("DUST2 CLASSIC")
                expect(popup.mode).to.equal("TEAM DEATHMATCH")
                expect(popup.seconds).to.equal(5)
                expect(lobby()._MapTitle("gm_construct")).to.equal("CONSTRUCT")
                expect(lobby()._MapTitle("shipment")).to.equal("SHIPMENT")
                expect(lobby()._MapTitle("gm_construct", "Construct Night")).to.equal("CONSTRUCT NIGHT")
                expect(lobby()._MapTitle("gm_construct", "gm_construct")).to.equal("CONSTRUCT")
            end
        },
        {
            name = "Map change: announced with map, mode and end time; changelevel only after the delay; guard busy",
            func = function(state)
                state.now = 1000
                installChanger(state, 5)
                ---@type string[]
                local begun = {}
                stub(changer(), "_Begin").with(function(mode, map)
                    begun[#begun + 1] = mode.ClassName .. "@" .. map
                    return true
                end)
                local mode = { ClassName = "pwt_flow" }
                expect(changer().Schedule(mode, "gm_flow_there")).to.beTrue()
                local announced = must(state.announced[1]) --[[@as { map: string, mode: string, at: number }]]
                expect(announced.map).to.equal("gm_flow_there")
                expect(announced.mode).to.equal("pwt_flow")
                expect(announced.at).to.equal(1005)
                expect(changer().IsChanging()).to.beTrue()
                expect(changer()._Decide("gm_flow_here", "gm_other", changer().IsChanging())).to.equal("busy")
                state.now = 1004.9
                changer()._Tick()
                expect(#begun).to.equal(0)
                state.now = 1005
                changer()._Tick()
                expect(begun[1]).to.equal("pwt_flow@gm_flow_there")
                changer()._Tick()
                expect(#begun).to.equal(1)
            end,
            cleanup = restoreChanger
        },
        {
            name = "Map change: no delay runs at once; a cancelled change never runs and clears the announcement",
            func = function(state)
                state.now = 1000
                installChanger(state, 0)
                local begun = 0
                stub(changer(), "_Begin").with(function()
                    begun = begun + 1
                    return true
                end)
                expect(changer().Schedule({ ClassName = "pwt_flow" }, "gm_flow_there")).to.beTrue()
                expect(begun).to.equal(1)
                expect(#state.announced).to.equal(0)
                installChanger(state, 5)
                expect(changer().Schedule({ ClassName = "pwt_flow" }, "gm_flow_there")).to.beTrue()
                expect(changer()._Cancel("test")).to.beTrue()
                expect(changer().IsChanging()).to.beFalse()
                local cleared = must(state.announced[2]) --[[@as { map: string, mode: string, at: number }]]
                expect(cleared.at).to.equal(-1)
                state.now = 1010
                changer()._Tick()
                expect(begun).to.equal(1)
                expect(changer()._Cancel("again")).to.beFalse()
            end,
            cleanup = restoreChanger
        },
        {
            name = "Map change delay setting: pw_mapchange_delay exists with the default 5, range 0..60",
            func = function()
                local convar = must(GetConVar("pw_mapchange_delay"))
                expect(convar:GetDefault()).to.equal("5")
                expect(convar:GetMin()).to.equal(0)
                expect(convar:GetMax()).to.equal(60)
            end
        },
        {
            name = "Lobby unspawn rule: entering LOBBY from a match unspawns; the first lobby and other phases do not",
            func = function()
                expect(jip()._Unspawns("LOBBY", "POSTMATCH")).to.beTrue()
                expect(jip()._Unspawns("LOBBY", "LIVE")).to.beTrue()
                expect(jip()._Unspawns("LOBBY", "VOTE")).to.beTrue()
                expect(jip()._Unspawns("LOBBY", "PREMATCH")).to.beTrue()
                expect(jip()._Unspawns("LOBBY", nil)).to.beFalse()
                expect(jip()._Unspawns("LOBBY", "LOBBY")).to.beFalse()
                expect(jip()._Unspawns("POSTMATCH", "LIVE")).to.beFalse()
                expect(jip()._Unspawns("PREMATCH", "LOBBY")).to.beFalse()
            end
        },
        {
            name = "Players are unspawned in the post-match lobby: every human and bot, after the phase change",
            func = function()
                ---@type Player[]
                local unspawned = {}
                ---@type fun()[]
                local deferred = {}
                local a, b = fakePlayer({}), fakePlayer({})
                local store = must(jip()._NewStore)({
                    players = function() return { a, b } end,
                    unspawn = function(ply) unspawned[#unspawned + 1] = ply end,
                    defer = function(fn) deferred[#deferred + 1] = fn end
                })
                expect(must(jip()._OnLobby)(store, "LOBBY", "POSTMATCH")).to.equal(2)
                expect(#unspawned).to.equal(0)
                for _, fn in ipairs(deferred) do fn() end
                expect(unspawned[1]).to.equal(a)
                expect(unspawned[2]).to.equal(b)
                expect(must(jip()._OnLobby)(store, "PREMATCH", "LOBBY")).to.equal(0)
            end
        },
        {
            name = "Unspawn is the first lobby's state: no team (TEAM_UNASSIGNED), then a spawn as a spectator",
            func = function()
                ---@type string[]
                local log = {}
                local store = must(jip()._NewStore)()
                store.unspawn(fakePlayer(log))
                expect(log[1]).to.equal("team:" .. TEAM_UNASSIGNED)
                expect(log[2]).to.equal("spawn")
            end
        }
    }
}
