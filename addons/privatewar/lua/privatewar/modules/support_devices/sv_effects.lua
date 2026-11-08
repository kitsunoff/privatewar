-- One bounded player snapshot per maintenance step. No entity search and no support reward events.
local lib = PW.Devices --[[@as PW.DevicesLib]]

---@param record PW.SupportDevice
---@param target Player
---@return boolean
local function visible(record, target)
    local tr = util.TraceLine({ start = record.entity:WorldSpaceCenter(), endpos = target:WorldSpaceCenter(),
        filter = record.entity, mask = MASK_VISIBLE })
    return tr.Fraction >= 0.99 or tr.Entity == target
end

---@param record PW.SupportDevice
---@param recipient Player
---@return boolean
local function eligible(record, recipient)
    local teams = PW.Teams
    local teamMode = teams ~= nil and #teams.GetActive() > 0
    return assert(PW.SupportStreaks).SupportEligible({ owner = record.owner, recipient = recipient,
        teams = teamMode, allied = not PW.IsEnemy(record.owner, recipient), alive = recipient:Alive(),
        allowed = PW.Ask("PW_CanUseLoadoutKind", recipient, "streaks") ~= false,
        distance = record.position:Distance(recipient:GetPos()), radius = lib.Config[record.kind].radius,
        visible = visible(record, recipient) })
end

---@param record PW.SupportDevice
---@param players Player[]
---@param now number
local function cache(record, players, now)
    local ammo = PW.WeaponAmmo
    if ammo == nil then return end
    for _, recipient in ipairs(players) do
        if assert(PW.SupportStreaks).ReceiptReady(record.charges or 0, assert(record.receipts)[recipient], now)
            and record.position:DistToSqr(recipient:GetPos()) <= 160 * 160 and eligible(record, recipient) then
            local supplied = ammo.Resupply(recipient, recipient:GetWeapons(), { fraction = 1, maxMagazines = 3 })
            if next(supplied) ~= nil then
                record.charges = (record.charges or 0) - 1
                assert(record.receipts)[recipient] = now
            end
        end
    end
end

---@param record PW.SupportDevice
---@param players Player[]
local function sensor(record, players)
    ---@type Player[]
    local targets = {}
    for _, target in ipairs(players) do
        if target:Alive() and PW.IsEnemy(record.owner, target)
            and assert(PW.SupportStreaks).SensorEligible(record.position, target:GetPos(), true)
            and visible(record, target) then targets[#targets + 1] = target end
    end
    local streaks = PW.Streaks
    if streaks ~= nil and streaks.Viewer ~= nil and PW.Reveal ~= nil then
        PW.Reveal(streaks.Viewer(record.owner), targets, 2.1, record.owner)
    end
end

---@param record PW.SupportDevice
---@param now number
---@return boolean
local function live(record, now)
    local owner = record.owner
    return IsValid(record.entity) and record.instance:IsValid() and assert(PW.SupportStreaks).EndReason({
        now = now, ends = record.ends, ownerValid = IsValid(owner), team = record.team,
        currentTeam = IsValid(owner) and owner:Team() or -1, enabled = lib.Enabled(record.kind),
        allowed = IsValid(owner) and PW.Ask("PW_CanUseLoadoutKind", owner, "streaks") ~= false }) == nil
end

---@param record PW.SupportDevice
---@param players Player[]
---@param rates table<Player, number[]>
local function medical(record, players, rates)
    for _, recipient in ipairs(players) do
        if record.position:DistToSqr(recipient:GetPos()) <= 180 * 180 and eligible(record, recipient) then
            rates[recipient] = rates[recipient] or {}
            rates[recipient][#rates[recipient] + 1] = 5
        end
    end
end

---@param now number
---@param dt number
function MODULE:Maintain(now, dt)
    for i = #lib._Records, 1, -1 do
        local record = lib._Records[i]
        if not live(record, now) then lib.Remove(record) end
    end
    if #lib._Records == 0 then
        for recipient in pairs(lib._Healing) do lib._Healing[recipient] = nil end
        return
    end
    local players = player.GetAll()
    ---@type table<Player, number[]>
    local rates = {}
    for _, record in ipairs(lib._Records) do
        if record.kind == "medical_station" then
            medical(record, players, rates)
        elseif now >= (record.pulse or 0) then
            record.pulse = now + (record.kind == "ground_sensor" and 2 or 1)
            if record.kind == "ammo_cache" then cache(record, players, now) else sensor(record, players) end
        end
    end
    for recipient, offered in pairs(rates) do
        local amount = assert(PW.SupportStreaks).HealAmount(recipient:Health(), recipient:GetMaxHealth(),
            lib._Damaged[recipient] or now - 5, now, dt, offered)
        if amount > 0 then
            local accumulated = amount + (lib._Healing[recipient] or 0)
            local whole = math.floor(accumulated + 1e-7)
            lib._Healing[recipient] = accumulated - whole
            if whole > 0 then recipient:SetHealth(math.min(recipient:GetMaxHealth(), recipient:Health() + whole)) end
        else lib._Healing[recipient] = nil end
    end
    for recipient in pairs(lib._Healing) do if rates[recipient] == nil then lib._Healing[recipient] = nil end end
end
