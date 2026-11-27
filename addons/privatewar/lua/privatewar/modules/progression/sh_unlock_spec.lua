-- Progression unlock authority (06-progression.md d.8): data normalization, references and requirement copy.
local lib = PW.Unlocks --[[@as PW.UnlocksLib]]
local progression = PW.Progression --[[@as PW.ProgressionLib]]

lib.MaxHintLength = 128
lib.MaxSourceLength = 16

function lib._CheckHint(value)
    if isstring(value) and value ~= "" and #value <= lib.MaxHintLength then return value end
    return nil
end

function lib._CheckSource(value)
    if isstring(value) and #value <= lib.MaxSourceLength and value:match("^%l[%l_]*$") then return value end
    return nil
end

---@param value any
---@return integer|false
local function normalLevel(value)
    if value == false then return false end
    if isnumber(value) and value == value and value > 0 and value < math.huge then return math.floor(value) end
    return 0
end

function lib._Spec(unlock)
    if istable(unlock) then
        return {
            level = normalLevel(unlock.level), declared = true,
            hint = lib._CheckHint(unlock.hint), reward = lib._CheckSource(unlock.reward)
        }
    end
    return { level = normalLevel(unlock), declared = unlock ~= nil }
end

---@param kind string
---@return string
local function canonicalKind(kind)
    return kind == "camo" and "camos" or kind
end

function lib.ParseKey(key)
    if not isstring(key) or #key > progression.MaxKeyLength then return nil end
    local kind, id = string.match(key, "^(%l[%l_]*):([%w_%-%.:]+)$")
    if kind == nil or id == nil then return nil end
    kind = canonicalKind(kind)
    if #kind + #id + 1 > progression.MaxKeyLength then return nil end
    if kind == "attachments" or kind == "camos" then
        local weapon, option = string.match(id, "^([^:]+):(.+)$")
        if weapon == nil or option == nil then return nil end
        return kind, id, weapon, option
    end
    return kind, id
end

function lib.KeyOf(item)
    ---@type string
    local key
    if type(item) == "string" then
        key = item
    elseif istable(item) then
        if not isstring(item.kind) or not isstring(item.id) or item.id == "" then return nil end
        local kind = canonicalKind(item.kind)
        local id = item.id
        if kind == "attachments" or kind == "camos" then
            local weapon = item.weapon
            if type(weapon) ~= "string" or string.match(weapon, "^[%w_%-%.]+$") == nil then return nil end
            id = weapon .. ":" .. id
        end
        key = progression._OwnedKey(kind, id)
    else
        return nil
    end
    local kind, id = lib.ParseKey(key)
    if kind == nil or id == nil then return nil end
    return progression._OwnedKey(kind, id)
end

function lib._Price(entity)
    local price = entity.Price
    if not isnumber(price) or price ~= price or price < 1 or price > 2 ^ 31 then return nil end
    return math.floor(price)
end

function lib.LockText(req)
    if req.unlocked or req.reason == "hidden" then return nil, nil end
    if req.reason == "level" and req.level ~= nil then return "LV " .. req.level, "Unlocks at level " .. req.level end
    if req.reason == "weapon_level" and req.weaponLevel ~= nil then
        return "LV " .. req.weaponLevel, "Unlocks at weapon level " .. req.weaponLevel
    end
    if (req.reason == "price" or req.reason == "grant_only") and req.price ~= nil then
        return req.price .. " CR", "Buy it in the STORE for " .. req.price .. " CR"
    end
    if req.reason == "grant_only" then return "REWARD", req.hint or "Earned as a reward" end
    if req.reason == "override" then return "LOCKED", "Locked on this server" end
    return "LOCKED", "Not available"
end

function lib._StaticRequirement(entity, isOption)
    ---@type PW.UnlockRequirement
    local out = { unlocked = false, reason = "unknown" }
    if entity == nil then
        out.lockText, out.text = lib.LockText(out)
        return out
    end
    if isOption and entity.Hidden == true then
        out.reason = "hidden"
        return out
    end
    local spec = lib._Spec(entity.Unlock)
    if not isOption then out.price = lib._Price(entity) end
    if spec.level == false then
        out.reason = "grant_only"
    elseif not spec.declared and out.price ~= nil then
        out.reason = "price"
    elseif spec.level == 0 then
        return { unlocked = true, reason = "default" }
    elseif isOption then
        out.reason, out.weaponLevel = "weapon_level", spec.level
    else
        out.reason, out.level = "level", spec.level
    end
    out.hint = spec.hint
    out.lockText, out.text = lib.LockText(out)
    return out
end
