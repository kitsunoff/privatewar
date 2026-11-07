-- T-11.7 stat-based unlock levels (TASKS.md, "Mandatory test cases" Phase 11 T-11.7; 06-progression.md d.2 revision
-- 2026-11-07; docs/api/progression.md "Automatic unlock levels"). Pure cases on fake stats; Run cases with a fake
-- adapter, an in-memory cache file and fresh weapons registries (the engine registry is not touched). The live case
-- needs ARC9 and is skipped without it.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.AutoUnlockLib
local function lib()
    return must(PW.AutoUnlock)
end

---@return PW.AutoUnlockWeights
local function weights()
    return table.Copy(lib().Weights)
end

local caps = { maxLevel = 55, maxWeaponLevel = 30 }

---A plain AR: 30 damage near, 20 far, 700 rpm.
---@param fields? table<string, any>
---@return PW.Stats
local function stats(fields)
    local value = { damageNear = 30, damageFar = 20, rangeNear = 10, rangeFar = 40, rpm = 700, recoil = 1,
        spread = 0.01, adsTime = 0.3, sprintToFire = 0.3, moveMult = 0.9, magazine = 30 }
    for key, field in pairs(fields or {}) do value[key] = field end
    return value
end

---The score of class "a" in a category with two fixed neighbours.
---@param a PW.Stats
---@return number
local function scoreOfA(a)
    local w = weights()
    local features = {
        a = lib()._WeaponFeatures(a, w),
        b = lib()._WeaponFeatures(stats({ damageNear = 20, damageFar = 15, rpm = 600, recoil = 2, spread = 0.02,
            adsTime = 0.4, sprintToFire = 0.4, moveMult = 0.8 }), w),
        c = lib()._WeaponFeatures(stats({ damageNear = 50, damageFar = 40, rpm = 900, recoil = 0.5, spread = 0.005,
            adsTime = 0.2, sprintToFire = 0.2, moveMult = 1 }), w)
    }
    return lib()._ScoreCategory(features, w).a
end

---@param class string
---@param category string
---@param fields? table<string, any>
---@param slots? PW.AutoUnlockSlot[]
---@return PW.AutoUnlockWeapon
local function weapon(class, category, fields, slots)
    return { class = class, category = category, stats = stats(fields), slots = slots or {} }
end

---A fake adapter: stats, slots and options from tables.
---@param data table fields stats, slots, options ("class|slot"), optionStats (by option id), setKey
---@return PW.Adapter
local function fakeAdapter(data)
    return {
        ClassName = "fake",
        IsAvailable = function() return true end,
        Claims = function() return true end,
        ListWeapons = function() return {} end,
        GetBaseStats = function(_, class) return data.stats[class] or {} end,
        GetSlots = function(_, class) return (data.slots or {})[class] or {} end,
        GetOptions = function(_, class, slot) return (data.options or {})[class .. "|" .. slot] or {} end,
        GetOptionStats = function(_, _, _, option) return (data.optionStats or {})[option] end,
        GetOptionSetKey = function() return data.setKey or "set1" end
    } --[[@as PW.Adapter]]
end

