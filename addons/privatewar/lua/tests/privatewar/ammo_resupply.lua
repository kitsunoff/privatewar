-- Shared ordinary-reserve service, frozen for scavenging and future support streaks.
-- Tests precede runtime. Missing APIs fail inside cases, never in runner setup.

---@param name string
---@return fun(...: any): any
local function api(name)
    local fn = rawget(PW.WeaponAmmo, name)
    assert(isfunction(fn), "ordinary reserve API missing: " .. name)
    return fn
end

---@param bot boolean
---@return Player, table<integer, integer>, Weapon, Weapon
local function participant(bot)
    local reserves = { [1] = 0, [2] = 0 }
    local owner
    local function weapon(class, ammo, capacity)
        return {
            IsValid = function() return true end, IsWeapon = function() return true end,
            GetClass = function() return class end, GetOwner = function() return owner end,
            GetPrimaryAmmoType = function() return ammo end,
            Clip1 = function() return 7 end, GetMaxClip1 = function() return capacity end,
            SetClip1 = function() error("resupply must never refill a clip") end
        } --[[@as Weapon]]
    end
    local a, b = weapon("pwt_a", 1, 30), weapon("pwt_b", 1, 20)
    owner = {
        IsValid = function() return true end, IsPlayer = function() return true end,
        Alive = function() return true end, IsBot = function() return bot end,
        GetAmmoCount = function(_, ammo) return reserves[ammo] or 0 end,
        SetAmmo = function(_, count, ammo) reserves[ammo] = count end,
        GetWeapons = function() return { a, b } end,
        Give = function() error("resupply must never give a weapon") end,
        GiveAmmo = function() error("absolute capped reserve is authoritative") end
    } --[[@as Player]]
    return owner, reserves, a, b
end

