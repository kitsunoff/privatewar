-- T-4.7 Classes: repair removes unavailable items and keeps the rest; the size-limited upload rejects an oversized
-- payload; a class is marked unavailable when a playlist lowers the budget (TASKS.md, "Mandatory test cases" T-4.7;
-- 05-loadout.md d.12, d.13). Pure cases over plain data (fake catalogue, injected context); the net cases drive the
-- receive path (PW.Net._Dispatch) with one shared sender (a live bot, else a stand-in), a fresh net store and a fresh
-- class store.

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
        pwt_smg = { Category = "smg", Attachments = { optic = {}, grip = {}, secret = { Hidden = true } } },
        pwt_ar = { Category = "ar" },
        pwt_banned = { Category = "ar" },
        pwt_pistol = { Category = "pistol" }
    },
    perks = { pwt_perk = {} }
}

---@param kind string
---@param id string
---@return table<string, any>?
local function lookup(kind, id)
    local data = catalogue[kind]
    return data ~= nil and data[id] or nil
end

local slots = {
    primary = { id = "primary", kind = "weapons", filter = { "ar", "smg" } },
    secondary = { id = "secondary", kind = "weapons", filter = { "pistol" } },
    perk1 = { id = "perk1", kind = "perks" }
}

---@param over table<string, any>?
---@return PW.LoadoutContext
local function ctxWith(over)
    local ctx = {
        lookup = lookup, budget = 10, maxattachments = 5,
        bannedWeapons = { pwt_banned = true }, bannedAttachments = { grip = true }
    }
    for key, value in pairs(over or {}) do ctx[key] = value end
    return ctx --[[@as PW.LoadoutContext]]
end

