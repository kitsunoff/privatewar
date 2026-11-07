-- T-4.5 equipment and throwables (TASKS.md, "Mandatory test cases" T-4.5; 05-loadout.md d.11). Pure cases for the
-- counts, the cooldown, the slot keys, the throw vector, the fuse, the flash strength and the blind fade; module
-- cases over a fresh equipment store with a test item and a fake clock and phase (the slot key's use through the
-- grenade release, the count and its refill on spawn, the bot path with the shared bot); the last case is the
-- in-game check: in a LIVE test match the shared bot throws a real frag and its count drops.
-- T-11.4 (grenades as inventory SWEPs) removed the use message: the slot key selects the grenade SWEP and its
-- release uses the slot (PW.Equipment._Release); the grenade cases are grenades_inventory.lua.

local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---A recorded OnUse call.
---@class PW.EquipmentTestUse
---@field self table the instance OnUse ran on
---@field owner Player
---@field id string

---A recorded publish.
---@class PW.EquipmentTestPublish
---@field ply Player
---@field slot string
---@field id string
---@field count integer

---State of this group; reset in beforeEach.
---@class PW.EquipmentTestState
---@field now number
---@field phase string
---@field alive boolean
---@field refuse boolean
---@field uses PW.EquipmentTestUse[]
---@field published PW.EquipmentTestPublish[]
---@field thrownAfter integer[] counts the store's afterThrow saw
---@field previousEquipment PW.EquipmentStore?
---@field bot Player?
---@field created Player?
---@field thrown boolean
local test = { now = 0, phase = "LIVE", alive = true, refuse = false, uses = {}, published = {}, thrownAfter = {},
    thrown = false }

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

---@return PW.ThrowablesLib
local function throw()
    return must(PW.Throwables)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---The shared bot of the module cases. A bot another group left behind is reused: the suite is close to
