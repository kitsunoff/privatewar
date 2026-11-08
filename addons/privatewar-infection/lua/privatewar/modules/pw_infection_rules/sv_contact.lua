-- Native contact conversion at match_rules' existing public veto. Never changes a weapon or respawns a player.
local lib = PW.Infection --[[@as PW.InfectionLib]]
local rules = PW.InfectionRules --[[@as PW.InfectionRulesLib]]

---@param ply Player
---@return integer?
local function livingLife(ply)
    local s = assert(lib.State)
    local id = s.identities[ply]
    local row = id ~= nil and assert(s.current).players[id] or nil
    local life = s.lives[ply]
    if row == nil or s.actors[id] ~= ply or not row.present or not row.alive or not ply:Alive()
        or life ~= row.life or row.deadLife == life then return nil end
    return life
end

---@param attacker Player
---@param damage CTakeDamageInfo
---@return boolean
local function nativeHit(attacker, damage)
    local amount = damage:GetDamage()
    if not isnumber(amount) or amount <= 0 or amount ~= amount or amount == math.huge then return false end
    local weapon = damage:GetInflictor()
    -- Stock fists use DMG_GENERIC (zero). Neither an active-weapon guess nor a damage-type mask proves a punch.
    if damage:GetDamageType() ~= DMG_GENERIC or not IsValid(weapon) or not weapon:IsWeapon()
        or weapon:GetClass() ~= "weapon_fists" or weapon:GetOwner() ~= attacker
        or attacker:GetActiveWeapon() ~= weapon then return false end
    return true
end

---@param victim Player
local function applyRole(victim)
    local ok, note = assert(PW.Teams).Transition(victim, 2, "role_change")
    assert(ok, "Infection contact conversion failed: " .. tostring(note))
    if PW.Perks ~= nil then PW.Perks.Revoke(victim) end
    if PW.Equipment ~= nil then PW.Equipment.Revoke(victim) end
    if PW.Streaks ~= nil then PW.Streaks.Revoke(victim) end
    assert(PW.Loadout).Give(victim, { melee = "weapon_fists" })
    assert(assert(PW.PlayerOverrides).Refresh(victim))
    -- Intentional live role initialization, not a spawn notification or an ordinary refresh heal.
    local profile = PW.Ask("PW_PlayerOverrides", victim) --[[@as PW.PlayerOverrideProfile]]
    victim:SetHealth(assert(profile.spawnHealth))
    assert(PW.Operators).Refresh(victim)
    lib.ValidateModel(victim)
end

function lib.Damage(victim, attacker, damage)
    if not lib.Active() then return end
    local s = assert(lib.State)
    if not s.playing or lib.Role(victim) == nil then return false end
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
        and (lib.Role(attacker --[[@as Player]]) == nil
            or not assert(PW.IsEnemy)(victim, attacker --[[@as Player]])) then return false end
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    local source = attacker --[[@as Player]]
    if lib.Role(source) ~= "infected" or lib.Role(victim) ~= "survivor" or not nativeHit(source, damage) then return end
    local victimLife, sourceLife = livingLife(victim), livingLife(source)
    if victimLife == nil or sourceLife == nil then return end
    local converted = rules.Touch(assert(s.current), assert(s.identities[victim]), victimLife,
        assert(s.identities[source]), sourceLife, CurTime())
    if converted then
        applyRole(victim)
        local id = assert(s.identities[source])
        s.infections[id] = (s.infections[id] or 0) + 1
    end
    if assert(s.current).winner ~= nil then s.playing = false end
    lib.Publish()
    if converted or not s.playing then return false end
end
