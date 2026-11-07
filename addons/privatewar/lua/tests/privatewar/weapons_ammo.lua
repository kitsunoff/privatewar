-- T-3.4 ammo owned by the core (TASKS.md, "Mandatory test cases" T-3.4; 04-weapons.md d.1; docs/api/adapter.md
-- "Ammo"). Pure cases check the magazine arithmetic and the setting. In-game cases give weapon_smg1 and weapon_pistol
-- to the host (no bots), then strip them and restore the host's weapons and ammo.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.WeaponAmmoLib
local function ammo()
    return must(PW.WeaponAmmo)
end

---@return Player
local function host()
    return must(player.GetHumans()[1])
end

---Runs body with the host's state saved; afterwards the given classes are stripped (unless the host held them) and
---the ammo of their types is restored.
---@param classes string[]
---@param body fun(ply: Player)
local function withHost(classes, body)
    local ply = host()
    ---@type table<string, boolean>
    local held = {}
    ---@type table<string, integer>
    local savedAmmo = {}
    for _, class in ipairs(classes) do
        held[class] = ply:HasWeapon(class)
        local stored = ply:GetWeapon(class)
        if IsValid(stored) then savedAmmo[class] = ply:GetAmmoCount(stored:GetPrimaryAmmoType()) end
    end
    local ok, err = pcall(body, ply)
    for _, class in ipairs(classes) do
        local wep = ply:GetWeapon(class)
        if IsValid(wep) then
            local ammoType = wep:GetPrimaryAmmoType()
            if not held[class] then
                ply:StripWeapon(class)
                ply:SetAmmo(0, ammoType)
            else
                ply:SetAmmo(savedAmmo[class] or 0, ammoType)
            end
        end
    end
    if not ok then error(err, 0) end
end

return {
    groupName = "PW weapon ammo",
    cases = {
        {
            name = "Magazines: reserve is magazines times the clip, rounded down, never negative",
            func = function()
                expect(ammo()._ReserveFor(30, 3)).to.equal(90)
                expect(ammo()._ReserveFor(30.9, 2)).to.equal(60)
                expect(ammo()._ReserveFor(30, 0)).to.equal(0)
                expect(ammo()._ReserveFor(30, -2)).to.equal(0)
            end
        },
        {
            name = "Magazines: a weapon without a clip gets one round per magazine",
            func = function()
                expect(ammo()._ReserveFor(-1, 3)).to.equal(3)
                expect(ammo()._ReserveFor(0, 4)).to.equal(4)
            end
        },
        {
            name = "Magazines: the match setting weapons_ammo.magazines defaults to 3",
            func = function()
                expect(PW.Setting("weapons_ammo.magazines")).to.equal(3)
                expect(ammo()._Magazines()).to.equal(3)
            end
        },
        {
            name = "Give: default ammo is suppressed through the adapter and nothing is left over",
            func = function()
                local lib = PW.Adapters
                local original = lib.CallFor
                ---@type string[]
                local methods = {}
                rawset(lib, "CallFor", function(weaponOrClass, method, ...)
                    methods[#methods + 1] = method
                    return original(weaponOrClass, method, ...)
                end)
                local ok, err = pcall(function()
                    withHost({ "weapon_smg1" }, function(ply)
                        ply:StripWeapon("weapon_smg1")
                        local wep = must(ammo().Give(ply, "weapon_smg1", { magazines = 0 }))
                        expect(table.HasValue(methods, "SuppressDefaultAmmo")).to.beTrue()
                        expect(ply:GetAmmoCount(wep:GetPrimaryAmmoType())).to.equal(0)
                    end)
                end)
                rawset(lib, "CallFor", original)
                if not ok then error(err, 0) end
            end
        },
        {
            name = "Give: the core gives the configured magazines (reserve equals magazines times the clip)",
            func = function()
                withHost({ "weapon_smg1", "weapon_pistol" }, function(ply)
                    ply:StripWeapon("weapon_smg1")
                    ply:StripWeapon("weapon_pistol")
                    local smg = must(ammo().Give(ply, "weapon_smg1", { magazines = 3 }))
                    expect(ply:GetAmmoCount(smg:GetPrimaryAmmoType())).to.equal(3 * smg:GetMaxClip1())
                    expect(smg:Clip1()).to.equal(smg:GetMaxClip1())
                    local pistol = must(ammo().Give(ply, "weapon_pistol", { magazines = 2 }))
                    expect(ply:GetAmmoCount(pistol:GetPrimaryAmmoType())).to.equal(2 * pistol:GetMaxClip1())
                end)
            end
        },
        {
            name = "Give: without options the magazines come from the setting",
            func = function()
                withHost({ "weapon_smg1" }, function(ply)
                    ply:StripWeapon("weapon_smg1")
                    local wep = must(ammo().Give(ply, "weapon_smg1"))
                    expect(ply:GetAmmoCount(wep:GetPrimaryAmmoType())).to.equal(ammo()._Magazines() * wep:GetMaxClip1())
                end)
            end
        },
        {
            name = "Give: an unknown class gives nothing",
            func = function()
                expect(ammo().Give(host(), "pwt_no_such_weapon", { magazines = 3 })).to.beNil()
            end
        }
    }
}
