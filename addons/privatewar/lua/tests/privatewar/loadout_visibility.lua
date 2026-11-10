-- T-11.15: human picker policy is separate from registry, technical resolution and bot pool eligibility.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@return PW.LoadoutLib
local function lib() return must(PW.Loadout) end

---@param ref string
---@return PW.LoadoutClassEntry
local function entry(ref)
    return { ref = ref, name = ref, loadout = { primary = "weapon_smg1" }, removed = {}, available = true }
end

---@param entries PW.LoadoutClassEntry[]
---@return string[]
local function refs(entries)
    ---@type string[]
    local out = {}
    for index, value in ipairs(entries) do out[index] = value.ref end
    return out
end

---@param state PW.LoadoutClassState
---@param editor? boolean
---@return PW.LoadoutClassState
local function humanState(state, editor)
    return lib().HumanClassState(state, editor)
end

---@param test table<string, any>
local function setup(test)
    test.classes, test.store, test.net = PW.Classes, PW._LoadoutClasses, PW._Net
    test.ply = { IsValid = function() return false end, IsBot = function() return true end }
    local registry = PW.Registry.New("visibility_fixtures", { subscribe = "never", preRegister = function() end })
    registry.Register({ Name = "Z legacy", Loadout = { primary = "weapon_smg1" } }, "legacy")
    registry.Register({ Name = "A hidden", Hidden = true, Loadout = { primary = "weapon_smg1" } }, "technical")
    registry.Register({ Name = "B visible", Hidden = false, Loadout = { secondary = "weapon_pistol" } }, "visible")
    registry.Register({ Name = "Blocked", Hidden = true, Loadout = { primary = "weapon_shotgun" } }, "blocked")
    registry.ResolveAll()
    PW.Classes = registry
    PW._LoadoutClasses = lib()._NewClassStore({
        context = function() return lib()._Context(function() return nil end, lib()._RegistryLookup) end,
        send = function(_, state) test.sent = state end,
        read = function() return test.upload or {} end,
        readPick = function() return test.pick or "" end
    })
    PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return 1000 end })
    lib()._RegisterClassNet(nil)
end

