-- Final targeted regressions. No game RED/GREEN has been observed.
---@generic T
---@param value T?
---@return T
local function must(value) assert(value ~= nil) return value end
---@return PW.SNDLib
local function snd() return must(PW.SND) end
---@return PW.MapLib
local function map() return must(PW.Map) end
---@param x? number
---@return PW.SNDMapData
local function layout(x)
    return { bomb = Vector(x or -200, 0, 0), spawns = {
        [1] = { { pos = Vector(-200, 0, 0), yaw = 0 } },
        [2] = { { pos = Vector(1500, 0, 0), yaw = 180 } }
    }, sites = {
        { id = "A", pos = Vector(0, 0, 0), approach = Vector(0, 0, 0), radius = 64, above = 72, below = 16 },
        { id = "B", pos = Vector(1000, 0, 0), approach = Vector(1000, 0, 0), radius = 64, above = 72, below = 16 }
    } }
end

---@param makeStub fun(object: table, key: string): table<string, any>
---@param authored any
---@return PW.Mode, PW.Mode
local function modes(makeStub, authored)
    local get = PW.Modes.Get
    local base = must(get("snd"))
    local child = setmetatable({ ClassName = "pw_snd_child", BaseClass = base,
        IsValid = function() return true end }, { __index = base })
    local own = setmetatable({ ClassName = "pw_snd_authored", BaseClass = child,
        IsValid = function() return true end }, { __index = child })
    makeStub(PW.Modes, "Get").with(function(id)
        if id == child.ClassName then return child end
        if id == own.ClassName then return own end
        return get(id)
    end)
    makeStub(PW.Modes, "GetEnabledList").with(function() return { own, child, base } end)
    makeStub(map(), "Get").with(function() return { Modes = { [own.ClassName] = authored } } end)
    makeStub(map(), "IsNavReady").with(function() return true end)
    makeStub(game, "GetMap").with(function() return "de_pw_targeted_fixture" end)
    makeStub(_G, "SetGlobal2String").with(function() end)
    makeStub(_G, "SetGlobal2Bool").with(function() end)
    return child --[[@as PW.Mode]], own --[[@as PW.Mode]]
end

---@class PW.SNDTestStream
---@field bits integer
---@field cursor integer
---@field tokens { kind: string, value: any, bits: integer }[]

