-- T-11.4 grenades as inventory items (TASKS.md, Phase 11 "Mandatory test cases"; 05-loadout.md d.11 revision
-- 2026-11-07). Pure cases for the cook timer and its cap, the cooked fuse, the switch back after the last grenade,
-- the key -> slot -> SWEP mapping and the count answer of a perk; wiring cases for the built-in items and SWEPs; the
-- in-game smoke runs a LIVE test match: the shared bot gets both grenade SWEPs with ammo = count, selecting a
-- grenade does not throw, the bot path switches to the grenade and throws it, the frag's blast credits the grenade
-- SWEP, the last grenade returns to the previous weapon and a perk that answers PW_EquipmentCount changes the ammo.
-- Death drop (user decision 2026-11-07, the local checklist item 66.3; it replaced "death with the pin pulled drops
-- nothing"): a bot killed while cooking a frag drops the live grenade at its body; it explodes with the remaining
-- fuse and the bot as the attacker.

local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---@class PW.GrenadesTestState
---@field bot Player?
---@field created Player?
---@field steps string[]
---@field inflictor Entity? the inflictor of the last util.BlastDamage (stubbed in the in-game case)
---@field attacker Entity? the attacker of the last util.BlastDamage
---@field blastAt Vector? the origin of the last util.BlastDamage
local test = { steps = {} }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.EquipmentLib
local function lib()
    return must(PW.Equipment)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

local frag, flash = "weapon_pw_frag", "weapon_pw_flash"

local pureCases = {
    {
        name = "Mandatory: holding attack cooks, the cook time is capped at about 3 s",
        func = function()
            local cap = lib().CookCap
            expect(cap >= 2.5 and cap <= 3.5).to.beTrue()
            local state = lib()._CookState
            expect({ state(0, 10, true, true, cap) }).to.deepEqual({ "idle", 0 })
            expect({ state(10, 11, true, true, cap) }).to.deepEqual({ "hold", 1 })
            expect({ state(10, 11.5, false, true, cap) }).to.deepEqual({ "throw", 1.5 })
            expect({ state(10, 10 + cap, true, true, cap) }).to.deepEqual({ "overcook", cap })
            expect({ state(10, 10 + cap + 2, true, true, cap) }).to.deepEqual({ "overcook", cap })
            -- An item that does not cook (the flash) never goes off in hand and is thrown with no cook time.
            expect({ state(10, 10 + cap + 2, true, false, cap) }).to.deepEqual({ "hold", 0 })
            expect({ state(10, 12, false, false, cap) }).to.deepEqual({ "throw", 0 })
        end
    },
    {
        name = "Cooked fuse: the cook time comes off the fuse; a full cook leaves the minimum fuse",
        func = function()
            local throwables = must(PW.Throwables)
            expect(lib()._CookedFuse(3, 1)).to.equal(2)
            expect(lib()._CookedFuse(3, 0)).to.equal(3)
            expect(lib()._CookedFuse(3, -1)).to.equal(3)
            expect(throwables._Fuse({ cook = lib()._CookedFuse(3, lib().CookCap) }))
                .to.equal(throwables.Defaults.minFuse)
        end
    },
    {
        name = "Mandatory: throwing the last grenade returns to the previous weapon (pure decision)",
        func = function()
            expect(lib()._ShouldSwitchBack(0)).to.beTrue()
            expect(lib()._ShouldSwitchBack(1)).to.beFalse()
            local grenades = { [frag] = true, [flash] = true }
            local back = lib()._ReturnWeapon
            local owned = { "weapon_crowbar", "weapon_ar2", frag, "weapon_pistol" }
            expect(back({ "weapon_pistol" }, owned, grenades)).to.equal("weapon_pistol")
            expect(back({ "weapon_rpg", "weapon_ar2" }, owned, grenades)).to.equal("weapon_ar2")
            expect(back({ frag }, owned, grenades)).to.equal("weapon_crowbar")
            expect(back({}, { frag, "weapon_smg1" }, grenades)).to.equal("weapon_smg1")
            expect(back({ frag }, { frag, flash }, grenades)).to.beNil()
        end
    },
    {
        name = "Mandatory: the slot key switches to the grenade and does not throw at once (key -> slot -> SWEP)",
        func = function()
            local codes = { lethal = KEY_G, tactical = KEY_4 }
            local weapons = { lethal = frag, tactical = flash }
            local ammo = { [frag] = 1, [flash] = 0 }
            expect(lib()._KeyWeapon(KEY_G, codes, weapons, ammo)).to.equal(frag)
            expect(lib()._KeyWeapon(KEY_4, codes, weapons, ammo)).to.beNil()
            ammo[flash] = 2
            expect(lib()._KeyWeapon(KEY_4, codes, weapons, ammo)).to.equal(flash)
            expect(lib()._KeyWeapon(KEY_F, codes, weapons, ammo)).to.beNil()
            expect(lib()._SlotWeapon("lethal", { tactical = flash }, ammo)).to.beNil()
            -- No use message any more: the key only selects the weapon, the throw is the SWEP's release.
            expect(rawget(lib(), "NetName")).to.beNil()
            expect(rawget(lib(), "_Receive")).to.beNil()
        end
    },
    {
        name = "Mandatory: death drop: dying while cooking drops the grenade with the remaining fuse (at least the"
            .. " minimum); no pin pulled or an item that does not cook drops nothing",
        func = function()
            local min = lib().DeathMinFuse
            expect(min > 0 and min <= 0.5).to.beTrue()
            local remaining = lib()._RemainingFuse
            expect(remaining(3, 1, 0.1)).to.equal(2)
            expect(remaining(3, 0, 0.1)).to.equal(3)
            expect(remaining(3, -1, 0.1)).to.equal(3)
            expect(remaining(3, 2.95, 0.1)).to.equal(0.1)
            expect(remaining(3, 3, 0.1)).to.equal(0.1)
            local cap = lib().CookCap
            local drop = lib()._DeathDrop
            expect(drop(0, 10, true, cap)).to.beNil()
            expect(drop(10, 11, true, cap)).to.equal(1)
            expect(drop(10, 10 + cap + 5, true, cap)).to.equal(cap)
            expect(drop(10, 11, false, cap)).to.beNil()
            local opts = lib()._ThrowOptions(3, true, { cooked = 1, death = true })
            expect(opts.cook).to.equal(2)
            expect(opts.drop).to.beTrue()
            expect(opts.speed).to.equal(0)
            expect(opts.lift).to.equal(0)
            expect(lib()._ThrowOptions(3, true, { cooked = cap, death = true }).cook).to.equal(min)
            expect(lib()._ThrowOptions(3, true, { cooked = 1 }).drop).toNot.beTrue()
        end
    },
    {
        name = "Count answer: a perk's number replaces the count (rounded down, never below 0); nil keeps it",
        func = function()
            expect(lib()._CountFor(1, nil)).to.equal(1)
            expect(lib()._CountFor(1, 3)).to.equal(3)
            expect(lib()._CountFor(1, 2.7)).to.equal(2)
            expect(lib()._CountFor(1, -4)).to.equal(0)
            expect(lib()._CountFor(1, "x")).to.equal(1)
        end
    }
}

local wiringCases = {
    {
        name = "Wiring: frag and flash name their grenade SWEPs; the SWEPs exist, are not spawnable, use own ammo",
        func = function()
            local registry = must(PW.Registries.equipment)
            local fragDef = must(registry.Get("frag")) --[[@as PW.EquipmentItem]]
            local flashDef = must(registry.Get("flash")) --[[@as PW.EquipmentItem]]
            expect(fragDef.Weapon).to.equal(frag)
            expect(flashDef.Weapon).to.equal(flash)
            expect(fragDef.Cook).to.beTrue()
            expect(flashDef.Cook).toNot.beTrue()
            for _, class in ipairs({ frag, flash }) do
                local swep = must(weapons.Get(class)) --[[@as table<string, any>]]
                expect(swep.Spawnable).toNot.beTrue()
                expect(swep.PWGrenade).to.beTrue()
                local ammo = must(lib()._AmmoOf(class))
                expect(game.GetAmmoID(ammo) >= 0).to.beTrue()
            end
            expect(lib()._AmmoOf(frag)).toNot.equal(lib()._AmmoOf(flash))
            expect(lib()._AmmoOf("weapon_does_not_exist")).to.beNil()
        end
    }
}

---The shared bot. A bot another group left behind is reused; only a bot this group made is kicked.
---@return Player
local function sharedBot()
    local bot = test.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW grenades test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        test.created = bot
    end
    test.bot = bot
    return bot
end

---@param bot Player
---@return integer
local function grenadesOf(bot)
    local n = 0
    for _, ent in ipairs(ents.FindByClass(must(PW.Throwables).EntityClass)) do
        if ent:GetOwner() == bot then n = n + 1 end
    end
    return n
end

---@param bot Player
---@param class string
---@return integer
local function ammoOf(bot, class)
    return bot:GetAmmoCount(must(lib()._AmmoOf(class)))
end

---@param bot Player
---@return string
local function activeClass(bot)
    local wep = bot:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() or ""
end

---Step 1: the SWEPs were given on spawn with ammo = count; selecting the grenade does not throw.
---@param bot Player
---@param fail fun(message: string)
local function checkGiven(bot, fail)
    for slot, class in pairs({ lethal = frag, tactical = flash }) do
        if not bot:HasWeapon(class) then return fail("no " .. class .. " after spawn") end
        local count = lib().Count(bot, slot)
        if count < 1 then return fail(slot .. " count is " .. count) end
        if ammoOf(bot, class) ~= count then
            return fail(class .. " ammo " .. ammoOf(bot, class) .. " ~= count " .. count)
        end
    end
    local before = lib().Count(bot, "lethal")
    bot:SelectWeapon(frag)
    if activeClass(bot) ~= frag then return fail("SelectWeapon did not reach the frag") end
    if grenadesOf(bot) ~= 0 or lib().Count(bot, "lethal") ~= before then return fail("selecting threw") end
    test.steps[#test.steps + 1] = "given"
end

---Step 2: the bot path switches to the grenade and throws it; the blast credits the grenade SWEP; the bot is back
---on its previous weapon afterwards.
---@param bot Player
---@param fail fun(message: string)
---@param after fun()
local function checkBotThrow(bot, fail, after)
    bot:SelectWeapon("weapon_crowbar")
    local previous = activeClass(bot)
    local before = lib().Count(bot, "lethal")
    test.inflictor = nil
    if not lib().Use(bot, "lethal", { cooked = lib().CookCap }) then return fail("Use refused the frag") end
    if activeClass(bot) ~= frag then return fail("the bot did not switch to the frag") end
    if lib().Count(bot, "lethal") ~= before - 1 or ammoOf(bot, frag) ~= before - 1 then
        return fail("count or ammo did not drop")
    end
    if grenadesOf(bot) ~= 1 then return fail("no grenade of the bot") end
    timer.Simple(lib().BotHold + 0.4, function()
        if test.inflictor ~= bot:GetWeapon(frag) then return fail("the blast does not credit the frag SWEP") end
        if activeClass(bot) ~= previous then
            return fail("the bot is not back on " .. previous .. ": " .. activeClass(bot))
        end
        test.steps[#test.steps + 1] = "bot throw"
        after()
    end)
end

---Step 3: the human release of the last grenade returns to the previous weapon.
---@param bot Player
---@param fail fun(message: string)
---@param after fun()
local function checkLastThrow(bot, fail, after)
    bot:SelectWeapon("weapon_crowbar")
    bot:SelectWeapon(flash)
    local wep = bot:GetWeapon(flash)
    if not IsValid(wep) or activeClass(bot) ~= flash then return fail("the bot cannot hold the flash") end
    local store = must(PW._Equipment)
    must(store.players[bot]).tactical.count = 1
    store.publish(bot, "tactical", "flash", 1)
    if not must(lib()._Release)(bot, wep --[[@as Weapon]], { cooked = 0 }) then return fail("release refused") end
    if ammoOf(bot, flash) ~= 0 then return fail("flash ammo not 0 after the last throw") end
    timer.Simple(lib().SwitchDelay + 0.4, function()
        if activeClass(bot) ~= "weapon_crowbar" then
            return fail("not back after the last grenade: " .. activeClass(bot))
        end
        test.steps[#test.steps + 1] = "last throw"
        after()
    end)
end

---Step 4: a perk instance that answers PW_EquipmentCount changes the ammo on the next refill.
---@param bot Player
---@param fail fun(message: string)
local function checkPerkCount(bot, fail)
    local base = must(must(PW.Registries.equipment).Get("frag")).Count --[[@as number]]
    local perk = PW.Instance({ ClassName = "pwt_grenadier", OnEquip = function(self)
        self:Hook("PW_EquipmentCount", function(_, ply, slot, _, count)
            if ply == bot and slot == "lethal" then return count + 2 end
        end)
    end }, bot)
    must(lib()._Equip)(bot)
    must(lib()._GiveWeapons)(bot)
    perk:Remove()
    if lib().Count(bot, "lethal") ~= base + 2 then return fail("count not raised: " .. lib().Count(bot, "lethal")) end
    if ammoOf(bot, frag) ~= base + 2 then return fail("ammo not raised: " .. ammoOf(bot, frag)) end
    test.steps[#test.steps + 1] = "perk count"
end

---Step 5 (66.3, user decision 2026-11-07): killed while cooking the frag, the bot drops the live grenade at its body;
---it explodes after the remaining fuse with the bot as the attacker.
---@param bot Player
---@param fail fun(message: string)
---@param after fun()
local function checkDeathDrop(bot, fail, after)
    bot:SelectWeapon(frag)
    local wep = bot:GetWeapon(frag)
    if not IsValid(wep) or activeClass(bot) ~= frag then return fail("the bot cannot hold the frag") end
    if ammoOf(bot, frag) < 1 then return fail("no frag left for the death drop") end
    local cooked = 1
    -- Bots never pull the pin through the SWEP: start the cook by hand and kill in the same tick, before the SWEP's
    -- Think sees the attack released.
    wep:SetDTFloat(0, CurTime() - cooked)
    test.inflictor, test.attacker, test.blastAt = nil, nil, nil
    local body = bot:GetPos()
    bot:Kill()
    local dropped = nil
    for _, ent in ipairs(ents.FindByClass(must(PW.Throwables).EntityClass)) do
        if ent:GetOwner() == bot then dropped = ent end
    end
    if dropped == nil then return fail("no grenade dropped on death") end
    if dropped:GetPos():Distance(body) > 100 then return fail("the grenade is not at the body") end
    local fuse = must(must(PW.Registries.equipment).Get("frag")).Fuse --[[@as number]]
    timer.Simple(fuse - cooked + 0.5, function()
        if IsValid(dropped) then return fail("the dropped grenade did not explode") end
        if test.attacker ~= bot then return fail("the blast does not have the bot as the attacker") end
        if test.blastAt == nil or test.blastAt:Distance(body) > 200 then return fail("the blast is not at the body") end
        test.steps[#test.steps + 1] = "death drop"
        after()
    end)
end

---@param bot Player
---@param fail fun(message: string)
---@param after fun()
local function runSteps(bot, fail, after)
    if not IsValid(bot) then return fail("the shared bot is gone") end
    if not bot:Alive() then bot:Spawn() end
    timer.Simple(0.3, function()
        checkGiven(bot, fail)
        checkBotThrow(bot, fail, function()
            checkLastThrow(bot, fail, function()
                checkPerkCount(bot, fail)
                checkDeathDrop(bot, fail, after)
            end)
        end)
    end)
end

local gameCases = {
    {
        name = "Mandatory: in a LIVE match the bot gets the grenade SWEPs (count = ammo), switches to the grenade and"
            .. " throws it, the last grenade returns to the previous weapon, a perk count changes the ammo; killed"
            .. " while cooking, it drops the live frag at its body and the blast credits it",
        async = true,
        timeout = 30,
        func = function()
            test.steps = {}
            -- GLuaTest's stub exists only inside a case: the blast is recorded instead of dealt.
            stub(util, "BlastDamage").with(function(ent, attacker, pos)
                test.inflictor, test.attacker, test.blastAt = ent, attacker, pos
            end)
            ---@type table<string, string>
            local saved = {}
            for _, name in ipairs(phaseConVars) do saved[name] = must(GetConVar(name)):GetString() end
            local function restore()
                for name, value in pairs(saved) do must(GetConVar(name)):SetString(value) end
                must(must(PW.Throwables)._RemoveAll)()
            end
            must(GetConVar("pw_prematch_timeout")):SetString("0")
            must(GetConVar("pw_countdown")):SetString("0")
            must(GetConVar("pw_postmatch_time")):SetString("0.5")
            must(GetConVar("pw_aftermatch")):SetString("lobby")
            expect(match().GetPhase()).to.equal("LOBBY")
            expect(match().Start(must(PW.Modes.Get("tdm")))).to.beTrue()
            local function fail(message)
                restore()
                if match().GetPhase() ~= "LOBBY" then match().Abort("grenades smoke: " .. message) end
                error(message, 0)
            end
            local function waitFor(phase, deadline, after)
                if match().GetPhase() == phase then return after() end
                if CurTime() > deadline then fail("phase " .. phase .. " not reached, still " .. match().GetPhase()) end
                timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
            end
            waitFor("LIVE", CurTime() + 5, function()
                runSteps(sharedBot(), fail, function()
                    match().Abort("grenades smoke done")
                    waitFor("LOBBY", CurTime() + 5, function()
                        restore()
                        expect(test.steps).to.deepEqual({ "given", "bot throw", "last throw", "perk count",
                            "death drop" })
                        done()
                    end)
                end)
            end)
        end
    }
}

---@param ... table[]
---@return table[]
local function join(...)
    ---@type table[]
    local all = {}
    ---@type table[][]
    local lists = { ... }
    for _, list in ipairs(lists) do
        for _, case in ipairs(list) do all[#all + 1] = case end
    end
    return all
end

return {
    groupName = "PW grenades inventory",
    afterAll = function()
        local created = test.created
        if created ~= nil and IsValid(created) then created:Kick("grenades tests done") end
    end,
    cases = join(pureCases, wiringCases, gameCases)
}
