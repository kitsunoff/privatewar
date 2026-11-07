-- Phase 1 optional-addon boundary scaffold, not gameplay or an observed RED/GREEN result.
-- Presence is established from the mounted source, never from successful registration: an installed but broken
-- mode must fail instead of looking like an absent optional addon. A manifest/type-only scaffold is not a mode.

local modeId = "pw_infection"
local modePath = "privatewar/modes/" .. modeId .. ".lua"

local suite = {
    groupName = "PW Infection addon boundary",
    cases = {
        {
            name = "Infection: base modes remain registered with or without the optional addon",
            func = function()
                for _, id in ipairs({ "tdm", "ffa", "dom", "kc", "round_base" }) do
                    expect(PW.Modes.Get(id)).to.exist()
                end
            end
        },
        {
            name = "Infection: mounted mode source requires registration; absence leaves no mode entry",
            func = function()
                local stored = PW.Modes.GetStored(modeId)
                if file.Exists(modePath, "LUA") then
                    assert(stored ~= nil, "mounted Infection source failed to register; this is not an absent addon")
                    local mode = PW.Modes.Get(modeId)
                    assert(mode ~= nil, "mounted Infection mode failed Base resolution")
                    expect(mode.Base).to.equal("round_base")
                    expect(mode.Teams).to.equal(2)
                    expect(mode.Abstract == true).to.beFalse()
                else
                    expect(stored).to.beNil()
                    expect(PW.Modes.Get(modeId)).to.beNil()
                end
            end
        }
    }
}

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection addon has not implemented its rules")
    return value
end

---Only a genuinely unmounted addon may skip addon-specific rules. Never infer absence from a missing API.
---@return boolean
local function absent()
    return not file.Exists("privatewar/types/pw_infection.lua", "LUA") and not file.Exists(modePath, "LUA")
end

---@return PW.InfectionRulesLib
local function rules() return must(PW.InfectionRules) end

---@return PW.InfectionParticipant[]
local function roster()
    return { { id = "host", bot = false, life = 1 }, { id = "bot1", bot = true, life = 1 },
        { id = "bot2", bot = true, life = 1 } }
end

---@param seed string?
---@return PW.InfectionRound
local function round(seed) return must(rules().NewRound(roster(), seed or "bot1", 120)) end

local cases = {
    {
        name = "Infection: one host plus one bot is sufficient; fewer than two cannot start",
        func = function()
            local players = roster()
            table.remove(players)
            expect(rules().NewRound(players, "host", 120)).to.exist()
            table.remove(players)
            local value, reason = rules().NewRound(players, "host", 120)
            expect(value).to.beNil()
            expect(isstring(reason) and reason ~= "").to.beTrue()
        end
    },
    {
        name = "Infection: either actor type can be seeded and repeats are avoided when another identity is eligible",
        func = function()
            local players = roster()
            expect(rules().PickSeed(players, nil, function() return 0 end)).to.equal("host")
            expect(rules().PickSeed(players, nil, function() return 0.999 end)).to.equal("bot2")
            for _, previous in ipairs({ "host", "bot1", "bot2" }) do
                for _, roll in ipairs({ 0, 0.5, 0.999 }) do
                    expect(rules().PickSeed(players, previous, function() return roll end) ~= previous).to.beTrue()
                end
            end
        end
    },
    {
        name = "Infection: roles are seeded before loadout resolution and every new round resets converted lives",
        func = function()
            local first = round()
            expect(first.players.host.role).to.equal("survivor")
            expect(first.players.bot1.role).to.equal("infected")
            expect(first.players.bot1.initial).to.beTrue()
            expect(rules().Death(first, "host", 1, 10)).to.beTrue()
            expect(first.players.host.role).to.equal("infected")
            local nextRound = round("bot2")
            expect(nextRound.players.host.role).to.equal("survivor")
            expect(nextRound.players.bot1.role).to.equal("survivor")
            expect(nextRound.players.bot2.initial).to.beTrue()
        end
    },
    {
        name = "Infection: survivor death converts once; stale duplicate and infected death do not reconvert",
        func = function()
            local current = round()
            expect(rules().Death(current, "host", 0, 10)).to.beFalse()
            expect(rules().Death(current, "host", 1, 10)).to.beTrue()
            expect(rules().Death(current, "host", 1, 10)).to.beFalse()
            expect(rules().Death(current, "bot1", 1, 11)).to.beFalse()
            expect(current.players.host.converted).to.beTrue()
            -- No attacker is required: world/suicide conversion cannot fabricate credit or an award.
            expect(current.players.host.initial).to.beFalse()
        end
    },
    {
        name = "Infection: dead pending infected remains present; last infected disconnect gives survivors victory",
        func = function()
            local current = round()
            rules().Death(current, "bot1", 1, 1)
            expect(rules().Winner(current, 2)).to.beNil()
            rules().Disconnect(current, "bot1", 3)
            expect(rules().Winner(current, 3)).to.equal("survivor")
        end
    },
    {
        name = "Infection: all-converted wins early; exact deadline has priority and cannot be overwritten",
        func = function()
            local before, exact = round(), round()
            rules().Death(before, "host", 1, 119)
            rules().Death(before, "bot2", 1, 119.9)
            expect(rules().Winner(before, 119.9)).to.equal("infected")
            expect(rules().Winner(before, 121)).to.equal("infected")
            rules().Death(exact, "host", 1, 119)
            expect(rules().Death(exact, "bot2", 1, 120)).to.beFalse()
            expect(rules().Winner(exact, 120)).to.equal("survivor")
            rules().Disconnect(exact, "bot2", 121)
            expect(rules().Winner(exact, 122)).to.equal("survivor")
        end
    },
    {
        name = "Infection: reconnect and new JIP identities cannot gain a life during the current round",
        func = function()
            local current = round()
            rules().Disconnect(current, "host", 1)
            expect(rules().Admit(current, { id = "host", bot = false, life = 2 })).to.beFalse()
            expect(rules().Admit(current, { id = "newcomer", bot = false, life = 1 })).to.beFalse()
            expect(current.players.host.present).to.beFalse()
            expect(current.players.newcomer).to.beNil()
        end
    },
    {
        name = "Infection: living survivors and winning initial seeds earn round wins; converted winners do not",
        func = function()
            local infectedWin, survivorWin = round(), round("host")
            rules().Death(infectedWin, "host", 1, 1)
            rules().Death(infectedWin, "bot2", 1, 2)
            rules().Winner(infectedWin, 2)
            rules().Winner(survivorWin, 120)
            local result = rules().Summary({ infectedWin, survivorWin })
            expect(result.teams).to.beFalse()
            expect(result.standings).to.deepEqual({ { id = "bot1", score = 2 },
                { id = "bot2", score = 1 }, { id = "host", score = 0 } })
            expect(result.draw).to.beFalse()
            expect(result.winner).to.equal("bot1")
            local tie = rules().Summary({ survivorWin })
            expect(tie.draw).to.beTrue()
            expect(tie.winner).to.beNil()
        end
    }
}

for _, case in ipairs(cases) do
    case.skip = absent
    suite.cases[#suite.cases + 1] = case
end

return suite
