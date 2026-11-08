-- Thin native-player smoke; all numeric/eligibility boundaries remain in the focused suites.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "perk smoke requires the public owner API")
    return value
end

---@param body fun(bot: Player)
local function withBot(body)
    local bot = player.GetBots()[1]
    local created = false
    if not IsValid(bot) then bot = player.CreateNextBot("PW perk smoke") created = true end
    assert(IsValid(bot), "perk smoke needs a native player slot")
    local match = must(PW.Match)
    local phase, mode = match.GetPhase, PW.ActiveMode
    rawset(match, "GetPhase", function() return "LIVE" end)
    PW.ActiveMode = must(PW.Modes.Get("ffa"))
    must(PW.MatchRules).Spawn(bot)
    local ok, err = pcall(body, bot)
    must(PW.Perks).Revoke(bot)
    must(PW.Equipment).Revoke(bot)
    must(PW.Throwables).ClearBlind(bot)
    rawset(match, "GetPhase", phase)
    PW.ActiveMode = mode
    if created and IsValid(bot) then bot:Kick("perk smoke finished") end
    if not ok then error(err, 0) end
end

return {
    groupName = "PW native perk effects smoke",
    cases = {
        {
            name = "Native bot: Stockpile grants both actual grenade ammo types once and Fleet Foot restores baseline",
            func = function()
                withBot(function(bot)
                    local perks, equipment = must(PW.Perks), must(PW.Equipment)
                    must(perks.Refresh)(bot, { perk1 = "stockpile" })
                    equipment._Equip(bot)
                    equipment._GiveWeapons(bot)
                    for _, slot in ipairs({ "lethal", "tactical" }) do
                        expect(equipment.Count(bot, slot)).to.equal(2)
                        local class = must(equipment._ItemWeapon(must(equipment.Item(bot, slot))))
                        local weapon = bot:GetWeapon(class)
                        expect(IsValid(weapon)).to.beTrue()
                        expect(bot:GetAmmoCount(weapon:GetPrimaryAmmoType())).to.equal(2)
                    end
                    local walk, run, health = bot:GetWalkSpeed(), bot:GetRunSpeed(), bot:Health()
                    must(perks.Refresh)(bot, { perk1 = "fleet_foot" })
                    expect(math.abs(bot:GetWalkSpeed() - walk * 1.1) < 0.001).to.beTrue()
                    expect(math.abs(bot:GetRunSpeed() - run * 1.1) < 0.001).to.beTrue()
                    must(perks._Recompute)(bot)
                    expect(math.abs(bot:GetWalkSpeed() - walk * 1.1) < 0.001).to.beTrue()
                    perks.Revoke(bot)
                    expect(bot:GetWalkSpeed()).to.equal(walk)
                    expect(bot:Health()).to.equal(health)
                end)
            end
        },
        {
            name = "Native bot: Quiet Steps replicates and ordinary flash gates sight and fire until owner cleanup",
            func = function()
                withBot(function(bot)
                    local perks, status = must(PW.Perks), must(PW.Throwables)
                    must(perks.Refresh)(bot, { perk3 = "quiet_steps" })
                    expect(bot:GetNW2Bool("pw_silent_steps", false)).to.beTrue()
                    expect(perks.FootstepsAudible(bot)).to.beFalse()
                    expect(status.Blind(bot, 1)).to.beTrue()
                    expect(PW.BotPerception._FlashCanSee(bot, CurTime())).to.beFalse()
                    expect(must(PW.BotAim)._FlashCanFire(bot, CurTime())).to.beFalse()
                    status.ClearBlind(bot)
                    expect(PW.BotPerception._FlashCanSee(bot, CurTime())).to.beTrue()
                    expect(must(PW.BotAim)._FlashCanFire(bot, CurTime())).to.beTrue()
                    perks.Revoke(bot)
                    expect(bot:GetNW2Bool("pw_silent_steps", true)).to.beFalse()
                end)
            end
        }
    }
}
