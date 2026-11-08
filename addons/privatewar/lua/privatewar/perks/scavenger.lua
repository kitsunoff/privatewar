PERK.Name = "Scavenger"
PERK.Group = 2
PERK.Cost = 1
PERK.Unlock = 1
PERK.Description = "Direct enemy weapon kills restore half a magazine of that gun's reserve, up to three magazines."

function PERK:OnKill(owner, victim, dmg)
    if owner == victim or not IsValid(victim) or not victim:IsPlayer() or PW.WeaponAmmo == nil then return end
    if PW.IsEnemy == nil or not PW.IsEnemy(owner, victim) then return end
    local weapon, direct = PW.WeaponAmmo.DamageWeapon(owner, dmg)
    if weapon == nil or not direct then return end
    PW.WeaponAmmo.Resupply(owner, { weapon }, { fraction = 0.5, maxMagazines = 3 })
end
