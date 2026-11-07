-- Pure ordinary-reserve arithmetic and conservative damage provenance.
local lib = PW.WeaponAmmo --[[@as PW.WeaponAmmoLib]]

---@param value any
---@return boolean
local function positive(value)
    return isnumber(value) and value > 0 and value < math.huge
end

function lib._ResupplyAmount(capacity, reserve, fraction, maxMagazines)
    if not positive(capacity) or not positive(fraction) or not positive(maxMagazines) then return 0 end
    if not isnumber(reserve) or reserve < 0 or reserve >= math.huge then return 0 end
    local size = math.floor(capacity)
    if size < 1 then return 0 end
    local ceiling = math.floor(size * maxMagazines)
    local requested = math.max(1, math.floor(size * fraction))
    if ceiling >= math.huge or requested >= math.huge then return 0 end
    return math.max(0, math.min(requested, ceiling - math.floor(reserve)))
end

function lib._ResupplyPlan(entries, fraction, maxMagazines)
    ---@type table<integer, PW.ResupplyEntry>
    local chosen = {}
    for _, entry in ipairs(entries) do
        local ammo = entry.ammo
        if positive(entry.capacity) and isnumber(ammo) and ammo >= 0 and ammo < math.huge
            and ammo == math.floor(ammo) then
            local old = chosen[ammo]
            if old == nil or entry.capacity > old.capacity then chosen[ammo] = entry end
        end
    end
    ---@type table<integer, integer>
    local plan = {}
    for ammo, entry in pairs(chosen) do
        local amount = lib._ResupplyAmount(entry.capacity, entry.reserve, fraction, maxMagazines)
        if amount > 0 then plan[ammo] = amount end
    end
    return plan
end

function lib._DamageSource(facts)
    if facts.weapon and facts.owned then return "weapon", facts.direct == true and not facts.grenade end
    if facts.playerInflictor and facts.active and facts.direct then return "active", true end
    return nil, false
end
