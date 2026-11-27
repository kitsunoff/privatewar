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

---@class PW.ClaimBalances
---@field xp number
---@field params? PW.ProgressionParams
---@field currency number

---@param amount any
---@return boolean
local function validAmount(amount)
    return amount == nil or (type(amount) == "number" and amount >= 0 and amount < math.huge)
end

---@param store PW.ProgressionStore
---@param xp number?
---@param currency number?
---@return PW.ClaimBalances?
local function prepareBalances(store, xp, currency)
    ---@type PW.ClaimBalances
    local balances = { xp = 0, currency = 0 }
    if xp ~= nil and xp > 0 then
        balances.xp, balances.params = progression._PrepareXP(store, xp)
        if not validAmount(balances.xp) then return nil end
    end
    if currency ~= nil and currency > 0 and store.ownedActive() then balances.currency = currency end
    return balances
end

---@param current table<string, integer>?
---@param grant string
---@param at integer
---@return table<string, integer>
local function retainedClaims(current, grant, at)
    local claims = table.Copy(current or {}) --[[@as table<string, integer>]]
    claims[grant] = at
    return lib._CheckClaims(claims)
end

---@param store PW.ProgressionStore
---@param ply Player
---@param scaled number
---@return string?
local function rewardXPRefusal(store, ply, scaled)
    -- Only a positive XP reward reserves room. Legacy and currency-only grants never gate unrelated XP.
    if scaled <= 0 then return nil end
    local limit = progression.MaxDeltaXP
    if scaled > limit then return "badreward" end
    local pending = store.pending[ply]
    if pending ~= nil and pending.xp > limit - scaled then return "balancefull" end
    return nil
end

---@param store PW.ProgressionStore
---@param ply Player
---@param balances PW.ClaimBalances?
local function flushGrant(store, ply, balances)
    local params = balances ~= nil and balances.params or nil
    if balances == nil then
        progression._Flush(store, ply)
        return
    end
    progression._AddCurrency(store, ply, balances.currency)
    ---@type integer?
    local before
    if params ~= nil and balances.xp > 0 then before = progression._StageClaimXP(store, ply, balances.xp, params) end
    -- Nothing can observe or flush partially staged balances; even an XP listener may flush again.
    progression._Flush(store, ply)
    if params ~= nil and before ~= nil then progression._NotifyClaimXP(store, ply, balances.xp, before, params) end
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
    local xp, currency = opts.xp, opts.currency
    local hasReward = xp ~= nil or currency ~= nil
    if hasReward and (grant == nil or not validAmount(xp) or not validAmount(currency)) then return 0, "badreward" end
    local keys, err = itemKeys(items, true)
    if keys == nil then return 0, err end
    local balances = hasReward and prepareBalances(store, xp, currency) or nil
    if hasReward then
        if balances == nil then return 0, "badreward" end
        -- Key resolution, settings and the economy edge can reenter before we stage anything.
        why = refusal(store, ply)
        if why ~= nil then return 0, why end
        state = progression._StateOf(store, ply)
        if grant ~= nil and lib._HasClaim(state.claims, grant) then return 0, "claimed" end
    end
    local grants = state.grants or {}
    ---@type string[]
    local added = {}
    for _, key in ipairs(keys) do
        if grants[key] == nil then added[#added + 1] = key end
    end
    if table.Count(grants) + #added > lib.MaxGrants then return 0, "full" end
    why = balances ~= nil and rewardXPRefusal(store, ply, balances.xp) or nil
    if why ~= nil then return 0, why end
    if #added > 0 or grant ~= nil then
        local at = os.time()
        local claims = hasReward and grant ~= nil and retainedClaims(state.claims, grant, at) or nil
        if hasReward and grant ~= nil and not lib._HasClaim(claims, grant) then return 0, "claimfull" end
        local pending = progression._PendingOf(store, ply)
        pending.granted, pending.claims = pending.granted or {}, pending.claims or {}
        for _, key in ipairs(added) do
            local meta = { source = source, at = at, grant = grant }
            grants[key], pending.granted[key] = meta, meta
        end
        state.grants = grants
        if grant ~= nil then
            pending.claims[grant] = at
            if claims == nil then
                local previous = state.claims or {}
                previous[grant] = at
                claims = lib._CheckClaims(previous)
            end
            state.claims = claims
        end
    end
    flushGrant(store, ply, balances)
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

local adminPrivilege = "pw_unlocks_admin"
PW.Privilege(adminPrivilege, "superadmin")

---@type table<PW.UnlockAdminAction, string>
local adminSyntax = {
    grant = "pw_unlock_grant <player> <key>",
    revoke = "pw_unlock_revoke <player> <key>",
    list = "pw_unlock_list <player>"
}

---@param id string
---@return Player?
local function adminTarget(id)
    local humans = player.GetHumans()
    for _, ply in ipairs(humans) do
        if tostring(ply:UserID()) == id then return ply end
    end
    ---@type Player?
    local target
    for _, ply in ipairs(humans) do
        if ply:Nick() == id then
            if target ~= nil then return nil end
            target = ply
        end
    end
    return target
end

---@param line string
local function printAdmin(line)
    print("[PW] " .. line)
end

---@param target Player
---@param out PW.LogFn
local function listAdmin(target, out)
    local entries = lib.ListEntitled(target)
    local keys = table.GetKeys(entries) --[[@as string[] ]]
    table.sort(keys)
    out(string.format("Entitlements for %q (%d):", target:Nick(), #keys))
    for _, key in ipairs(keys) do out(string.format("%s (%s)", key, entries[key].source)) end
end

function lib._AdminCommand(caller, action, args, out)
    out = out or printAdmin
    if caller ~= nil and IsValid(caller) and not PW.Can(caller, adminPrivilege) then
        out("Unlock command denied: needs " .. adminPrivilege)
        return false
    end
    local syntax = adminSyntax[action]
    if syntax == nil then return false end
    if #args ~= (action == "list" and 1 or 2) then
        out("Usage: " .. syntax)
        return false
    end
    local target = adminTarget(args[1])
    if target == nil then
        out(string.format("No unique human player matches %q", args[1]))
        return false
    end
    if action == "list" then
        listAdmin(target, out)
        return true
    end
    local apply = action == "grant" and lib.Grant or lib.Revoke
    local count, reason = apply(target, { args[2] }, { source = "admin" })
    if reason ~= nil then
        out(string.format("Unlock %s refused: %s", action, reason))
        return false
    end
    out(string.format("Unlock %s: %d affected for %q", action, count, target:Nick()))
    return true
end

---@param action PW.UnlockAdminAction
local function registerAdmin(action)
    local help = "Private War: " .. adminSyntax[action]
        .. " (player user id or exact name; needs " .. adminPrivilege .. ")"
    concommand.Add("pw_unlock_" .. action, function(caller, _, args)
        if not IsValid(module) then return end
        assert(lib._AdminCommand)(IsValid(caller) and caller or nil, action, args)
    end, nil, help)
end

registerAdmin("grant")
registerAdmin("revoke")
registerAdmin("list")
