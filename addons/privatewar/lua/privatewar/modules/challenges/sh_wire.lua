-- Bounded bit codec. Strings are NUL-terminated octets, so the decoder can check every read before touching it.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]
local labelBytes, maxActive, keyBytes = 8, 12, 64
local itemBits = (lib._MaxInstanceId + 1) * 8 + 3 + lib._MaxObjectives * 20 + 1
local weekBits = (labelBytes + 1) * 8 + 32 + 5 + lib._MaxItems * itemBits
lib.UploadMaxBytes = math.ceil((3 + lib._MaxWeeks * weekBits) / 8)

---@alias PW.ChallengeWireMessage "upload"|"state"|"progress"|"delta"
---@alias PW.ChallengeWirePayload PW.ChallengeFileWeeks|PW.ChallengeWireState|PW.ChallengeFileItems|PW.ChallengeDelta

---@type PW.ChallengeTier[]
local tiers = { "easy", "medium", "hard" }
local tierIds = { easy = 0, medium = 1, hard = 2 }

---@param value number
---@param width integer
---@return integer
local function clamp(value, width)
    if value ~= value or value < 0 then return 0 end
    return math.floor(math.min(2 ^ width - 1, value))
end

---@param write PW.ChallengeWireWriter
---@param value string
---@param limit integer
local function writeString(write, value, limit)
    assert(#value <= limit and not value:find("\0", 1, true), "Invalid challenge wire string")
    for i = 1, #value do write(value:byte(i), 8) end
    write(0, 8)
end

---@param read PW.ChallengeWireReader
---@param limit integer
---@return string
local function readString(read, limit)
    ---@type string[]
    local chars = {}
    for i = 1, limit + 1 do
        local byte = read(8)
        if byte == 0 then return table.concat(chars) end
        if i > limit then break end
        chars[i] = string.char(byte)
    end
    error("Unterminated challenge wire string", 0)
end

---@generic T
---@param rows table<string, T>
---@return string[]
local function sortedKeys(rows)
    ---@type string[]
    local keys = {}
    for key in pairs(rows) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

---@param read PW.ChallengeWireReader
---@param width integer
---@param max integer
---@return integer
local function readCount(read, width, max)
    local n = read(width)
    if n > max then error("Too many challenge wire entries", 0) end
    return n
end

---@param read PW.ChallengeWireReader
---@return string
local function readId(read)
    local id = readString(read, lib._MaxInstanceId)
    if not lib._ValidInstanceId(id) then error("Invalid challenge instance ID", 0) end
    return id
end

---@param read PW.ChallengeWireReader
---@return string
local function readLabel(read)
    local label = readString(read, labelBytes)
    if not lib._ValidWeekLabel(label) then error("Invalid challenge week label", 0) end
    return label
end

---@param write PW.ChallengeWireWriter
---@param items PW.ChallengeFileItems
---@param width integer
---@param limit integer
local function writeItems(write, items, width, limit)
    local ids = sortedKeys(items)
    local count = math.min(#ids, limit)
    write(count, width)
    for i = 1, count do
        local id, item = ids[i], items[ids[i]]
        writeString(write, id, lib._MaxInstanceId)
        local n = math.min(#item.p, lib._MaxObjectives)
        write(n, 3)
        for slot = 1, n do write(lib._BoundCounter(item.p[slot]), 20) end
        write(item.done == true and 1 or 0, 1)
    end
end

---@param read PW.ChallengeWireReader
---@param width integer
---@param limit integer
---@return PW.ChallengeFileItems
local function readItems(read, width, limit)
    ---@type PW.ChallengeFileItems
    local items = {}
    for _ = 1, readCount(read, width, limit) do
        local id = readId(read)
        if items[id] ~= nil then error("Repeated challenge instance ID", 0) end
        ---@type integer[]
        local values = {}
        for slot = 1, readCount(read, 3, lib._MaxObjectives) do values[slot] = lib._BoundCounter(read(20)) end
        items[id] = { p = values, done = read(1) == 1 }
    end
    return items
end

---@param write PW.ChallengeWireWriter
---@param weeks PW.ChallengeFileWeeks
local function writeUpload(write, weeks)
    local labels = sortedKeys(weeks)
    local count = math.min(#labels, lib._MaxWeeks)
    write(count, 3)
    for i = 1, count do
        local label = labels[i]
        local week = weeks[label]
        writeString(write, label, labelBytes)
        write(clamp(week.index, 32), 32)
        writeItems(write, week.items, 5, lib._MaxItems)
    end
end

---@param read PW.ChallengeWireReader
---@return PW.ChallengeFileWeeks
local function readUpload(read)
    ---@type PW.ChallengeFileWeeks
    local weeks = {}
    for _ = 1, readCount(read, 3, lib._MaxWeeks) do
        local label = readLabel(read)
        if weeks[label] ~= nil then error("Repeated challenge week label", 0) end
        local index = read(32)
        weeks[label] = { index = index, items = readItems(read, 5, lib._MaxItems) }
    end
    return weeks
end

---@param write PW.ChallengeWireWriter
---@param reward PW.ChallengeReward
local function writeReward(write, reward)
    write(clamp(reward.xp or 0, 24), 24)
    write(clamp(reward.currency or 0, 20), 20)
    local items = reward.items or {}
    local count = math.min(7, #items)
    write(count, 3)
    for i = 1, count do
        local item = items[i]
        writeString(write, item.kind, keyBytes)
        writeString(write, item.id, keyBytes)
        writeString(write, item.weapon or "", keyBytes)
    end
end

---@param read PW.ChallengeWireReader
---@return PW.ChallengeReward
local function readReward(read)
    local xp, currency = read(24), read(20)
    ---@type PW.ChallengeRewardItem[]
    local items = {}
    for i = 1, read(3) do
        local kind, id, weapon = readString(read, keyBytes), readString(read, keyBytes), readString(read, keyBytes)
        items[i] = { kind = kind, id = id, weapon = weapon ~= "" and weapon or nil }
    end
    return { xp = xp, currency = currency, items = items }
end

---@param write PW.ChallengeWireWriter
---@param instance PW.ChallengeInstance
---@param item PW.ChallengeFileItem?
local function writeInstance(write, instance, item)
    writeString(write, instance.id, lib._MaxInstanceId)
    writeString(write, instance.template, lib._MaxInstanceId)
    write(tierIds[instance.tier], 2)
    local params = sortedKeys(instance.params)
    local count = math.min(#params, 7)
    write(count, 3)
    for i = 1, count do
        local key = params[i]
        writeString(write, key, keyBytes)
        writeString(write, instance.params[key], lib._MaxInstanceId)
    end
    local n = math.min(#instance.targets, lib._MaxObjectives)
    write(n, 3)
    for slot = 1, n do
        write(clamp(instance.targets[slot], 20), 20)
        write(lib._BoundCounter(item ~= nil and item.p[slot] or 0), 20)
    end
    write(item ~= nil and item.done == true and 1 or 0, 1)
    writeReward(write, instance.reward)
end

---@param read PW.ChallengeWireReader
---@return PW.ChallengeInstance, PW.ChallengeFileItem
local function readInstance(read)
    local id, template = readId(read), readId(read)
    if template:find(".", 1, true) then error("Dotted challenge template ID", 0) end
    local tier = tiers[read(2) + 1]
    if tier == nil then error("Invalid challenge tier", 0) end
    ---@type PW.ChallengeParams
    local params = {}
    for _ = 1, read(3) do
        local key, value = readString(read, keyBytes), readString(read, lib._MaxInstanceId)
        if key == "" or params[key] ~= nil or not value:match("^[%w_%-]+$") then
            error("Invalid challenge parameter", 0)
        end
        params[key] = value
    end
    ---@type integer[]
    local targets = {}
    ---@type integer[]
    local values = {}
    for slot = 1, readCount(read, 3, lib._MaxObjectives) do
        targets[slot] = read(20)
        values[slot] = math.min(targets[slot], lib._BoundCounter(read(20)))
    end
    local done = read(1) == 1
    return { id = id, template = template, tier = tier, params = params, targets = targets, reward = readReward(read) },
        { p = values, done = done }
end

---@param write PW.ChallengeWireWriter
---@param state PW.ChallengeWireState
local function writeState(write, state)
    local week = state.week
    writeString(write, week.label, labelBytes)
    write(clamp(week.index, 32), 32)
    write(clamp(week.startsAt, 32), 32)
    write(clamp(week.endsAt, 32), 32)
    write(math.min(week.bonus.needed, maxActive), 4)
    write(state.bonus and 1 or 0, 1)
    writeReward(write, week.bonus.reward)
    local count = math.min(#week.items, maxActive)
    write(count, 4)
    for i = 1, count do writeInstance(write, week.items[i], state.items[week.items[i].id]) end
end

---@param read PW.ChallengeWireReader
---@return PW.ChallengeWireState
local function readState(read)
    local label = readLabel(read)
    local index, startsAt, endsAt = read(32), read(32), read(32)
    local needed, bonus = readCount(read, 4, maxActive), read(1) == 1
    ---@type PW.ChallengeWeek
    local week = { label = label, index = index, startsAt = startsAt, endsAt = endsAt, seed = 0, items = {},
        bonus = { needed = needed, reward = readReward(read) } }
    ---@type PW.ChallengeFileItems
    local items = {}
    for i = 1, readCount(read, 4, maxActive) do
        local instance, item = readInstance(read)
        if items[instance.id] ~= nil then error("Repeated challenge instance ID", 0) end
        week.items[i], items[instance.id] = instance, item
    end
    return { week = week, items = items, bonus = bonus }
end

---@param write PW.ChallengeWireWriter
---@param delta PW.ChallengeDelta
local function writeDelta(write, delta)
    write(clamp(delta.session, 32), 32)
    write(clamp(delta.seq, 32), 32)
    writeString(write, delta.label, labelBytes)
    write(clamp(delta.index, 32), 32)
    writeItems(write, delta.items, 5, lib._MaxItems)
    write(delta.bonus and 1 or 0, 1)
end

---@param read PW.ChallengeWireReader
---@return PW.ChallengeDelta
local function readDelta(read)
    local session, seq, label = read(32), read(32), readLabel(read)
    local index, items = read(32), readItems(read, 5, lib._MaxItems)
    return { session = session, seq = seq, label = label, index = index, items = items, bonus = read(1) == 1 }
end

---@param message PW.ChallengeWireMessage
---@param value PW.ChallengeWirePayload
---@param write PW.ChallengeWireWriter
local function writePacket(message, value, write)
    if message == "upload" then writeUpload(write, value --[[@as PW.ChallengeFileWeeks]])
    elseif message == "state" then writeState(write, value --[[@as PW.ChallengeWireState]])
    elseif message == "progress" then writeItems(write, value --[[@as PW.ChallengeFileItems]], 4, maxActive)
    else writeDelta(write, value --[[@as PW.ChallengeDelta]]) end
end

---@param message PW.ChallengeWireMessage
---@param read PW.ChallengeWireReader
---@return PW.ChallengeWirePayload
local function readPacket(message, read)
    if message == "upload" then return readUpload(read) end
    if message == "state" then return readState(read) end
    if message == "progress" then return readItems(read, 4, maxActive) end
    return readDelta(read)
end

---@param message PW.ChallengeWireMessage
---@param bits integer
---@param read PW.ChallengeWireReader
---@return PW.ChallengeWirePayload?
local function readBounded(message, bits, read)
    if bits < 0 or (message == "upload" and bits > lib.UploadMaxBytes * 8) then return nil end
    ---@param width integer
    ---@return integer
    local function take(width)
        if width > bits then error("Truncated challenge packet", 0) end
        bits = bits - width
        return read(width)
    end
    local ok, packet = pcall(readPacket, message, take)
    if not ok or bits ~= 0 then return nil end
    return packet
end

lib._WriteWire = writePacket --[[@as PW.ChallengeWriteWire]]
lib._ReadWire = readBounded --[[@as PW.ChallengeReadWire]]
