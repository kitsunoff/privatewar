PERK.Name = "Retaliation"
PERK.Group = 3
PERK.Cost = 1
PERK.Unlock = 1
PERK.Description = "Once per 5 seconds, mark a living direct weapon attacker in current LOS for 1.5 seconds."

function PERK:OnDamaged(owner, attacker, dmg)
    local now = CurTime()
    if now < (self.NextRevealAt or 0) or not owner:Alive() then return end
    if attacker == owner or not IsValid(attacker) or not attacker:IsPlayer() or not attacker:Alive() then return end
    local enemy = attacker --[[@as Player]]
    if PW.IsEnemy == nil or not PW.IsEnemy(owner, enemy) or PW.WeaponAmmo == nil then return end
    local _, direct = PW.WeaponAmmo.DamageWeapon(enemy, dmg)
    if not direct or PW.Streaks == nil or PW.Reveal == nil then return end
    local tr = util.TraceLine({ start = owner:EyePos(), endpos = attacker:WorldSpaceCenter(),
        filter = { owner, attacker }, mask = MASK_OPAQUE_AND_NPCS })
    if tr.Hit then return end
    self.NextRevealAt = now + 5
    PW.Reveal(PW.Streaks.Viewer(owner), { enemy }, 1.5, owner)
end