return {
    groupName = "PW class visibility T-11.15",
    beforeEach = setup,
    afterEach = function(test)
        lib().SetClass(test.ply, nil)
        PW.Classes, PW._LoadoutClasses, PW._Net = test.classes, test.store, test.net
    end,
    cases = {
        {
            name = "T-11.15: pure human-list policy takes plain metadata and never sorts source tables",
            func = function()
                local entries = { entry("preset:hidden"), entry("preset:old"), entry("custom:2"), entry("custom:1") }
                local before = table.Copy(entries)
                local lookup = function(id)
                    return { ClassName = id, Name = id, Loadout = {}, Hidden = id == "hidden" }
                end
                local filtered = lib()._HumanClassEntries(entries, false, lookup)
                expect(refs(filtered)).to.deepEqual({ "custom:2", "custom:1", "preset:old" })
                expect(refs(lib()._HumanClassEntries(entries, true, lookup)))
                    .to.deepEqual({ "custom:2", "custom:1" })
                expect(entries).to.deepEqual(before)
                expect(filtered[1]).to.equal(entries[3])
            end
        },
        {
            name = "Mandatory T-11.15: editor custom-only, never code presets",
            func = function()
                local state = { selected = "preset:visible", entries = {
                    entry("preset:visible"), entry("custom:2"), entry("preset:technical"), entry("custom:1")
                } }
                local filtered = humanState(state, true)
                expect(refs(filtered.entries)).to.deepEqual({ "custom:2", "custom:1" })
                expect(filtered.selected).to.equal("")
                local cards = lib()._ClassCards(state, true)
                expect(#cards).to.equal(2)
                expect(cards[1].tags).to.equal("Custom class")
            end
        },
        {
            name = "Mandatory T-11.15: respawn custom-first then visible presets, stable and nonmutating",
            func = function()
                local state = { selected = "custom:1", entries = {
                    entry("preset:visible"), entry("custom:2"), entry("preset:legacy"), entry("custom:1")
                } }
                local before = table.Copy(state)
                local filtered = humanState(state)
                expect(refs(filtered.entries)).to.deepEqual({
                    "custom:2", "custom:1", "preset:visible", "preset:legacy"
                })
                expect(state).to.deepEqual(before)
                expect(filtered.entries[1]).to.equal(state.entries[2])
                expect(filtered.entries == state.entries).to.beFalse()
            end
        },
        {
            name = "Mandatory T-11.15: legacy code classes default visible; explicit false is visible",
            func = function(test)
                local state = lib().ClassState(test.ply)
                expect(refs(state.entries)).to.deepEqual({ "preset:legacy", "preset:visible" })
            end
        },
        {
            name = "Mandatory T-11.15: Hidden absent from lobby, preview, pause and death picker models",
            func = function()
                local state = { selected = "preset:technical", entries = {
                    entry("preset:technical"), entry("preset:legacy"), entry("custom:1")
                } }
                local cards, selected = must(PW.UI).Match.ClassCards(state)
                expect(#cards).to.equal(2)
                expect(cards[1].id).to.equal("custom:1")
                expect(cards[2].id).to.equal("preset:legacy")
                expect(selected).to.beNil()
                local sent = false
                local result = must(PW.UI).Match.Choose(state, "preset:technical", function() sent = true end)
                expect(result).to.equal("unknown")
                expect(sent).to.beFalse()
                expect(#lib()._ClassCards(state, true)).to.equal(1)
                expect(#lib()._ClassCards(state)).to.equal(2)
            end
        },
        {
            name = "Mandatory T-11.15: empty human lists and hidden-only lists are safe",
            func = function()
                expect(humanState({ selected = "", entries = {} })).to.deepEqual({ selected = "", entries = {} })
                expect(humanState({ selected = "preset:technical", entries = { entry("preset:technical") } }))
                    .to.deepEqual({ selected = "", entries = {} })
                local cards, current = must(PW.UI).Match.ClassCards(nil)
                expect(#cards).to.equal(0)
                expect(current).to.beNil()
            end
        },
        {
            name = "Mandatory T-11.15: hidden technical definition remains registered and resolvable",
            func = function(test)
                local preset = must(must(PW.Classes).Get("technical"))
                expect(preset.Hidden).to.beTrue()
                expect(preset.Abstract).to.beNil()
                expect(IsValid(preset)).to.beTrue()
                lib().SetClass(test.ply, preset.Loadout)
                local value, source = lib().Resolve(test.ply)
                expect(value).to.deepEqual(preset.Loadout)
                expect(source).to.equal("class")
                local ask = PW.Ask
                stub(PW, "Ask").with(function(name, ...)
                    if name == "PW_PlayerLoadout" then return preset.Loadout end
                    return ask(name, ...)
                end)
                local modeValue, modeSource = lib().Resolve(test.ply)
                expect(modeValue).to.deepEqual(preset.Loadout)
                expect(modeSource).to.equal("mode")
            end
        },
        {
            name = "Mandatory T-11.15: authorized bot pool keeps hidden presets but retains bans and source policy",
            func = function(test)
                local setting = PW.Setting
                local sources = { preset = true }
                stub(PW, "Setting").with(function(id)
                    if id == "bots.classes" then return sources end
                    if id == "bots_arc9_loadouts.generate" then return false end -- isolate preset source policy
                    if id == "loadout.bannedweapons" then return { weapon_shotgun = true } end
                    return setting(id)
                end)
                local bots = must(PW.BotLoadouts)
                local pool = bots.PoolFor(test.ply)
                expect(bots.Find(pool, "preset:technical")).to.exist()
                expect(bots.Find(pool, "preset:blocked")).to.beNil()
                local pick = must(bots.Find(pool, "preset:technical"))
                lib().SetClass(test.ply, pick.loadout)
                expect(lib().Resolve(test.ply)).to.deepEqual(pick.loadout)
                sources = {}
                expect(#bots.PoolFor(test.ply)).to.equal(0)
            end
        },
        {
            name = "Mandatory T-11.15: human net selection cannot bypass hiding, even with bot sender",
            func = function(test)
                lib()._OnClasses(test.ply, { { name = "Mine", loadout = { secondary = "weapon_pistol" } } })
                expect(lib()._OnPick(test.ply, "custom:1")).to.beTrue()
                test.pick = "preset:technical"
                expect(must(PW.Net)._Dispatch("pw_loadout_pick", 128, test.ply)).to.beTrue()
                expect(test.sent.selected).to.equal("custom:1")
                expect(lib()._OnPick(test.ply, test.pick)).to.beFalse()
                expect(lib().GetClass(test.ply)).to.deepEqual({ secondary = "weapon_pistol" })
            end
        },
        {
            name = "Mandatory T-11.15: save cannot select hidden id; equivalent custom contents remain legitimate",
            func = function(test)
                local raw = { primary = "weapon_smg1", builds = { primary = { cleared = false } } }
                test.upload = { { name = "My build", loadout = raw } }
                PW._LoadoutClasses.picks[test.ply] = "preset:technical"
                lib().SetClass(test.ply, { primary = "weapon_smg1" })
                expect(must(PW.Net)._Dispatch("pw_loadout_classes", 128, test.ply)).to.beTrue()
                expect(test.sent.selected).to.equal("")
                expect(PW._LoadoutClasses.picks[test.ply]).to.beNil()
                expect(lib().GetClass(test.ply)).to.beNil()
                expect(PW._LoadoutClasses.uploads[test.ply][1].loadout).to.deepEqual(raw)
                expect(lib()._OnPick(test.ply, "custom:1")).to.beTrue()
                expect(must(lib().GetClass(test.ply)).primary).to.equal("weapon_smg1")
            end
        },
        {
            name = "T-11.15: server state custom-first; hiding preserves saved slots and unavailable builds",
            func = function(test)
                local classes = {
                    { name = "Z mine", loadout = { primary = "weapon_smg1" } },
                    { name = "A mine", loadout = { primary = "weapon_smg1", secondary = "weapon_pistol" } }
                }
                local before = table.Copy(classes)
                lib()._OnClasses(test.ply, classes)
                rawset(PW._LoadoutClasses, "context", function()
                    return lib()._Context(function(id) if id == "loadout.budget" then return 1 end end,
                        lib()._RegistryLookup)
                end)
                local state = lib().RefreshClasses(test.ply)
                expect(refs(state.entries)).to.deepEqual({ "custom:1", "custom:2", "preset:legacy", "preset:visible" })
                expect(state.entries[2].available).to.beFalse()
                expect(state.entries[2].loadout).to.deepEqual(classes[2].loadout)
                expect(classes).to.deepEqual(before)
            end
        }
    }
}
