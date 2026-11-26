-- Exercise the actual client entry point on the server runner, without touching live net or DATA.
local sourcePath = "privatewar/modules/challenges/cl_init.lua"
local prefix = "pw_challenges_"
local label, index = "2026-W47", 2967
local instanceId = "kills.smg"

---@return PW.ChallengeWireState
local function hostState()
    return {
        week = { label = label, index = index, startsAt = 1794787200, endsAt = 1795392000, seed = 0,
            items = { { id = instanceId, template = "kills", tier = "medium", targets = { 8, 4 },
                params = { category = "smg" }, reward = { xp = 5000 } } },
            bonus = { needed = 1, reward = { xp = 10000 } } },
        items = { [instanceId] = { p = { 3, 1 }, done = false } },
        bonus = false
    }
end

---@return PW.ChallengeFile
local function storedFile()
    return { v = 1, batch = { session = 41, seq = 3 }, weeks = {
        ["2026-W46"] = { index = index - 1, items = { old = { p = { 1 } } } },
        [label] = { index = index, items = { [instanceId] = { p = { 6, 2 } }, other = { p = { 4 } } } },
        ["2026-W48"] = { index = index + 1, items = { future = { p = { 7 } } } }
    } }
end

---@return PW.ChallengeDelta
local function delta()
    return { session = 41, seq = 4, label = label, index = index,
        items = { [instanceId] = { p = { 1, 0 }, done = false } }, bonus = true }
end

---@class PW.ChallengeClientTestPacket
---@field write PW.ChallengeWireWriter
---@field read PW.ChallengeWireReader
---@field size fun(): integer

