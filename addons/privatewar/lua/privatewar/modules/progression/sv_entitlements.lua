-- Server-side entitlement transactions (06-progression.md d.5 and d.8).
local lib = PW.Unlocks --[[@as PW.UnlocksLib]]
local progression = PW.Progression --[[@as PW.ProgressionLib]]
local module = MODULE --[[@as PW.Module]]

---@param ply Player
---@return string?
local function playerRefusal(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return "badplayer" end
    if ply:IsBot() then return "bot" end
    return nil
end

function lib._IsReady(store, ply)
    return playerRefusal(ply) == nil and store.unlocksUploaded[ply] == true
end

---@param raw table<string, boolean>
---@param check fun(raw: any): string?
---@param limit integer
---@return string[]
local function uploadedKeys(raw, check, limit)
    ---@type string[]
    local keys = {}
    for value, accepted in pairs(raw) do
        local key = accepted == true and check(value) or nil
        if key ~= nil then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for index = #keys, limit + 1, -1 do keys[index] = nil end
    return keys
end

function lib._OnUpload(store, ply, raw)
    if playerRefusal(ply) ~= nil or raw == nil or store.unlocksUploaded[ply] then return false end
    ---@type table<string, PW.UnlockGrantMeta>, table<string, integer>
    local grants, claims = {}, {}
    for _, key in ipairs(uploadedKeys(raw.grants, lib._EntitlementKey, lib.MaxGrants)) do
        grants[key] = { source = "grant", at = 0 }
    end
    for _, key in ipairs(uploadedKeys(raw.claims, lib._CheckGrantId, lib.MaxClaims)) do claims[key] = 0 end
    local state = progression._StateOf(store, ply)
    state.grants, state.claims = grants, claims
    store.unlocksUploaded[ply] = true
    store.refresh(ply)
    return true
end

---@param items (PW.UnlockItem|string)[]
---@param forGrant boolean
---@return string[]?, string?
local function itemKeys(items, forGrant)
    if not istable(items) then return nil, "badkey" end
    if forGrant and #items > lib.MaxGrantPerCall then return nil, "toomany" end
    ---@type string[]
    local keys = {}
    ---@type table<string, boolean>
    local seen = {}
    local count = 0
    for index, item in pairs(items) do
        if not isnumber(index) or index < 1 or index > #items or math.floor(index) ~= index then
            return nil, "badkey"
        end
        count = count + 1
        local key = lib._EntitlementKey(lib.KeyOf(item))
        if key == nil then return nil, "badkey" end
        if not seen[key] then
            if forGrant and not lib._Known(key) then return nil, "unknown" end
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    if count ~= #items then return nil, "badkey" end
    table.sort(keys)
    return keys
end

---@param store PW.ProgressionStore
---@param ply Player
---@return string?
local function refusal(store, ply)
    local why = playerRefusal(ply)
    if why ~= nil then return why end
    if not store.unlocksUploaded[ply] then return "notready" end
    return nil
end

function lib._Grant(store, ply, items, opts)
    local why = refusal(store, ply)
    if why ~= nil then return 0, why end
    local source = istable(opts) and lib._CheckSource(opts.source) or nil
    if source == nil then return 0, "badsource" end
    local grant = lib._CheckGrantId(opts.grant)
    if opts.grant ~= nil and grant == nil then return 0, "badgrant" end
    local state = progression._StateOf(store, ply)
    if grant ~= nil and lib._HasClaim(state.claims, grant) then return 0, "claimed" end
    local keys, err = itemKeys(items, true)
    if keys == nil then return 0, err end
    local grants = state.grants or {}
    ---@type string[]
    local added = {}
    for _, key in ipairs(keys) do
        if grants[key] == nil then added[#added + 1] = key end
    end
    if table.Count(grants) + #added > lib.MaxGrants then return 0, "full" end
    if #added > 0 or grant ~= nil then
        local at = os.time()
        local pending = progression._PendingOf(store, ply)
        pending.granted, pending.claims = pending.granted or {}, pending.claims or {}
        for _, key in ipairs(added) do
            local meta = { source = source, at = at, grant = grant }
            grants[key], pending.granted[key] = meta, meta
        end
        state.grants = grants
        if grant ~= nil then
            local claims = state.claims or {}
            claims[grant], pending.claims[grant] = at, at
            state.claims = lib._CheckClaims(claims)
        end
    end
    progression._Flush(store, ply)
    if #added > 0 then
        store.refresh(ply)
        store.notify("PW_UnlockGranted", ply, added, source, grant)
    end
    return #added
end

function lib._Revoke(store, ply, items, opts)
    local why = refusal(store, ply)
    if why ~= nil then return 0, why end
    local source = istable(opts) and lib._CheckSource(opts.source) or nil
    if source == nil then return 0, "badsource" end
    local keys, err = itemKeys(items, false)
    if keys == nil then return 0, err end
    local grants = progression._StateOf(store, ply).grants or {}
    ---@type string[]
    local removed = {}
    for _, key in ipairs(keys) do
        if grants[key] ~= nil then removed[#removed + 1] = key end
    end
    if #removed == 0 then return 0 end
    for first = 1, #removed, lib.MaxDeltaRevokes do
        local pending = progression._PendingOf(store, ply)
        pending.revoked = pending.revoked or {}
        for index = first, math.min(#removed, first + lib.MaxDeltaRevokes - 1) do
            local key = removed[index]
            grants[key], pending.revoked[key] = nil, source
        end
        progression._Flush(store, ply)
    end
    store.refresh(ply)
    store.notify("PW_UnlockRevoked", ply, removed, source)
    return #removed
end

function lib.IsReady(ply)
    local store = PW._Progression
    return store ~= nil and lib._IsReady(store, ply)
end

function lib.HasClaim(ply, grant)
    local store = PW._Progression
    if store == nil or not lib._IsReady(store, ply) then return false end
    return lib._HasClaim(progression._StateOf(store, ply).claims, grant)
end

function lib.Grant(ply, items, opts)
    local store = PW._Progression
    if store == nil then return 0, "notready" end
    return lib._Grant(store, ply, items, opts)
end

function lib.Revoke(ply, items, opts)
    local store = PW._Progression
    if store == nil then return 0, "notready" end
    return lib._Revoke(store, ply, items, opts)
end

---@param len integer payload length in bits
---@return PW.UnlockUpload?
local function decodeUpload(len)
    local reader = progression._NetReader()
    local left, invalid = len, false
    local data = lib._DecodeUpload({
        uint = function(width)
            if left < width then
                invalid = true
                return 0
            end
            left = left - width
            return reader.uint(width)
        end,
        string = function()
            if left < 8 then
                invalid = true
                return ""
            end
            local value = reader.string()
            left = left - (#value + 1) * 8
            if left < 0 then invalid = true end
            return value
        end,
        bool = function() return false end
    })
    if invalid or left ~= 0 then return nil end
    return data
end

PW.Net.Receive("pw_unlocks_upload", { who = "any", rate = 0.5, maxLen = lib.UploadMaxBytes, owner = module },
    function(ply, len)
        local store = PW._Progression
        if store == nil or len < 40 or playerRefusal(ply) ~= nil or lib._IsReady(store, ply) then return end
        lib._OnUpload(store, ply, decodeUpload(len))
    end)