return {
    groupName = "PW capped ordinary reserve resupply",
    cases = {
        {
            name = "Resupply: half magazine floor minimum one and three magazine cap",
            func = function()
                local amount = api("_ResupplyAmount")
                expect(amount(30, 0, 0.5, 3)).to.equal(15)
                expect(amount(31, 0, 0.5, 3)).to.equal(15)
                expect(amount(1, 0, 0.5, 3)).to.equal(1)
                expect(amount(30, 89, 0.5, 3)).to.equal(1)
                expect(amount(30, 90, 0.5, 3)).to.equal(0)
                expect(amount(30, 120, 0.5, 3)).to.equal(0)
            end
        },
        {
            name = "Resupply: invalid clipless nonfinite and negative requests add nothing",
            func = function()
                local amount = api("_ResupplyAmount")
                for _, capacity in ipairs({ -1, 0, math.huge, 0 / 0 }) do
                    expect(amount(capacity, 0, 0.5, 3)).to.equal(0)
                end
                for _, fraction in ipairs({ -1, 0, math.huge, 0 / 0 }) do
                    expect(amount(30, 0, fraction, 3)).to.equal(0)
                end
                expect(amount(30, 0, 0.5, 0)).to.equal(0)
            end
        },
        {
            name = "Resupply: shared ammo deduplicates deterministically using largest eligible magazine",
            func = function()
                local plan = api("_ResupplyPlan")
                local a = { ammo = 1, capacity = 30, reserve = 80 }
                local b = { ammo = 1, capacity = 20, reserve = 80 }
                local c = { ammo = 2, capacity = 8, reserve = 0 }
                expect(plan({ a, b, a, c }, 0.5, 3)).to.deepEqual({ [1] = 10, [2] = 4 })
                expect(plan({ c, b, a }, 0.5, 3)).to.deepEqual({ [1] = 10, [2] = 4 })
                expect(plan({ { ammo = -1, capacity = 30, reserve = 0 } }, 0.5, 3)).to.deepEqual({})
            end
        },
        {
            name = "Resupply: public service changes reserve only equally for humans and bots",
            func = function()
                for _, bot in ipairs({ false, true }) do
                    local owner, reserves, a, b = participant(bot)
                    local result = api("Resupply")(owner, { a, b, a }, { fraction = 0.5, maxMagazines = 3 })
                    expect(result).to.deepEqual({ [1] = 15 })
                    expect(reserves[1]).to.equal(15)
                    expect(a:Clip1()).to.equal(7)
                    reserves[1] = 89
                    expect(api("Resupply")(owner, { a }, { fraction = 0.5, maxMagazines = 3 }))
                        .to.deepEqual({ [1] = 1 })
                    expect(reserves[1]).to.equal(90)
                end
            end
        },
        {
            name = "Support cache: same API adds one deduplicated magazine per ammo type capped at three",
            func = function()
                local owner, reserves, a, b = participant(false)
                expect(api("Resupply")(owner, { a, b, a }, { fraction = 1, maxMagazines = 3 }))
                    .to.deepEqual({ [1] = 30 })
                expect(reserves[1]).to.equal(30)
                reserves[1] = 80
                expect(api("Resupply")(owner, { b, a }, { fraction = 1, maxMagazines = 3 }))
                    .to.deepEqual({ [1] = 10 })
                expect(reserves[1]).to.equal(90)
            end
        },
        {
            name = "Resupply: grenade SWEP equipment ammo foreign weapons and clipless weapons are excluded",
            func = function()
                local owner, reserves, a, b = participant(false)
                rawset(a, "PWGrenade", true)
                rawset(b, "GetOwner", function() return NULL end)
                expect(api("Resupply")(owner, { a, b }, { fraction = 0.5, maxMagazines = 3 })).to.deepEqual({})
                expect(reserves[1]).to.equal(0)
                rawset(a, "PWGrenade", false)
                rawset(a, "GetPrimaryAmmoType", function() return game.GetAmmoID("pw_frag") end)
                expect(api("Resupply")(owner, { a }, { fraction = 0.5, maxMagazines = 3 })).to.deepEqual({})
                rawset(a, "GetPrimaryAmmoType", function() return 1 end)
                rawset(a, "GetMaxClip1", function() return -1 end)
                expect(api("Resupply")(owner, { a }, { fraction = 0.5, maxMagazines = 3 })).to.deepEqual({})
            end
        },
        {
            name = "Resupply: no weapon grant no clip refill and full reserve is never reduced",
            func = function()
                local owner, reserves, a = participant(false)
                reserves[1] = 120
                expect(api("Resupply")(owner, { a }, { fraction = 0.5, maxMagazines = 3 })).to.deepEqual({})
                expect(reserves[1]).to.equal(120)
                expect(a:Clip1()).to.equal(7)
            end
        },
        {
            name = "Provenance: weapon inflictor credits that weapon but world streak and delayed nonweapon"
                .. " never held gun",
            func = function()
                local owner, _, a = participant(false)
                ---@type Entity
                local inflictor = a
                local kind = DMG_BULLET
                local dmg = {
                    GetAttacker = function() return owner end,
                    GetInflictor = function() return inflictor end,
                    IsDamageType = function(_, mask) return bit.band(kind, mask) ~= 0 end,
                    IsBulletDamage = function() return kind == DMG_BULLET end
                }
                expect({ api("DamageWeapon")(owner, dmg) }).to.deepEqual({ a, true })
                inflictor = game.GetWorld()
                expect(api("DamageWeapon")(owner, dmg)).to.beNil()
                kind = DMG_BLAST
                expect(api("DamageWeapon")(owner, dmg)).to.beNil()
                inflictor = owner
                expect(api("DamageWeapon")(owner, dmg)).to.beNil()
            end
        },
        {
            name = "Provenance: direct engine player bullets may use active weapon but blast and grenade"
                .. " are not direct",
            func = function()
                local owner, _, a = participant(true)
                rawset(owner, "GetActiveWeapon", function() return a end)
                -- Real DamageInfo setters require engine entities; _DamageSource is the pure classifier.
                local classify = api("_DamageSource")
                expect({ classify({ weapon = true, owned = true, grenade = false, direct = true }) })
                    .to.deepEqual({ "weapon", true })
                expect({ classify({ playerInflictor = true, active = true, direct = true }) })
                    .to.deepEqual({ "active", true })
                expect(classify({ playerInflictor = true, active = true, direct = false })).to.beNil()
                expect({ classify({ weapon = true, owned = true, grenade = true, direct = false }) })
                    .to.deepEqual({ "weapon", false })
                expect(classify({ weapon = true, owned = false, direct = true })).to.beNil()
                expect(classify({ active = true, direct = true })).to.beNil()
            end
        }
    }
}
