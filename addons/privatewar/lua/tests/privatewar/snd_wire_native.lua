-- Real engine transport. The client only echoes bounded raw bits; it does not simulate vector encoding.
-- Loaded clientside only when this test file is present (not included in published packages).
local request, reply = "pw_test_snd_wire_echo", "pw_test_snd_wire_reply"
if CLIENT then
    net.Receive(request, function(length)
        if length < 16 or length > 2048 then return end
        local token = net.ReadUInt(16)
        net.Start(reply)
        net.WriteUInt(token, 16)
        local remaining = length - 16
        while remaining > 0 do
            local count = math.min(32, remaining)
            net.WriteUInt(net.ReadUInt(count), count)
            remaining = remaining - count
        end
        net.SendToServer()
    end)
    return { groupName = "PW SND native wire client relay", cases = {} }
end

---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil) return value end
---@return PW.SNDLib
local function lib() return must(PW.SND) end
local receivers = net.Receivers --[[@as table<string, function>]]
---@type { host: Player, token: integer, read: fun(length: integer) }?
local pending

---@class PW.SNDNativeTransport
---@field token integer
---@field host? Player
---@field bucketSaved? boolean
---@field previousBucket? PW.NetBucket
---@field failed? boolean relay timeout; do not repeat a missing-client fixture failure

---@param state table<string, any>
---@param done fun()
---@param check fun(value: any): table<string, any>
---@param write fun()
---@param read fun(length: integer)
local function roundtrip(state, done, check, write, read)
    local transport = state.transport --[[@as PW.SNDNativeTransport]]
    ---@type Player?
    local host
    for _, ply in ipairs(player.GetHumans()) do if ply:IsListenServerHost() then host = ply break end end
    if transport.failed or host == nil or must(PW.Match).GetPhase() ~= "LOBBY" then
        print("[PW] native S&D wire fixture needs a responding loaded listen host in LOBBY")
        check(false).to.beTrue() -- A missing loaded client/LOBBY is a fixture failure, not engine RED.
        done()
        return
    end
    transport.host = host
    if not transport.bucketSaved then
        local buckets = PW._Net.buckets[host]
        transport.previousBucket = buckets ~= nil and buckets[reply] or nil
        transport.bucketSaved = true
    end
    transport.token = (transport.token + 1) % 65536
    pending = { host = host, token = transport.token, read = function(length)
        local ok, failure = pcall(read, length)
        if not ok then print("[PW] native S&D wire assertion: " .. tostring(failure)) check(ok).to.beTrue() end
        pending = nil
        done()
    end }
    net.Start(request)
    net.WriteUInt(transport.token, 16)
    local _, before = net.BytesWritten()
    local ok, failure = pcall(write)
    if not ok then
        net.Abort()
        print("[PW] native S&D wire writer: " .. tostring(failure))
        check(ok).to.beTrue()
        pending = nil
        done()
        return
    end
    local _, after = net.BytesWritten()
    state.writtenBits = after - before -- Measured delta: no assumption about native message overhead.
    net.Send(host)
end

---@param pos Vector
---@return PW.SNDSnapshot
local function view(pos)
    return { generation = 7, phase = "planted", deadline = 120, fuse = 45, site = "B", pos = pos, progress = 0 }
end
---@param pos Vector
---@return PW.SNDPublicSite[]
local function sites(pos)
    return { { id = "A", pos = Vector(0, 0, 0) }, { id = "B", pos = pos } }
end
---@param actual Vector
---@param expected Vector
---@return boolean
local function near(actual, expected)
    return actual:DistToSqr(expected) <= 3 * (1 / 32 + 0.0001) ^ 2
end