---@return PW.SNDWire, PW.SNDTestStream
local function stream()
    ---@type PW.SNDTestStream
    local data = { bits = 0, cursor = 1, tokens = {} }
    ---@param kind string
    ---@param value any
    ---@param bits integer
    local function write(kind, value, bits)
        data.tokens[#data.tokens + 1] = { kind = kind, value = value, bits = bits }
        data.bits = data.bits + bits
    end
    ---@param kind string
    ---@param bits? integer
    ---@return any
    local function read(kind, bits)
        local token = assert(data.tokens[data.cursor], "truncated fixture stream")
        assert(token.kind == kind and (bits == nil or token.bits == bits), "incompatible wire field")
        data.cursor = data.cursor + 1
        return token.value
    end
    return {
        WriteUInt = function(value, bits) write("uint", value, bits) end,
        WriteFloat = function(value) write("float", value, 32) end,
        WriteBool = function(value) write("bool", value, 1) end,
        WriteString = function(value) write("string", value, (#value + 1) * 8) end,
        WriteVector = function(value) write("vector", value, 96) end,
        ReadUInt = function(bits) return read("uint", bits) end,
        ReadFloat = function() return read("float") end,
        ReadBool = function() return read("bool") end,
        ReadString = function() return read("string") end,
        ReadVector = function() return read("vector") end
    }, data
end

---@param wire PW.SNDWire
---@param phase integer
local function legacyPayload(wire, phase)
    wire.WriteUInt(7, 32)
    wire.WriteUInt(9, 32)
    wire.WriteUInt(phase, 3)
    if phase == 0 then return end
    wire.WriteFloat(120)
    wire.WriteFloat(45)
    wire.WriteString("B")
    wire.WriteUInt(0, 16)
    wire.WriteBool(true)
    wire.WriteVector(Vector(1000, 0, 0))
    wire.WriteUInt(0, 2)
    wire.WriteUInt(0, 8)
end

---@param wire PW.SNDWire
---@param length integer
---@return string?
local function legacyReceive(wire, length)
    assert(length >= 67 and length <= 1024, "legacy receiver rejects oversized state")
    wire.ReadUInt(32)
    wire.ReadUInt(32)
    local phase = wire.ReadUInt(3)
    if phase == 0 then return nil end
    wire.ReadFloat()
    wire.ReadFloat()
    wire.ReadString()
    wire.ReadUInt(16)
    if wire.ReadBool() then wire.ReadVector() end
    wire.ReadUInt(2)
    wire.ReadUInt(8)
    return ({ "carried", "dropped", "planted", "resolved" })[phase]
end

return { groupName = "PW SND final targeted rework",
    beforeEach = function(state)
        state.mapStore, state.sndStore, state.active = PW._Map, PW._SND, PW.ActiveMode
        PW._Map = map()._NewStore()
        PW._Map.entitiesReady = true
        PW._SND = { generation = 7, serial = 8, nextSnapshot = 0 }
        rawset(PW, "ActiveMode", nil)
    end,
    afterEach = function(state)
        PW._Map = state.mapStore --[[@as PW.MapStore]]
        PW._SND = state.sndStore --[[@as PW.SNDStore]]
        rawset(PW, "ActiveMode", state.active)
    end,
    cases = {
        { name = "SND targeted: reset placeholders cannot mask a ready base and authored child resolves separately",
            func = function()
            local authored, generated = layout(-300), layout()
            local child, own = modes(stub, authored)
            local detects, activations = 0, 0
            stub(snd(), "Detect").with(function() detects = detects + 1 return generated end)
            stub(snd(), "Activate").with(function() activations = activations + 1 end)
            map()._ResetGenerated("fixture reload")
            map().SetModeReadiness(child.ClassName, "pending")
            snd()._ReadinessThink()
            expect(map().GetModeReadiness(child.ClassName)).to.equal("ready")
            expect(map().GetModeData(child.ClassName)).to.equal(generated)
            expect(map().GetModeReadiness(own.ClassName)).to.equal("ready")
            expect(map().GetModeData(own.ClassName)).to.equal(authored)
            expect(detects).to.equal(1)
            expect(activations).to.equal(2)
        end },
        { name = "SND targeted: invalid authored child rejects without hiding its ready generated base",
            func = function()
            local child, own = modes(stub, false)
            stub(snd(), "Detect").with(function() return layout() end)
            stub(snd(), "Activate").with(function() end)
            snd()._ReadinessThink()
            expect(map().GetModeReadiness(child.ClassName)).to.equal("ready")
            expect(map().GetModeReadiness(own.ClassName)).to.equal("rejected")
            expect(map().GetModeData(own.ClassName)).to.beNil()
            expect(map().GetModeData(child.ClassName) ~= nil).to.beTrue()
        end },
        { name = "SND targeted: authored child world activation failure never poisons the inherited generated source",
            func = function()
            local child, own = modes(stub, layout(-300))
            stub(snd(), "Detect").with(function() return layout() end)
            stub(snd(), "Activate").with(function(data)
                if (data --[[@as PW.SNDMapData]]).bomb.x == -300 then error("fixture blocked authored child") end
            end)
            snd()._ReadinessThink()
            expect(map().GetModeReadiness(child.ClassName)).to.equal("ready")
            expect(map().GetModeReadiness(own.ClassName)).to.equal("rejected")
            expect(map().GetModeData(child.ClassName) ~= nil).to.beTrue()
        end },
        { name = "SND targeted: readiness state reason and source keys cannot alias legal mode ids", func = function()
            ---@type table<string, string>
            local values = {}
            stub(_G, "SetGlobal2String").with(function(key, value) values[key] = value end)
            map().SetModeReadiness("snd", "ready", nil, "generated")
            map().SetModeReadiness("snd_source", "rejected", "Source mode rejected")
            map().SetModeReadiness("snd_reason", "ready", "Reason mode", "authored")
            expect(values[map()._ReadinessKey("source", "snd")]).to.equal("generated")
            expect(values[map()._ReadinessKey("state", "snd_source")]).to.equal("rejected")
            expect(values[map()._ReadinessKey("reason", "snd_source")]).to.equal("Source mode rejected")
            expect(values[map()._ReadinessKey("state", "snd_reason")]).to.equal("ready")
            expect(values[map()._ReadinessKey("reason", "snd")]).to.equal("")
        end },
        { name = "SND targeted: new state writer retains the complete legacy planted payload without site fields",
            func = function()
            local wire, data = stream()
            local authored = layout()
            authored.sites[1].id, authored.sites[2].id = string.rep("A", 32), string.rep("B", 32)
            local state = snd().NewRound(authored, {}, 0, 7)
            state.phase, state.fuse, state.site = "planted", 45, authored.sites[2].id
            local view = snd().Snapshot(state, 2, "defender", 0)
            snd()._WriteState(wire, 7, 9, view)
            expect(legacyReceive(wire, data.bits)).to.equal("planted")
            expect(data.cursor).to.equal(#data.tokens + 1)
        end },
        { name = "SND targeted: new state decoder accepts every legacy phase and reset without optional sites",
            func = function()
            for phase = 0, 4 do
                local wire, data = stream()
                legacyPayload(wire, phase)
                local packet = must(snd()._ReadState(wire, data.bits))
                expect(packet.generation).to.equal(7)
                expect(packet.serial).to.equal(9)
                if phase == 0 then expect(packet.view).to.beNil()
                else expect(must(packet.view).sites).to.beNil() end
                expect(data.cursor).to.equal(#data.tokens + 1)
            end
        end },
        { name = "SND targeted: optional versioned sites match only the exact legacy snapshot and reject stale stamps",
            func = function()
            local wire, data = stream()
            snd()._WriteSites(wire, 7, 9, snd().PublicSites(layout().sites))
            local packet = must(snd()._ReadSites(wire, data.bits))
            expect(#must(snd()._SitesFor(packet, 7, 9))).to.equal(2)
            expect(snd()._SitesFor(packet, 8, 9)).to.beNil()
            expect(snd()._SitesFor(packet, 7, 10)).to.beNil()
            local reset, resetData = stream()
            snd()._WriteSites(reset, 7, 10, nil)
            expect(must(snd()._ReadSites(reset, resetData.bits)).sites).to.beNil()
        end },
        { name = "SND targeted: unknown or malformed optional sites cannot invalidate a legacy match state",
            func = function()
            local legacy, legacyData = stream()
            legacyPayload(legacy, 3)
            expect(must(must(snd()._ReadState(legacy, legacyData.bits)).view).phase).to.equal("planted")
            local wire, data = stream()
            snd()._WriteSites(wire, 7, 9, snd().PublicSites(layout().sites))
            data.tokens[1].value = 99
            expect(snd()._ReadSites(wire, data.bits)).to.beNil()
            local malformed, malformedData = stream()
            local sites = must(snd().PublicSites(layout().sites))
            sites[1].pos.x = 0 / 0
            snd()._WriteSites(malformed, 7, 9, sites)
            expect(snd()._ReadSites(malformed, malformedData.bits)).to.beNil()
        end },
        { name = "SND targeted: one server publish serves legacy and modern clients through separate channels",
            func = function()
            local old, modern = {}, {}
            ---@type PW.SNDWire?
            local wire
            ---@type PW.SNDTestStream?
            local data
            local channel, ignored = "", 0
            ---@type string?
            local oldPhase
            ---@type PW.SNDStatePacket?
            local modernState
            ---@type PW.SNDSitesPacket?
            local modernSites
            stub(player, "GetHumans").with(function() return { old, modern } end)
            stub(snd(), "Identity").with(function(ply) return ply == old and "old" or "modern" end)
            stub(net, "Start").with(function(name) channel, wire, data = name, stream() end)
            for _, name in ipairs({ "WriteUInt", "WriteFloat", "WriteBool", "WriteString", "WriteVector" }) do
                local field = name
                stub(net, field).with(function(...)
                    (must(wire) --[[@as table<string, function>]])[field](...)
                end)
            end
            stub(net, "Send").with(function(ply)
                if ply == old then
                    if channel == "pw_snd_state" then oldPhase = legacyReceive(must(wire), must(data).bits)
                    else ignored = ignored + 1 end
                elseif channel == "pw_snd_state" then
                    modernState = snd()._ReadState(must(wire), must(data).bits)
                elseif channel == "pw_snd_sites" then
                    modernSites = snd()._ReadSites(must(wire), must(data).bits)
                end
            end)
            local state = snd().NewRound(layout(), {}, 0, 7)
            state.phase, state.fuse, state.site = "planted", 45, "B"
            snd().Publish(state, true)
            expect(oldPhase).to.equal("planted")
            expect(ignored).to.equal(1)
            expect(must(must(modernState).view).phase).to.equal("planted")
            expect(#must(snd()._SitesFor(must(modernSites), 7, 9))).to.equal(2)
        end }
    }
}
