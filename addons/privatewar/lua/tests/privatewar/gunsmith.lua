-- T-4.8 Gunsmith server flow: validation on save; partial application repairs the class and sends one message
-- (TASKS.md, "Mandatory test cases" T-4.8; 05-loadout.md d.15, d.12). Also: apply on spawn calls the adapter with the
-- build; the HL2 fallback (no gunsmith) is a no-op with a debug log; repair removes only the offending options; the
-- attachment limit includes wildcards and progression. Pure cases over fake adapter data (offered options, a static
-- conflict rule); the glue cases use a stand-in player, a fresh class store and stubbed adapter or progression calls.
-- No bot is created.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LoadoutLib
local function loadout()
    return must(PW.Loadout)
end

local catalogue = {
    weapons = {
        pwg_ar = {
            Category = "ar",
            Attachments = { acog = { Unlock = 5 }, ghost = { Hidden = true } },
            Camos = { gold = {} }
        },
        pwg_smg = { Category = "smg" }
    },
    wildcards = {
        pwg_gunfighter = {
            ModifySlots = function(_, slots)
                slots.primary.maxattachments = (slots.primary.maxattachments or 0) + 1
            end
        }
    }
}

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

-- What the fake adapter offers per build slot of pwg_ar (pwg_smg has no gunsmith: nothing offered).
local offered = {
    optic = { reddot = true, acog = true, ghost = true }, muzzle = { supp = true, comp = true },
    grip = { vgrip = true }, stock = { light = true }, barrel = { long = true }, camo = { gold = true }
}

---@param weaponId string
---@return table<string, table<string, boolean>>
local function adapterOptions(weaponId)
    if weaponId ~= "pwg_ar" then return {} end
    return offered
end

---The static conflict rule of the fake adapter: a long barrel does not fit with a suppressor.
---@param build table<string, string|false>
---@return table<string, string>
local function adapterValidate(_, build)
    if build.muzzle == "supp" and build.barrel == "long" then return { barrel = "conflicts_with_muzzle" } end
    return {}
end

local slots = {
    primary = { id = "primary", kind = "weapons", filter = { "ar", "smg" } },
    secondary = { id = "secondary", kind = "weapons", filter = { "ar", "smg" } },
    wildcard = { id = "wildcard", kind = "wildcards", count = 2 }
}

---@param over table<string, any>?
---@return PW.LoadoutContext
local function ctxWith(over)
    local ctx = {
        lookup = lookup, budget = 0, maxattachments = 5, bannedWeapons = {}, bannedAttachments = {},
        adapterOptions = adapterOptions, adapterValidate = adapterValidate
    }
    for key, value in pairs(over or {}) do ctx[key] = value end
    return ctx --[[@as PW.LoadoutContext]]
end

---@param problems PW.GunsmithProblem[]
---@return table<string, string>
local function whyByOption(problems)
    ---@type table<string, string>
    local out = {}
    for _, problem in ipairs(problems) do out[problem.option] = problem.why end
    return out
end

---A stand-in player: enough for the class store (weak keys) and the gunsmith glue.
---@return Player
local function standIn()
    local ply = {
        IsValid = function() return true end, IsBot = function() return false end,
        Nick = function() return "PW gunsmith stand-in" end
    }
    return ply --[[@as Player]]
end