---@type GLuaTest_TestCase[]
local cases = {
    { name = "SND native wire: genuine compressed zero sparse and negative vectors roundtrip with measured bit use",
        async = true, timeout = 8, func = function(state)
        local points = { Vector(0, 0, 0), Vector(1000, 0, 0), Vector(-1000.125, 24, -16.5) }
        roundtrip(state, done, expect, function()
            for _, pos in ipairs(points) do net.WriteVector(pos) end
        end, function(length)
            ---@type integer[]
            local sizes = {}
            for i, expected in ipairs(points) do
                local _, before = net.BytesLeft()
                local actual = net.ReadVector()
                local _, after = net.BytesLeft()
                sizes[i] = before - after
                expect(near(actual, expected)).to.beTrue()
                expect(sizes[i] > 0 and sizes[i] <= length).to.beTrue()
            end
            expect(sizes[1] < sizes[3]).to.beTrue()
            print("[PW] native S&D vector bits: " .. table.concat(sizes, ","))
        end)
    end },
    { name = "SND native wire: truncated legacy interaction tail is rejected after genuine vector decoding",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            net.WriteUInt(7, 32) net.WriteUInt(9, 32) net.WriteUInt(3, 3)
            net.WriteFloat(120) net.WriteFloat(45) net.WriteString("B")
            net.WriteUInt(0, 16) net.WriteBool(true) net.WriteVector(Vector(1000, 0, 0))
            -- Neither action nor progress is written.
        end, function(length) expect(lib()._ReadState(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: an independent legacy receiver reads the unchanged compressed planted payload",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            lib()._WriteState(net --[[@as PW.SNDWire]], 7, 9, view(Vector(1000, 0, 0)))
        end, function(length)
            expect(length >= 166 and length <= 1024).to.beTrue()
            expect(net.ReadUInt(32)).to.equal(7)
            expect(net.ReadUInt(32)).to.equal(9)
            expect(net.ReadUInt(3)).to.equal(3)
            expect(net.ReadFloat()).to.equal(120)
            expect(net.ReadFloat()).to.equal(45)
            expect(net.ReadString()).to.equal("B")
            expect(net.ReadUInt(16)).to.equal(0)
            expect(net.ReadBool()).to.beTrue()
            expect(near(net.ReadVector(), Vector(1000, 0, 0))).to.beTrue()
            expect(net.ReadUInt(2)).to.equal(0)
            expect(net.ReadUInt(8)).to.equal(0)
        end)
    end },
    { name = "SND native wire: truncated sites with a missing second identifier and vector are rejected",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            net.WriteUInt(1, 8) net.WriteUInt(7, 32) net.WriteUInt(9, 32) net.WriteBool(true)
            net.WriteString("A") net.WriteVector(Vector(0, 0, 0))
        end, function(length) expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: a declared frame ending inside the final native vector rejects without size guesses",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            lib()._WriteSites(net --[[@as PW.SNDWire]], 7, 9, sites(Vector(0, 0, 0)))
        end, function(length)
            local written = state.writtenBits --[[@as integer]]
            expect(length >= written).to.beTrue()
            -- The native buffer is intact; only the application frame is cut, independently of transport padding.
            expect(lib()._ReadSites(net --[[@as PW.SNDWire]], written - 1)).to.beNil()
        end)
    end },
    { name = "SND native wire: unterminated site identifier is rejected without a synthesized empty site",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            net.WriteUInt(1, 8) net.WriteUInt(7, 32) net.WriteUInt(9, 32) net.WriteBool(true)
            for _ = 1, 33 do net.WriteUInt(65, 8) end -- No null terminator and no vectors.
        end, function(length) expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: nonfinite legacy deadline rejects even when the native vector itself is valid",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            local invalid = view(Vector(0, 0, 0))
            invalid.deadline = 0 / 0
            lib()._WriteState(net --[[@as PW.SNDWire]], 7, 9, invalid)
        end, function(length) expect(lib()._ReadState(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: unknown optional version is rejected independently of the legacy codec",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            net.WriteUInt(99, 8) net.WriteUInt(7, 32) net.WriteUInt(9, 32) net.WriteBool(false)
        end, function(length) expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: duplicate public site ids reject with genuine compressed vector fields",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            local duplicate = sites(Vector(1000, 0, 0))
            duplicate[2].id = "A"
            lib()._WriteSites(net --[[@as PW.SNDWire]], 7, 9, duplicate)
        end, function(length) expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: identifiers longer than 32 bytes reject without changing the vector codec",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            local oversized = sites(Vector(1000, 0, 0))
            oversized[1].id = string.rep("A", 33)
            lib()._WriteSites(net --[[@as PW.SNDWire]], 7, 9, oversized)
        end, function(length) expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil() end)
    end },
    { name = "SND native wire: the existing 1024 bit cap rejects oversized native messages in both decoders",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            for _ = 1, 33 do net.WriteUInt(0, 32) end
        end, function(length)
            expect(length > 1024).to.beTrue()
            expect(lib()._ReadState(net --[[@as PW.SNDWire]], length)).to.beNil()
            expect(lib()._ReadSites(net --[[@as PW.SNDWire]], length)).to.beNil()
        end)
    end }
}

for _, item in ipairs({ { label = "zero", pos = Vector(0, 0, 0) },
    { label = "sparse", pos = Vector(1000, 0, 0) }, { label = "negative", pos = Vector(-1000.125, 24, -16.5) } }) do
    local pos, label = item.pos, item.label
    cases[#cases + 1] = { name = "SND native wire: legacy planted payload roundtrips " .. label .. " coordinates",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            lib()._WriteState(net --[[@as PW.SNDWire]], 7, 9, view(pos))
        end, function(length)
            local packet = must(lib()._ReadState(net --[[@as PW.SNDWire]], length))
            expect(packet.generation).to.equal(7)
            expect(packet.serial).to.equal(9)
            expect(near(must(must(packet.view).pos), pos)).to.beTrue()
            expect(must(packet.view).phase).to.equal("planted")
        end)
    end }
    cases[#cases + 1] = { name = "SND native wire: public sites payload roundtrips " .. label .. " coordinates",
        async = true, timeout = 8, func = function(state)
        roundtrip(state, done, expect, function()
            lib()._WriteSites(net --[[@as PW.SNDWire]], 7, 9, sites(pos))
        end, function(length)
            local packet = must(lib()._ReadSites(net --[[@as PW.SNDWire]], length))
            expect(packet.generation).to.equal(7)
            expect(#must(packet.sites)).to.equal(2)
            expect(near(must(packet.sites)[2].pos, pos)).to.beTrue()
        end)
    end }
end

return { groupName = "PW SND native compressed net vectors", cases = cases,
    beforeAll = function(state)
        state.transport = { token = os.time() % 65536 }
        state.previousDef, state.previousReceiver = PW._Net.defs[reply], receivers[reply]
        util.AddNetworkString(request)
        must(PW.Net).Receive(reply, { owner = must(PW.Modules.Get("snd")), who = "pw.match.start",
            phases = { "LOBBY" }, rate = 128, maxLen = 256 }, function(ply, length)
            if length < 16 then return end
            local token = net.ReadUInt(16)
            local current = pending
            if current == nil or current.host ~= ply or current.token ~= token then return end
            current.read(length - 16)
        end)
    end,
    afterEach = function(state)
        if pending ~= nil then (state.transport --[[@as PW.SNDNativeTransport]]).failed = true end
        pending = nil
    end,
    afterAll = function(state)
        pending = nil
        PW._Net.defs[reply] = state.previousDef
        receivers[reply] = state.previousReceiver --[[@as function?]]
        local transport = state.transport --[[@as PW.SNDNativeTransport]]
        local host = transport.host
        local buckets = host ~= nil and PW._Net.buckets[host] or nil
        if buckets ~= nil then buckets[reply] = transport.previousBucket end
    end
}
