-- T-4.11 Medals (TASKS.md, "Mandatory test cases" T-4.11; 06-progression.md d.3). Pure cases over plain kill facts
-- (time, attacker, victim, enemy) and plain player stand-ins; the store cases run over injected award, notify and
-- send functions. No bots, no real players.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.MedalsLib
local function lib()
    return must(PW.Medals)
end

---A player stand-in with a team (teammates share the number).
---@param name string
---@param team integer
---@return table
local function player(name, team)
    return { name = name, team = team, IsValid = function() return true end }
end

---@param a table
---@param b table
---@return boolean
local function isAlly(a, b)
    return a ~= b and a.team == b.team
end

---@class PW.MedalsTestRig
---@field state PW.MedalsState

---@return PW.MedalsTestRig
local function rig()
    return { state = lib()._NewState() }
end

---Feeds one kill to the detectors; returns the medal ids it earned.
---@param r PW.MedalsTestRig
---@param time number
---@param attacker table?
---@param victim table
---@param enemy? boolean defaults to true
---@return string[]
local function kill(r, time, attacker, victim, enemy)
    return lib()._OnKill(r.state, { time = time, attacker = attacker, victim = victim, enemy = enemy ~= false }, isAlly)
end

---@param ids string[]
---@param id string
---@return boolean
local function has(ids, id)
    for _, v in ipairs(ids) do
        if v == id then return true end
    end
    return false
end