---A fake environment: settings, one adapter for every class, an in-memory file system; counts calls by method.
---@param adapter PW.Adapter
---@param opts? { enabled?: boolean, files?: table<string, string> }
---@return PW.AutoUnlockEnv env, table<string, integer> calls, string[] logs, table<string, string> files
local function fakeEnv(adapter, opts)
    opts = opts or {}
    local files = opts.files or {}
    ---@type table<string, integer>
    local calls = {}
    ---@type string[]
    local logs = {}
    local env = {
        setting = function(id)
            if id == "progression.autounlock" then return opts.enabled ~= false end
            if id == "progression.maxlevel" then return 55 end
            if id == "progression.maxweaponlevel" then return 30 end
            return nil
        end,
        adapterFor = function() return adapter end,
        call = function(target, method, ...)
            calls[method] = (calls[method] or 0) + 1
            local fn = (target --[[@as table<string, any>]])[method]
            if isfunction(fn) then return fn(target, ...) end
            return nil
        end,
        read = function(path) return files[path] end,
        write = function(path, text) files[path] = text end,
        hash = function(text) return util.CRC(text) .. ":" .. #text end,
        clock = SysTime,
        log = function(message) logs[#logs + 1] = message end
    }
    return env, calls, logs, files
end

---A fresh, resolved weapons registry holding the given entries.
---@param entries table<string, table<string, any>>
---@return PW.Registry
local function registry(entries)
    local reg = PW.Registry.New("weapons", { log = function() end })
    for class, fields in pairs(entries) do reg.Register(table.Copy(fields), class) end
    reg.ResolveAll()
    return reg
end

---Four ARs and two pistols with stats from weak to strong, and one AR slot with options.
---@return table<string, table<string, any>> entries, table data
local function fixture()
    local entries = {
        ar_a = { Category = "ar", Kind = "gun" }, ar_b = { Category = "ar", Kind = "gun" },
        ar_c = { Category = "ar", Kind = "gun" }, ar_d = { Category = "ar", Kind = "gun" },
        pi_a = { Category = "pistol", Kind = "gun" }, pi_b = { Category = "pistol", Kind = "gun" },
        knife = { Kind = "melee" }
    }
    local data = {
        stats = {
            ar_a = stats({ damageNear = 20 }), ar_b = stats({ damageNear = 25 }), ar_c = stats({ damageNear = 30 }),
            ar_d = stats({ damageNear = 40 }), pi_a = stats({ damageNear = 15, rpm = 400 }),
            pi_b = stats({ damageNear = 50, rpm = 200 })
        },
        slots = { ar_a = { { id = "1", name = "Muzzle", cosmetic = false },
            { id = "2", name = "Skin", cosmetic = true } } },
        options = {
            ["ar_a|1"] = { { id = "comp", name = "Comp", cosmetic = false },
                { id = "supp", name = "Supp", cosmetic = false }, { id = "flash", name = "Flash", cosmetic = false },
                { id = "dummy", name = "Dummy", cosmetic = false } },
            ["ar_a|2"] = { { id = "gold", name = "Gold", cosmetic = true } }
        },
        optionStats = { comp = { recoil = 0.8 }, supp = { recoil = 0.9, range = 1.1, adsTime = 1.05 },
            flash = { spread = 0.98 } }
    }
    return entries, data
end

---Live case: prints a few weapons per category (weakest, middle, strongest) and a few options per slot of one gun.
---@param result PW.AutoUnlockResult
local function printSamples(result)
    ---@type table<string, string[]>
    local byCategory = {}
    for class in pairs(result.weapons) do
        local entry = must(PW.Weapons).Get(class)
        local category = entry ~= nil and entry.Category or "?"
        byCategory[category] = byCategory[category] or {}
        table.insert(byCategory[category], class)
    end
    ---@type string[]
    local categories = table.GetKeys(byCategory) --[[@as string[] ]]
    table.sort(categories)
    for _, category in ipairs(categories) do
        local classes = byCategory[category]
        table.sort(classes, function(a, b)
            if result.weapons[a] ~= result.weapons[b] then return result.weapons[a] < result.weapons[b] end
            return a < b
        end)
        ---@type string[]
        local out = {}
        for _, i in ipairs({ 1, 2, 3, math.floor(#classes / 2), #classes - 1, #classes }) do
            local class = classes[i]
            if class ~= nil then out[#out + 1] = class .. "=" .. result.weapons[class] end
        end
        print(string.format("[PW] autounlock sample %s (%d): %s", category, #classes, table.concat(out, " ")))
    end
end

---Live case: the options of the first slots of one gun with their levels.
---@param result PW.AutoUnlockResult
---@param class string
local function printOptions(result, class)
    local adapter = must(PW.Adapters.For(class))
    local levels = result.attachments[class] or {}
    for index, slot in ipairs(PW.Adapters.Call(adapter, "GetSlots", class, nil) --[[@as PW.Slot[] ]]) do
        if index > 6 then break end
        ---@type string[]
        local out = {}
        for _, option in ipairs(PW.Adapters.Call(adapter, "GetOptions", class, slot.id) --[[@as PW.Option[] ]]) do
            if levels[option.id] ~= nil then out[#out + 1] = option.id .. "=" .. levels[option.id] end
        end
        table.sort(out)
        print(string.format("[PW] autounlock sample %s slot %s %s: %s", class, slot.id, slot.name,
            table.concat(out, " ", 1, math.min(#out, 8))))
    end
end

return {
    groupName = "PW stat-based unlock levels",
    cases = {
        {
            name = "Score: more damage and rate of fire raise it, more recoil and spread lower it",
            func = function()
                local base = scoreOfA(stats())
                expect(scoreOfA(stats({ damageNear = 36, damageFar = 24 }))).to.beGreaterThan(base)
                expect(scoreOfA(stats({ rpm = 800 }))).to.beGreaterThan(base)
                expect(scoreOfA(stats({ recoil = 1.5 }))).to.beLessThan(base)
                expect(scoreOfA(stats({ spread = 0.015 }))).to.beLessThan(base)
                expect(scoreOfA(stats({ adsTime = 0.35 }))).to.beLessThan(base)
                expect(scoreOfA(stats({ moveMult = 0.95 }))).to.beGreaterThan(base)
            end
        },
        {
            name = "Rank: stable, ties broken by class",
            func = function()
                local scores = { c = 1, a = 1, b = 0.5, d = 2 }
                expect(table.concat(lib()._Rank(scores), ",")).to.equal("b,a,c,d")
                expect(table.concat(lib()._Rank(table.Copy(scores)), ",")).to.equal("b,a,c,d")
            end
        },
        {
            name = "Spread: levels 1..55, 1-2 weapons per category open at level 1",
            func = function()
                ---@type PW.AutoUnlockWeapon[]
                local list = {}
                for i = 1, 8 do list[#list + 1] = weapon("ar_" .. i, "ar", { damageNear = 20 + i * 3 }) end
                list[#list + 1] = weapon("pi_1", "pistol", { damageNear = 15 })
                list[#list + 1] = weapon("pi_2", "pistol", { damageNear = 40 })
                list[#list + 1] = weapon("sg_1", "shotgun", { damageNear = 80 })
                local result = lib()._Compute(list, weights(), caps)
                local levels = result.weapons
                expect(levels.ar_1).to.equal(1)
                expect(levels.ar_2).to.equal(1)
                expect(levels.ar_3).to.beGreaterThan(1)
                for i = 3, 8 do
                    expect(levels["ar_" .. i]).to.beLessThan(56)
                    if i > 3 then expect(levels["ar_" .. i]).to.beGreaterThan(levels["ar_" .. (i - 1)] - 1) end
                end
                expect(levels.ar_8).to.beGreaterThan(40)
                expect(levels.pi_1).to.equal(1)
                expect(levels.pi_2).to.beGreaterThan(1)
                expect(levels.sg_1).to.equal(1)
                expect(result.report.weapons).to.equal(11)
                expect(result.report.categories).to.equal(3)
                expect(table.concat(lib()._Spread(4, 2, 55), ",")).to.equal("1,1,19,37")
            end
        },
        {
            name = "Attachments: ranked within the slot by stat gain, spread over 1..30",
            func = function()
                local slot = { id = "1", options = {
                    { id = "best", stats = { damage = 1.2, recoil = 0.8 } },
                    { id = "worst", stats = { damage = 0.8, recoil = 1.3 } },
                    { id = "mid", stats = { recoil = 0.95 } }
                } }
                local res = lib()._SlotLevels(slot, stats(), weights(), 30)
                expect(res.noStats).to.equal(0)
                expect(res.levels.worst).to.beLessThan(res.levels.mid)
                expect(res.levels.mid).to.beLessThan(res.levels.best)
                expect(res.levels.worst).to.beGreaterThan(0)
                expect(res.levels.best).to.beLessThan(31)
                expect(lib()._OptionGain({ damage = 1.1 }, stats(), weights())).to.beGreaterThan(0)
                expect(lib()._OptionGain({ adsTime = 1.1 }, stats(), weights())).to.beLessThan(0)
                expect(lib()._OptionGain({ magazineAdd = 10 }, stats(), weights())).to.beGreaterThan(0)
            end
        },
        {
            name = "Attachments: an option without numeric stats gets the middle level and is counted",
            func = function()
                local slot = { id = "1", options = {
                    { id = "a", stats = { recoil = 0.9 } }, { id = "b", stats = { recoil = 0.8 } },
                    { id = "c", stats = { recoil = 0.7 } }, { id = "plain" }
                } }
                local res = lib()._SlotLevels(slot, stats(), weights(), 30)
                expect(res.noStats).to.equal(1)
                expect(res.levels.plain).to.equal(math.floor((res.levels.a + res.levels.c) / 2 + 0.5))
                local only = lib()._SlotLevels({ id = "2", options = { { id = "x" } } }, stats(), weights(), 30)
                expect(only.levels.x).to.equal(16)
                local result = lib()._Compute({ weapon("w", "ar", nil, { slot }) }, weights(), caps)
                expect(result.report.noStats).to.equal(1)
                expect(result.report.options).to.equal(4)
            end
        },
        {
            name = "Few stats (HL2 weapons): levels still assigned, missing stats count as the middle",
            func = function()
                local list = {
                    { class = "weapon_pistol", category = "pistol", stats = { damageNear = 8, rpm = 400 }, slots = {} },
                    { class = "weapon_357", category = "pistol", stats = { damageNear = 75, rpm = 70 }, slots = {} },
                    { class = "nothing", category = "pistol", stats = {}, slots = {} }
                }
                local result = lib()._Compute(list, weights(), caps)
                expect(result.weapons.weapon_pistol).to.equal(1)
                expect(result.weapons.weapon_357).to.beGreaterThan(1)
                expect(result.weapons.nothing).to.beGreaterThan(0)
            end
        },
        {
            name = "Starters: weapons of the preset classes open at level 1 and count toward the open weapons",
            func = function()
                ---@type PW.AutoUnlockWeapon[]
                local list = {}
                for i = 1, 6 do list[#list + 1] = weapon("ar_" .. i, "ar", { damageNear = 20 + i * 3 }) end
                list[6].starter = true
                local levels = lib()._Compute(list, weights(), caps).weapons
                expect(levels.ar_6).to.equal(1)
                expect(levels.ar_1).to.equal(1)
                expect(levels.ar_2).to.beGreaterThan(1)
                local presets = lib()._PresetWeapons(must(PW.Classes))
                expect(presets.weapon_ar2).to.beTrue()
                expect(presets.weapon_pistol).to.beTrue()
            end
        },
        {
            name = "Cache key: the same sets give the same key, a changed set another",
            func = function()
                local hash = function(text) return util.CRC(text) .. ":" .. #text end
                local parts = { weapons = { "ar_a|ar", "ar_b|ar" }, options = { "fake:set1" }, caps = caps }
                local same = { caps = caps, options = { "fake:set1" }, weapons = { "ar_a|ar", "ar_b|ar" } }
                expect(lib()._CacheKey(parts, hash)).to.equal(lib()._CacheKey(same, hash))
                local more = { weapons = { "ar_a|ar", "ar_b|ar", "ar_c|ar" }, options = { "fake:set1" }, caps = caps }
                expect(lib()._CacheKey(more, hash)).notTo.equal(lib()._CacheKey(parts, hash))
                local atts = { weapons = { "ar_a|ar", "ar_b|ar" }, options = { "fake:set2" }, caps = caps }
                expect(lib()._CacheKey(atts, hash)).notTo.equal(lib()._CacheKey(parts, hash))
            end
        },
        {
            name = "Run: computes and caches, reuses the cache when the set is unchanged, recomputes when it changes",
            func = function()
                local entries, data = fixture()
                local env, calls, _, files = fakeEnv(fakeAdapter(data))
                local first = lib().Run(registry(entries), env)
                expect(first.cacheHit).to.beFalse()
                expect(first.registered).to.equal(6)
                expect(files[lib().CachePath]).toNot.beNil()
                local statCalls = calls.GetBaseStats
                expect(statCalls).to.equal(6)
                local reg = registry(entries)
                local second = lib().Run(reg, env)
                expect(second.cacheHit).to.beTrue()
                expect(calls.GetBaseStats).to.equal(statCalls)
                expect(must(reg.Get("ar_d")).Unlock).to.equal(must(first.result).weapons.ar_d)
                entries.ar_e = { Category = "ar", Kind = "gun" }
                data.stats.ar_e = stats({ damageNear = 60 })
                local third = lib().Run(registry(entries), env)
                expect(third.cacheHit).to.beFalse()
                expect(calls.GetBaseStats).to.equal(statCalls + 7)
                expect(must(third.result).weapons.ar_e).toNot.beNil()
            end
        },
        {
            name = "Run: soft registration, hand curation wins option by option",
            func = function()
                local entries, data = fixture()
                entries.ar_d.Unlock = 3
                entries.ar_a.Attachments = { comp = { Unlock = 29 }, supp = { Cost = 2 } }
                local reg = registry(entries)
                local env = fakeEnv(fakeAdapter(data))
                local run = lib().Run(reg, env)
                local result = must(run.result)
                expect(must(reg.Get("ar_d")).Unlock).to.equal(3)
                expect(must(reg.Get("ar_c")).Unlock).to.equal(result.weapons.ar_c)
                local atts = must(must(reg.Get("ar_a")).Attachments) --[[@as table<string, table<string, any>>]]
                expect(atts.comp.Unlock).to.equal(29)
                expect(atts.supp.Cost).to.equal(2)
                expect(atts.supp.Unlock).to.equal(result.attachments.ar_a.supp)
                expect(atts.flash.Unlock).to.equal(result.attachments.ar_a.flash)
                expect(atts.gold).to.beNil()
                expect(must(reg.Get("knife")).Unlock).to.beNil()
            end
        },
        {
            name = "Merge: a weapon with a Price stays shop-only; curated fields are never overwritten",
            func = function()
                expect(lib()._EntryFor({ Price = 500 }, 12, nil)).to.beNil()
                local entry = must(lib()._EntryFor({ Unlock = 4 }, 12, { a = 3 }))
                expect(entry.Unlock).to.beNil()
                expect(entry.Attachments.a.Unlock).to.equal(3)
                expect(must(lib()._EntryFor({}, 12, nil)).Unlock).to.equal(12)
            end
        },
        {
            name = "Setting off: no levels, the unlock by count stays",
            func = function()
                local entries, data = fixture()
                local reg = registry(entries)
                local env, calls = fakeEnv(fakeAdapter(data), { enabled = false })
                local run = lib().Run(reg, env)
                expect(run.enabled).to.beFalse()
                expect(run.registered).to.equal(0)
                expect(calls.GetBaseStats).to.beNil()
                local ar = must(reg.Get("ar_a"))
                expect(ar.Unlock).to.beNil()
                expect(ar.Attachments).to.beNil()
                local view = { level = 1, unlockAll = false, maxAttachments = 5,
                    weaponLevel = function() return 1 end,
                    lookup = function(_, id) return reg.Get(id) end }
                local locked = PW.Progression._LockedOptions(view --[[@as PW.ProgressionView]], "ar_a",
                    { ["1"] = "comp", ["3"] = "flash" })
                expect(locked.comp).to.beNil()
                expect(locked.flash).to.beTrue()
            end
        },
        {
            name = "ARC9 option stats: Mult, Add against the base value, Override; nothing numeric gives nil",
            skip = rawget(PW, "Arc9") == nil,
            func = function()
                local arc9 = must(PW.Arc9)
                local base = { AimDownSightsTime = 0.4, Recoil = 2 }
                local s = must(arc9._OptionStats({ RecoilMult = 0.8, AimDownSightsTimeAdd = 0.1, ClipSizeAdd = 10,
                    DamageMaxMult = 1.2 }, base))
                expect(s.recoil).to.aboutEqual(0.8)
                expect(s.adsTime).to.aboutEqual(1.25)
                expect(s.magazineAdd).to.equal(10)
                expect(s.damage).to.aboutEqual(math.sqrt(1.2))
                expect(must(arc9._OptionStats({ RecoilOverride = 1 }, base)).recoil).to.aboutEqual(0.5)
                expect(arc9._OptionStats({ PrintName = "Skin", SortOrder = 3 }, base)).to.beNil()
                expect(arc9._OptionStats({ SprintToFireTimeAdd = 0.1 }, {})).to.beNil()
            end
        },
        {
            name = "Live: ARC9 weapons got levels; the computation time is logged",
            skip = rawget(_G, "ARC9") == nil,
            func = function()
                local env = lib()._DefaultEnv()
                env.read = function() return nil end
                env.write = function() end
                local run = lib().Run(must(PW.Weapons), env)
                local result = must(run.result)
                local arc9 = 0
                for class in pairs(result.weapons) do
                    if weapons.IsBasedOn(class, "arc9_base") then arc9 = arc9 + 1 end
                end
                print(string.format("[PW] autounlock live: %d ARC9 weapons of %d got levels, %d options (%d without " ..
                    "stats), computed in %.1f ms", arc9, result.report.weapons, result.report.options,
                    result.report.noStats, run.ms))
                expect(arc9).to.beGreaterThan(0)
                expect(result.report.options).to.beGreaterThan(0)
                expect(result.weapons.weapon_ar2).to.equal(1)
                printSamples(result)
                ---@type string?
                local sample = nil
                ---@type string[]
                local classes = table.GetKeys(result.attachments) --[[@as string[] ]]
                table.sort(classes)
                for _, class in ipairs(classes) do
                    local count = table.Count(result.attachments[class])
                    if sample == nil and weapons.IsBasedOn(class, "arc9_base") and count > 20 then sample = class end
                end
                if sample ~= nil then printOptions(result, sample) end
                local cached = PW._AutoUnlock and PW._AutoUnlock.last
                expect(cached).toNot.beNil()
            end
        }
    }
}
