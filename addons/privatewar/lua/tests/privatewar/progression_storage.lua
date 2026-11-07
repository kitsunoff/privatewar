-- T-4.10 Progression storage (TASKS.md, "Mandatory test cases" T-4.10; 06-progression.md d.5). Pure cases over plain
-- tables (delta apply, sanity checks, the file, the wire through an in-memory buffer) and server cases over a fresh
-- store with injected settings, senders, clock-free ticks and player stand-ins. No bots, no real players, no net.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.ProgressionLib
local function lib()
    return must(PW.Progression)
end

---@return Player
local function fakePlayer()
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsBot = function() return false end
    fake.SetNW2Int = function() end
    return fake --[[@as Player]]
end

---@param class string
---@return Weapon
local function fakeWeapon(class)
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.GetClass = function() return class end
    return fake --[[@as Weapon]]
end

---@class PW.ProgressionStorageRig
---@field store PW.ProgressionStore
---@field deltas table[] { ply, delta }
---@field levels table[] { ply, levels }
---@field summaries table[] { ply, summary }
---@field refreshed Player[]

---@param settings? table<string, any>
---@param medals? table<string, integer> what the medals module answers (nil: no medals module)
---@return PW.ProgressionStorageRig
local function rig(settings, medals)
    local values = settings or {}
    ---@type table[], table[], table[], Player[]
    local deltas, levels, summaries, refreshed = {}, {}, {}, {}
    local store = lib()._NewStore({
        read = function(id) return values[id] end,
        publish = function() end,
        notify = function() end,
        sendDelta = function(ply, delta) deltas[#deltas + 1] = { ply, delta } end,
        sendLevels = function(ply, sent) levels[#levels + 1] = { ply, sent } end,
        sendSummary = function(ply, summary) summaries[#summaries + 1] = { ply, summary } end,
        refresh = function(ply) refreshed[#refreshed + 1] = ply end,
        isMedal = function(eventId) return eventId == "pwt_medal" end,
        medalsOf = function() return medals end
    })
    return { store = store, deltas = deltas, levels = levels, summaries = summaries, refreshed = refreshed }
end

---An in-memory wire: the writer appends, the reader consumes in order (missing values read as 0, "" and false).
---@return PW.ProgressionWriter writer, PW.ProgressionReader reader
local function wire()
    ---@type any[]
    local buffer = {}
    local position = 0
    ---@return any
    local function nextValue()
        position = position + 1
        return buffer[position]
    end
    ---@type PW.ProgressionWriter
    local writer = {
        uint = function(value, width)
            assert(value >= 0 and value < 2 ^ width, "uint out of range: " .. tostring(value))
            buffer[#buffer + 1] = value
        end,
        string = function(value) buffer[#buffer + 1] = value end,
        bool = function(value) buffer[#buffer + 1] = value end
    }
    ---@type PW.ProgressionReader
    local reader = {
        uint = function() return nextValue() or 0 end,
        string = function() return nextValue() or "" end,
        bool = function() return nextValue() == true end
    }
    return writer, reader
end

---@param session integer
---@param seq integer
---@param xp number
---@param weapons? table<string, number>
---@return PW.ProgressionDelta
local function delta(session, seq, xp, weapons)
    return { session = session, seq = seq, xp = xp, weapons = weapons or {} }
end

---@param xp number
---@param weapons? table<string, number>
---@return PW.ProgressionFile
local function file(xp, weapons)
    return { v = 1, xp = xp, weapons = weapons or {}, batch = { session = 0, seq = 0 } }
end

local catalogue = {
    weapons = {
        pwt_locked = { Category = "ar", Unlock = 3 },
        pwt_curated = { Category = "ar", Attachments = { optic = { Unlock = 2 } } }
    }
}

---@type PW.LoadoutLookup
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

return {
    groupName = "PW progression storage",
    cases = {
        {
            name = "Delta apply: additive to player XP and per weapon, pure (the input file is not changed)",
            func = function()
                local before = file(100, { pwt_a = 50 })
                local after, applied = lib()._ApplyDelta(before, delta(7, 1, 25, { pwt_a = 10, pwt_b = 5 }))
                expect(applied).to.beTrue()
                expect(after.xp).to.equal(125)
                expect(after.weapons.pwt_a).to.equal(60)
                expect(after.weapons.pwt_b).to.equal(5)
                expect(after.batch.session).to.equal(7)
                expect(after.batch.seq).to.equal(1)
                expect(before.xp).to.equal(100)
                expect(before.weapons.pwt_a).to.equal(50)
                expect(before.weapons.pwt_b).to.beNil()
                expect(before.batch.seq).to.equal(0)
            end
        },
        {
            name = "Delta apply: idempotent per batch id; an older batch is ignored, a new session applies",
            func = function()
                local once = lib()._ApplyDelta(file(0), delta(7, 1, 25, { pwt_a = 10 }))
                local twice, again = lib()._ApplyDelta(once, delta(7, 1, 25, { pwt_a = 10 }))
                expect(again).to.beFalse()
                expect(twice.xp).to.equal(25)
                expect(twice.weapons.pwt_a).to.equal(10)
                local second = lib()._ApplyDelta(twice, delta(7, 2, 5))
                expect(second.xp).to.equal(30)
                local stale, staleApplied = lib()._ApplyDelta(second, delta(7, 1, 25))
                expect(staleApplied).to.beFalse()
                expect(stale.xp).to.equal(30)
                local other, otherApplied = lib()._ApplyDelta(second, delta(9, 1, 1))
                expect(otherApplied).to.beTrue()
                expect(other.xp).to.equal(31)
            end
        },
        {
            name = "Sanity check: delta apply rejects negative or absurd values and keeps the valid ones",
            func = function()
                local max = lib().MaxDeltaXP
                local after = lib()._ApplyDelta(file(100, { pwt_a = 50 }), delta(1, 1, -40, {
                    pwt_a = max + 1, pwt_b = 0 / 0, pwt_c = math.huge, pwt_d = -3, pwt_e = 12
                }))
                expect(after.xp).to.equal(100)
                expect(after.weapons.pwt_a).to.equal(50)
                expect(after.weapons.pwt_b).to.beNil()
                expect(after.weapons.pwt_c).to.beNil()
                expect(after.weapons.pwt_d).to.beNil()
                expect(after.weapons.pwt_e).to.equal(12)
                expect(lib()._ApplyDelta(file(0), delta(1, 1, max)).xp).to.equal(max)
                expect(lib()._CheckXP(-1, 10)).to.beNil()
                expect(lib()._CheckXP(11, 10)).to.beNil()
                expect(lib()._CheckXP("5", 10)).to.beNil()
                expect(lib()._CheckXP(9.7, 10)).to.equal(9)
            end
        },
        {
            name = "Sanity check: an upload drops negative, absurd and malformed values and bounds its size",
            func = function()
                local weapons = { pwt_neg = -5, pwt_nan = 0 / 0, pwt_big = lib().MaxXP + 1, pwt_ok = 300.9,
                    [string.rep("x", lib().MaxClassLength + 1)] = 10, [""] = 10, [5] = 10 }
                local checked = lib()._CheckState({ xp = -1, weapons = weapons }, lib().MaxWeapons)
                expect(checked.xp).to.equal(0)
                expect(checked.weapons.pwt_ok).to.equal(300)
                local count = 0
                for _ in pairs(checked.weapons) do count = count + 1 end
                expect(count).to.equal(1)
                expect(lib()._CheckState({ xp = lib().MaxXP + 1 }).xp).to.equal(0)
                expect(lib()._CheckState("garbage").xp).to.equal(0)
                ---@type table<string, number>
                local many = {}
                for index = 1, lib().MaxWeapons + 20 do many["pwt_w" .. index] = index end
                local bounded = lib()._CheckState({ xp = 5, weapons = many }, lib().MaxWeapons)
                count = 0
                for _ in pairs(bounded.weapons) do count = count + 1 end
                expect(count).to.equal(lib().MaxWeapons)
                expect(bounded.weapons["pwt_w" .. (lib().MaxWeapons + 20)]).to.equal(lib().MaxWeapons + 20)
                expect(bounded.weapons.pwt_w1).to.beNil()
            end
        },
        {
            name = "Join upload: validated and clamped, accepted once, then levels sent and classes refreshed",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                local accepted = lib()._OnUpload(r.store, ply, { xp = 2500.5, weapons = { pwt_a = 900, pwt_b = -1 } })
                expect(accepted).to.beTrue()
                local state = lib()._GetState(r.store, ply)
                expect(state.xp).to.equal(2500)
                expect(state.weapons.pwt_a).to.equal(900)
                expect(state.weapons.pwt_b).to.beNil()
                expect(#r.levels).to.equal(1)
                expect(r.levels[1][2].level).to.equal(2)
                expect(r.levels[1][2].weapons.pwt_a).to.equal(2)
                expect(#r.refreshed).to.equal(1)
                expect(lib()._OnUpload(r.store, ply, { xp = 999999 })).to.beFalse()
                expect(lib()._GetState(r.store, ply).xp).to.equal(2500)
                expect(lib()._OnUpload(rig().store, fakePlayer(), { xp = -50 })).to.beTrue()
            end
        },
        {
            name = "Batching: deltas leave every 10 s, summed per player, never empty, with a growing batch id",
            func = function()
                local r = rig()
                local a, b = fakePlayer(), fakePlayer()
                lib()._Tick(r.store, 100)
                lib()._OnScoreEvent(r.store, a, "kill", 100, 100, fakeWeapon("pwt_a"))
                lib()._OnScoreEvent(r.store, a, "assist", 50, 50)
                lib()._OnScoreEvent(r.store, b, "kill", 100, 100, fakeWeapon("pwt_b"))
                lib()._Tick(r.store, 105)
                expect(#r.deltas).to.equal(0)
                lib()._Tick(r.store, 110)
                expect(#r.deltas).to.equal(2)
                ---@type table<Player, PW.ProgressionDelta>
                local byPlayer = {}
                for _, sent in ipairs(r.deltas) do byPlayer[sent[1]] = sent[2] end
                expect(byPlayer[a].xp).to.equal(150)
                expect(byPlayer[a].weapons.pwt_a).to.equal(100)
                expect(byPlayer[a].seq).to.equal(1)
                expect(byPlayer[b].weapons.pwt_b).to.equal(100)
                expect(byPlayer[a].session ~= 0).to.beTrue()
                lib()._Tick(r.store, 120)
                expect(#r.deltas).to.equal(2)
                lib()._OnScoreEvent(r.store, a, "kill", 100, 100)
                lib()._Tick(r.store, 125)
                expect(#r.deltas).to.equal(2)
                lib()._Tick(r.store, 130)
                expect(#r.deltas).to.equal(3)
                expect(r.deltas[3][2].seq).to.equal(2)
                expect(r.deltas[3][2].session).to.equal(byPlayer[a].session)
                expect(lib().FlushInterval).to.equal(10)
            end
        },
        {
            name = "POSTMATCH: pending XP is flushed at once and every player gets the summary",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                lib()._Tick(r.store, 0)
                lib()._BeginMatch(r.store)
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 100)
                lib()._OnPostmatch(r.store)
                expect(#r.deltas).to.equal(1)
                expect(r.deltas[1][2].xp).to.equal(100)
                expect(#r.summaries).to.equal(1)
                expect(r.summaries[1][1]).to.equal(ply)
                expect(r.summaries[1][2].xp).to.equal(100)
                lib()._Tick(r.store, 10)
                expect(#r.deltas).to.equal(1)
            end
        },
        {
            name = "Summary: XP gained, level before and after, weapon levels gained and medals of this match",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                lib()._OnUpload(r.store, ply, { xp = 900, weapons = { pwt_old = 100 } })
                lib()._BeginMatch(r.store)
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 100, fakeWeapon("pwt_a"))
                lib()._OnScoreEvent(r.store, ply, "kill", 600, 600, fakeWeapon("pwt_a"))
                lib()._OnScoreEvent(r.store, ply, "pwt_medal", 50, 50)
                lib()._OnScoreEvent(r.store, ply, "pwt_medal", 50, 50)
                lib()._OnScoreEvent(r.store, ply, "kill", 10, 10, fakeWeapon("pwt_old"))
                local summary = lib()._Summary(r.store, ply)
                expect(summary.xp).to.equal(810)
                expect(summary.levelBefore).to.equal(1)
                expect(summary.levelAfter).to.equal(2)
                expect(#summary.weapons).to.equal(1)
                expect(summary.weapons[1].class).to.equal("pwt_a")
                expect(summary.weapons[1].before).to.equal(1)
                expect(summary.weapons[1].after).to.equal(2)
                expect(#summary.medals).to.equal(1)
                expect(summary.medals[1].id).to.equal("pwt_medal")
                expect(summary.medals[1].count).to.equal(2)
                lib()._BeginMatch(r.store)
                local fresh = lib()._Summary(r.store, ply)
                expect(fresh.xp).to.equal(0)
                expect(fresh.levelBefore).to.equal(2)
                expect(fresh.levelAfter).to.equal(2)
                expect(#fresh.weapons).to.equal(0)
            end
        },
        {
            name = "Level up: classes are refreshed and the levels resent at once; a plain gain does neither",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 100)
                expect(#r.refreshed).to.equal(0)
                expect(#r.levels).to.equal(0)
                lib()._OnScoreEvent(r.store, ply, "kill", 1000, 1000)
                expect(#r.refreshed).to.equal(1)
                expect(#r.levels).to.equal(1)
                expect(r.levels[1][2].level).to.equal(2)
                lib()._OnScoreEvent(r.store, ply, "kill", 500, 500, fakeWeapon("pwt_a"))
                expect(#r.refreshed).to.equal(2)
                expect(r.levels[2][2].weapons.pwt_a).to.equal(2)
            end
        },
        {
            name = "Levels for the client: player level, weapon levels above 1, unlockall and the attachment cap",
            func = function()
                local r = rig({ ["progression.unlockall"] = true, ["loadout.maxattachments"] = 3 })
                local ply = fakePlayer()
                lib()._SetState(r.store, ply, { xp = 0, weapons = { pwt_a = 600, pwt_b = 10 } })
                local levels = lib()._LevelsOf(r.store, ply)
                expect(levels.level).to.equal(1)
                expect(levels.weapons.pwt_a).to.equal(2)
                expect(levels.weapons.pwt_b).to.beNil()
                expect(levels.unlockAll).to.beTrue()
                expect(levels.maxAttachments).to.equal(3)
            end
        },
        {
            name = "Client IsUnlocked: the view built from the received levels answers like the server",
            func = function()
                local levels = { level = 3, weapons = { pwt_curated = 2 }, unlockAll = false, maxAttachments = 5 }
                local v = lib()._ViewFromLevels(levels, lookup)
                expect(lib()._IsUnlocked(v, "weapons", "pwt_locked")).to.beTrue()
                expect(lib()._IsUnlocked(v, "attachments", "pwt_curated:optic")).to.beTrue()
                expect(v.weaponLevel("pwt_other")).to.equal(1)
                local low = lib()._ViewFromLevels({ level = 2, weapons = {}, unlockAll = false, maxAttachments = 5 },
                    lookup)
                expect(lib()._IsUnlocked(low, "weapons", "pwt_locked")).to.beFalse()
                expect(lib()._IsUnlocked(low, "attachments", "pwt_curated:optic")).to.beFalse()
            end
        },
        {
            name = "Wire: upload, delta, levels and summary survive encode and decode",
            func = function()
                local w, rd = wire()
                lib()._EncodeState({ xp = 1234, weapons = { pwt_a = 5, pwt_b = 7 } }, w)
                local state = lib()._DecodeState(rd)
                expect(state.xp).to.equal(1234)
                expect(state.weapons.pwt_b).to.equal(7)
                w, rd = wire()
                lib()._EncodeDelta(delta(77, 3, 40, { pwt_a = 40 }), w)
                local d = lib()._DecodeDelta(rd)
                expect(d.session).to.equal(77)
                expect(d.seq).to.equal(3)
                expect(d.weapons.pwt_a).to.equal(40)
                w, rd = wire()
                lib()._EncodeLevels({ level = 9, weapons = { pwt_a = 4 }, unlockAll = true, maxAttachments = 2 }, w)
                local levels = lib()._DecodeLevels(rd)
                expect(levels.level).to.equal(9)
                expect(levels.weapons.pwt_a).to.equal(4)
                expect(levels.unlockAll).to.beTrue()
                expect(levels.maxAttachments).to.equal(2)
                w, rd = wire()
                lib()._EncodeSummary({ xp = 810, levelBefore = 1, levelAfter = 2,
                    weapons = { { class = "pwt_a", before = 1, after = 3 } }, medals = { { id = "m", count = 2 } } }, w)
                local summary = lib()._DecodeSummary(rd)
                expect(summary.xp).to.equal(810)
                expect(summary.levelAfter).to.equal(2)
                expect(summary.weapons[1].after).to.equal(3)
                expect(summary.medals[1].count).to.equal(2)
            end
        },
        {
            name = "Wire: a forged count cannot make the decoder read past the size bound",
            func = function()
                local w, rd = wire()
                w.uint(10, 32)
                w.uint(65535, 16)
                local state = lib()._DecodeState(rd)
                expect(state.xp).to.equal(10)
                local count = 0
                for _ in pairs(state.weapons) do count = count + 1 end
                expect(count).to.equal(0)
                expect(lib().UploadMaxBytes < 65536).to.beTrue()
            end
        },
        {
            name = "File: JSON shape round trip; a malformed file gives an empty progression",
            func = function()
                ---@type PW.ProgressionFile
                local stored = { v = 1, xp = 300, weapons = { pwt_a = 40 }, batch = { session = 5, seq = 2 } }
                local text = util.TableToJSON(lib()._FileToJson(stored))
                local loaded = lib()._FileFromJson(util.JSONToTable(text))
                expect(loaded.v).to.equal(lib().FileVersion)
                expect(loaded.xp).to.equal(300)
                expect(loaded.weapons.pwt_a).to.equal(40)
                expect(loaded.batch.session).to.equal(5)
                expect(loaded.batch.seq).to.equal(2)
                local empty = lib()._FileFromJson(nil)
                expect(empty.xp).to.equal(0)
                expect(empty.batch.seq).to.equal(0)
                expect(lib()._FileFromJson({ xp = -9, weapons = "x" }).xp).to.equal(0)
            end
        },
        {
            name = "Summary: the medals come from the medals module when it is loaded",
            func = function()
                local r = rig(nil, { double_kill = 2, first_blood = 1 })
                local ply = fakePlayer()
                lib()._BeginMatch(r.store)
                lib()._OnScoreEvent(r.store, ply, "pwt_medal", 50, 50)
                local summary = lib()._Summary(r.store, ply)
                expect(#summary.medals).to.equal(2)
                expect(summary.medals[1].id).to.equal("double_kill")
                expect(summary.medals[1].count).to.equal(2)
                expect(summary.medals[2].id).to.equal("first_blood")
                local idle = lib()._Summary(rig(nil, { revenge = 1 }).store, fakePlayer())
                expect(#idle.medals).to.equal(1)
                expect(idle.xp).to.equal(0)
            end
        },
        {
            name = "The public API exists: MatchSummary on both realms, the client-side unlock checks",
            func = function()
                expect(isfunction(lib().MatchSummary)).to.beTrue()
                expect(isfunction(lib().IsUnlocked)).to.beTrue()
                expect(isfunction(lib().GetWeaponLevel)).to.beTrue()
                local summary = lib()._Summary(rig().store, fakePlayer())
                expect(summary.xp).to.equal(0)
                expect(summary.levelBefore).to.equal(1)
            end
        }
    }
}
