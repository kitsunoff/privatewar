-- T-7.4 Classes and gunsmith screens (TASKS.md "Mandatory test cases": T-7.4 each screen's data model built from
-- registries without drawing; 05-loadout.md d.2-d.5, d.12, d.13, d.15). Pure cases over a fake catalogue: the class
-- editor's effective slots with and without a wildcard, the allowed items per slot (filter, perk group rule, locks,
-- costs), the budget meter, the gunsmith model (locked options, the attachment limit, the HL2 fallback, the preview),
-- name validation, the save flow (it writes and sends the class) and the server's answer. One wiring case builds the
-- editor from the real registries. No bots.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LoadoutUILib
local function ui()
    return must(PW.LoadoutUI)
end

local catalogue = {
    weapons = {
        pwu_smg = { Name = "SMG", Category = "smg" },
        pwu_ar = { Name = "Rifle", Category = "ar", Cost = 2, Unlock = 4 },
        pwu_banned = { Name = "Banned", Category = "smg" },
        pwu_pistol = { Name = "Pistol", Category = "pistol" }
    },
    equipment = { pwu_frag = { Name = "Frag", Category = "lethal" } },
    perks = {
        pwu_p1a = { Name = "Quick", Group = 1 },
        pwu_p1b = { Name = "Light", Group = 1 },
        pwu_p2 = { Name = "Hands", Group = 2 }
    },
    streaks = { pwu_uav = { Name = "UAV", Kills = 3 } },
    wildcards = {
        pwu_greed = {
            Name = "Greed",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.perk1.count = 2 end
        },
        pwu_overkill = {
            Name = "Overkill",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.secondary.filter = { "pistol", "ar", "smg" } end
        },
        pwu_gunfighter = {
            Name = "Gunfighter",
            ---@param slots table<string, PW.LoadoutSlot>
            ModifySlots = function(_, slots) slots.primary.maxattachments = slots.primary.maxattachments + 1 end
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

---@param kind string
---@return table<string, any>[]
local function list(kind)
    ---@type string[]
    local ids = table.GetKeys(catalogue[kind] or {}) --[[@as string[] ]]
    table.sort(ids)
    ---@type table<string, any>[]
    local out = {}
    for index, id in ipairs(ids) do
        local entity = table.Copy(catalogue[kind][id]) --[[@as table<string, any>]]
        entity.ClassName = id
        out[index] = entity
    end
    return out
end

-- Declaration order is not display order: modules declare their slots at different times.
local order = { "primary", "wildcard", "secondary", "streak1", "perk2", "lethal", "perk1" }

---@return table<string, PW.LoadoutSlot>
local function declared()
    return {
        primary = { id = "primary", kind = "weapons", filter = { "ar", "smg" } },
        secondary = { id = "secondary", kind = "weapons", filter = { "pistol" } },
        lethal = { id = "lethal", kind = "equipment", filter = { "lethal" }, label = "#pw.slot.lethal" },
        perk1 = { id = "perk1", kind = "perks", group = 1 },
        perk2 = { id = "perk2", kind = "perks", group = 2 },
        wildcard = { id = "wildcard", kind = "wildcards", count = 2 },
        streak1 = { id = "streak1", kind = "streaks" }
    }
end

---@param loadout PW.Loadout
---@param extra? table<string, any> context fields
---@return PW.LoadoutUIEditorInput
local function input(loadout, extra)
    ---@type PW.LoadoutContext
    local ctx = { lookup = lookup, budget = 10, maxattachments = 5, bannedWeapons = {}, bannedAttachments = {} }
    for key, value in pairs(extra or {}) do ctx[key] = value end
    return { declared = declared(), order = order, loadout = loadout, ctx = ctx, list = list }
end

---@param rows PW.LoadoutUIRow[]
---@return string[]
local function rowIds(rows)
    ---@type string[]
    local ids = {}
    for index, row in ipairs(rows) do ids[index] = row.id end
    return ids
end

---@param rows PW.LoadoutUIRow[]
---@param id string
---@return PW.LoadoutUIRow
local function rowOf(rows, id)
    for _, row in ipairs(rows) do
        if row.id == id then return row end
    end
    error("no row " .. id)
end

---@param options { id: string }[]
---@return string[]
local function optionIds(options)
    ---@type string[]
    local ids = {}
    for index, option in ipairs(options) do ids[index] = option.id end
    return ids
end

---@param options { id: string }[]
---@param id string
---@return table<string, any>
local function optionOf(options, id)
    for _, option in ipairs(options) do
        if option.id == id then return option end
    end
    error("no option " .. id)
end

---@param build table<string, string|false>
---@param extra? table<string, any>
---@return PW.LoadoutUIGunsmithInput
local function gunsmithInput(build, extra)
    ---@type table<string, PW.Option[]>
    local options = {
        optic = {
            { id = "red_dot", name = "Red dot", cosmetic = false },
            { id = "acog", name = "ACOG", cosmetic = false }
        },
        muzzle = {
            { id = "suppressor", name = "Suppressor", cosmetic = false },
            { id = "brake", name = "Brake", cosmetic = false },
            { id = "meme", name = "Meme", cosmetic = false }
        },
        grip = { { id = "vertical", name = "Vertical grip", cosmetic = false } },
        skin = { { id = "gold", name = "Gold", cosmetic = true } }
    }
    ---@type PW.LoadoutUIGunsmithInput
    local data = {
        weaponId = "pwu_smg", weaponName = "SMG", build = build, weaponLevel = 1, unlockAll = false, cap = 5,
        banned = {},
        weapon = { Attachments = { acog = { Unlock = 5, Cost = 2 }, meme = { Hidden = true } } },
        slots = {
            { id = "grip", name = "Grip", cosmetic = false }, { id = "muzzle", name = "Muzzle", cosmetic = false },
            { id = "optic", name = "Optic", cosmetic = false }, { id = "skin", name = "Skin", cosmetic = true }
        },
        options = function(slotId) return options[slotId] or {} end
    }
    for key, value in pairs(extra or {}) do data[key] = value end
    return data
end

return {
    groupName = "PW UI classes and gunsmith",
    cases = {
        {
            name = "Editor: one row per position of the declared slots (weapons, equipment, perks, wildcards, streaks)",
            func = function()
                local model = ui().Editor(input({ primary = "pwu_smg", perk1 = "pwu_p1a" }))
                expect(table.concat(rowIds(model.rows), ",")).to.equal(
                    "primary,secondary,lethal,perk1,perk2,wildcard#1,wildcard#2,streak1")
                local primary = rowOf(model.rows, "primary")
                expect(primary.item).to.equal("pwu_smg")
                expect(primary.itemName).to.equal("SMG")
                expect(primary.gunsmith).to.beTrue()
                expect(rowOf(model.rows, "secondary").itemName).to.equal("EMPTY")
                expect(rowOf(model.rows, "secondary").gunsmith).to.beFalse()
                expect(rowOf(model.rows, "perk1").label).to.equal("PERK 1")
                expect(rowOf(model.rows, "lethal").label).to.equal("LETHAL")
                expect(rowOf(model.rows, "wildcard#2").label).to.equal("WILDCARD #2")
            end
        },
        {
            name = "Editor: a wildcard re-evaluates the effective slots (Greed adds a second perk 1 row)",
            func = function()
                local loadout = { perk1 = { "pwu_p1a", "pwu_p1b" }, wildcard = "pwu_greed" }
                local model = ui().Editor(input(loadout))
                expect(table.concat(rowIds(model.rows), ",")).to.equal(
                    "primary,secondary,lethal,perk1#1,perk1#2,perk2,wildcard#1,wildcard#2,streak1")
                expect(rowOf(model.rows, "perk1#2").item).to.equal("pwu_p1b")
                expect(rowOf(model.rows, "perk1#2").label).to.equal("PERK 1 #2")
                expect(rowOf(model.rows, "perk1#2").problem).to.beNil()
            end
        },
        {
            name = "Editor: removing the wildcard restores the slots and drops the extra pick",
            func = function()
                local data = input({ perk1 = { "pwu_p1a", "pwu_p1b" }, wildcard = "pwu_greed" })
                local after = ui().SetItem(data, "wildcard#1", nil)
                expect(after.wildcard).to.beNil()
                expect(after.perk1).to.equal("pwu_p1a")
                data.loadout = after
                expect(table.concat(rowIds(ui().Editor(data).rows), ",")).to.equal(
                    "primary,secondary,lethal,perk1,perk2,wildcard#1,wildcard#2,streak1")
            end
        },
        {
            name = "Allowed items: the empty choice first, then the kind's items that fit the slot filter",
            func = function()
                local data = input({ primary = "pwu_smg" })
                local model = ui().Editor(data)
                local primary = ui().Options(data, rowOf(model.rows, "primary"), model.slots)
                expect(table.concat(optionIds(primary), ",")).to.equal(",pwu_ar,pwu_banned,pwu_smg")
                expect(optionOf(primary, "pwu_smg").selected).to.beTrue()
                expect(optionOf(primary, "").name).to.equal("NONE")
                local secondary = ui().Options(data, rowOf(model.rows, "secondary"), model.slots)
                expect(table.concat(optionIds(secondary), ",")).to.equal(",pwu_pistol")
            end
        },
        {
            name = "Allowed items: a perk slot lists only the perks of its group",
            func = function()
                local data = input({})
                local model = ui().Editor(data)
                expect(table.concat(optionIds(ui().Options(data, rowOf(model.rows, "perk1"), model.slots)), ","))
                    .to.equal(",pwu_p1a,pwu_p1b")
                expect(table.concat(optionIds(ui().Options(data, rowOf(model.rows, "perk2"), model.slots)), ","))
                    .to.equal(",pwu_p2")
                local wrong = ui().Editor(input({ perk1 = "pwu_p2" }))
                expect(rowOf(wrong.rows, "perk1").problem).to.equal("A group 2 perk")
            end
        },
        {
            name = "Allowed items: Overkill opens the secondary slot to primary weapons",
            func = function()
                local data = input({ wildcard = "pwu_overkill" })
                local model = ui().Editor(data)
                local secondary = ui().Options(data, rowOf(model.rows, "secondary"), model.slots)
                expect(table.concat(optionIds(secondary), ",")).to.equal(",pwu_ar,pwu_banned,pwu_pistol,pwu_smg")
            end
        },
        {
            name = "Allowed items: locked items are greyed with their unlock level, banned ones with the reason",
            func = function()
                local data = input({ primary = "pwu_ar" }, {
                    isUnlocked = function(_, id) return id ~= "pwu_ar" end,
                    bannedWeapons = { pwu_banned = true }
                })
                local model = ui().Editor(data)
                local options = ui().Options(data, rowOf(model.rows, "primary"), model.slots)
                local ar = optionOf(options, "pwu_ar")
                expect(ar.locked).to.beTrue()
                expect(ar.lockText).to.equal("LV 4")
                expect(ar.reason).to.equal("Unlocks at level 4")
                local banned = optionOf(options, "pwu_banned")
                expect(banned.locked).to.beTrue()
                expect(banned.reason).to.equal("Banned in this match")
                expect(optionOf(options, "pwu_smg").locked).to.beFalse()
                expect(rowOf(model.rows, "primary").problem).to.equal("Locked: unlocks at level 4")
            end
        },
        {
            name = "Allowed items: per-item cost (Cost field, default 1, streaks outside the budget)",
            func = function()
                local data = input({})
                local model = ui().Editor(data)
                local primary = ui().Options(data, rowOf(model.rows, "primary"), model.slots)
                expect(optionOf(primary, "pwu_ar").cost).to.equal(2)
                expect(optionOf(primary, "pwu_ar").costText).to.equal("2")
                expect(optionOf(primary, "pwu_smg").cost).to.equal(1)
                expect(optionOf(primary, "").cost).to.equal(0)
                local streak = optionOf(ui().Options(data, rowOf(model.rows, "streak1"), model.slots), "pwu_uav")
                expect(streak.cost).to.equal(0)
                expect(streak.costText).to.equal("3 KILLS")
            end
        },
        {
            name = "Allowed items: an item already picked in another position of the slot is locked",
            func = function()
                local data = input({ wildcard = { "pwu_greed" } })
                local model = ui().Editor(data)
                local second = ui().Options(data, rowOf(model.rows, "wildcard#2"), model.slots)
                expect(optionOf(second, "pwu_greed").locked).to.beTrue()
                expect(optionOf(second, "pwu_greed").reason).to.equal("Already picked")
                expect(optionOf(second, "pwu_overkill").locked).to.beFalse()
            end
        },
        {
            name = "Budget meter: ok, full, over and unlimited",
            func = function()
                local ok = ui().Budget(6, 10)
                expect(ok.state).to.equal("ok")
                expect(ok.text).to.equal("6 / 10")
                expect(ok.fraction).to.equal(0.6)
                expect(ui().Budget(10, 10).state).to.equal("full")
                local over = ui().Budget(12, 10)
                expect(over.state).to.equal("over")
                expect(over.fraction).to.equal(1)
                local free = ui().Budget(12, 0)
                expect(free.state).to.equal("unlimited")
                expect(free.text).to.equal("12 (no limit)")
                expect(free.fraction).to.equal(0)
            end
        },
        {
            name = "Editor: the total cost feeds the meter and an over-budget class names the broken rule",
            func = function()
                local loadout = { primary = "pwu_ar", secondary = "pwu_pistol", perk1 = "pwu_p1a", streak1 = "pwu_uav" }
                local model = ui().Editor(input(loadout))
                expect(model.cost).to.equal(4)
                expect(model.meter.state).to.equal("ok")
                expect(model.check).to.beNil()
                local tight = ui().Editor(input(loadout, { budget = 3 }))
                expect(tight.meter.state).to.equal("over")
                expect(tight.check).to.equal("the loadout costs 4, the budget is 3")
            end
        },
        {
            name = "Editor: a new weapon drops the old build, the same weapon keeps it",
            func = function()
                local data = input({ primary = "pwu_smg", builds = { primary = { optic = "red_dot" } } })
                local same = ui().SetItem(data, "primary", "pwu_smg")
                expect((must(same.builds) --[[@as table<string, any>]]).primary.optic).to.equal("red_dot")
                local changed = ui().SetItem(data, "primary", "pwu_ar")
                expect(changed.primary).to.equal("pwu_ar")
                expect(changed.builds).to.beNil()
                local cleared = ui().SetItem(data, "primary", "")
                expect(cleared.primary).to.beNil()
            end
        },
        {
            name = "Gunsmith: the HL2 fallback (no slots) is a clear no-gunsmith state",
            func = function()
                local model = ui().Gunsmith(gunsmithInput({}, { slots = {} }))
                expect(model.gunsmith).to.beFalse()
                expect(#model.slots).to.equal(0)
                expect(string.find(model.note, "no gunsmith", 1, true) ~= nil).to.beTrue()
            end
        },
        {
            name = "Gunsmith: slots with their options, a curated option locked by its weapon level, Hidden skipped",
            func = function()
                local model = ui().Gunsmith(gunsmithInput({ optic = "red_dot" }))
                expect(model.gunsmith).to.beTrue()
                expect(#model.slots).to.equal(4)
                local optic = model.slots[3]
                expect(optic.id).to.equal("optic")
                expect(optic.currentName).to.equal("Red dot")
                expect(table.concat(optionIds(optic.options), ",")).to.equal(",red_dot,acog")
                local acog = optionOf(optic.options, "acog")
                expect(acog.locked).to.beTrue()
                expect(acog.unlock).to.equal(5)
                expect(acog.lockText).to.equal("LV 5")
                expect(acog.reason).to.equal("Unlocks at weapon level 5")
                expect(acog.cost).to.equal(2)
                expect(table.concat(optionIds(model.slots[2].options), ",")).to.equal(",suppressor,brake")
                local opened = ui().Gunsmith(gunsmithInput({}, { weaponLevel = 5 }))
                expect(optionOf(opened.slots[3].options, "acog").locked).to.beFalse()
            end
        },
        {
            name = "Gunsmith: the weapon level limits uncurated attachments; a swap in the same slot stays allowed",
            func = function()
                local model = ui().Gunsmith(gunsmithInput({ optic = "red_dot", skin = "gold" }))
                expect(model.count).to.equal(1)
                expect(model.levelCount).to.equal(1)
                expect(model.levelLimit).to.equal(1)
                expect(model.countText).to.equal("1 / 5")
                local suppressor = optionOf(model.slots[2].options, "suppressor")
                expect(suppressor.locked).to.beTrue()
                expect(suppressor.lockText).to.equal("FULL")
                expect(optionOf(model.slots[4].options, "gold").locked).to.beFalse()
                local swap = ui().Gunsmith(gunsmithInput({ muzzle = "brake" }))
                expect(optionOf(swap.slots[2].options, "suppressor").locked).to.beFalse()
                local unlocked = ui().Gunsmith(gunsmithInput({ optic = "red_dot" }, { unlockAll = true }))
                expect(unlocked.levelLimit).to.beNil()
                expect(optionOf(unlocked.slots[2].options, "suppressor").locked).to.beFalse()
            end
        },
        {
            name = "Gunsmith: the match cap (a wildcard may raise it) and the over state",
            func = function()
                local build = { optic = "red_dot", muzzle = "brake", grip = "vertical" }
                local capped = ui().Gunsmith(gunsmithInput(build, { weaponLevel = 30, cap = 2 }))
                expect(capped.count).to.equal(3)
                expect(capped.over).to.beTrue()
                expect(capped.countText).to.equal("3 / 2")
                expect(#capped.problems > 0).to.beTrue()
                local raised = ui().Gunsmith(gunsmithInput(build, { weaponLevel = 30, cap = 3 }))
                expect(raised.over).to.beFalse()
                local data = input({ primary = "pwu_smg", wildcard = "pwu_gunfighter" }, { maxattachments = 2 })
                expect(ui().Editor(data).slots.primary.maxattachments).to.equal(3)
            end
        },
        {
            name = "Gunsmith: the client-side preview names options the adapter does not offer and banned ones",
            func = function()
                local model = ui().Gunsmith(gunsmithInput({ optic = "laser", muzzle = "brake" },
                    { weaponLevel = 30, banned = { brake = true } }))
                expect(table.concat(model.problems, "; ")).to.equal("laser (not available); Brake (banned)")
                expect(optionOf(model.slots[2].options, "brake").locked).to.beTrue()
                expect(optionOf(model.slots[2].options, "brake").reason).to.equal("Banned in this match")
            end
        },
        {
            name = "Gunsmith: SetOption sets or clears one build slot on a copy",
            func = function()
                local build = { optic = "red_dot" }
                local set = ui().SetOption(build, "muzzle", "brake")
                expect(set.muzzle).to.equal("brake")
                expect(build.muzzle).to.beNil()
                local cleared = ui().SetOption(set, "optic", "")
                expect(cleared.optic).to.beNil()
                expect(cleared.muzzle).to.equal("brake")
            end
        },
        {
            name = "Name validation: trimmed, not empty, at most 32 bytes, printable, unique ignoring case",
            func = function()
                expect(ui().ValidateName("  Rusher  ", { "Sniper" })).to.equal("Rusher")
                local _, empty = ui().ValidateName("   ", {})
                expect(empty).to.equal("Enter a name")
                local _, long = ui().ValidateName(string.rep("a", 33), {})
                expect(long).to.equal("At most 32 characters")
                expect(ui().ValidateName(string.rep("a", 32), {})).to.equal(string.rep("a", 32))
                local _, control = ui().ValidateName("bad\nname", {})
                expect(control).to.equal("No control characters")
                local _, taken = ui().ValidateName("sniper", { "Sniper" })
                expect(taken).to.equal("Another class is called Sniper")
                local _, notText = ui().ValidateName(nil, {})
                expect(notText).to.equal("Enter a name")
            end
        },
        {
            name = "Name validation: a free name for a new class or a copy",
            func = function()
                expect(ui().FreeName("Assault", {})).to.equal("Assault")
                expect(ui().FreeName("Assault", { "assault", "Assault 2" })).to.equal("Assault 3")
                expect(#ui().FreeName(string.rep("x", 40), { string.rep("x", 32) })).to.equal(32)
            end
        },
        {
            name = "Save sends the class: classes.json gets the draft at its index and the upload goes out once",
            func = function()
                local classes = {
                    { name = "One", loadout = { primary = "pwu_smg" } },
                    { name = "Two", loadout = { primary = "pwu_ar" } }
                }
                ---@type table<string, any>[]
                local written = {}
                local uploads = 0
                local draft = { index = 2, name = "Renamed", loadout = { primary = "pwu_smg", perk1 = "pwu_p1a" } }
                local saved = ui()._Save(classes, draft --[[@as PW.LoadoutUIDraft]], {
                    write = function(data) written[#written + 1] = data end,
                    upload = function() uploads = uploads + 1 end
                })
                expect(uploads).to.equal(1)
                expect(#written).to.equal(1)
                expect(written[1].version).to.equal(1)
                expect(written[1].classes[2].name).to.equal("Renamed")
                expect(written[1].classes[2].loadout.perk1).to.equal("pwu_p1a")
                expect(classes[2].name).to.equal("Two")
                -- What goes on the wire round-trips through the loadout module's own codec.
                ---@type any[]
                local wire = {}
                must(PW.Loadout)._EncodeClasses(saved, {
                    uint = function(value) wire[#wire + 1] = value end,
                    string = function(value) wire[#wire + 1] = value end,
                    bool = function(value) wire[#wire + 1] = value end
                })
                local at = 0
                local function nextValue() at = at + 1 return wire[at] end
                local reader = { uint = nextValue, string = nextValue, bool = nextValue }
                local decoded = must(PW.Loadout)._DecodeClasses(reader --[[@as PW.LoadoutReader]], 10)
                expect(decoded[2].name).to.equal("Renamed")
                expect(decoded[2].loadout.perk1).to.equal("pwu_p1a")
            end
        },
        {
            name = "Save: uploads are spaced by the server's rate limit",
            func = function()
                expect(ui().UploadDelay(10, nil, 2.1)).to.equal(0)
                expect(ui().UploadDelay(10, 9, 2.1) > 1.09 and ui().UploadDelay(10, 9, 2.1) < 1.11).to.beTrue()
                expect(ui().UploadDelay(20, 9, 2.1)).to.equal(0)
            end
        },
        {
            name = "Save: the server's answer is shown (waiting, accepted, removed with reasons, not usable)",
            func = function()
                ---@type PW.LoadoutClassState
                local state = {
                    selected = "",
                    entries = {
                        { ref = "custom:1", name = "A", available = true, removed = {}, loadout = {} },
                        { ref = "custom:2", name = "B", available = true, loadout = {},
                            removed = { "acog (locked)", "pwu_x (not available)" } },
                        { ref = "custom:3", name = "C", available = false, removed = {}, loadout = {},
                            reason = "the loadout costs 12, the budget is 10" }
                    }
                }
                expect(ui().SaveResult(state, "custom:1", false).status).to.equal("waiting")
                expect(ui().SaveResult(state, "custom:1", true).status).to.equal("accepted")
                local repaired = ui().SaveResult(state, "custom:2", true)
                expect(repaired.status).to.equal("repaired")
                expect(table.concat(repaired.lines, "; ")).to.equal("acog (locked); pwu_x (not available)")
                local unusable = ui().SaveResult(state, "custom:3", true)
                expect(unusable.status).to.equal("unavailable")
                expect(unusable.lines[1]).to.equal("the loadout costs 12, the budget is 10")
                expect(ui().SaveResult(state, "custom:9", true).status).to.equal("missing")
            end
        },
        {
            name = "Class list actions: presets copy only, custom classes edit, rename and delete, a full list locks",
            func = function()
                ---@param actions PW.LoadoutUIAction[]
                ---@return table<string, PW.LoadoutUIAction>
                local function byId(actions)
                    ---@type table<string, PW.LoadoutUIAction>
                    local out = {}
                    for _, action in ipairs(actions) do out[action.id] = action end
                    return out
                end
                local preset = byId(ui().ClassActions("preset:assault", 2, 10))
                expect(preset.edit.locked).to.beTrue()
                expect(preset.copy.locked).to.beFalse()
                expect(preset.rename.locked).to.beTrue()
                expect(preset.delete.locked).to.beTrue()
                expect(preset.new.locked).to.beFalse()
                local custom = byId(ui().ClassActions("custom:2", 2, 10))
                expect(custom.edit.locked).to.beFalse()
                expect(custom.rename.locked).to.beFalse()
                expect(custom.delete.locked).to.beFalse()
                local full = byId(ui().ClassActions("custom:1", 10, 10))
                expect(full.copy.locked).to.beTrue()
                expect(full.new.locked).to.beTrue()
                expect(full.new.reason).to.equal("You have 10 custom classes, the server keeps 10")
                expect(full.edit.locked).to.beFalse()
                local none = byId(ui().ClassActions(nil, 0, 10))
                expect(none.edit.locked).to.beTrue()
                expect(none.new.locked).to.beFalse()
            end
        },
        {
            name = "Delete: the server pick follows the shifted refs",
            func = function()
                expect(ui().PickAfterDelete("custom:1", 2, "preset:assault")).to.beNil()
                expect(ui().PickAfterDelete("custom:2", 2, "preset:assault")).to.equal("preset:assault")
                expect(ui().PickAfterDelete("custom:3", 2, "preset:assault")).to.equal("custom:2")
                expect(ui().PickAfterDelete("preset:assault", 1, "preset:assault")).to.beNil()
            end
        },
        {
            name = "Editor model from the real registries: built-in slots, presets' items and the meter",
            func = function()
                local loadout = must(PW.Loadout)
                local preset = must(must(PW.Classes).Get("assault")) --[[@as PW.ClassPreset]]
                local registries = must(PW.Registries)
                ---@type PW.LoadoutUIEditorInput
                local data = {
                    declared = PW._Loadout.slots, order = PW._Loadout.order, loadout = table.Copy(preset.Loadout),
                    ctx = loadout._Context(function() return nil end, loadout._RegistryLookup),
                    list = function(kind)
                        local registry = registries[kind]
                        return registry ~= nil and registry.GetEnabledList() or {}
                    end
                }
                local model = ui().Editor(data)
                local ids = table.concat(rowIds(model.rows), ",")
                for _, slot in ipairs({ "primary", "secondary", "perk1", "perk2", "perk3", "wildcard#1", "streak1" }) do
                    expect(string.find("," .. ids .. ",", "," .. slot .. ",", 1, true) ~= nil).to.beTrue()
                end
                expect(rowOf(model.rows, "primary").item).to.equal("weapon_ar2")
                expect(model.meter.text).to.equal("8 / 10")
                local perks = ui().Options(data, rowOf(model.rows, "perk2"), model.slots)
                for _, option in ipairs(perks) do
                    if option.id ~= "" then
                        expect(must(registries.perks.Get(option.id)).Group).to.equal(2)
                    end
                end
            end
        }
    }
}
