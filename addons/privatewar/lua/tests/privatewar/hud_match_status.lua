-- T-6.2 / U-8 HUD match status (TASKS.md, "Mandatory test cases" T-6.2 and U-8; 09-hud.md d.2). Pure: timer
-- formatting, which end the timer counts to, the victory/defeat decision, the score order, the score key of a
-- mode and the result fields the server publishes. Drawing is a checkpoint.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HudLib
local function hud()
    return must(PW.HUD)
end

---@return PW.MatchRulesLib
local function rules()
    return must(PW.MatchRules)
end

---@param teams boolean
---@param draw boolean
---@param winner any
---@param count integer
---@return PW.MatchResult
local function result(teams, draw, winner, count)
    ---@type PW.Standing[]
    local standings = {}
    for i = 1, count do standings[i] = { id = i, score = 0 } end
    return { reason = "scorelimit", teams = teams, draw = draw, winner = winner, standings = standings }
end

return {
    groupName = "PW HUD match status",
    cases = {
        {
            name = "The match_status element is registered and phase_label is gone",
            func = function()
                local registry = must(PW.Registries["hud"])
                expect(registry.Get("match_status")).to.exist()
                expect(registry.Get("phase_label")).to.beNil()
            end
        },
        {
            name = "Timer: the remaining time comes from the end time, nil when there is none, never negative",
            func = function()
                expect(hud()._Remaining(110, 100)).to.equal(10)
                expect(hud()._Remaining(-1, 100)).to.beNil()
                expect(hud()._Remaining(nil, 100)).to.beNil()
                expect(hud()._Remaining(90, 100)).to.equal(0)
            end
        },
        {
            name = "Timer: formatted M:SS, rounded up, no tenths",
            func = function()
                local format = hud()._FormatTime
                expect(format(461.2)).to.equal("7:42")
                expect(format(60)).to.equal("1:00")
                expect(format(59.01)).to.equal("1:00")
                expect(format(9.5)).to.equal("0:10")
                expect(format(0.2)).to.equal("0:01")
                expect(format(0)).to.equal("0:00")
                expect(format(-3)).to.equal("0:00")
                expect(format(3600)).to.equal("60:00")
            end
        },
        {
            name = "Timer: LIVE counts to the mode end, every other phase to the phase end",
            func = function()
                local timerEnd = hud()._TimerEnd
                expect(timerEnd("LIVE", 500, 300)).to.equal(300)
                expect(timerEnd("LIVE", 500, -1)).to.equal(-1)
                expect(timerEnd("PREMATCH", 12, 300)).to.equal(12)
                expect(timerEnd("POSTMATCH", 40, 300)).to.equal(40)
            end
        },
        {
            name = "Victory/defeat: team mode, the local team won, lost or drew",
            func = function()
                local verdict = hud()._Verdict
                expect(verdict(false, 1, 2, 1, 5)).to.equal("victory")
                expect(verdict(false, 2, 2, 1, 5)).to.equal("defeat")
                expect(verdict(true, 0, 2, 1, 5)).to.equal("draw")
            end
        },
        {
            name = "Victory/defeat: FFA compares the winner with the local user id",
            func = function()
                local verdict = hud()._Verdict
                expect(verdict(false, 5, 0, 0, 5)).to.equal("victory")
                expect(verdict(false, 9, 0, 0, 5)).to.equal("defeat")
                expect(verdict(true, 0, 0, 0, 5)).to.equal("draw")
            end
        },
        {
            name = "Victory/defeat: no result gives nothing, a spectator gets a neutral verdict",
            func = function()
                local verdict = hud()._Verdict
                expect(verdict(false, 0, 2, 1, 5)).to.beNil()
                expect(verdict(false, 1, 2, 0, 5)).to.equal("over")
                expect(verdict(false, 1, 2, 3, 5)).to.equal("over")
            end
        },
        {
            name = "Score order: own team first, the leading other team second",
            func = function()
                local first, second = hud()._Lead({ 10, 52, 47 }, 3, 3)
                expect(first).to.equal(3)
                expect(second).to.equal(2)
                first, second = hud()._Lead({ 10, 52 }, 2, 1)
                expect(first).to.equal(1)
                expect(second).to.equal(2)
            end
        },
        {
            name = "Score order: ties go to the lower index; without an own team the top two",
            func = function()
                local first, second = hud()._Lead({ 4, 9, 9 }, 3, 1)
                expect(first).to.equal(1)
                expect(second).to.equal(2)
                first, second = hud()._Lead({ 4, 9, 7 }, 3, nil)
                expect(first).to.equal(2)
                expect(second).to.equal(3)
                first, second = hud()._Lead({ 4 }, 1, 1)
                expect(first).to.equal(1)
                expect(second).to.beNil()
            end
        },
        {
            name = "Score order: FFA shows own frags against the best other player's",
            func = function()
                -- frags of the players in a list; the local player is index 2 with 3 frags
                local first, second = hud()._Lead({ 12, 3, 8 }, 3, 2)
                expect(first).to.equal(2)
                expect(second).to.equal(1)
            end
        },
        {
            name = "Score key: the mode field wins, then the known modes, then the kill count",
            func = function()
                local key = rules()._HudScoreKey
                expect(key({ ClassName = "x", HudScoreKey = "pw_custom_" })).to.equal("pw_custom_")
                expect(key({ ClassName = "dom", Base = "tdm" })).to.equal("pw_dom_score_")
                expect(key({ ClassName = "kc", Base = "tdm" })).to.equal("pw_kc_confirms_")
                expect(key({ ClassName = "sd", Base = "round_base" })).to.equal("pw_round_wins_")
                expect(key({ ClassName = "tdm" })).to.equal("pw_kills_team_")
                expect(key(nil)).to.equal("pw_kills_team_")
            end
        },
        {
            name = "Result fields: team winner, draw and FFA winner become plain numbers",
            func = function()
                local fields = rules()._ResultFields
                local winner, draw, teams = fields(result(true, false, 2, 2))
                expect(winner).to.equal(2)
                expect(draw).to.beFalse()
                expect(teams).to.equal(2)
                winner, draw, teams = fields(result(true, true, nil, 3))
                expect(winner).to.equal(0)
                expect(draw).to.beTrue()
                expect(teams).to.equal(3)
                local player = { UserID = function() return 7 end }
                winner, draw, teams = fields(result(false, false, player, 1))
                expect(winner).to.equal(7)
                expect(teams).to.equal(0)
            end
        }
    }
}