---maxplayers, so this group adds a bot only when none exists and kicks only that one.
---@return Player
local function sharedBot()
    local bot = test.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        bot = player.CreateNextBot("PW equipment test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        test.created = bot
    end
    test.bot = bot
    return bot
end

---A player stand-in: a unique table is enough for the store and the net buckets.
---@return Player
local function fakePlayer()
    return { IsValid = function() return true end, Nick = function() return "fake" end } --[[@as Player]]
end

---A test item whose OnUse records the instance and the owner; Count 2.
---@param id string
---@return PW.EquipmentItem
local function testItem(id)
    return {
        ClassName = id, Name = string.upper(id), Count = 2,
        OnUse = function(self, owner)
            test.uses[#test.uses + 1] = { self = self, owner = owner, id = id }
            return test.refuse ~= true
        end
    } --[[@as PW.EquipmentItem]]
end

---Installs a fresh equipment store: test items, a fixed loadout, recorded publishes, fake clock and phase.
local function installStore()
    test.uses, test.published, test.thrownAfter = {}, {}, {}
    local items = { pwt_frag = testItem("pwt_frag"), pwt_flash = testItem("pwt_flash") }
    PW._Equipment = must(lib()._NewStore)({
        lookup = function(id) return items[id] end,
        resolve = function() return { lethal = "pwt_frag", tactical = "pwt_flash" } end,
        publish = function(ply, slot, id, count)
            test.published[#test.published + 1] = { ply = ply, slot = slot, id = id, count = count }
        end,
        clock = function() return test.now end,
        phase = function() return test.phase end,
        alive = function() return test.alive ~= false end,
        afterThrow = function(_, _, count) test.thrownAfter[#test.thrownAfter + 1] = count end
    })
end

---@param ply Player
---@param slot string
---@return PW.EquipmentEntry
local function entryOf(ply, slot)
    return must(must(must(PW._Equipment).players[ply])[slot])
end

local pureCases = {
    {
        name = "Counts: an item refills to its Count, rounded down, never below 0",
        func = function()
            expect(lib()._Refill({ Count = 2 })).to.equal(2)
            expect(lib()._Refill({ Count = 1.7 })).to.equal(1)
            expect(lib()._Refill({ Count = -3 })).to.equal(0)
            expect(lib()._Refill({ Count = "x" })).to.equal(0)
        end
    },
    {
        name = "Use rule: no uses left, an invalid instance and the cooldown refuse; otherwise allowed",
        func = function()
            local valid = { IsValid = function() return true end }
            local invalid = { IsValid = function() return false end }
            expect({ lib()._CanUse({ count = 1, last = -math.huge, instance = valid }, 10, 1) }).to.deepEqual({ true })
            expect({ lib()._CanUse({ count = 0, last = -math.huge, instance = valid }, 10, 1) })
                .to.deepEqual({ false, "empty" })
            expect({ lib()._CanUse({ count = 1, last = -math.huge, instance = invalid }, 10, 1) })
                .to.deepEqual({ false, "invalid" })
            expect({ lib()._CanUse({ count = 1, last = 9.5, instance = valid }, 10, 1) })
                .to.deepEqual({ false, "cooldown" })
            expect(lib()._CanUse({ count = 1, last = 9, instance = valid }, 10, 1)).to.beTrue()
        end
    },
    {
        name = "Slot keys: G is lethal, 4 is tactical, another key is no slot",
        func = function()
            local codes = { lethal = KEY_G, tactical = KEY_4 }
            expect(lib()._KeySlot(KEY_G, codes)).to.equal("lethal")
            expect(lib()._KeySlot(KEY_4, codes)).to.equal("tactical")
            expect(lib()._KeySlot(KEY_F, codes)).to.beNil()
            expect(lib()._KeySlot(KEY_NONE, { lethal = KEY_NONE })).to.beNil()
            expect(lib().Keys.lethal.default).to.equal("g")
            expect(lib().Keys.tactical.default).to.equal("4")
        end
    },
    {
        name = "Throw vector: spawned in front of the eye along the normalized aim, thrown along it with lift",
        func = function()
            local d = throw().Defaults
            local pos, vel = throw()._Launch(Vector(0, 0, 64), Vector(2, 0, 0), nil, nil)
            expect(pos).to.equal(Vector(d.forward, 0, 64))
            expect(vel).to.equal(Vector(d.speed, 0, d.lift))
            local pos2, vel2 = throw()._Launch(Vector(10, 10, 10), Vector(0, 1, 0), Vector(5, 0, 0),
                { speed = 100, lift = 0, forward = 20 })
            expect(pos2).to.equal(Vector(10, 30, 10))
            expect(vel2).to.equal(Vector(5, 100, 0))
        end
    },
    {
        name = "Fuse: cook wins, then fuse, then the default; clamped to the limits",
        func = function()
            local d = throw().Defaults
            expect(throw()._Fuse({ cook = 4 })).to.equal(4)
            expect(throw()._Fuse({ fuse = 2 })).to.equal(2)
            expect(throw()._Fuse({ cook = 1, fuse = 2 })).to.equal(1)
            expect(throw()._Fuse(nil)).to.equal(d.fuse)
            expect(throw()._Fuse({ cook = -1 })).to.equal(d.minFuse)
            expect(throw()._Fuse({ cook = 1000 })).to.equal(d.maxFuse)
        end
    },
    {
        name = "Flash strength: full when close and facing; less by angle and by distance; zero without sight",
        func = function()
            local f = throw().Flash
            local s = throw()._FlashStrength
            expect(s(f.near / 2, 1, true)).to.equal(1)
            expect(s(f.near / 2, 1, false)).to.equal(0)
            expect(s(f.radius + 1, 1, true)).to.equal(0)
            expect(s(f.near / 2, -1, true)).to.equal(f.behind)
            local side = s(f.near / 2, 0, true)
            expect(side < 1 and side > f.behind).to.beTrue()
            local mid, far = s((f.near + f.radius) / 2, 1, true), s(f.radius * 0.95, 1, true)
            expect(mid < 1 and mid > far and far > 0).to.beTrue()
        end
    },
    {
        name = "Blind: duration grows with strength; the white is held, then fades to zero",
        func = function()
            local f = throw().Flash
            expect(throw()._BlindTime(1)).to.equal(f.maxTime)
            expect(throw()._BlindTime(0.5) < throw()._BlindTime(1)).to.beTrue()
            expect(throw()._BlindAlpha(0, 1)).to.equal(1)
            local total = throw()._BlindTime(1)
            local half = throw()._BlindAlpha(total * 0.7, 1)
            expect(half > 0 and half < 1).to.beTrue()
            expect(throw()._BlindAlpha(total, 1)).to.equal(0)
            expect(throw()._BlindAlpha(0, 0.2) < 1).to.beTrue()
            expect(throw()._DecodeStrength(throw()._EncodeStrength(0.5))).to.aboutEqual(0.5, 0.01)
            expect(throw()._EncodeStrength(3)).to.equal(255)
        end
    }
}

local moduleCases = {
    {
        name = "Mandatory: the slot key triggers OnUse on the player's instance (through the grenade release)",
        func = function()
            local ply = fakePlayer()
            must(lib()._Equip)(ply)
            local slots = must(must(PW._Equipment).players[ply])
            must(slots.lethal).weapon, must(slots.tactical).weapon = "pwt_frag_swep", "pwt_flash_swep"
            ---@param slot string
            ---@param class string
            ---@return Weapon
            local function grenade(slot, class)
                return { PWSlot = slot, GetClass = function() return class end } --[[@as Weapon]]
            end
            local release = must(lib()._Release)
            local codes = { lethal = KEY_G, tactical = KEY_4 }
            local lethal = must(lib()._KeySlot(KEY_G, codes))
            test.phase = "PREMATCH"
            expect(release(ply, grenade(lethal, "pwt_frag_swep"), { cooked = 1 })).to.beFalse()
            expect(#test.uses).to.equal(0)
            test.phase = "LIVE"
            expect(release(ply, grenade(lethal, "pwt_other_swep"))).to.beFalse()
            expect(release(ply, grenade(lethal, "pwt_frag_swep"), { cooked = 1 })).to.beTrue()
            expect(#test.uses).to.equal(1)
            expect(test.uses[1].self).to.equal(entryOf(ply, "lethal").instance)
            expect(test.uses[1].owner).to.equal(ply)
            expect(test.uses[1].id).to.equal("pwt_frag")
            expect(test.thrownAfter).to.deepEqual({ 1 })
            test.now = test.now + 5
            local tactical = must(lib()._KeySlot(KEY_4, codes))
            expect(release(ply, grenade(tactical, "pwt_flash_swep"))).to.beTrue()
            expect(test.uses[2].id).to.equal("pwt_flash")
            expect(#test.uses).to.equal(2)
        end
    },
    {
        name = "Mandatory: the count decreases on use and refills on spawn",
        func = function()
            local ply = fakePlayer()
            local onSpawn = must(lib()._OnSpawn)
            test.phase = "LOBBY"
            expect(onSpawn(ply)).to.beFalse()
            expect(lib().Count(ply, "lethal")).to.equal(0)
            test.phase = "LIVE"
            expect(onSpawn(ply)).to.beTrue()
            expect(lib().Count(ply, "lethal")).to.equal(2)
            expect(lib().Item(ply, "lethal")).to.equal("pwt_frag")
            local use = must(lib().Use)
            expect(use(ply, "lethal")).to.beTrue()
            expect(lib().Count(ply, "lethal")).to.equal(1)
            expect(use(ply, "lethal")).to.beFalse() -- cooldown
            test.now = test.now + lib().Cooldown
            expect(use(ply, "lethal")).to.beTrue()
            expect(lib().Count(ply, "lethal")).to.equal(0)
            test.now = test.now + lib().Cooldown
            expect(use(ply, "lethal")).to.beFalse()
            expect(#test.uses).to.equal(2)
            local last = test.published[#test.published]
            expect(last.slot).to.equal("lethal")
            expect(last.count).to.equal(0)
            local old = entryOf(ply, "lethal").instance
            expect(onSpawn(ply)).to.beTrue()
            expect(lib().Count(ply, "lethal")).to.equal(2)
            expect(lib().Count(ply, "tactical")).to.equal(2)
            expect(old:IsValid()).to.beFalse()
            must(lib()._Clear)(ply)
            expect(lib().Count(ply, "lethal")).to.equal(0)
        end
    },
    {
        name = "Use: refused outside LIVE, for a dead player, and when OnUse refuses (count kept)",
        func = function()
            local ply = fakePlayer()
            local use = must(lib().Use)
            test.phase = "POSTMATCH"
            expect(use(ply, "lethal")).to.beFalse()
            test.phase = "LIVE"
            test.alive = false
            expect(use(ply, "lethal")).to.beFalse()
            test.alive = true
            test.refuse = true
            expect(use(ply, "lethal")).to.beFalse()
            expect(lib().Count(ply, "lethal")).to.equal(2)
            expect(use(ply, "nope")).to.beFalse()
        end
    },
    {
        name = "Mandatory: the bot path PW.Equipment.Use works (directly and through PW.BotTactics.UseEquipment)",
        func = function()
            local bot = sharedBot()
            expect(lib().Count(bot, "lethal")).to.equal(0)
            expect(must(lib().Use)(bot, "lethal")).to.beTrue()
            expect(test.uses[1].self).to.equal(entryOf(bot, "lethal").instance)
            expect(test.uses[1].owner).to.equal(bot)
            expect(lib().Count(bot, "lethal")).to.equal(1)
            local tactics = must(PW.BotTactics)
            test.now = test.now + lib().Cooldown
            ---@type table
            local raw = { _api = {}, bot = bot }
            local ctx = raw --[[@as PW.BotBrainCtx]]
            expect(tactics.UseEquipment(ctx, "lethal")).to.beTrue()
            expect(lib().Count(bot, "lethal")).to.equal(0)
            test.now = test.now + lib().Cooldown
            expect(tactics.UseEquipment(ctx, "lethal")).to.beFalse()
        end
    }
}

local wiringCases = {
    {
        name = "Wiring: the kind, the sample items, the slots and the default loadout",
        func = function()
            local registry = must(PW.Registries.equipment)
            local frag, flash = must(registry.Get("frag")), must(registry.Get("flash"))
            expect(frag.Category).to.equal("lethal")
            expect(flash.Category).to.equal("tactical")
            expect(frag.Count >= 1 and flash.Count >= 1).to.beTrue()
            local loadout = must(PW.Loadout)
            local lethal, tactical = must(loadout.GetSlot("lethal")), must(loadout.GetSlot("tactical"))
            expect(lethal.kind).to.equal("equipment")
            expect(lethal.key).to.equal("pw_lethal")
            expect(tactical.key).to.equal("pw_tactical")
            local default = loadout.Default()
            expect(default.lethal).to.equal("frag")
            expect(default.tactical).to.equal("flash")
            expect(loadout.Validate(fakePlayer(), default)).to.beTrue()
            expect(loadout.Validate(fakePlayer(), { lethal = "flash" })).to.beFalse()
        end
    },
    {
        name = "Wiring: no use message any more (the slot key selects the grenade SWEP); pw_blind is registered",
        func = function()
            expect(rawget(lib(), "NetName")).to.beNil()
            expect(must(PW._Net).defs.pw_equipment_use).to.beNil()
            expect(util.NetworkStringToID("pw_blind")).toNot.equal(0)
        end
    }
}

---@param bot Player
---@param fail fun(message: string)
local function throwFrag(bot, fail)
    if not IsValid(bot) then return fail("the shared bot is gone") end
    if not bot:Alive() then bot:Spawn() end
    local before = lib().Count(bot, "lethal")
    if before < 1 then return fail("the bot has no frag after spawn: " .. before) end
    if not must(lib().Use)(bot, "lethal") then return fail("Use refused the frag") end
    if lib().Count(bot, "lethal") ~= before - 1 then return fail("the count did not drop") end
    local found = false
    for _, ent in ipairs(ents.FindByClass(throw().EntityClass)) do
        if ent:GetOwner() == bot then found = true end
        ent:Remove()
    end
    if not found then return fail("no grenade of the bot") end
    test.thrown = true
end

local gameCases = {
    {
        name = "In-game: in a LIVE test match the shared bot throws a frag and its count drops",
        async = true,
        timeout = 20,
        func = function()
            PW._Equipment = test.previousEquipment
            ---@type table<string, string>
            local saved = {}
            for _, name in ipairs(phaseConVars) do saved[name] = must(GetConVar(name)):GetString() end
            local function restore()
                for name, value in pairs(saved) do must(GetConVar(name)):SetString(value) end
                must(throw()._RemoveAll)()
            end
            must(GetConVar("pw_prematch_timeout")):SetString("0")
            must(GetConVar("pw_countdown")):SetString("0")
            must(GetConVar("pw_postmatch_time")):SetString("0.5")
            must(GetConVar("pw_aftermatch")):SetString("lobby")
            expect(match().GetPhase()).to.equal("LOBBY")
            expect(match().Start(must(PW.Modes.Get("tdm")))).to.beTrue()
            local function fail(message)
                restore()
                if match().GetPhase() ~= "LOBBY" then match().Abort("equipment smoke: " .. message) end
                error(message, 0)
            end
            local function waitFor(phase, deadline, after)
                if match().GetPhase() == phase then return after() end
                if CurTime() > deadline then fail("phase " .. phase .. " not reached, still " .. match().GetPhase()) end
                timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
            end
            waitFor("LIVE", CurTime() + 5, function()
                -- Taken in LIVE: entering LOBBY (an earlier group's match) kicks every bot a tick later.
                local bot = sharedBot()
                timer.Simple(0.5, function()
                    throwFrag(bot, fail)
                    match().Abort("equipment smoke done")
                    waitFor("LOBBY", CurTime() + 5, function()
                        restore()
                        expect(test.thrown).to.beTrue()
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
    groupName = "PW equipment",
    beforeEach = function()
        test.previousEquipment = PW._Equipment
        test.now, test.phase, test.alive, test.refuse, test.thrown = 1000, "LIVE", true, false, false
        installStore()
    end,
    afterEach = function()
        local store = PW._Equipment
        if store ~= nil and store ~= test.previousEquipment then
            for ply in pairs(store.players) do must(lib()._Clear)(ply) end
        end
        PW._Equipment = test.previousEquipment
    end,
    afterAll = function()
        local created = test.created
        if created ~= nil and IsValid(created) then created:Kick("equipment tests done") end
    end,
    cases = join(pureCases, moduleCases, wiringCases, gameCases)
}
