-- Pure checks, serialization and delta application for the separate unlocks file (06-progression.md d.5 and d.8).
local lib = PW.Unlocks --[[@as PW.UnlocksLib]]
local progression = PW.Progression --[[@as PW.ProgressionLib]]

lib.FilePath, lib.FileVersion = "privatewar/unlocks.json", 1
lib.MaxGrants, lib.MaxClaims = 384, 256
lib.MaxGrantIdLength, lib.MaxGrantPerCall = 64, 32
lib.MaxDeltaGrants, lib.MaxDeltaRevokes, lib.MaxDeltaClaims = 32, 32, 8
lib.UploadMaxBytes = 5 + lib.MaxGrants * (progression.MaxKeyLength + 1) + lib.MaxClaims * (lib.MaxGrantIdLength + 1)

function lib._CheckGrantId(value)
    if isstring(value) and #value <= lib.MaxGrantIdLength and value:match("^[%w_%-%.:]+$") then return value end
    return nil
end

function lib._CheckTime(value)
    if isnumber(value) and value >= 0 and value < 2 ^ 32 and math.floor(value) == value then return value end
    return nil
end

function lib._EntitlementKey(value)
    if type(value) ~= "string" or lib.KeyOf(value) ~= value then return nil end
    local kind = lib.ParseKey(value)
    if kind == "bundles" or kind == "classes" then return nil end
    return value
end