---@param log table[]
---@return PW.MedalsStore
local function loggingStore(log)
    return lib()._NewStore({
        isAlly = isAlly,
        award = function(ply, id)
            log[#log + 1] = { "award", ply, id }
            return true
        end,
        notify = function(name, ply, id) log[#log + 1] = { name, ply, id } end,
        send = function(ply, id) log[#log + 1] = { "send", ply, id } end
    })
end

return {
    groupName = "PW medals",
    cases = {
        {
            name = "First blood: the first enemy kill of the match, once",
            func = function()
                local r = rig()
                local a, b, c = player("a", 1), player("b", 2), player("c", 2)
                expect(has(kill(r, 1, a, b), "first_blood")).to.beTrue()
                expect(has(kill(r, 2, a, c), "first_blood")).to.beFalse()
            end
        },
        {
            name = "First blood: a suicide, a world death and a teamkill do not use it up",
            func = function()
                local r = rig()
                local a, b, mate = player("a", 1), player("b", 2), player("mate", 1)
                expect(#kill(r, 1, nil, b, false)).to.equal(0)
                expect(#kill(r, 2, b, b, false)).to.equal(0)
                expect(#kill(r, 3, a, mate, false)).to.equal(0)
                expect(has(kill(r, 4, a, b), "first_blood")).to.beTrue()
            end
        },
        {
            name = "Double kill: two kills within the window; the same two kills outside it are none",
            func = function()
                local r = rig()
                local a, b, c = player("a", 1), player("b", 2), player("c", 2)
                kill(r, 10, a, b)
                expect(has(kill(r, 10 + lib().Window, a, c), "double_kill")).to.beTrue()
                local r2 = rig()
                kill(r2, 10, a, b)
                expect(has(kill(r2, 10 + lib().Window + 0.01, a, c), "double_kill")).to.beFalse()
            end
        },
        {
            name = "Triple kill: a third kill within the window of the second; no double kill on it",
            func = function()
                local r = rig()
                local a, b, c, d = player("a", 1), player("b", 2), player("c", 2), player("d", 2)
                kill(r, 10, a, b)
                kill(r, 12, a, c)
                local ids = kill(r, 14, a, d)
                expect(has(ids, "triple_kill")).to.beTrue()
                expect(has(ids, "double_kill")).to.beFalse()
            end
        },
        {
            name = "Triple kill: a third kill outside the window of the second is not a triple kill",
            func = function()
                local r = rig()
                local a, b, c, d = player("a", 1), player("b", 2), player("c", 2), player("d", 2)
                kill(r, 10, a, b)
                kill(r, 12, a, c)
                local ids = kill(r, 12 + lib().Window + 1, a, d)
                expect(has(ids, "triple_kill")).to.beFalse()
                expect(has(ids, "double_kill")).to.beFalse()
            end
        },
        {
            name = "Double kill: the chain is per attacker and dying breaks it",
            func = function()
                local r = rig()
                local a, b, c, d = player("a", 1), player("b", 2), player("c", 2), player("d", 3)
                kill(r, 10, a, b)
                expect(has(kill(r, 11, d, c), "double_kill")).to.beFalse()
                kill(r, 12, c, a)
                expect(has(kill(r, 13, a, d), "double_kill")).to.beFalse()
            end
        },
        {
            name = "Revenge: killing the player who killed you last; killing anyone else is none",
            func = function()
                local r = rig()
                local a, b, c = player("a", 1), player("b", 2), player("c", 2)
                kill(r, 1, a, b)
                expect(has(kill(r, 30, b, c), "revenge")).to.beFalse()
                local r2 = rig()
                kill(r2, 1, a, b)
                expect(has(kill(r2, 30, b, a), "revenge")).to.beTrue()
            end
        },
        {
            name = "Revenge: only the last killer counts and only once per death",
            func = function()
                local r = rig()
                local a, b, c = player("a", 1), player("b", 2), player("c", 3)
                kill(r, 1, a, b)
                kill(r, 5, c, b)
                expect(has(kill(r, 30, b, a), "revenge")).to.beFalse()
                expect(has(kill(r, 40, b, c), "revenge")).to.beTrue()
                expect(has(kill(r, 50, b, c), "revenge")).to.beFalse()
            end
        },
        {
            name = "Streak: the fifth kill without dying is a 5-kill streak, the fourth and sixth are not",
            func = function()
                local r = rig()
                local a = player("a", 1)
                for i = 1, 4 do
                    expect(has(kill(r, i * 10, a, player("v" .. i, 2)), "streak5")).to.beFalse()
                end
                expect(has(kill(r, 50, a, player("v5", 2)), "streak5")).to.beTrue()
                expect(has(kill(r, 60, a, player("v6", 2)), "streak5")).to.beFalse()
            end
        },
        {
            name = "Streak: dying resets the count; four plus four kills around a death are none",
            func = function()
                local r = rig()
                local a, b = player("a", 1), player("b", 2)
                for i = 1, 4 do kill(r, i * 10, a, player("v" .. i, 2)) end
                kill(r, 45, b, a)
                for i = 5, 8 do
                    expect(has(kill(r, i * 10, a, player("w" .. i, 2)), "streak5")).to.beFalse()
                end
            end
        },
        {
            name = "Saviour: killing an enemy who damaged a teammate within the window",
            func = function()
                local r = rig()
                local a, mate, foe = player("a", 1), player("mate", 1), player("foe", 2)
                lib()._OnDamage(r.state, { attacker = foe, victim = mate, time = 10 })
                expect(has(kill(r, 10 + lib().SaviourWindow, a, foe), "saviour")).to.beTrue()
            end
        },
        {
            name = "Saviour: not when the damage is older than the window",
            func = function()
                local r = rig()
                local a, mate, foe = player("a", 1), player("mate", 1), player("foe", 2)
                lib()._OnDamage(r.state, { attacker = foe, victim = mate, time = 10 })
                expect(has(kill(r, 10 + lib().SaviourWindow + 0.01, a, foe), "saviour")).to.beFalse()
            end
        },
        {
            name = "Saviour: not when the enemy hurt only the killer or an enemy of the killer",
            func = function()
                local r = rig()
                local a, foe, other = player("a", 1), player("foe", 2), player("other", 3)
                lib()._OnDamage(r.state, { attacker = foe, victim = a, time = 10 })
                lib()._OnDamage(r.state, { attacker = foe, victim = other, time = 10 })
                expect(has(kill(r, 11, a, foe), "saviour")).to.beFalse()
            end
        },
        {
            name = "Saviour: the damage that killed the teammate counts; a reset forgets all damage",
            func = function()
                local r = rig()
                local a, mate, foe = player("a", 1), player("mate", 1), player("foe", 2)
                lib()._OnDamage(r.state, { attacker = foe, victim = mate, time = 10 })
                kill(r, 10.5, foe, mate)
                expect(has(kill(r, 12, a, foe), "saviour")).to.beTrue()
                lib()._Reset(r.state)
                lib()._OnDamage(r.state, { attacker = foe, victim = mate, time = 20 })
                lib()._Reset(r.state)
                expect(has(kill(r, 21, a, foe), "saviour")).to.beFalse()
            end
        },
        {
            name = "Reset: first blood, chains and streaks start over",
            func = function()
                local r = rig()
                local a, b = player("a", 1), player("b", 2)
                kill(r, 1, a, b)
                lib()._Reset(r.state)
                local ids = kill(r, 2, a, b)
                expect(has(ids, "first_blood")).to.beTrue()
                expect(has(ids, "double_kill")).to.beFalse()
            end
        },
        {
            name = "Store: a medal is counted, awarded as its own score event, notified and sent to the owner",
            func = function()
                ---@type table[]
                local log = {}
                local store = loggingStore(log)
                local a, b = player("a", 1), player("b", 2)
                lib()._Kill(store, { time = 1, attacker = a, victim = b, enemy = true })
                ---@type table<string, integer>
                local kinds = {}
                for _, entry in ipairs(log) do kinds[entry[1]] = (kinds[entry[1]] or 0) + 1 end
                expect(kinds.award).to.equal(1)
                expect(kinds.PW_Medal).to.equal(1)
                expect(kinds.send).to.equal(1)
                expect(must(log[1])[3]).to.equal("first_blood")
                expect(lib()._Counts(store, a).first_blood).to.equal(1)
                expect(next(lib()._Counts(store, b))).to.equal(nil)
            end
        },
        {
            name = "Store: counts accumulate per player, reset clears them and Get-style reads are copies",
            func = function()
                local store = loggingStore({})
                local a = player("a", 1)
                for i = 1, 5 do
                    lib()._Kill(store, { time = i, attacker = a, victim = player("v" .. i, 2), enemy = true })
                end
                local counts = lib()._Counts(store, a)
                expect(counts.first_blood).to.equal(1)
                expect(counts.streak5).to.equal(1)
                expect(counts.double_kill).to.equal(1)
                expect(counts.triple_kill).to.equal(1)
                counts.streak5 = 99
                expect(lib()._Counts(store, a).streak5).to.equal(1)
                lib()._ResetStore(store)
                expect(next(lib()._Counts(store, a))).to.equal(nil)
            end
        },
        {
            name = "Store: a bot owner is not sent a message; a failed award still counts the medal",
            func = function()
                local sent = 0
                local store = lib()._NewStore({
                    isAlly = isAlly,
                    award = function() return false end,
                    notify = function() end,
                    send = function() sent = sent + 1 end
                })
                local bot = player("bot", 1)
                bot.IsBot = function() return true end
                lib()._Kill(store, { time = 1, attacker = bot, victim = player("v", 2), enemy = true })
                expect(sent).to.equal(0)
                expect(lib()._Counts(store, bot).first_blood).to.equal(1)
            end
        },
        {
            name = "The medal score events are registered as medals with their own ids",
            func = function()
                local registry = must(PW.Registries["score_events"])
                for _, id in ipairs(lib().Ids) do
                    local event = must(registry.Get(id)) --[[@as PW.ScoreEvent]]
                    expect(event.Medal).to.beTrue()
                    expect(event.Points > 0).to.beTrue()
                end
            end
        }
    }
}
