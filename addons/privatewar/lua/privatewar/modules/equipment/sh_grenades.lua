-- Grenades as inventory items (T-11.4; 05-loadout.md d.11 revision 2026-11-07). Shared and pure: the cook timer and
-- its cap, the cooked fuse, the switch back after the last grenade, the key -> slot -> SWEP mapping and the count a
-- perk answers. Also the ammo types of the grenade SWEPs (one per SWEP, so a frag and a flash never share a count).
-- The SWEPs are gamemodes/privatewar/entities/weapons/weapon_pw_*.lua; the server glue is init.lua.
--
-- Decisions of the lane agent (pending confirmation items are in the local checklist section 7, item 64):
--   1. Cook cap 3 s (CookCap). Reaching it sets the grenade off in hand: it is dropped with the minimum fuse.
--   2. Only an item with Cook = true cooks (the frag). The flash is held without a timer and its fuse starts on
--      release, so it never goes off in hand.
--   3. After the last grenade the player returns to the previous weapon after SwitchDelay (the throw animation).
--      The bot path (PW.Equipment.Use) always returns, BotHold after the throw.
-- Confirmed by the user on 2026-11-07 (the local checklist, items 64 and 66), with one change (66.3): dying while
-- cooking drops the live grenade at the body (CoD-style). It goes off after the remaining fuse (the fuse less the
-- time cooked, at least DeathMinFuse); the thrower stays the attacker. Switching weapons while cooking still cancels.

local lib = PW.Equipment --[[@as PW.EquipmentLib]]

lib.CookCap = 3
lib.SwitchDelay = 0.5
lib.BotHold = 0.3
lib.DeathMinFuse = 0.1
lib.AmmoTypes = { "pw_frag", "pw_flash" }

-- Ammo types exist only when added before the game initialises; a pw_reload must not add them twice.
PW._GrenadeAmmo = PW._GrenadeAmmo or {}
for _, name in ipairs(lib.AmmoTypes) do
    if not PW._GrenadeAmmo[name] then
        PW._GrenadeAmmo[name] = true
        game.AddAmmoType({ name = name, dmgtype = DMG_BLAST, tracer = TRACER_NONE, plydmg = 0, npcdmg = 0,
            force = 0, maxcarry = 9 })
    end
end

function lib._CookState(start, now, held, cooks, cap)
    if start <= 0 then return "idle", 0 end
    local elapsed = math.max(0, now - start)
    if cooks and elapsed >= cap then return "overcook", cap end
    local cooked = cooks and elapsed or 0
    if held then return "hold", cooked end
    return "throw", cooked
end

function lib._CookedFuse(fuse, cooked)
    return fuse - math.max(0, cooked)
end

function lib._RemainingFuse(fuse, cooked, min)
    return math.max(min, lib._CookedFuse(fuse, cooked))
end

function lib._DeathDrop(start, now, cooks, cap)
    if not cooks or start <= 0 then return nil end
    local _, cooked = lib._CookState(start, now, true, true, cap)
    return cooked
end

function lib._ShouldSwitchBack(count)
    return count <= 0
end

function lib._ReturnWeapon(candidates, owned, grenades)
    ---@type table<string, true>
    local has = {}
    for _, class in ipairs(owned) do has[class] = true end
    for _, class in ipairs(candidates) do
        if has[class] and not grenades[class] then return class end
    end
    for _, class in ipairs(owned) do
        if not grenades[class] then return class end
    end
    return nil
end

function lib._SlotWeapon(slot, weapons, ammo)
    local class = weapons[slot]
    if class == nil or (ammo[class] or 0) < 1 then return nil end
    return class
end

function lib._KeyWeapon(button, codes, weapons, ammo)
    local slot = lib._KeySlot(button, codes)
    if slot == nil then return nil end
    return lib._SlotWeapon(slot, weapons, ammo)
end

function lib._CountFor(base, answer)
    if not isnumber(answer) then return base end
    return math.max(0, math.floor(answer --[[@as number]]))
end

function lib._WeaponOf(def)
    local class = def ~= nil and def.Weapon or nil
    if isstring(class) then return class end
    return nil
end

function lib._AmmoOf(class)
    local swep = weapons.GetStored(class) --[[@as table<string, any>?]]
    local primary = swep ~= nil and swep.Primary or nil
    local ammo = istable(primary) and primary.Ammo or nil
    if not isstring(ammo) or ammo == "none" then return nil end
    return ammo
end

---The definition of an item id (registered and valid), else nil.
---@param id string
---@return PW.EquipmentItem?
function lib._Lookup(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.equipment or nil
    if registry == nil then return nil end
    local def = registry.Get(id)
    if def == nil or not def:IsValid() then return nil end
    return def --[[@as PW.EquipmentItem]]
end

---The grenade SWEP class of an item id, nil when the item has none.
---@param id string?
---@return string?
function lib._ItemWeapon(id)
    if id == nil then return nil end
    return lib._WeaponOf(lib._Lookup(id))
end

function lib._ThrowOptions(fuse, cooks, use)
    local cooked = cooks and use ~= nil and tonumber(use.cooked) or 0
    ---@type PW.ThrowOptions
    local opts = { cook = lib._CookedFuse(fuse, cooked) }
    if use ~= nil and use.death then
        opts.cook, opts.drop = lib._RemainingFuse(fuse, cooked, lib.DeathMinFuse), true
    end
    if use ~= nil and (use.drop or use.death) then opts.speed, opts.lift = 0, 0 end
    return opts
end
