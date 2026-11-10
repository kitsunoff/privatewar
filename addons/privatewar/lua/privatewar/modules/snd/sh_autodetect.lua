-- Cold, bounded geometry derivation. Labels are deterministic, not Counter-Strike label recovery.
local lib = PW.SND --[[@as PW.SNDLib]]

---@param n any
---@return boolean
local function finite(n) return isnumber(n) and n == n and math.abs(n) < math.huge end
---@param v any
---@return boolean
local function vector(v) return isvector(v) and finite(v.x) and finite(v.y) and finite(v.z) end

function lib.PublicSites(raw)
    if not istable(raw) or #raw ~= 2 or table.Count(raw) ~= 2 then return nil end
    ---@cast raw table<string, any>[]
    ---@type PW.SNDPublicSite[]
    local out = {}
    for _, site in ipairs(raw) do
        if not istable(site) or not isstring(site.id) or #site.id < 1 or #site.id > 32
            or not vector(site.pos) then return nil end
        out[#out + 1] = { id = site.id, pos = Vector(site.pos.x, site.pos.y, site.pos.z) }
    end
    if out[1].id == out[2].id then return nil end
    return out
end

---@param a PW.SNDTarget
---@param b PW.SNDTarget
---@param gap number
---@return boolean
local function adjacent(a, b, gap)
    return a.mins.x <= b.maxs.x + gap and b.mins.x <= a.maxs.x + gap
        and a.mins.y <= b.maxs.y + gap and b.mins.y <= a.maxs.y + gap
        and a.mins.z <= b.maxs.z + gap and b.mins.z <= a.maxs.z + gap
end
---@param a PW.SNDTarget
---@param b PW.SNDTarget
---@return boolean
local function order(a, b)
    for _, axis in ipairs({ "x", "y", "z" }) do
        if a.mins[axis] ~= b.mins[axis] then return a.mins[axis] < b.mins[axis] end
        if a.maxs[axis] ~= b.maxs[axis] then return a.maxs[axis] < b.maxs[axis] end
    end
    return a.name < b.name
end

function lib.GroupTargets(targets)
    if #targets > 128 then return nil, "S&D target limit exceeded" end
    ---@type PW.SNDTarget[]
    local list = {}
    for _, t in ipairs(targets) do
        if not t.disabled then
            if not vector(t.mins) or not vector(t.maxs) or not isstring(t.name)
                or t.mins.x >= t.maxs.x or t.mins.y >= t.maxs.y or t.mins.z >= t.maxs.z then
                return nil, "Invalid S&D target bounds"
            end
            list[#list + 1] = t
        end
    end
    table.sort(list, order)
    ---@type integer[]
    local roots = {}
    for i = 1, #list do roots[i] = i end
    ---@param i integer
    ---@return integer
    local function root(i)
        while roots[i] ~= i do i = roots[i] end
        return i
    end
    for i, a in ipairs(list) do
        for j = i + 1, #list do
            local b = list[j]
            local named = a.name ~= "" and b.name ~= ""
            if named and a.name ~= b.name and adjacent(a, b, 0) then
                return nil, "Overlapping named S&D sites are ambiguous"
            end
            if (named and a.name == b.name) or (not named and adjacent(a, b, 128)) then
                roots[root(j)] = root(i)
            end
        end
    end
    ---@type table<integer, PW.SNDTarget[]>
    local buckets = {}
    for i, t in ipairs(list) do
        local key = root(i)
        buckets[key] = buckets[key] or {}
        buckets[key][#buckets[key] + 1] = t
    end
    ---@type PW.SNDTarget[][]
    local groups = {}
    for _, group in pairs(buckets) do
        local name = ""
        for _, t in ipairs(group) do
            if t.name ~= "" and name ~= "" and t.name ~= name then
                return nil, "Unnamed S&D target bridges named sites"
            end
            if t.name ~= "" then name = t.name end
        end
        groups[#groups + 1] = group
    end
    if #groups ~= 2 then return nil, "S&D needs exactly two unambiguous bomb sites" end
    table.sort(groups, function(a, b) return order(a[1], b[1]) end)
    return groups
end

---@param pos Vector
---@param group PW.SNDTarget[]
---@return PW.SNDTarget?
local function contains(pos, group)
    for _, t in ipairs(group) do
        if pos.x >= t.mins.x and pos.x <= t.maxs.x and pos.y >= t.mins.y and pos.y <= t.maxs.y
            and pos.z >= t.mins.z - 16 and pos.z <= t.maxs.z then return t end
    end
end

---@param group PW.SNDTarget[]
---@param input PW.SNDDeriveInput
---@param bomb Vector
---@param id string
---@return PW.SNDSite?
local function sitePoint(group, input, bomb, id)
    -- Area centres only, bounded by the input cap; never use a union AABB's empty gaps.
    local probes = 0
    for _, pos in ipairs(input.points) do
        local t = vector(pos) and contains(pos, group) or nil
        if t ~= nil then
            probes = probes + 1
            if probes > 16 then return nil end
        end
        if t ~= nil and input.safe(pos) and input.mutual(bomb, pos) then
            return { id = id, pos = pos, approach = pos,
                radius = math.Clamp(math.min(t.maxs.x - t.mins.x, t.maxs.y - t.mins.y) / 2, 32, 320),
                above = math.Clamp(t.maxs.z - pos.z, 72, 256), below = 16 }
        end
    end
end

function lib.Derive(input)
    if #input.points > 4096 then return nil, "S&D nav point limit exceeded" end
    local groups, reason = lib.GroupTargets(input.targets)
    if groups == nil then return nil, reason end
    ---@type table<integer, PW.SpawnPoint[]>
    local spawns = { {}, {} }
    for side = 1, 2 do
        local pool = input.spawns[side] or {}
        if #pool > 64 then return nil, "S&D side spawn limit exceeded" end
        for _, spawn in ipairs(pool) do
            if vector(spawn.pos) and finite(spawn.yaw) and input.safe(spawn.pos) then
                spawns[side][#spawns[side] + 1] = { pos = spawn.pos, yaw = spawn.yaw }
            end
        end
        if #spawns[side] == 0 then return nil, "S&D side " .. side .. " has no safe spawn" end
        table.sort(spawns[side], function(a, b)
            if a.pos.x ~= b.pos.x then return a.pos.x < b.pos.x end
            if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
            if a.pos.z ~= b.pos.z then return a.pos.z < b.pos.z end
            return a.yaw < b.yaw
        end)
    end
    local bomb = spawns[1][1].pos
    for side = 1, 2 do
        ---@type PW.SpawnPoint[]
        local filtered = {}
        for _, spawn in ipairs(spawns[side]) do
            if input.mutual(bomb, spawn.pos) then filtered[#filtered + 1] = spawn end
        end
        spawns[side] = filtered
        if #filtered == 0 then return nil, "S&D side " .. side .. " has no mutual nav route" end
    end
    ---@type PW.SNDSite[]
    local sites = {}
    for i, group in ipairs(groups) do
        local id = i == 1 and "A" or "B"
        local site = sitePoint(group, input, bomb, id)
        if site == nil then return nil, "S&D site " .. id .. " has no safe reachable nav point" end
        sites[i] = site
    end
    local data = { sites = sites, bomb = bomb, spawns = spawns }
    local ok, invalid = lib.Validate(data)
    if not ok then return nil, invalid end
    return data
end
