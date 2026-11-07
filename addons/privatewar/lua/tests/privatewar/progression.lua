-- T-4.9 Progression (TASKS.md, "Mandatory test cases" T-4.9; 06-progression.md d.1, d.2, d.4). Pure cases over plain
-- numbers, a fake catalogue and player stand-ins (a table with IsValid, IsBot and SetNW2Int); no bots, no real
-- players. The server cases run over a fresh store with injected settings, publisher and notifier.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.ProgressionLib
local function lib()
    return must(PW.Progression)
end

---@param over? table<string, any>
---@return fun(id: string): any
local function reader(over)
    local values = over or {}
    return function(id) return values[id] end
end

---@return Player
local function fakePlayer()
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.IsBot = function() return false end
    fake.SetNW2Int = function() end
    return fake --[[@as Player]]
end

---@param class string
---@return Weapon
local function fakeWeapon(class)
    ---@type table<string, any>
    local fake = {}
    fake.IsValid = function() return true end
    fake.GetClass = function() return class end
    return fake --[[@as Weapon]]
end

---@class PW.ProgressionTestRig
---@field store PW.ProgressionStore
---@field published table[]
---@field notes table[]

---@param settings? table<string, any>
---@return PW.ProgressionTestRig
local function rig(settings)
    ---@type table[]
    local published = {}
    ---@type table[]
    local notes = {}
    local store = lib()._NewStore({
        read = reader(settings),
        publish = function(ply, level, into, need) published[#published + 1] = { ply, level, into, need } end,
        notify = function(name, ...) notes[#notes + 1] = { name, ... } end
    })
    return { store = store, published = published, notes = notes }
end

local catalogue = {
    weapons = {
        pwt_plain = { Category = "ar" },
        pwt_locked = { Category = "ar", Unlock = 10 },
        pwt_table = { Category = "ar", Unlock = { level = 20 } },
        pwt_curated = {
            Category = "ar",
            Attachments = {
                optic = { Unlock = 5 }, supp = { Unlock = 12, Cost = 2 }, meme = { Hidden = true },
                grip = {}, laser = {}, tint = { Cosmetic = true }
            },
            Camos = { gold = { Unlock = 30 }, plain = {} }
        }
    },
    perks = { pwt_perk = { Unlock = 3 } }
}

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

---@param level integer
---@param weaponLevel integer
---@param unlockAll? boolean
---@return PW.ProgressionView
local function view(level, weaponLevel, unlockAll)
    return {
        level = level, weaponLevel = function() return weaponLevel end, lookup = lookup,
        unlockAll = unlockAll == true, maxAttachments = 5
    }
end

return {
    groupName = "PW progression",
    cases = {
        {
            name = "XP curve: XP to next level at levels 1, 10 and 55, and the level cap",
            func = function()
                local p = lib().Defaults
                expect(lib()._XpToNext(1, p.xpBase, p.xpExp)).to.equal(1000)
                expect(lib()._XpToNext(10, p.xpBase, p.xpExp)).to.equal(math.floor(1000 * 10 ^ 1.2))
                expect(lib()._XpToNext(10, p.xpBase, p.xpExp)).to.equal(15848)
                expect(lib()._XpToNext(55, p.xpBase, p.xpExp)).to.equal(math.floor(1000 * 55 ^ 1.2))
                expect(lib()._XpToNext(55, p.xpBase, p.xpExp)).to.equal(122584)
                expect(p.maxLevel).to.equal(55)
                expect(p.maxWeaponLevel).to.equal(30)
                expect(lib()._XpToNext(1, p.weaponBase, p.weaponExp)).to.equal(500)
            end
        },
        {
            name = "XP curve: level from XP at the boundaries; the maximum level is a full bar",
            func = function()
                local p = lib().Defaults
                local level, into, need = lib()._PlayerLevel(p, 0)
                expect(level).to.equal(1)
                expect(into).to.equal(0)
                expect(need).to.equal(1000)
                level, into = lib()._PlayerLevel(p, 999)
                expect(level).to.equal(1)
                expect(into).to.equal(999)
                level, into, need = lib()._PlayerLevel(p, 1000)
                expect(level).to.equal(2)
                expect(into).to.equal(0)
                expect(need).to.equal(lib()._XpToNext(2, p.xpBase, p.xpExp))
                local toTen = lib()._XpForLevel(10, p.xpBase, p.xpExp)
                expect(lib()._PlayerLevel(p, toTen - 1)).to.equal(9)
                expect(lib()._PlayerLevel(p, toTen)).to.equal(10)
                local toMax = lib()._XpForLevel(55, p.xpBase, p.xpExp)
                expect(lib()._PlayerLevel(p, toMax - 1)).to.equal(54)
                level, into, need = lib()._PlayerLevel(p, toMax * 3)
                expect(level).to.equal(55)
                expect(need).to.equal(0)
                expect(lib()._Fraction(into, need)).to.equal(1)
                expect(lib()._Fraction(250, 1000)).to.equal(0.25)
                expect(lib()._WeaponLevel(p, 500)).to.equal(2)
            end
        },
        {
            name = "Settings: the coefficients and unlockall come from the reader, the design defaults fill the rest",
            func = function()
                local d = lib()._Params(reader())
                expect(d.maxLevel).to.equal(55)
                expect(d.xpBase).to.equal(1000)
                expect(d.xpExp).to.equal(1.2)
                expect(d.weaponBase).to.equal(500)
                expect(d.weaponExp).to.equal(1.1)
                expect(d.xpScale).to.equal(1)
                expect(d.unlockAll).to.beFalse()
                local custom = lib()._Params(reader({
                    ["progression.maxlevel"] = 10, ["progression.xpbase"] = 200, ["progression.unlockall"] = true,
                    ["progression.xpscale"] = 2
                }))
                expect(custom.maxLevel).to.equal(10)
                expect(custom.xpBase).to.equal(200)
                expect(custom.xpScale).to.equal(2)
                expect(custom.unlockAll).to.beTrue()
            end
        },
        {
            name = "Weapon XP comes only from events that carry a weapon; player XP from every event",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 100, fakeWeapon("pwt_plain"))
                lib()._OnScoreEvent(r.store, ply, "dom_capture", 200, 200, nil)
                local state = lib()._GetState(r.store, ply)
                expect(state.xp).to.equal(300)
                expect(state.weapons.pwt_plain).to.equal(100)
                local count = 0
                for _ in pairs(state.weapons) do count = count + 1 end
                expect(count).to.equal(1)
                -- A weapon without a class, an invalid weapon and an event without XP add nothing to any weapon.
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 0, fakeWeapon("pwt_plain"))
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 50, {} --[[@as Weapon]])
                state = lib()._GetState(r.store, ply)
                expect(state.weapons.pwt_plain).to.equal(100)
                expect(state.xp).to.equal(350)
            end
        },
        {
            name = "XP scale multiplies both player and weapon XP; bots earn nothing",
            func = function()
                local r = rig({ ["progression.xpscale"] = 2 })
                local ply = fakePlayer()
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 100, fakeWeapon("pwt_plain"))
                local state = lib()._GetState(r.store, ply)
                expect(state.xp).to.equal(200)
                expect(state.weapons.pwt_plain).to.equal(200)
                local bot = fakePlayer()
                ---@diagnostic disable-next-line: duplicate-set-field
                bot.IsBot = function() return true end
                lib()._OnScoreEvent(r.store, bot, "kill", 100, 100, fakeWeapon("pwt_plain"))
                expect(lib()._GetState(r.store, bot).xp).to.equal(0)
            end
        },
        {
            name = "Level ups: published to the owner and notified for the player and for the weapon",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                lib()._OnScoreEvent(r.store, ply, "kill", 100, 1000, fakeWeapon("pwt_plain"))
                local last = r.published[#r.published]
                expect(last[1]).to.equal(ply)
                expect(last[2]).to.equal(2)
                expect(last[3]).to.equal(0)
                ---@type table<string, table>
                local byName = {}
                for _, note in ipairs(r.notes) do byName[note[1]] = note end
                local up = must(byName.PW_ProgressionLevelUp)
                expect(up[2]).to.equal(ply)
                expect(up[3]).to.equal(2)
                expect(up[4]).to.equal(1)
                local weaponUp = must(byName.PW_ProgressionWeaponLevelUp)
                expect(weaponUp[3]).to.equal("pwt_plain")
                expect(weaponUp[4]).to.equal(2)
                expect(weaponUp[5]).to.equal(1)
                expect(must(byName.PW_ProgressionXP)[3]).to.equal(1000)
            end
        },
        {
            name = "State shape: SetState sanitises, GetState returns a copy",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                local dirty = { xp = 2500, weapons = { pwt_plain = 700, bad = -5, worse = "x" } }
                lib()._SetState(r.store, ply, dirty --[[@as PW.ProgressionState]])
                local state = lib()._GetState(r.store, ply)
                expect(state.xp).to.equal(2500)
                expect(state.weapons.pwt_plain).to.equal(700)
                expect(state.weapons.bad).to.beNil()
                expect(state.weapons.worse).to.beNil()
                state.xp = 0
                expect(lib()._GetState(r.store, ply).xp).to.equal(2500)
                local junk = { xp = -10, weapons = "nope" }
                lib()._SetState(r.store, ply, junk --[[@as any]])
                expect(lib()._GetState(r.store, ply).xp).to.equal(0)
                expect(lib()._Level(r.store, ply)).to.equal(1)
            end
        },
        {
            name = "Unlock by curation: the player level for entities, the weapon level for options and camos",
            func = function()
                local at = function(level, weaponLevel) return view(level, weaponLevel) end
                expect(lib()._IsUnlocked(at(1, 1), "weapons", "pwt_plain")).to.beTrue()
                expect(lib()._IsUnlocked(at(9, 1), "weapons", "pwt_locked")).to.beFalse()
                expect(lib()._IsUnlocked(at(10, 1), "weapons", "pwt_locked")).to.beTrue()
                expect(lib()._IsUnlocked(at(19, 1), "weapons", "pwt_table")).to.beFalse()
                expect(lib()._IsUnlocked(at(20, 1), "weapons", "pwt_table")).to.beTrue()
                expect(lib()._IsUnlocked(at(2, 1), "perks", "pwt_perk")).to.beFalse()
                expect(lib()._IsUnlocked(at(3, 1), "perks", "pwt_perk")).to.beTrue()
                expect(lib()._IsUnlocked(at(55, 30), "weapons", "pwt_missing")).to.beFalse()
                expect(lib()._IsUnlocked(at(55, 4), "attachments", "pwt_curated:optic")).to.beFalse()
                expect(lib()._IsUnlocked(at(1, 5), "attachments", "pwt_curated:optic")).to.beTrue()
                expect(lib()._IsUnlocked(at(1, 11), "attachments", "pwt_curated:supp")).to.beFalse()
                expect(lib()._IsUnlocked(at(1, 12), "attachments", "pwt_curated:supp")).to.beTrue()
                expect(lib()._IsUnlocked(at(55, 30), "attachments", "pwt_curated:meme")).to.beFalse()
                expect(lib()._IsUnlocked(at(1, 29), "camos", "pwt_curated:gold")).to.beFalse()
                expect(lib()._IsUnlocked(at(1, 30), "camos", "pwt_curated:gold")).to.beTrue()
                expect(lib()._IsUnlocked(at(1, 1), "camos", "pwt_curated:plain")).to.beTrue()
                expect(lib()._IsUnlocked(at(1, 1), "attachments", "malformed")).to.beFalse()
            end
        },
        {
            name = "Unlock by count: the weapon level is the number of uncurated attachments, capped by the setting",
            func = function()
                expect(lib()._AttachmentLimit(1, 5)).to.equal(1)
                expect(lib()._AttachmentLimit(3, 5)).to.equal(3)
                expect(lib()._AttachmentLimit(30, 5)).to.equal(5)
                local build = { muzzle = "grip", rail = "laser", optic = "optic" }
                -- Level 1: one counted option (grip, in slot order: muzzle, optic, rail) is kept, laser is locked.
                local locked = lib()._LockedOptions(view(1, 1), "pwt_curated", build)
                expect(locked.laser).to.beTrue()
                expect(locked.grip).to.beNil()
                -- The curated optic (weapon level 5) is locked by curation, not counted.
                expect(locked.optic).to.beTrue()
                locked = lib()._LockedOptions(view(1, 5), "pwt_curated", build)
                expect(locked.laser).to.beNil()
                expect(locked.grip).to.beNil()
                expect(locked.optic).to.beNil()
                -- A cosmetic option is neither counted nor locked by count.
                locked = lib()._LockedOptions(view(1, 1), "pwt_curated", { muzzle = "grip", skin = "tint" })
                expect(next(locked)).to.beNil()
                -- A cleared slot is ignored; an unknown weapon locks nothing.
                expect(next(lib()._LockedOptions(view(1, 1), "pwt_curated", { muzzle = false }))).to.beNil()
                expect(next(lib()._LockedOptions(view(1, 1), "pwt_missing", build))).to.beNil()
            end
        },
        {
            name = "Level from kills: weapon XP of kills raises the weapon level that the count rule reads",
            func = function()
                local r = rig()
                local ply = fakePlayer()
                for _ = 1, 5 do lib()._OnScoreEvent(r.store, ply, "kill", 100, 100, fakeWeapon("pwt_curated")) end
                expect(lib()._WeaponLevelOf(r.store, ply, "pwt_curated")).to.equal(2)
                expect(lib()._WeaponLevelOf(r.store, ply, "pwt_plain")).to.equal(1)
                local v = lib()._ViewOf(r.store, ply, lookup)
                local locked = lib()._LockedOptions(v, "pwt_curated", { a = "grip", b = "laser" })
                expect(next(locked)).to.beNil()
                locked = lib()._LockedOptions(v, "pwt_curated", { a = "grip", b = "laser", c = "meme" })
                expect(locked.meme).to.beTrue()
            end
        },
        {
            name = "unlockall opens every level gate and the count limit; Hidden stays hidden",
            func = function()
                local all = function() return view(1, 1, true) end
                expect(lib()._IsUnlocked(all(), "weapons", "pwt_table")).to.beTrue()
                expect(lib()._IsUnlocked(all(), "perks", "pwt_perk")).to.beTrue()
                expect(lib()._IsUnlocked(all(), "attachments", "pwt_curated:supp")).to.beTrue()
                expect(lib()._IsUnlocked(all(), "camos", "pwt_curated:gold")).to.beTrue()
                expect(lib()._IsUnlocked(all(), "attachments", "pwt_curated:meme")).to.beFalse()
                expect(lib()._IsUnlocked(all(), "weapons", "pwt_missing")).to.beFalse()
                local locked = lib()._LockedOptions(all(), "pwt_curated", { a = "grip", b = "laser", c = "supp" })
                expect(next(locked)).to.beNil()
                local r = rig({ ["progression.unlockall"] = true })
                local v = lib()._ViewOf(r.store, fakePlayer(), lookup)
                expect(v.unlockAll).to.beTrue()
                expect(lib()._IsUnlocked(v, "weapons", "pwt_locked")).to.beTrue()
                local off = lib()._ViewOf(rig().store, fakePlayer(), lookup)
                expect(lib()._IsUnlocked(off, "weapons", "pwt_locked")).to.beFalse()
            end
        },
        {
            name = "The public API exists and the classes repair uses the unlock context",
            func = function()
                expect(lib().IsUnlocked).to.beA("function")
                expect(lib().LockedOptions).to.beA("function")
                expect(lib().GetLevel).to.beA("function")
                local slots = { primary = { id = "primary", kind = "weapons" } }
                ---@type PW.LoadoutContext
                local ctx = {
                    lookup = lookup, budget = 0, maxattachments = 5,
                    isUnlocked = function(kind, id) return not (kind == "weapons" and id == "pwt_locked") end,
                    lockedOptions = function(_, build)
                        ---@type table<string, boolean>
                        local set = {}
                        for _, option in pairs(build) do
                            if option == "optic" then set.optic = true end
                        end
                        return set
                    end
                }
                local repaired, removed = must(PW.Loadout)._RepairClass(slots, { primary = "pwt_locked" }, ctx)
                expect(repaired.primary).to.beNil()
                expect(#removed).to.equal(1)
                repaired = must(PW.Loadout)._RepairClass(slots, {
                    primary = "pwt_curated", builds = { primary = { optic = "optic", muzzle = "grip" } }
                }, ctx)
                local builds = repaired.builds --[[@as table<string, table<string, string|false>> ]]
                expect(builds.primary.muzzle).to.equal("grip")
                expect(builds.primary.optic).to.beNil()
            end
        }
    }
}
