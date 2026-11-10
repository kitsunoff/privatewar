-- The original state channel stays byte-for-byte compatible. Optional public sites use a separate codec.
local lib = PW.SND --[[@as PW.SNDLib]]
local phases = { "carried", "dropped", "planted", "resolved" }
local phaseIds = { carried = 1, dropped = 2, planted = 3, resolved = 4 }

function lib._WriteState(wire, generation, serial, view)
    wire.WriteUInt(generation, 32)
    wire.WriteUInt(serial, 32)
    wire.WriteUInt(view ~= nil and phaseIds[view.phase] or 0, 3)
    if view == nil then return end
    wire.WriteFloat(view.deadline)
    wire.WriteFloat(view.fuse)
    wire.WriteString(view.site or "")
    wire.WriteUInt(view.carrier or 0, 16)
    wire.WriteBool(view.pos ~= nil)
    if view.pos ~= nil then wire.WriteVector(view.pos) end
    wire.WriteUInt(view.action == "plant" and 1 or (view.action == "defuse" and 2 or 0), 2)
    wire.WriteUInt(math.floor(view.progress * 255 + 0.5), 8)
end

---@param n number
---@return boolean
local function time(n) return n == n and n >= 0 and n < math.huge end
---@param pos Vector
---@return boolean
local function vector(pos)
    return pos.x == pos.x and pos.y == pos.y and pos.z == pos.z
        and math.abs(pos.x) < math.huge and math.abs(pos.y) < math.huge and math.abs(pos.z) < math.huge
end

---@param wire PW.SNDWire
---@param length integer
---@return PW.SNDWire
local function bounded(wire, length)
    -- Native cursor, not byte-count guesses: https://wiki.facepunch.com/gmod/net.BytesLeft
    ---@return integer
    local function bits()
        local _, count = wire.BytesLeft()
        if count == nil then error("No native read cursor", 0) end
        assert(count >= 0 and count < math.huge and count == math.floor(count), "Invalid native read cursor")
        return count --[[@as integer]]
    end
    local initial = bits()
    assert(initial >= length, "Truncated native message")
    ---@param func function
    ---@param minimum integer
    ---@param exact? integer
    ---@param ... any
    ---@return any, integer
    local function take(func, minimum, exact, ...)
        local before = bits()
        local used = initial - before
        assert(used >= 0 and used <= length and length - used >= minimum, "Truncated field")
        ---@type any
        local value = func(...)
        ---@type integer
        local consumed = before - bits()
        assert(consumed >= minimum and consumed <= length - used
            and (exact == nil or consumed == exact), "Native read exceeded payload budget")
        return value, consumed
    end
    return setmetatable({
        ReadUInt = function(count) return take(wire.ReadUInt, count, count, count) end,
        ReadFloat = function() return take(wire.ReadFloat, 32, 32) end,
        ReadBool = function() return take(wire.ReadBool, 1, 1) end,
        ReadString = function()
            local value, consumed = take(wire.ReadString, 8)
            assert(#value <= 32 and consumed == (#value + 1) * 8, "Invalid bounded identifier")
            return value
        end,
        -- No fixed vector size: use the engine's actual cursor movement. ReadVector can silently return zero
        -- on failure (net.ReadVector docs); without an overflow flag not every corrupt final vector is distinguishable.
        ReadVector = function() return take(wire.ReadVector, 1) end
    }, { __index = wire }) --[[@as PW.SNDWire]]
end

---@param wire PW.SNDWire
---@param length integer
---@return PW.SNDStatePacket?
local function readState(wire, length)
    wire = bounded(wire, length)
    local generation, serial, phase = wire.ReadUInt(32), wire.ReadUInt(32), wire.ReadUInt(3)
    if phase == 0 then return { generation = generation, serial = serial } end
    if phases[phase] == nil or length < 166 then return nil end
    ---@type PW.SNDSnapshot
    local view = { generation = generation, phase = phases[phase], deadline = wire.ReadFloat(),
        fuse = wire.ReadFloat(), site = wire.ReadString(), progress = 0 }
    if #assert(view.site) > 32 or not time(view.deadline) or not time(view.fuse)
        or length < 166 + #assert(view.site) * 8 then return nil end
    local carrier = wire.ReadUInt(16)
    if carrier > 0 then view.carrier = carrier end
    if view.site == "" then view.site = nil end
    if wire.ReadBool() then
        local pos = wire.ReadVector()
        if not vector(pos) then return nil end
        view.pos = pos
    end
    local action = wire.ReadUInt(2)
    view.action = action == 1 and "plant" or (action == 2 and "defuse" or nil)
    view.progress = wire.ReadUInt(8) / 255
    return { generation = generation, serial = serial, view = view }
end

function lib._ReadState(wire, length)
    if length < 67 or length > 1024 then return nil end
    local ok, packet = pcall(readState, wire, length)
    return ok and packet or nil
end

function lib._WriteSites(wire, generation, serial, sites)
    wire.WriteUInt(1, 8)
    wire.WriteUInt(generation, 32)
    wire.WriteUInt(serial, 32)
    wire.WriteBool(sites ~= nil)
    if sites == nil then return end
    for _, site in ipairs(sites) do
        wire.WriteString(site.id)
        wire.WriteVector(site.pos)
    end
end

---@param wire PW.SNDWire
---@param length integer
---@return PW.SNDSitesPacket?
local function readSites(wire, length)
    wire = bounded(wire, length)
    if wire.ReadUInt(8) ~= 1 then return nil end
    local generation, serial = wire.ReadUInt(32), wire.ReadUInt(32)
    if not wire.ReadBool() then return { generation = generation, serial = serial } end
    ---@type PW.SNDPublicSite[]
    local raw = {}
    for i = 1, 2 do
        local id = wire.ReadString()
        if #id == 0 or #id > 32 then return nil end
        raw[i] = { id = id, pos = wire.ReadVector() }
    end
    local sites = lib.PublicSites(raw)
    if sites == nil then return nil end
    return { generation = generation, serial = serial, sites = sites }
end

function lib._ReadSites(wire, length)
    if length < 73 or length > 1024 then return nil end
    local ok, packet = pcall(readSites, wire, length)
    return ok and packet or nil
end

function lib._SitesFor(packet, generation, serial)
    if packet == nil or packet.generation ~= generation or packet.serial ~= serial then return nil end
    return lib.PublicSites(packet.sites)
end
