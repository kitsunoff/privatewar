-- Client file normalization and the server's bounded, read-only projection of an upload.
local lib = PW.Challenges --[[@as PW.ChallengesLib]]

lib.FileVersion = 1
lib.FilePath = "privatewar/challenges.json"
lib._MaxWeeks = 4
lib._MaxItems = 16
lib._MaxObjectives = 4
lib._MaxCount = 1000000
lib._MaxUInt32 = 2 ^ 32 - 1

function lib._ValidWeekLabel(label)
    return type(label) == "string" and label:match("^%d%d%d%d%-W%d%d$") ~= nil
end

function lib._ValidInstanceId(id)
    return type(id) == "string" and #id <= lib._MaxInstanceId
        and id:match("^%l[%w_%.%-]*$") ~= nil and not id:find("..", 1, true) and id:sub(-1) ~= "."
end

function lib._BoundCounter(value)
    if type(value) ~= "number" or not (value >= 0 and value < math.huge) then return 0 end
    return math.floor(math.min(lib._MaxCount, value))
end

---@param value any
---@return integer?
local function uint32(value)
    if type(value) ~= "number" or not (value >= 0 and value <= lib._MaxUInt32) or value % 1 ~= 0 then return nil end
    return value
end

---@param input any
---@return table<string, any>
local function fields(input)
    return type(input) == "table" and input or {}
end

---@param raw any
---@return PW.ChallengeFileItem
local function cleanItem(raw)
    local item = fields(raw)
    ---@type PW.ChallengeFileItem
    local clean = { p = {}, done = item.done == true }
    if type(item.p) ~= "table" then return clean end
    local values = item.p --[[@as table<integer, any>]]
    for slot = 1, math.min(#values, lib._MaxObjectives) do clean.p[slot] = lib._BoundCounter(values[slot]) end
    return clean
end

---@param raw any
---@return PW.ChallengeFileItems
local function cleanItems(raw)
    local items = fields(raw)
    ---@type string[]
    local ids = {}
    for id, item in pairs(items) do
        if lib._ValidInstanceId(id) and type(item) == "table" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    ---@type PW.ChallengeFileItems
    local clean = {}
    for slot = 1, math.min(#ids, lib._MaxItems) do
        local id = ids[slot]
        clean[id] = cleanItem(items[id])
    end
    return clean
end

---@param raw any
---@param minimum? integer
---@return PW.ChallengeFileWeeks
local function cleanWeeks(raw, minimum)
    local weeks = fields(raw)
    ---@type { label: string, index: integer }[]
    local newest = {}
    for label, entry in pairs(weeks) do
        local index = uint32(fields(entry).index)
        if lib._ValidWeekLabel(label) and index ~= nil and (minimum == nil or index >= minimum) then
            newest[#newest + 1] = { label = label, index = index }
        end
    end
    table.sort(newest, function(a, b)
        if a.index ~= b.index then return a.index > b.index end
        return a.label < b.label
    end)
    ---@type PW.ChallengeFileWeeks
    local clean = {}
    for slot = 1, math.min(#newest, lib._MaxWeeks) do
        local row = newest[slot]
        local week = fields(weeks[row.label])
        clean[row.label] = { index = row.index, items = cleanItems(week.items), bonus = week.bonus == true }
    end
    return clean
end

function lib._Migrate(raw)
    local input = fields(raw)
    if input.v ~= lib.FileVersion then return { v = lib.FileVersion, weeks = {} } end
    local batch = fields(input.batch)
    local session, seq = uint32(batch.session), uint32(batch.seq)
    return { v = lib.FileVersion, weeks = cleanWeeks(input.weeks),
        batch = session ~= nil and seq ~= nil and { session = session, seq = seq } or nil }
end

function lib._FileFromJson(json)
    local raw = fields(json ~= nil and json ~= "" and util.JSONToTable(json, false, true) or nil)
    return lib._Migrate(raw), type(raw.v) == "number" and raw.v > lib.FileVersion
end

function lib._FileToJson(file, currentIndex, readOnly)
    if readOnly or file.v > lib.FileVersion then return nil end
    return util.TableToJSON({
        v = lib.FileVersion,
        weeks = cleanWeeks(file.weeks, currentIndex - 1),
        batch = file.batch
    })
end

function lib._ApplyDelta(current, delta)
    local batch = current.batch
    if batch ~= nil and batch.session == delta.session and delta.seq <= batch.seq then return current, false end
    if not lib._ValidWeekLabel(delta.label) or uint32(delta.index) == nil then return current, false end
    ---@type PW.ChallengeFileWeeks
    local weeks = {}
    for label, week in pairs(current.weeks) do weeks[label] = week end
    local previous = weeks[delta.label]
    ---@type PW.ChallengeFileItems
    local items = {}
    if previous ~= nil and previous.index == delta.index then
        for id, item in pairs(previous.items) do items[id] = item end
    end
    for id, item in pairs(delta.items) do items[id] = item end
    weeks[delta.label] = { index = delta.index, items = items, bonus = delta.bonus }
    return {
        v = lib.FileVersion,
        weeks = cleanWeeks(weeks),
        batch = { session = delta.session, seq = delta.seq }
    }, true
end

---@param item PW.ChallengeFileItem
---@param instance PW.ChallengeInstance
---@param mode PW.ChallengeCombine?
---@return PW.ChallengeFileItem
local function admitItem(item, instance, mode)
    ---@type PW.ChallengeFileItem
    local admitted = { p = {} }
    local finished = 0
    for slot, target in ipairs(instance.targets) do
        local count = math.min(target, lib._BoundCounter(item.p[slot]))
        admitted.p[slot] = count
        if count >= target then finished = finished + 1 end
    end
    admitted.done = finished == #instance.targets or (mode == "any" and finished > 0)
    return admitted
end

function lib._UploadWeek(weeks, active, modes)
    ---@type PW.ChallengeFileWeek
    local week = { index = active.index, items = {}, bonus = false }
    local uploaded = weeks[active.label]
    if uploaded == nil or uploaded.index ~= active.index then return week end
    local completed = 0
    for _, instance in ipairs(active.items) do
        local item = uploaded.items[instance.id]
        if item ~= nil then
            local admitted = admitItem(item, instance, modes[instance.id])
            if admitted.done then completed = completed + 1 end
            week.items[instance.id] = admitted
        end
    end
    week.bonus = active.bonus.needed > 0 and completed >= active.bonus.needed
    return week
end
