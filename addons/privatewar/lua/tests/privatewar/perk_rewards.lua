-- Owner-local event effects. Patch only public consumers and restore them even on assertion failures.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "approved event perk is missing")
    return value
end

---@param patches { target: table, key: string, value: any }[]
---@param body fun()
local function patched(patches, body)
    ---@type table<integer, any>
    local old = {}
    for i, patch in ipairs(patches) do
        old[i] = rawget(patch.target, patch.key)
        rawset(patch.target, patch.key, patch.value)
    end
    local ok, err = pcall(body)
    for i, patch in ipairs(patches) do rawset(patch.target, patch.key, old[i]) end
    if not ok then error(err, 0) end
end

---@param bot boolean
---@return Player
local function participant(bot)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        EyePos = function() return Vector() end, WorldSpaceCenter = function() return Vector(10, 0, 0) end
    } --[[@as Player]]
end

---@param id string
---@return table<string, any>
local function instance(id)
    return setmetatable({}, { __index = must(must(PW.Registries.perks).Get(id)) })
end

return {
    groupName = "PW approved perk event effects",
    cases = {
        {
            name = "Scavenger: enemy direct kill resupplies only proven kill weapon half magazine capped at three",
            func = function()
                for _, bot in ipairs({ false, true }) do
                    local owner, victim = participant(bot), participant(not bot)
                    local weapon = {} -- explicit kill weapon, never the unrelated active gun
                    ---@type table<string, any>[]
                    local calls = {}
                    patched({
                        { target = PW, key = "IsEnemy", value = function(a, b) return a == owner and b == victim end },
                        { target = PW.WeaponAmmo, key = "DamageWeapon", value = function(ply)
                            expect(ply).to.equal(owner)
                            return weapon, true
                        end },
                        { target = PW.WeaponAmmo, key = "Resupply", value = function(ply, weapons, opts)
                            calls[#calls + 1] = { ply = ply, weapons = weapons, opts = opts }
                            return { [1] = 15 }
                        end }
                    }, function()
                        local perk = instance("scavenger")
                        perk:OnKill(owner, victim, {})
                    end)
                    expect(calls).to.deepEqual({ { ply = owner, weapons = { weapon },
                        opts = { fraction = 0.5, maxMagazines = 3 } } })
                end
            end
        },
        {
            name = "Scavenger: ally suicide world autonomous streak and delayed nonweapon kills never refill",
            func = function()
                local owner, victim = participant(false), participant(true)
                local enemy, direct, weapon = false, true, {}
                local calls = 0
                patched({
                    { target = PW, key = "IsEnemy", value = function() return enemy end },
                    { target = PW.WeaponAmmo, key = "DamageWeapon", value = function() return weapon, direct end },
                    { target = PW.WeaponAmmo, key = "Resupply", value = function() calls = calls + 1 return {} end }
                }, function()
                    local perk = instance("scavenger")
                    perk:OnKill(owner, victim, {}) -- ally
                    enemy = true
                    perk:OnKill(owner, owner, {}) -- suicide, even with a permissive relationship provider
                    weapon, direct = nil, false
                    perk:OnKill(owner, victim, {}) -- world/autonomous/delayed nonweapon
                    weapon = {}
                    perk:OnKill(owner, victim, {}) -- explicit grenade/delayed weapon provenance, not direct
                end)
                expect(calls).to.equal(0)
            end
        },
        {
            name = "Retaliation: one current LOS direct attacker pulse lasts 1.5 seconds per five seconds"
                .. " through Viewer Reveal",
            func = function()
                local owner, attacker = participant(true), participant(false)
                local now, traces = 10, 0
                ---@type any[][]
                local reveals = {}
                patched({
                    { target = _G, key = "CurTime", value = function() return now end },
                    { target = PW, key = "IsEnemy", value = function(a, b) return a ~= b end },
                    { target = PW.WeaponAmmo, key = "DamageWeapon", value = function() return {}, true end },
                    { target = util, key = "TraceLine", value = function()
                        traces = traces + 1
                        return { Hit = false, Fraction = 1, Entity = attacker }
                    end },
                    { target = must(PW.Streaks), key = "Viewer", value = function(ply)
                        expect(ply).to.equal(owner)
                        return 2
                    end },
                    { target = PW, key = "Reveal", value = function(viewer, targets, duration, source)
                        reveals[#reveals + 1] = { viewer, targets, duration, source }
                        return 1
                    end }
                }, function()
                    local perk = instance("retaliation")
                    perk:OnDamaged(owner, attacker, {})
                    now = 14.999
                    perk:OnDamaged(owner, attacker, {})
                    expect(#reveals).to.equal(1)
                    now = 15
                    perk:OnDamaged(owner, attacker, {})
                end)
                expect(reveals).to.deepEqual({ { 2, { attacker }, 1.5, owner }, { 2, { attacker }, 1.5, owner } })
                expect(traces <= 2).to.beTrue()
            end
        },
        {
            name = "Retaliation: teammate dead nonplayer nonweapon and occluded attacker never disclose a position",
            func = function()
                local owner, attacker = participant(false), participant(true)
                local enemy, direct, los = false, true, true
                local revealed = 0
                patched({
                    { target = PW, key = "IsEnemy", value = function() return enemy end },
                    { target = PW.WeaponAmmo, key = "DamageWeapon", value = function() return {}, direct end },
                    { target = util, key = "TraceLine", value = function()
                        return { Hit = not los, Fraction = los and 1 or 0, Entity = NULL }
                    end },
                    { target = PW, key = "Reveal", value = function() revealed = revealed + 1 return 1 end }
                }, function()
                    local perk = instance("retaliation")
                    perk:OnDamaged(owner, attacker, {})
                    enemy, direct = true, false
                    perk:OnDamaged(owner, attacker, {})
                    direct, los = true, false
                    perk:OnDamaged(owner, attacker, {})
                    rawset(attacker, "Alive", function() return false end)
                    los = true
                    perk:OnDamaged(owner, attacker, {})
                    perk:OnDamaged(owner, game.GetWorld(), {})
                    perk:OnDamaged(owner, owner, {})
                end)
                expect(revealed).to.equal(0)
            end
        }
    }
}
