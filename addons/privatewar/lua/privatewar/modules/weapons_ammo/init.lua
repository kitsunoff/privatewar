-- Weapon ammo module, server glue (T-3.4). Thin wrapper around the pure arithmetic of shared.lua: the engine calls
-- (Give, SetClip1, SetAmmo) and the adapter calls are here.

local lib = PW.WeaponAmmo --[[@as PW.WeaponAmmoLib]]

include("privatewar/modules/weapons_ammo/sv_resupply.lua")

function lib.Give(ply, class, opts)
    if not IsValid(ply) or not isstring(class) or ply:HasWeapon(class) then return nil end
    -- bNoAmmo: the engine gives no default ammo; the adapter then stops what the base gives on its own.
    local wep = ply:Give(class, true)
    if not IsValid(wep) then return nil end
    PW.Adapters.CallFor(wep, "SuppressDefaultAmmo", wep)
    ---@type number?
    local capacity = select(2, PW.Adapters.CallFor(wep, "GetClip", wep))
    local clipSize = isnumber(capacity) and capacity or 0
    if clipSize > 0 then wep:SetClip1(clipSize) end
    local ammoType = PW.Adapters.CallFor(wep, "GetAmmoType", wep)
    if isnumber(ammoType) and ammoType >= 0 then
        local magazines = (opts ~= nil and opts.magazines) or lib._Magazines()
        -- Absolute: whatever the base left behind is replaced, not added to.
        ply:SetAmmo(lib._ReserveFor(clipSize, magazines), ammoType)
    end
    return wep
end