---@return PW.ChallengeClientTestPacket
local function packet()
    ---@type { value: integer, width: integer }[]
    local rows = {}
    local bits, cursor = 0, 0
    ---@param value integer
    ---@param width integer
    local function write(value, width)
        assert(value >= 0 and value < 2 ^ width and value % 1 == 0, "invalid wire value")
        rows[#rows + 1], bits = { value = value, width = width }, bits + width
    end
    ---@param width integer
    local function read(width)
        cursor = cursor + 1
        local row = assert(rows[cursor], "read beyond fixture packet")
        assert(row.width == width, "unexpected wire width")
        return row.value
    end
    return { write = write, read = read, size = function() return bits end }
end

---@class PW.ChallengeClientTestFixture
---@field lib PW.ChallengesLib
---@field player Player
---@field other Player
---@field enabled boolean
---@field pooled boolean
---@field raw? string
---@field reads integer
---@field writes integer
---@field dirs integer
---@field wireReads integer
---@field receivers table<string, fun(bits: integer)>
---@field hooks table<string, fun(module: table)>
---@field module? table
---@field reload? fun()
---@field sent { name: string, wire: PW.ChallengeClientTestPacket }[]
---@field notices PW.ChallengeWeek[]
---@field logs string[]
---@field incoming? PW.ChallengeClientTestPacket
---@field outName? string
---@field out? PW.ChallengeClientTestPacket

---@param f PW.ChallengeClientTestFixture
local function mockNet(f)
    return {
        ---@param name string
        ---@param handler fun(bits: integer)
        Receive = function(name, handler) f.receivers[name] = handler end,
        Start = function(name)
            assert(f.pooled, "upload net string is not pooled")
            assert(f.outName == nil, "previous upload was not sent")
            f.outName, f.out = name, packet()
        end,
        WriteUInt = function(value, width) assert(f.out).write(value, width) end,
        SendToServer = function()
            local sent = f.sent
            sent[#sent + 1] = { name = assert(f.outName), wire = assert(f.out) }
            f.outName, f.out = nil, nil
        end,
        ReadUInt = function(width)
            f.wireReads = f.wireReads + 1
            return assert(f.incoming).read(width)
        end
    }
end

---@param f PW.ChallengeClientTestFixture
local function mockFile(f)
    return {
        Read = function(path, realm)
            assert(path == "privatewar/challenges.json" and realm == "DATA")
            f.reads = f.reads + 1
            return f.raw
        end,
        CreateDir = function(path)
            assert(path == "privatewar")
            f.dirs = f.dirs + 1
        end,
        Write = function(path, json)
            assert(path == "privatewar/challenges.json")
            f.writes = f.writes + 1
            f.raw = json
            return true
        end
    }
end

---@param raw? string
---@return PW.ChallengeClientTestFixture
local function fixture(raw)
    local lib = table.Copy(assert(PW.Challenges))
    rawset(lib, "GetWeek", nil)
    rawset(lib, "GetActive", nil)
    rawset(lib, "GetProgress", nil)
    local f = {
        lib = lib, raw = raw, enabled = true, pooled = true, reads = 0, writes = 0, dirs = 0, wireReads = 0,
        player = {}, other = {}, receivers = {}, hooks = {}, sent = {}, notices = {}, logs = {}
    } --[[@as PW.ChallengeClientTestFixture]]
    local api = { Challenges = lib, HookFor = PW.HookFor, Notify = function(name, week)
        assert(name == "PW_ChallengesChanged")
        table.insert(f.notices, week)
    end }
    local env = setmetatable({
        PW = api, SERVER = false, CLIENT = true, net = mockNet(f), file = mockFile(f),
        os = { time = function() return lib.WeekBounds(index + 1) end },
        util = setmetatable({ NetworkStringToID = function(name)
            assert(name == prefix .. "upload")
            return f.pooled and 1 or 0
        end }, { __index = util }),
        LocalPlayer = function() return f.player end,
        IsValid = function(value)
            return value == f.player or value == f.other or (value ~= nil and value == f.module and f.enabled)
        end,
        print = function(message) table.insert(f.logs, message) end
    }, { __index = _G })
    local function reload()
        local module = { IsValid = function() return f.enabled end }
        env.MODULE, f.module = module, module
        f.receivers = {}
        if file.Exists(sourcePath, "LUA") then setfenv(assert(CompileFile(sourcePath)), env)() end
        f.hooks = rawget(module, "_EngineHooks") or {}
    end
    f.reload = reload
    reload()
    return f
end

---@param f PW.ChallengeClientTestFixture
local function join(f)
    local init = assert(f.hooks.InitPostEntity, "weekly challenges must register the initial client upload")
    init(assert(f.module))
end

---@param f PW.ChallengeClientTestFixture
---@param name string
---@param wire PW.ChallengeClientTestPacket
---@param bits? integer
local function receive(f, name, wire, bits)
    local handler = assert(f.receivers[prefix .. name], "weekly challenges must receive client " .. name)
    f.incoming = wire
    handler(bits or wire.size())
    f.incoming = nil
end

---@param f PW.ChallengeClientTestFixture
---@param state? PW.ChallengeWireState
local function receiveState(f, state)
    local wire = packet()
    f.lib._WriteWire("state", state or hostState(), wire.write)
    receive(f, "state", wire)
end

---@param f PW.ChallengeClientTestFixture
---@param items PW.ChallengeFileItems
local function receiveProgress(f, items)
    local wire = packet()
    f.lib._WriteWire("progress", items, wire.write)
    receive(f, "progress", wire)
end

---@param f PW.ChallengeClientTestFixture
---@param batch PW.ChallengeDelta
local function receiveDelta(f, batch)
    local wire = packet()
    f.lib._WriteWire("delta", batch, wire.write)
    receive(f, "delta", wire)
end

---@param f PW.ChallengeClientTestFixture
---@return PW.ChallengeProgress
local function ownerProgress(f)
    return assert(assert(f.lib.GetProgress)(f.player, instanceId))
end

return {
    groupName = "PW challenges client",
    cases = {
        {
            name = "Client upload: InitPostEntity sends the bounded saved weeks once, including after Lua reload",
            func = function()
                local raw = storedFile()
                raw.weeks["2026-W45"] = { index = index - 2, items = {} }
                raw.weeks["2026-W44"] = { index = index - 3, items = {} }
                raw.weeks.invalid = { index = index + 5, items = {} }
                raw.weeks[label].items[instanceId].p = { 2000000, 2, -1, 3.8, 5 }
                for i = 1, 16 do raw.weeks[label].items["z" .. i] = { p = {} } end
                local f = fixture(util.TableToJSON(raw))
                expect(#f.sent).to.equal(0)
                join(f)
                join(f)
                assert(f.reload)()
                join(f)
                expect(#f.sent).to.equal(1)
                expect(f.reads).to.equal(1)
                expect(f.writes).to.equal(0)
                local sent = f.sent[1]
                expect(sent.name).to.equal(prefix .. "upload")
                local bits = sent.wire.size()
                expect(bits <= f.lib.UploadMaxBytes * 8).to.beTrue()
                local rows = assert(f.lib._ReadWire("upload", bits, sent.wire.read))
                expect(table.Count(rows)).to.equal(4)
                expect(rows["2026-W44"]).to.beNil()
                expect(rows["2026-W45"].index).to.equal(index - 2)
                expect(rows["2026-W48"].index).to.equal(index + 1)
                expect(rows.invalid).to.beNil()
                expect(table.Count(rows[label].items)).to.equal(16)
                expect(rows[label].items[instanceId].p).to.deepEqual({ 1000000, 2, 0, 3 })
            end
        },
        {
            name = "Client upload: disabled or unpooled challenges never start a net message",
            func = function()
                local f = fixture()
                f.enabled = false
                join(f)
                f.enabled, f.pooled = true, false
                join(f)
                expect(#f.sent).to.equal(0)
                expect(f.writes).to.equal(0)
            end
        },
        {
            name = "Client state: the host owns the active week and counters, and progress is local-player only",
            func = function()
                local raw = util.TableToJSON(storedFile())
                local f = fixture(raw)
                join(f)
                local getWeek = assert(f.lib.GetWeek)
                local getActive = assert(f.lib.GetActive)
                local getProgress = assert(f.lib.GetProgress)
                expect(getWeek()).to.beNil()
                expect(#getActive()).to.equal(0)
                expect(getProgress(f.player, instanceId)).to.beNil()
                receiveState(f)
                local week = assert(getWeek())
                expect(week.label).to.equal(label)
                expect(week.index).to.equal(index)
                expect(week.startsAt).to.equal(1794787200)
                expect(week.endsAt).to.equal(1795392000)
                expect(week.bonus.needed).to.equal(1)
                expect(week.bonus.reward.xp).to.equal(10000)
                expect(getActive()[1].id).to.equal(instanceId)
                expect(getActive()[1].params.category).to.equal("smg")
                expect(ownerProgress(f).values).to.deepEqual({ 3, 1 })
                expect(ownerProgress(f).targets).to.deepEqual({ 8, 4 })
                expect(ownerProgress(f).done).to.beFalse()
                expect(getProgress(f.other, instanceId)).to.beNil()
                expect(getProgress(f.player, "other")).to.beNil()
                expect(#f.notices).to.equal(1)
                expect(f.notices[1].label).to.equal(label)

                local nextState = hostState()
                nextState.week.label, nextState.week.index = "2026-W48", index + 1
                nextState.week.startsAt, nextState.week.endsAt = f.lib.WeekBounds(index + 1)
                nextState.week.items, nextState.items = {}, {}
                receiveState(f, nextState)
                expect(assert(getWeek()).label).to.equal("2026-W48")
                expect(#getActive()).to.equal(0)
                expect(getProgress(f.player, instanceId)).to.beNil()
                expect(#f.notices).to.equal(2)
                expect(f.raw).to.equal(raw)
                expect(f.writes).to.equal(0)
            end
        },
        {
            name = "Client progress: owner view updates and notifies without changing persistent best runs",
            func = function()
                local raw = util.TableToJSON(storedFile())
                local f = fixture(raw)
                join(f)
                receiveState(f)
                receiveProgress(f, { [instanceId] = { p = { 8, 4 }, done = true } })
                expect(ownerProgress(f).values).to.deepEqual({ 8, 4 })
                expect(ownerProgress(f).done).to.beTrue()
                expect(ownerProgress(f).targets).to.deepEqual({ 8, 4 })
                expect(#f.notices).to.equal(2)
                expect(f.notices[2].label).to.equal(label)
                expect(f.raw).to.equal(raw)
                expect(f.writes).to.equal(0)

                receiveProgress(f, { other = { p = { 1 }, done = true } })
                expect(assert(f.lib.GetProgress)(f.player, "other")).to.beNil()
                expect(#f.notices).to.equal(2)
                receiveDelta(f, { session = 41, seq = 4, label = label, index = index, items = {}, bonus = false })
                local saved = f.lib._FileFromJson(f.raw)
                expect(saved.weeks[label].items[instanceId].p).to.deepEqual({ 6, 2 })
                expect(saved.weeks[label].items.other.p).to.deepEqual({ 4 })
                expect(ownerProgress(f).values).to.deepEqual({ 8, 4 })
            end
        },
        {
            name = "Client delta: absolute ordered batches write once and prune using the client's own clock",
            func = function()
                local f = fixture(util.TableToJSON(storedFile()))
                join(f)
                receiveState(f)
                local batch = delta()
                receiveDelta(f, batch)
                expect(f.writes).to.equal(1)
                expect(f.dirs > 0).to.beTrue()
                local saved = f.lib._FileFromJson(f.raw)
                expect(saved.batch).to.deepEqual({ session = 41, seq = 4 })
                expect(saved.weeks[label].items[instanceId].p).to.deepEqual({ 1, 0 })
                expect(saved.weeks[label].items.other.p).to.deepEqual({ 4 })
                expect(saved.weeks[label].bonus).to.beTrue()
                expect(saved.weeks["2026-W46"]).to.beNil()
                expect(saved.weeks["2026-W48"].items.future.p).to.deepEqual({ 7 })
                expect(ownerProgress(f).values).to.deepEqual({ 3, 1 })
                expect(#f.notices).to.equal(1)
                local afterFirst = f.raw
                batch.items[instanceId].p = { 99, 99 }
                receiveDelta(f, batch)
                batch.seq = 2
                receiveDelta(f, batch)
                expect(f.raw).to.equal(afterFirst)
                expect(f.writes).to.equal(1)

                batch.session, batch.seq, batch.bonus = 42, 1, false
                batch.items[instanceId].p = { 2, 0 }
                receiveDelta(f, batch)
                local latest = f.lib._FileFromJson(f.raw)
                expect(latest.batch).to.deepEqual({ session = 42, seq = 1 })
                expect(latest.weeks[label].items[instanceId].p).to.deepEqual({ 2, 0 })
                expect(latest.weeks[label].bonus).to.beFalse()
                expect(f.writes).to.equal(2)
            end
        },
        {
            name = "Client future file: upload is empty, view still works and persistence stays read-only",
            func = function()
                local raw = "{\"v\":2,\"shape\":\"future\"}"
                local f = fixture(raw)
                join(f)
                local wire = f.sent[1].wire
                expect(next(assert(f.lib._ReadWire("upload", wire.size(), wire.read)))).to.beNil()
                receiveState(f)
                receiveProgress(f, { [instanceId] = { p = { 8, 4 }, done = true } })
                expect(ownerProgress(f).done).to.beTrue()
                local batch = delta()
                receiveDelta(f, batch)
                batch.seq = batch.seq + 1
                receiveDelta(f, batch)
                assert(f.reload)()
                join(f)
                expect(#f.sent).to.equal(1)
                expect(#f.logs).to.equal(1)
                expect(f.raw).to.equal(raw)
                expect(f.dirs).to.equal(0)
                expect(f.writes).to.equal(0)
            end
        },
        {
            name = "Client wire: over-cap, malformed and truncated packets leave the view and file unchanged",
            func = function()
                local raw = util.TableToJSON(storedFile())
                local f = fixture(raw)
                join(f)
                receiveState(f)
                local before = f.wireReads
                receive(f, "state", packet(), f.lib._MaxStateBits + 1)
                expect(f.wireReads).to.equal(before)

                local badCount = packet()
                badCount.write(13, 4)
                receive(f, "progress", badCount)
                expect(f.wireReads).to.equal(before + 1)

                local trailing = packet()
                f.lib._WriteWire("state", { week = hostState().week, items = {}, bonus = false }, trailing.write)
                trailing.write(0, 8)
                receive(f, "state", trailing)

                local truncated = packet()
                f.lib._WriteWire("delta", delta(), truncated.write)
                receive(f, "delta", truncated, truncated.size() - 1)

                expect(assert(assert(f.lib.GetWeek)()).label).to.equal(label)
                expect(ownerProgress(f).values).to.deepEqual({ 3, 1 })
                expect(#f.notices).to.equal(1)
                expect(f.raw).to.equal(raw)
                expect(f.writes).to.equal(0)
                expect(f.dirs).to.equal(0)
                receiveDelta(f, delta())
                expect(f.writes).to.equal(1)
            end
        },
        {
            name = "Client disabled: getters hide the snapshot and receivers ignore messages",
            func = function()
                local f = fixture()
                join(f)
                receiveState(f)
                f.enabled = false
                expect(assert(f.lib.GetWeek)()).to.beNil()
                expect(#assert(f.lib.GetActive)()).to.equal(0)
                expect(assert(f.lib.GetProgress)(f.player, instanceId)).to.beNil()
                local before = f.wireReads
                receiveState(f)
                receiveProgress(f, { [instanceId] = { p = { 8, 4 }, done = true } })
                receiveDelta(f, delta())
                expect(f.wireReads).to.equal(before)
                expect(#f.notices).to.equal(1)
                expect(f.writes).to.equal(0)
            end
        }
    }
}