---@param raw table<any, any>
---@return string[]
local function keysOf(raw)
    ---@type string[]
    local keys = {}
    for key in pairs(raw) do
        if isstring(key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

---@param raw any
---@return PW.UnlockGrantMeta?
local function grantOf(raw)
    if not istable(raw) then return nil end
    local value = raw --[[@as table<string, any>]]
    local source = lib._CheckSource(value.source)
    local at = lib._CheckTime(value.at)
    local grant = lib._CheckGrantId(value.grant)
    if source == nil or at == nil or (value.grant ~= nil and grant == nil) then return nil end
    return { source = source, at = at, grant = grant }
end

function lib._CheckGrants(raw, limit)
    ---@type table<string, PW.UnlockGrantMeta>
    local out = {}
    if not istable(raw) then return out end
    local cap, count = limit or lib.MaxGrants, 0
    local entries = raw --[[@as table<string, any>]]
    for _, key in ipairs(keysOf(entries)) do
        if count >= cap then break end
        local meta = lib._EntitlementKey(key) ~= nil and grantOf(entries[key]) or nil
        if meta ~= nil then
            out[key] = meta
            count = count + 1
        end
    end
    return out
end

function lib._CheckClaims(raw, limit)
    ---@type table<string, integer>
    local out = {}
    if not istable(raw) then return out end
    ---@type { id: string, at: integer }[]
    local entries = {}
    for id, value in pairs(raw --[[@as table<any, any>]]) do
        local key, at = lib._CheckGrantId(id), lib._CheckTime(value)
        if key ~= nil and at ~= nil then entries[#entries + 1] = { id = key, at = at } end
    end
    table.sort(entries, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    for index = 1, math.min(#entries, limit or lib.MaxClaims) do
        local entry = entries[index]
        out[entry.id] = entry.at
    end
    return out
end

---@param raw table<string, string>?
---@return table<string, string>
local function checkedRevokes(raw)
    ---@type table<string, string>
    local out = {}
    if raw == nil then return out end
    local count = 0
    for _, key in ipairs(keysOf(raw)) do
        if count >= lib.MaxDeltaRevokes then break end
        local source = lib._EntitlementKey(key) ~= nil and lib._CheckSource(raw[key]) or nil
        if source ~= nil then
            out[key] = source
            count = count + 1
        end
    end
    return out
end

function lib._FileFromJson(decoded)
    local source = istable(decoded) and decoded --[[@as table<string, any>]] or {}
    if source.v ~= lib.FileVersion or not istable(source.grants) or not istable(source.claims)
        or not istable(source.batch) then
        return { v = lib.FileVersion, grants = {}, claims = {}, batch = { session = 0, seq = 0 } }
    end
    local batch = source.batch --[[@as table<string, any>]]
    return {
        v = lib.FileVersion, grants = lib._CheckGrants(source.grants), claims = lib._CheckClaims(source.claims),
        batch = { session = lib._CheckTime(batch.session) or 0, seq = lib._CheckTime(batch.seq) or 0 }
    }
end

function lib._FileToJson(stored)
    return lib._FileFromJson(stored)
end

function lib._ListEntitled(owned, granted)
    local out = lib._CheckGrants(granted)
    for key, present in pairs(owned or {}) do
        if present == true and out[key] == nil then out[key] = { source = "purchase", at = 0 } end
    end
    return out
end

function lib._ApplyDelta(current, delta)
    if delta.session == current.batch.session and delta.seq <= current.batch.seq then return current, false end
    local added = lib._CheckGrants(delta.granted, lib.MaxDeltaGrants)
    local removed = checkedRevokes(delta.revoked)
    local claims = lib._CheckClaims(delta.claims, lib.MaxDeltaClaims)
    if next(added) == nil and next(removed) == nil and next(claims) == nil then return current, false end
    local grants = lib._CheckGrants(current.grants)
    ---@type table<string, string>, table<string, PW.UnlockGrantMeta>
    local revoked, granted = {}, {}
    local count = table.Count(grants)
    for key, source in pairs(removed) do
        if grants[key] ~= nil then
            revoked[key], grants[key] = source, nil
            count = count - 1
        end
    end
    for _, key in ipairs(keysOf(added)) do
        if count >= lib.MaxGrants then break end
        if grants[key] == nil and removed[key] == nil then
            granted[key], grants[key] = added[key], added[key]
            count = count + 1
        end
    end
    local mergedClaims = lib._CheckClaims(current.claims)
    for id, at in pairs(claims) do mergedClaims[id] = math.max(mergedClaims[id] or 0, at) end
    return {
        v = lib.FileVersion, grants = grants, claims = lib._CheckClaims(mergedClaims),
        batch = { session = delta.session, seq = delta.seq }
    }, true, { granted = granted, revoked = revoked }
end

---@param values table<string, any>
---@param writer PW.ProgressionWriter
local function writeUploadKeys(values, writer)
    local keys = keysOf(values)
    writer.uint(#keys, 16)
    for _, key in ipairs(keys) do writer.string(key) end
end

function lib._EncodeUpload(stored, writer)
    writer.uint(lib.FileVersion, 8)
    writeUploadKeys(lib._CheckGrants(stored.grants), writer)
    writeUploadKeys(lib._CheckClaims(stored.claims), writer)
end

---@param reader PW.ProgressionReader
---@param max integer
---@param check fun(raw: any): string?
---@return table<string, boolean>?
local function readUploadKeys(reader, max, check)
    local count = reader.uint(16)
    if count > max then return nil end
    ---@type table<string, boolean>
    local kept = {}
    for _ = 1, count do
        local key = check(reader.string())
        if key ~= nil then kept[key] = true end
    end
    return kept
end

function lib._DecodeUpload(reader)
    if reader.uint(8) ~= lib.FileVersion then return nil end
    local grants = readUploadKeys(reader, lib.MaxGrants, lib._EntitlementKey)
    if grants == nil then return nil end
    local claims = readUploadKeys(reader, lib.MaxClaims, lib._CheckGrantId)
    if claims == nil then return nil end
    return { grants = grants, claims = claims }
end

function lib._EncodeDeltaPart(part, writer)
    local grants = lib._CheckGrants(part.granted, lib.MaxDeltaGrants)
    local grantKeys = keysOf(grants)
    writer.uint(#grantKeys, 8)
    for _, key in ipairs(grantKeys) do
        local meta = grants[key]
        writer.string(key)
        writer.string(meta.source)
        writer.string(meta.grant or "")
        writer.uint(meta.at, 32)
    end
    local revokes = checkedRevokes(part.revoked)
    local revokeKeys = keysOf(revokes)
    writer.uint(#revokeKeys, 8)
    for _, key in ipairs(revokeKeys) do
        writer.string(key)
        writer.string(revokes[key])
    end
    local claims = lib._CheckClaims(part.claims, lib.MaxDeltaClaims)
    local claimKeys = keysOf(claims)
    writer.uint(#claimKeys, 8)
    for _, id in ipairs(claimKeys) do
        writer.string(id)
        writer.uint(claims[id], 32)
    end
end

function lib._DecodeDeltaPart(reader)
    ---@type table<string, PW.UnlockGrantMeta>, table<string, string>, table<string, integer>
    local grants, revokes, claims = {}, {}, {}
    local count = reader.uint(8)
    if count > lib.MaxDeltaGrants then return {} end
    for _ = 1, count do
        local key = lib._EntitlementKey(reader.string())
        local source = reader.string()
        local grant = reader.string()
        local meta = grantOf({ source = source, at = reader.uint(32), grant = grant ~= "" and grant or nil })
        if key ~= nil and meta ~= nil and grants[key] == nil then grants[key] = meta end
    end
    count = reader.uint(8)
    if count > lib.MaxDeltaRevokes then return { granted = grants } end
    for _ = 1, count do
        local key = lib._EntitlementKey(reader.string())
        local source = lib._CheckSource(reader.string())
        if key ~= nil and source ~= nil and revokes[key] == nil then revokes[key] = source end
    end
    count = reader.uint(8)
    if count > lib.MaxDeltaClaims then return { granted = grants, revoked = revokes } end
    for _ = 1, count do
        local id = lib._CheckGrantId(reader.string())
        local at = lib._CheckTime(reader.uint(32))
        if id ~= nil and at ~= nil then claims[id] = math.max(claims[id] or 0, at) end
    end
    return { granted = grants, revoked = revokes, claims = claims }
end
