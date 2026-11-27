---@return PW.ChallengesLib
local function challenges()
    local lib = PW.Challenges
    assert(lib ~= nil)
    return lib
end

local label, index = "2026-W47", 2967

---@return PW.ChallengeFile
local function sampleFile()
    return { v = 1, weeks = { [label] = { index = index, items = { kills = { p = { 2, 3 }, done = true } },
        bonus = true } }, batch = { session = 5, seq = 9 } }
end

---@class PW.ChallengeRawTestFile
---@field v? integer
---@field weeks table<string, { index: integer, items: table<string, { p: (number|string)[] }> }>

---@return PW.ChallengeRawTestFile
local function rawFile()
    return { v = 1, weeks = { [label] = { index = index, items = { kills = { p = { 2, 3 } } } } } }
end

---@return PW.ChallengeWeek
local function sampleWeek()
    return { label = label, index = index, startsAt = 1794787200, endsAt = 1795392000, seed = 99,
        items = { { id = "kills.smg", template = "kills", tier = "medium", targets = { 4, 9 },
            params = { category = "smg" }, reward = { xp = 5000, currency = 100,
                items = { { kind = "camos", id = "sand", weapon = "smg" }, { kind = "cards", id = "path" } } } } },
        bonus = { needed = 1, reward = { xp = 10000, currency = 300, items = {} } } }
end