---Installs a fresh class store that records what it sends; the context is the test's.
---@param state table<string, any>
---@param ctx fun(): PW.LoadoutContext
local function freshClasses(state, ctx)
    state.previousClasses = PW._LoadoutClasses
    state.sent = {}
    PW._LoadoutClasses = loadout()._NewClassStore({
        read = function() return {} end,
        readPick = function() return "" end,
        send = function(_, classState)
            local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
            sent[#sent + 1] = classState
        end,
        context = ctx
    })
end

---Progression answers "everything unlocked, weapon level 30" while a glue case runs (the module may be absent).
---GLuaTest's stub exists only in the environment of a case function, so the case passes it in.
---@param stubFn fun(tbl: table, key: string): table
local function openProgression(stubFn)
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if progression == nil then return end
    stubFn(progression, "IsUnlocked").with(function() return true end)
    stubFn(progression, "LockedOptions").with(function() return {} end)
    stubFn(progression, "GetWeaponLevel").with(function() return 30 end)
end

---@param entries PW.LoadoutClassEntry[]
---@param ref string
---@return PW.LoadoutClassEntry
local function entryOf(entries, ref)
    for _, entry in ipairs(entries) do
        if entry.ref == ref then return entry end
    end
    error("no entry " .. ref)
end

return {
    groupName = "PW gunsmith",
    afterEach = function(state)
        if state.previousClasses ~= nil then PW._LoadoutClasses = state.previousClasses end
        rawset(state, "previousClasses", nil)
    end,
    cases = {
        {
            name = "Validate on save: a build of offered, unlocked, compatible options is accepted as it is",
            func = function()
                local build = { optic = "reddot", muzzle = "supp", grip = "vgrip", stock = false, camo = "gold" }
                local clean, problems = loadout()._ValidateBuild("pwg_ar", must(lookup("weapons", "pwg_ar")), build,
                    ctxWith({ attachmentLimit = function() return 3 end }))
                expect(#problems).to.equal(0)
                expect(clean).to.deepEqual(build)
            end
        },
        {
            name = "Validate on save: unknown, locked, conflicting and over-the-limit options are rejected",
            func = function()
                local build = {
                    optic = "acog", muzzle = "supp", barrel = "long", grip = "unknown_grip", stock = "light",
                    camo = "gold"
                }
                local ctx = ctxWith({
                    lockedOptions = function(_, single)
                        return single.optic == "acog" and { acog = true } or {}
                    end,
                    attachmentLimit = function() return 1 end
                })
                local clean, problems = loadout()._ValidateBuild("pwg_ar", must(lookup("weapons", "pwg_ar")), build,
                    ctx)
                expect(whyByOption(problems)).to.deepEqual({
                    unknown_grip = "not available", acog = "locked",
                    long = "conflict: conflicts_with_muzzle", stock = nil, light = "over the limit"
                })
                -- supp is the one uncurated attachment within the limit; the camo is cosmetic and not counted.
                expect(clean).to.deepEqual({ muzzle = "supp", camo = "gold" })
            end
        },
        {
            name = "Validate on save: a weapon without a gunsmith accepts only cleared slots",
            func = function()
                local clean, problems = loadout()._ValidateBuild("pwg_smg", must(lookup("weapons", "pwg_smg")),
                    { optic = "reddot", muzzle = false }, ctxWith())
                expect(whyByOption(problems)).to.deepEqual({ reddot = "not available" })
                expect(clean).to.deepEqual({ muzzle = false })
            end
        },
        {
            name = "Validate on save: the class save flow answers the rejected options with their reasons",
            func = function(state)
                freshClasses(state, function()
                    return ctxWith({ lookup = loadout()._RegistryLookup, adapterOptions = function(weaponId)
                        return weaponId == "weapon_ar2" and offered or {}
                    end })
                end)
                openProgression(stub)
                local ply = standIn()
                local classState = loadout()._OnClasses(ply, {
                    { name = "Conflict", loadout = {
                        primary = "weapon_ar2", builds = { primary = { muzzle = "supp", barrel = "long" } }
                    } },
                    { name = "Clean", loadout = {
                        primary = "weapon_ar2", builds = { primary = { optic = "reddot" } }
                    } }
                })
                local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
                expect(#sent).to.equal(1)
                local bad = entryOf(classState.entries, "custom:1")
                expect(bad.removed).to.deepEqual({ "long (conflict: conflicts_with_muzzle)" })
                expect(bad.loadout).to.deepEqual({ primary = "weapon_ar2", builds = { primary = { muzzle = "supp" } } })
                expect(bad.available).to.beTrue()
                local good = entryOf(classState.entries, "custom:2")
                expect(#good.removed).to.equal(0)
                local cleanBuild = { primary = { optic = "reddot" } }
                expect(good.loadout).to.deepEqual({ primary = "weapon_ar2", builds = cleanBuild })
            end
        },
        {
            name = "Repair removes only the offending options and keeps the rest of the class",
            func = function()
                local raw = {
                    primary = "pwg_ar", secondary = "pwg_smg",
                    builds = {
                        primary = { optic = "reddot", muzzle = "supp", barrel = "long", grip = "gone", camo = "gold" },
                        secondary = { optic = false }
                    }
                }
                local repaired, removed = loadout()._RepairClass(slots, raw, ctxWith())
                expect(repaired).to.deepEqual({
                    primary = "pwg_ar", secondary = "pwg_smg",
                    builds = {
                        primary = { optic = "reddot", muzzle = "supp", camo = "gold" },
                        secondary = { optic = false }
                    }
                })
                table.sort(removed)
                expect(removed).to.deepEqual({ "gone (not available)", "long (conflict: conflicts_with_muzzle)" })
            end
        },
        {
            name = "The attachment limit includes wildcards (match cap) and progression (weapon level)",
            func = function()
                local three = { optic = "reddot", muzzle = "supp", grip = "vgrip" }
                local function class(withWildcard)
                    return { primary = "pwg_ar", wildcard = withWildcard and "pwg_gunfighter" or nil,
                        builds = { primary = table.Copy(three) } }
                end
                local level = 10
                local ctx = ctxWith({ maxattachments = 2, attachmentLimit = function() return level end })
                -- Cap 2 without the wildcard: over the match cap, the class is unavailable and kept as it is.
                local status = loadout()._ClassStatus(slots, class(false), ctx)
                expect(status.available).to.beFalse()
                expect(#status.removed).to.equal(0)
                -- Gunfighter lifts the cap to 3: the same build is valid.
                status = loadout()._ClassStatus(slots, class(true), ctx)
                expect(status.reason).toNot.exist()
                expect(status.available).to.beTrue()
                -- Weapon level 2: progression allows two uncurated attachments; the third in slot order is removed.
                level = 2
                status = loadout()._ClassStatus(slots, class(true), ctx)
                expect(status.available).to.beTrue()
                expect(status.removed).to.deepEqual({ "reddot (over the limit)" })
                expect(status.loadout.builds).to.deepEqual({ primary = { grip = "vgrip", muzzle = "supp" } })
            end
        },
        {
            name = "Apply on spawn calls the adapter with the build of each weapon slot",
            func = function()
                local primary, secondary = { id = "ar" }, { id = "smg" }
                ---@type table[]
                local calls = {}
                local api = {
                    gunsmith = function() return true end,
                    apply = function(wep, build)
                        calls[#calls + 1] = { wep = wep, build = build }
                        return build
                    end,
                    debug = function() error("no debug line expected") end
                }
                local build = { optic = "reddot", muzzle = false }
                local failures = loadout()._ApplyBuilds({ primary = "pwg_ar", secondary = "pwg_smg",
                    builds = { primary = build } }, { primary = primary, secondary = secondary }, api)
                expect(#calls).to.equal(1)
                expect(calls[1].wep).to.equal(primary)
                expect(calls[1].build).to.deepEqual(build)
                expect(#failures).to.equal(0)
            end
        },
        {
            name = "HL2 fallback: a weapon without a gunsmith is a no-op with a debug line only",
            func = function()
                local debugLines = 0
                local api = {
                    gunsmith = function() return false end,
                    apply = function() error("Apply must not run without a gunsmith") end,
                    debug = function() debugLines = debugLines + 1 end
                }
                local failures = loadout()._ApplyBuilds({ primary = "weapon_smg1",
                    builds = { primary = { optic = "reddot" } } }, { primary = { id = "smg1" } }, api)
                expect(#failures).to.equal(0)
                expect(debugLines).to.equal(1)
                -- The live check: the HL2 fallback adapter (sweps) has no Apply.
                expect(loadout()._HasGunsmith("weapon_smg1")).to.beFalse()
            end
        },
        {
            name = "Partial application repairs the class and sends one message",
            func = function(state)
                freshClasses(state, function()
                    return ctxWith({ lookup = loadout()._RegistryLookup, adapterOptions = function(weaponId)
                        return (weaponId == "weapon_ar2" or weaponId == "weapon_357") and offered or {}
                    end })
                end)
                openProgression(stub)
                local ply = standIn()
                loadout()._OnClasses(ply, { { name = "Built", loadout = {
                    primary = "weapon_ar2", secondary = "weapon_357",
                    builds = { primary = { optic = "reddot", muzzle = "supp" }, secondary = { optic = "reddot" } }
                } } })
                expect(loadout()._OnPick(ply, "custom:1")).to.beTrue()
                local class = must(loadout().GetClass(ply))
                ---@type string[]
                local told = {}
                local api = {
                    gunsmith = function() return true end,
                    -- The live weapon refuses the suppressor of the primary and the optic of the secondary.
                    apply = function(wep, build)
                        local stuck = table.Copy(build) --[[@as table<string, any>]]
                        if wep.id == "ar2" then stuck.muzzle = nil else stuck.optic = nil end
                        return stuck
                    end,
                    debug = function() end,
                    tell = function(_, message) told[#told + 1] = message end,
                    name = function(wep) return wep.id end
                }
                loadout()._GunsmithOnGive(ply, class, { primary = { id = "ar2" }, secondary = { id = "357" } }, api)
                expect(#told).to.equal(1)
                expect(string.find(told[1], "supp", 1, true) ~= nil).to.beTrue()
                expect(string.find(told[1], "reddot", 1, true) ~= nil).to.beTrue()
                local repaired = must(loadout().GetClass(ply))
                expect(repaired.builds).to.deepEqual({ primary = { optic = "reddot" } })
                local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
                local entry = entryOf(sent[#sent].entries, "custom:1")
                table.sort(entry.removed)
                expect(entry.removed).to.deepEqual({ "reddot (not installed)", "supp (not installed)" })
                expect(entry.available).to.beTrue()
                -- Next spawn: the repaired build sticks, nothing more is said.
                loadout()._GunsmithOnGive(ply, repaired, { primary = { id = "ar2" } }, api)
                expect(#told).to.equal(1)
            end
        },
        {
            name = "Live adapter context: offered options and Validate come from the weapon's adapter",
            func = function()
                local fake = {
                    ClassName = "pwg_fake",
                    GetSlots = function()
                        return { { id = "optic", name = "Optic" }, { id = "muzzle", name = "Muzzle" } }
                    end,
                    GetOptions = function(_, _, slot)
                        if slot == "optic" then return { { id = "reddot", name = "Red dot" } } end
                        return {}
                    end,
                    Validate = function(_, _, build) return build, { muzzle = "bad_slot" } end,
                    Apply = function(_, _, build) return build end
                }
                stub(PW.Adapters, "For").with(function() return fake end)
                expect(loadout()._AdapterOptions("pwg_ar", {})).to.deepEqual({ optic = { reddot = true }, muzzle = {} })
                expect(loadout()._AdapterValidate("pwg_ar", { muzzle = "x" })).to.deepEqual({ muzzle = "bad_slot" })
                expect(loadout()._HasGunsmith("pwg_ar")).to.beTrue()
            end
        }
    }
}