---A writer and a reader over one list of values (stands in for net.Write*/net.Read*).
---@return PW.LoadoutWriter, PW.LoadoutReader, any[]
local function buffer()
    ---@type any[]
    local data = {}
    local pos = 0
    local function push(value) data[#data + 1] = value end
    local function pull()
        pos = pos + 1
        return data[pos]
    end
    local writer = { uint = push, string = push, bool = push }
    local reader = {
        uint = function() return pull() or 0 end,
        string = function() return pull() or "" end,
        bool = function() return pull() == true end
    }
    return writer, reader, data
end

---The sender: a bot another group left alive, else a stand-in player table. No bot is created: the suite runs at
---maxplayers 12, a kicked bot frees its slot late, and the groups after this one (net wrapper, map change) need two
---bots each. The stand-in is enough for the receive path (privilege "any" is not checked against the player; the
---buckets, the uploads and the class store are keyed by it). The class of a reused bot is saved and restored.
---@param state table<string, any>
---@return Player
local function sharedBot(state)
    local bot = state.bot --[[@as Player?]]
    if bot ~= nil then return bot end
    bot = player.GetBots()[1]
    if bot == nil then
        local standIn = { IsValid = function() return false end, Nick = function() return "PW classes stand-in" end }
        bot = standIn --[[@as Player]]
    end
    state.bot = bot
    state.savedClass = loadout().GetClass(bot)
    return bot
end

---Installs a fresh net store and a fresh class store that reads `state.upload` and records what it sends.
---@param state table<string, any>
local function freshStores(state)
    state.previousNet, state.previousClasses = PW._Net, PW._LoadoutClasses
    state.sent = {}
    PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end })
    PW._LoadoutClasses = loadout()._NewClassStore({
        read = function() return state.upload end,
        readPick = function() return state.pick end,
        send = function(_, classState)
            local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
            sent[#sent + 1] = classState
        end,
        context = function() return ctxWith({ lookup = loadout()._RegistryLookup }) end
    })
    loadout()._RegisterClassNet(nil)
end

return {
    groupName = "PW loadout classes",
    beforeAll = function(state) state.now = 1000 end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil then loadout().SetClass(bot, state.savedClass --[[@as PW.Loadout?]]) end
    end,
    afterEach = function(state)
        if state.previousNet ~= nil then PW._Net = state.previousNet end
        if state.previousClasses ~= nil then PW._LoadoutClasses = state.previousClasses end
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil then loadout().SetClass(bot, state.savedClass --[[@as PW.Loadout?]]) end
        rawset(state, "previousNet", nil)
        rawset(state, "previousClasses", nil)
    end,
    cases = {
        {
            name = "Repair: unavailable items are removed and the rest is kept",
            func = function()
                local raw = {
                    primary = "pwt_smg", secondary = "pwt_gone", perk1 = "pwt_perk", ghost = "pwt_ar",
                    builds = { primary = { optic = "optic", grip = "grip", hidden = "secret", cleared = false } }
                }
                local repaired, removed = loadout()._RepairClass(slots, raw, ctxWith())
                expect(repaired).to.deepEqual({
                    primary = "pwt_smg", perk1 = "pwt_perk",
                    builds = { primary = { optic = "optic", cleared = false } }
                })
                -- ghost (unknown slot), pwt_gone (unknown item), grip (banned), secret (hidden)
                expect(#removed).to.equal(4)
                -- A banned weapon goes with its build; the other slot stays.
                local banned = {
                    primary = "pwt_banned", secondary = "pwt_pistol", builds = { primary = { o = "optic" } }
                }
                local kept = loadout()._RepairClass(slots, banned, ctxWith())
                expect(kept).to.deepEqual({ secondary = "pwt_pistol" })
                -- A wrong category and too many items are removed too.
                local misfit = { primary = "pwt_pistol", secondary = { "pwt_pistol", "pwt_pistol" } }
                expect(loadout()._RepairClass(slots, misfit, ctxWith())).to.deepEqual({ secondary = "pwt_pistol" })
            end
        },
        {
            name = "Availability: a class is marked unavailable when a playlist lowers the budget, not trimmed",
            func = function()
                local raw = {
                    primary = "pwt_smg", secondary = "pwt_pistol", perk1 = "pwt_perk",
                    builds = { primary = { optic = "optic" } }
                }
                local settings = {}
                local read = function(id) return settings[id] end
                local status = loadout()._ClassStatus(slots, raw, loadout()._Context(read, lookup))
                expect(status.available).to.beTrue()
                settings["loadout.budget"] = 3 -- the playlist: smg + optic + pistol + perk = 4
                local lowered = loadout()._ClassStatus(slots, raw, loadout()._Context(read, lookup))
                expect(lowered.available).to.beFalse()
                expect(string.find(must(lowered.reason), "budget", 1, true)).to.exist()
                expect(lowered.loadout).to.deepEqual(raw)
                expect(#lowered.removed).to.equal(0)
                -- A class that nothing is left of is unavailable as well.
                local empty = loadout()._ClassStatus(slots, { primary = "pwt_gone" }, ctxWith())
                expect(empty.available).to.beFalse()
            end
        },
        {
            name = "Upload: an oversized payload is rejected before the handler; one within the limit is handled",
            func = function(state)
                freshStores(state)
                local bot = sharedBot(state)
                state.upload = { { name = "Mine", loadout = { primary = "weapon_ar2", secondary = "weapon_pistol" } } }
                local limit = loadout().ClassesMaxBytes
                local ok, reason = must(PW.Net)._Dispatch("pw_loadout_classes", (limit + 1) * 8, bot)
                expect(ok).to.beFalse()
                expect(reason).to.equal("length")
                expect(#state.sent).to.equal(0)
                state.now = state.now --[[@as number]] + 10
                expect(must(PW.Net)._Dispatch("pw_loadout_classes", limit * 8, bot)).to.beTrue()
                expect(#state.sent).to.equal(1)
                local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
                local entries = sent[1].entries
                expect(entries[1].ref).to.equal("custom:1")
                expect(entries[1].available).to.beTrue()
            end
        },
        {
            name = "Upload: messages over the rate are dropped",
            func = function(state)
                freshStores(state)
                local bot = sharedBot(state)
                state.upload = {}
                state.now = state.now --[[@as number]] + 10
                expect(must(PW.Net)._Dispatch("pw_loadout_classes", 64, bot)).to.beTrue()
                local ok, reason = must(PW.Net)._Dispatch("pw_loadout_classes", 64, bot)
                expect(ok).to.beFalse()
                expect(reason).to.equal("rate")
            end
        },
        {
            name = "Pick: an available class is set for the next spawn; an unavailable one is refused",
            func = function(state)
                freshStores(state)
                local bot = sharedBot(state)
                state.upload = {
                    { name = "Rifle", loadout = { primary = "weapon_ar2", secondary = "weapon_pistol" } },
                    { name = "Pricey", loadout = { primary = "weapon_ar2", secondary = "weapon_357" } }
                }
                state.now = state.now --[[@as number]] + 10
                expect(must(PW.Net)._Dispatch("pw_loadout_classes", 64, bot)).to.beTrue()
                state.pick = "custom:1"
                expect(must(PW.Net)._Dispatch("pw_loadout_pick", 64, bot)).to.beTrue()
                local class, source = loadout().Resolve(bot)
                expect(source).to.equal("class")
                expect(class).to.deepEqual({ primary = "weapon_ar2", secondary = "weapon_pistol" })
                local sent = state.sent --[[@as PW.LoadoutClassState[] ]]
                expect(sent[#sent].selected).to.equal("custom:1")
                -- Over the budget of 1: refused, the previous class stays.
                PW._LoadoutClasses.context = function()
                    return ctxWith({ lookup = loadout()._RegistryLookup, budget = 1 })
                end
                expect(loadout()._OnPick(bot, "custom:2")).to.beFalse()
                expect(loadout().GetClass(bot)).to.deepEqual({ primary = "weapon_ar2", secondary = "weapon_pistol" })
                expect(loadout()._OnPick(bot, "nonsense")).to.beFalse()
            end
        },
        {
            name = "Presets: the classes kind ships presets that pass Validate at the default budget",
            func = function()
                local list = must(PW.Classes).GetList()
                expect(#list >= 2).to.beTrue()
                local ctx = loadout()._Context(function() return nil end, loadout()._RegistryLookup)
                for _, preset in ipairs(list) do
                    local ok, err = loadout()._Validate(PW._Loadout.slots, preset.Loadout, ctx.lookup, ctx)
                    expect(err).toNot.exist()
                    expect(ok).to.beTrue()
                end
            end
        },
        {
            name = "Presets: every preset carries a lethal and a tactical and stays within the default budget",
            func = function()
                local ctx = loadout()._Context(function() return nil end, loadout()._RegistryLookup)
                for _, preset in ipairs(must(PW.Classes).GetList()) do
                    expect(preset.Loadout.lethal).to.equal("frag")
                    expect(preset.Loadout.tactical).to.equal("flash")
                    local ok, err = loadout()._Validate(PW._Loadout.slots, preset.Loadout, ctx.lookup, ctx)
                    expect(err).toNot.exist()
                    expect(ok).to.beTrue()
                    expect(loadout()._Cost(PW._Loadout.slots, preset.Loadout, ctx) <= ctx.budget).to.beTrue()
                end
            end
        },
        {
            name = "Wire: classes survive an encode and decode round trip; decoding caps the class count",
            func = function()
                local classes = {
                    {
                        name = "One",
                        loadout = { primary = "a", perk1 = { "p", "q" }, builds = { primary = { o = "x", c = false } } }
                    },
                    { name = "Two", loadout = { secondary = "b" } }
                }
                local writer, reader = buffer()
                loadout()._EncodeClasses(classes, writer)
                expect(loadout()._DecodeClasses(reader, 10)).to.deepEqual(classes)
                local writer2, reader2 = buffer()
                loadout()._EncodeClasses(classes, writer2)
                local capped = loadout()._DecodeClasses(reader2, 1)
                expect(#capped).to.equal(1)
                expect(capped[1].name).to.equal("One")
            end
        },
        {
            name = "Wire: the class state survives an encode and decode round trip",
            func = function()
                ---@type PW.LoadoutClassState
                local classState = {
                    selected = "preset:assault",
                    entries = {
                        { ref = "preset:assault", name = "Assault", available = true, removed = {},
                            loadout = { primary = "weapon_ar2" } },
                        { ref = "custom:1", name = "Mine", available = false, reason = "the budget is 3",
                            removed = { "pwt_gone (unknown)" }, loadout = { secondary = "weapon_pistol" } }
                    }
                }
                local writer, reader = buffer()
                loadout()._EncodeClassState(classState, writer)
                expect(loadout()._DecodeClassState(reader)).to.deepEqual(classState)
            end
        },
        {
            name = "File: classes.json is sanitized, nameless classes get a name, the list is capped",
            func = function()
                local parsed = loadout()._ClassesFromJson({
                    version = 1,
                    classes = {
                        { name = "Good", loadout = { primary = "a", builds = { primary = { o = "x", bad = 5 } } } },
                        { loadout = { primary = 7, secondary = "b" } },
                        "junk",
                        { name = "Third", loadout = {} }
                    }
                }, 2)
                expect(parsed).to.deepEqual({
                    { name = "Good", loadout = { primary = "a", builds = { primary = { o = "x" } } } },
                    { name = "Class 2", loadout = { secondary = "b" } }
                })
                expect(#loadout()._ClassesFromJson("nope", 5)).to.equal(0)
            end
        },
        {
            name = "Cards: an unavailable class shows its reason; the rows list the contents",
            func = function()
                ---@type PW.LoadoutClassState
                local classState = {
                    selected = "custom:1",
                    entries = {
                        { ref = "custom:1", name = "Mine", available = true, removed = {},
                            loadout = { primary = "weapon_ar2" } },
                        { ref = "custom:2", name = "Big", available = false, reason = "the budget is 3", removed = {},
                            loadout = { primary = "weapon_ar2", builds = { primary = { o = "x" } } } }
                    }
                }
                local cards = loadout()._ClassCards(classState)
                expect(#cards).to.equal(2)
                expect(cards[1].badge).to.equal("IN USE")
                expect(cards[2].badge).to.equal("N/A")
                expect(cards[2].text).to.equal("the budget is 3")
                local rows = loadout()._ClassRows(classState.entries[2], function(_, id) return "<" .. id .. ">" end)
                expect(rows[1][2]).to.equal("<weapon_ar2>")
                expect(#rows).to.equal(2)
            end
        }
    }
}
