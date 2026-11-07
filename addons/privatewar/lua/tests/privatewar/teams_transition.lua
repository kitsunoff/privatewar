-- Frozen generic team transition contract. No gameplay implementation and no real spawns/bots.
local listener = "PW_Test_TeamTransition"
local names = { "PW_CanChangeTeam", "PW_PlayerTeamChanging", "PW_PlayerTeamChanged", "PW_SelectLateTeam" }

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "frozen public API is not implemented")
    return value
end

---@param team integer
---@return Player, table<string, any>
local function participant(team)
    local data = { team = team, dead = true, spectating = false, spawned = 0, healed = 0, given = 0, valid = true }
    return {
        IsValid = function() return data.valid end, IsPlayer = function() return true end,
        IsBot = function() return false end, Alive = function() return not data.dead end,
        Team = function() return data.team end, SetTeam = function(_, to) data.team = to end,
        GetNW2Bool = function() return data.spectating end,
        GetObserverMode = function() return OBS_MODE_ROAMING end,
        Spawn = function() data.spawned = data.spawned + 1 end,
        SetHealth = function() data.healed = data.healed + 1 end,
        Give = function() data.given = data.given + 1 end
    } --[[@as Player]], data
end

---@param ply Player
---@param to any
---@param reason any
---@return boolean, string?
local function transition(ply, to, reason)
    return must(must(PW.Teams).Transition)(ply, to, reason)
end

return {
    groupName = "PW generic team transitions",
    beforeEach = function(state)
        state.mode = PW.ActiveMode
        state.phase = must(PW.Match).GetPhase
        state.nowPhase = "LIVE"
        rawset(must(PW.Match), "GetPhase", function() return state.nowPhase end)
        PW.ActiveMode = { ClassName = "test_managed", Teams = 2, TeamPolicy = "managed",
            IsValid = function() return true end, PW_CanChangeTeam = function() return true end }
    end,
    afterEach = function(state)
        for _, name in ipairs(names) do hook.Remove(name, listener) end
        must(PW.Match).GetPhase = state.phase
        PW.ActiveMode = state.mode
    end,
    cases = {
        {
            name = "Transition: admitted dead and pre-spawn observer bodies can change without spawn heal or give",
            func = function()
                local ply, data = participant(1)
                expect(transition(ply, 2, "role_change")).to.beTrue()
                expect(data.team).to.equal(2)
                expect({ data.spawned, data.healed, data.given }).to.deepEqual({ 0, 0, 0 })
            end
        },
        {
            name = "Transition: explicit authorization required; listener precedes mode, no global false veto",
            func = function()
                local ply = participant(1)
                must(PW.ActiveMode).PW_CanChangeTeam = function() return nil end
                expect(transition(ply, 2, "role_change")).to.beFalse()
                must(PW.ActiveMode).PW_CanChangeTeam = function() return false end
                hook.Add("PW_CanChangeTeam", listener, function() return true end)
                expect(transition(ply, 2, "role_change")).to.beTrue()
                hook.Add("PW_CanChangeTeam", listener, function() return false end)
                must(PW.ActiveMode).PW_CanChangeTeam = function() return true end
                expect(transition(ply, 1, "role_change")).to.beFalse()
                expect(ply:Team()).to.equal(2)
            end
        },
        {
            name = "Transition: changing sees old team, changed sees new; nested rejected, same-team no-op",
            func = function()
                local ply = participant(1)
                ---@type string[]
                local log = {}
                hook.Add("PW_PlayerTeamChanging", listener, function(who, from, to, reason)
                    expect(who).to.equal(ply)
                    expect({ from, to, reason, who:Team() }).to.deepEqual({ 1, 2, "role_change", 1 })
                    expect(transition(ply, 2, "role_change")).to.beFalse()
                    log[#log + 1] = "before"
                end)
                hook.Add("PW_PlayerTeamChanged", listener, function(who)
                    expect(who:Team()).to.equal(2)
                    log[#log + 1] = "after"
                end)
                expect(transition(ply, 2, "role_change")).to.beTrue()
                expect(transition(ply, 2, "role_change")).to.beTrue()
                expect(log).to.deepEqual({ "before", "after" })
            end
        },
        {
            name = "Transition: malformed spectator invalid FFA and non-LIVE requests mutate nothing and emit nothing",
            func = function(state)
                local ply, data = participant(1)
                local events = 0
                hook.Add("PW_PlayerTeamChanging", listener, function() events = events + 1 end)
                hook.Add("PW_PlayerTeamChanged", listener, function() events = events + 1 end)
                for _, to in ipairs({ 0, 3, 1.5, math.huge, "2", false }) do
                    expect(transition(ply, to, "role_change")).to.beFalse()
                end
                expect(transition(ply, 2, "unknown")).to.beFalse()
                data.spectating = true
                expect(transition(ply, 2, "role_change")).to.beFalse()
                data.spectating, data.valid = false, false
                expect(transition(ply, 2, "role_change")).to.beFalse()
                data.valid = true
                must(PW.ActiveMode).Teams = 0
                expect(transition(ply, 2, "role_change")).to.beFalse()
                must(PW.ActiveMode).Teams = 2
                state.nowPhase = "POSTMATCH"
                expect(transition(ply, 2, "role_change")).to.beFalse()
                expect(data.team).to.equal(1)
                expect(events).to.equal(0)
            end
        },
        {
            name = "Managed late placement: defer or invalid answer never falls back to balanced placement",
            func = function()
                local ply, data = participant(TEAM_UNASSIGNED)
                local other = participant(1)
                for _, answer in ipairs({ false, 3, 1.5, "2" }) do
                    must(PW.ActiveMode).PW_SelectLateTeam = function() return answer end
                    expect(must(must(PW.Teams)._PlaceLate)(ply, { ply, other })).to.beNil()
                    expect(data.team).to.equal(TEAM_UNASSIGNED)
                end
                must(PW.ActiveMode).PW_SelectLateTeam = function() return nil end
                expect(must(must(PW.Teams)._PlaceLate)(ply, { ply, other })).to.beNil()
                must(PW.ActiveMode).PW_SelectLateTeam = function() return 1 end
                expect(must(must(PW.Teams)._PlaceLate)(ply, { ply, other })).to.equal(1)
                expect(data.team).to.equal(1)
            end
        },
        {
            name = "Balanced mode: ordinary late placement remains smallest-team with no managed provider",
            func = function()
                local ply = participant(TEAM_UNASSIGNED)
                local other = participant(1)
                must(PW.ActiveMode).TeamPolicy = "balanced"
                expect(must(must(PW.Teams)._PlaceLate)(ply, { ply, other })).to.equal(2)
            end
        }
    }
}