---@param bitLimit? integer
local function buffer(bitLimit)
    ---@type { value: integer, width: integer }[]
    local values = {}
    local bits, cursor, reads = 0, 0, 0
    ---@param value integer
    ---@param width integer
    local function write(value, width)
        assert(value >= 0 and value < 2 ^ width and value % 1 == 0)
        values[#values + 1] = { value = value, width = width }
        bits = bits + width
    end
    ---@param width integer
    local function read(width)
        reads = reads + 1
        local row = assert(values[reads], "read beyond packet")
        cursor = cursor + width
        assert(cursor <= (bitLimit or bits), "read beyond bit limit")
        assert(row.width == width, "wire width mismatch")
        return row.value
    end
    return {
        values = values, write = write, read = read,
        size = function() return bitLimit or bits end, reads = function() return reads end
    }
end

---Twelve instances with all four objective pairs, plus an actual bonus item.
---@param finalRewardLength integer
---@return PW.ChallengeWireState
local function budgetState(finalRewardLength)
    local week = sampleWeek()
    week.items = {}
    week.bonus.reward.items = { { kind = "cards", id = "weekly_bonus" } }
    for slot = 1, 12 do
        local id = string.format("size_%02d", slot) .. string.rep("x", 33)
        local length = slot == 12 and finalRewardLength or 50
        week.items[slot] = { id = id, template = id, tier = "easy", params = {}, targets = { 1, 2, 3, 4 },
            reward = { items = { { kind = "cards", id = string.rep("g", length) } } } }
    end
    return { week = week, items = {}, bonus = false }
end

return {
    groupName = "PW challenges storage and wire",
    cases = {
        {
            name = "Storage: file round trip for version 1",
            func = function()
                local lib = challenges()
                expect(type(lib._FileToJson)).to.equal("function")
                local json = lib._FileToJson(sampleFile(), index)
                local decoded, readOnly = lib._FileFromJson(json)
                expect(decoded.v).to.equal(1)
                expect(decoded.weeks[label].items.kills.p[2]).to.equal(3)
                expect(decoded.weeks[label].items.kills.done).to.beTrue()
                expect(decoded.weeks[label].bonus).to.beTrue()
                local batch = decoded.batch
                assert(batch ~= nil)
                expect(batch.session).to.equal(5)
                expect(batch.seq).to.equal(9)
                expect(readOnly).to.beFalse()
            end
        },
        {
            name = "Storage: malformed, missing and non-table files read as empty",
            func = function()
                local lib = challenges()
                expect(type(lib._FileFromJson)).to.equal("function")
                local missing = lib._FileFromJson(nil)
                expect(next(missing.weeks)).to.beNil()
                for _, raw in ipairs({ "", "{oops", "[]", "true", "22", "{\"v\":1,\"weeks\":42}" }) do
                    local file, readOnly = lib._FileFromJson(raw)
                    expect(file.v).to.equal(1)
                    expect(next(file.weeks)).to.beNil()
                    expect(readOnly).to.beFalse()
                end
            end
        },
        {
            name = "Storage: unknown version newer than known is not rewritten",
            func = function()
                local lib = challenges()
                expect(type(lib._FileFromJson)).to.equal("function")
                local file, readOnly = lib._FileFromJson("{\"v\":2,\"shape\":\"future\"}")
                expect(readOnly).to.beTrue()
                expect(next(file.weeks)).to.beNil()
                expect(lib._FileToJson(file, index, readOnly)).to.beNil()
            end
        },
        {
            name = "Storage: bounds clamp counters, ids, labels, weeks and items",
            func = function()
                local lib = challenges()
                expect(type(lib._Migrate)).to.equal("function")
                local raw = rawFile()
                for i = 1, 5 do raw.weeks["2027-W0" .. i] = { index = index + i, items = {} } end
                raw.weeks.invalid = { index = index + 100, items = {} }
                local latest = raw.weeks["2027-W05"]
                latest.items.a = { p = { 2000000, 5.9, -1, 0 / 0, 3 } }
                latest.items.b = { p = { "fake" } }
                latest.items["a..b"] = { p = { 1 } }
                latest.items[string.rep("x", 41)] = { p = { 1 } }
                for i = 1, 30 do latest.items["z" .. i] = { p = { 1 } } end
                local clean = lib._Migrate(raw)
                expect(table.Count(clean.weeks)).to.equal(4)
                expect(clean.weeks.invalid).to.beNil()
                expect(clean.weeks["2027-W01"]).to.beNil()
                local items = clean.weeks["2027-W05"].items
                expect(table.Count(items)).to.equal(16)
                expect(items["a..b"]).to.beNil()
                expect(items[string.rep("x", 41)]).to.beNil()
                expect(#items.a.p).to.equal(4)
                expect(items.a.p[1]).to.equal(1000000)
                expect(items.a.p[2]).to.equal(5)
                expect(items.a.p[3]).to.equal(0)
                expect(items.a.p[4]).to.equal(0)
                expect(items.b.p[1]).to.equal(0)
            end
        },
        {
            name = "Storage: migration maps a missing version to an empty file",
            func = function()
                local lib = challenges()
                expect(type(lib._Migrate)).to.equal("function")
                local raw = rawFile()
                raw.v = nil
                local file = lib._Migrate(raw)
                expect(file.v).to.equal(1)
                expect(next(file.weeks)).to.beNil()
                expect(file.batch).to.beNil()
            end
        },
        {
            name = "Storage: delta apply is idempotent per batch id and applies absolute values in order",
            func = function()
                local lib = challenges()
                expect(type(lib._ApplyDelta)).to.equal("function")
                ---@type PW.ChallengeDelta
                local delta = { session = 5, seq = 10, label = label, index = index,
                    items = { kills = { p = { 1, 0 }, done = false } }, bonus = false }
                local file, applied = lib._ApplyDelta(sampleFile(), delta)
                expect(applied).to.beTrue()
                expect(file.weeks[label].items.kills.p[1]).to.equal(1)
                expect(file.weeks[label].items.kills.done).to.beFalse()
                expect(file.weeks[label].bonus).to.beFalse()
                delta.items.kills.p[1] = 8
                local unchanged, duplicate = lib._ApplyDelta(file, delta)
                expect(duplicate).to.beFalse()
                expect(unchanged.weeks[label].items.kills.p[1]).to.equal(1)
                delta.seq = 9
                local _, old = lib._ApplyDelta(file, delta)
                expect(old).to.beFalse()
                delta.session, delta.seq = 6, 1
                local nextFile, nextApplied = lib._ApplyDelta(file, delta)
                expect(nextApplied).to.beTrue()
                expect(nextFile.weeks[label].items.kills.p[1]).to.equal(8)
            end
        },
        {
            name = "Storage: upload keeps only the session week, clamps to targets and ignores unknown ids",
            func = function()
                local lib = challenges()
                expect(type(lib._UploadWeek)).to.equal("function")
                local raw = sampleFile()
                raw.weeks[label].items["kills.smg"] = { p = { 700, 1, 2 }, done = true }
                raw.weeks["2026-W46"] = { index = index - 1, items = { ["kills.smg"] = { p = { 4, 9 }, done = true } } }
                local uploaded = lib._UploadWeek(raw.weeks, sampleWeek(), {})
                expect(uploaded.items.kills).to.beNil()
                expect(#uploaded.items["kills.smg"].p).to.equal(2)
                expect(uploaded.items["kills.smg"].p[1]).to.equal(4)
                expect(uploaded.items["kills.smg"].p[2]).to.equal(1)
                expect(uploaded.items["kills.smg"].done).to.beFalse()
                expect(uploaded.bonus).to.beFalse()
                uploaded = lib._UploadWeek(raw.weeks, sampleWeek(), { ["kills.smg"] = "any" })
                expect(uploaded.items["kills.smg"].done).to.beTrue()
            end
        },
        {
            name = "Storage: progress of an expired week is ignored and not deleted by the server",
            func = function()
                local lib = challenges()
                expect(type(lib._UploadWeek)).to.equal("function")
                local raw = sampleFile()
                raw.weeks[label].items["kills.smg"] = { p = { 4, 9 }, done = true }
                local week = sampleWeek()
                week.label, week.index = "2026-W49", index + 2
                local uploaded = lib._UploadWeek(raw.weeks, week, {})
                expect(next(uploaded.items)).to.beNil()
                expect(raw.weeks[label].items["kills.smg"].p[1]).to.equal(4)
                local pruned = lib._FileFromJson(lib._FileToJson(raw, week.index))
                expect(pruned.weeks[label]).to.beNil()
            end
        },
        {
            name = "Wire: upload, state, progress and delta survive encode and decode",
            func = function()
                local lib = challenges()
                expect(type(lib._WriteWire)).to.equal("function")
                ---@type PW.ChallengeFileItems
                local items = { ["kills.smg"] = { p = { 1, 5 }, done = true } }
                ---@type PW.ChallengeWireState
                local state = { week = sampleWeek(), items = items, bonus = true }
                ---@type PW.ChallengeDelta
                local delta = { session = 9, seq = 3, label = label, index = index, items = items, bonus = true }
                local upload = buffer()
                lib._WriteWire("upload", sampleFile().weeks, upload.write)
                local decodedUpload = lib._ReadWire("upload", upload.size(), upload.read)
                assert(decodedUpload ~= nil)
                expect(decodedUpload[label].items.kills.p[2]).to.equal(3)

                local statePacket = buffer()
                lib._WriteWire("state", state, statePacket.write)
                local decodedState = lib._ReadWire("state", statePacket.size(), statePacket.read)
                assert(decodedState ~= nil)
                expect(decodedState.items["kills.smg"].p[2]).to.equal(5)
                expect(decodedState.items["kills.smg"].done).to.beTrue()
                local instance = decodedState.week.items[1]
                expect(instance.targets[2]).to.equal(9)
                expect(instance.tier).to.equal("medium")
                expect(instance.params.category).to.equal("smg")
                local rewardItems = instance.reward.items
                assert(rewardItems ~= nil)
                expect(rewardItems[1].weapon).to.equal("smg")
                expect(rewardItems[2].weapon).to.beNil()
                expect(decodedState.week.bonus.reward.xp).to.equal(10000)
                expect(decodedState.bonus).to.beTrue()

                local progressPacket = buffer()
                lib._WriteWire("progress", items, progressPacket.write)
                local decodedProgress = lib._ReadWire("progress", progressPacket.size(), progressPacket.read)
                assert(decodedProgress ~= nil)
                expect(decodedProgress["kills.smg"].p[2]).to.equal(5)
                expect(decodedProgress["kills.smg"].done).to.beTrue()

                local deltaPacket = buffer()
                lib._WriteWire("delta", delta, deltaPacket.write)
                local decodedDelta = lib._ReadWire("delta", deltaPacket.size(), deltaPacket.read)
                assert(decodedDelta ~= nil)
                expect(decodedDelta.items["kills.smg"].p[2]).to.equal(5)
                expect(decodedDelta.items["kills.smg"].done).to.beTrue()
                expect(decodedDelta.session).to.equal(9)
                expect(decodedDelta.seq).to.equal(3)
                expect(decodedDelta.label).to.equal(label)
                expect(decodedDelta.bonus).to.beTrue()
            end
        },
        {
            name = "Wire: all seven accepted parameters and reward items survive the state round trip",
            func = function()
                local lib = challenges()
                local week = sampleWeek()
                local instance = week.items[1]
                instance.id, instance.template = "limits" .. string.rep(".v", 7), "limits"
                instance.params = {}
                ---@type PW.ChallengeRewardItem[]
                local rewards = {}
                for i = 1, 7 do
                    instance.params["p" .. i] = "v"
                    rewards[i] = { kind = "cards", id = "g" .. i }
                end
                instance.reward.items = rewards
                local packet = buffer()
                lib._WriteWire("state", { week = week, items = {}, bonus = false }, packet.write)
                local decoded = lib._ReadWire("state", packet.size(), packet.read)
                expect(decoded ~= nil).to.beTrue()
                assert(decoded ~= nil)
                expect(decoded.week.items[1].id).to.equal(instance.id)
                expect(decoded.week.items[1].params).to.deepEqual(instance.params)
                expect(decoded.week.items[1].reward.items).to.deepEqual(rewards)
                expect(packet.size() < 2048 * 8).to.beTrue()
            end
        },
        {
            name = "Wire: complete state size includes the bonus at the 2048 and 2049 byte boundary",
            func = function()
                local lib = challenges()
                local exact, packet = budgetState(46), buffer()
                lib._WriteWire("state", exact, packet.write)
                expect(packet.size()).to.equal(2048 * 8)
                local bits = rawget(lib, "_StateBits") --[[@as (fun(state: PW.ChallengeWireState): integer)?]]
                expect(type(bits)).to.equal("function")
                assert(bits ~= nil)
                expect(bits(exact)).to.equal(packet.size())
                expect(bits(budgetState(47))).to.equal(2049 * 8)

                exact.week.bonus.reward.items = {}
                local noBonus = buffer()
                lib._WriteWire("state", exact, noBonus.write)
                expect(noBonus.size()).to.equal(2028 * 8)
                expect(bits(exact)).to.equal(noBonus.size())
            end
        },
        {
            name = "Wire: forged counts cannot read past the size bound",
            func = function()
                local lib = challenges()
                expect(type(lib._ReadWire)).to.equal("function")
                local forged = buffer()
                forged.write(7, 3)
                expect(lib._ReadWire("upload", forged.size(), forged.read)).to.beNil()
                expect(forged.reads()).to.equal(1)
                local truncated = buffer(4)
                truncated.write(1, 3)
                expect(lib._ReadWire("upload", truncated.size(), truncated.read)).to.beNil()
                expect(truncated.reads()).to.equal(1)
                local valid = buffer()
                lib._WriteWire("upload", sampleFile().weeks, valid.write)
                valid.values[12].value = 31 -- first week item count (3 + 9 bytes + 32-bit index)
                expect(lib._ReadWire("upload", valid.size(), valid.read)).to.beNil()
                expect(valid.reads()).to.equal(12)
            end
        }
    }
}
