-- Operators and bot names (06-progression.md d.7; docs/api/operators.md, bots-blackboard.md "Bots manager"). Pure
-- cases over plain data: the operator list (stock and economy models, owned, free and locked ones), the choice
-- resolution and the wire check, the server glue on fake players and a fake store (the request, PlayerSetModel, the
-- team colour, bots), the bot name pool and the unique name pick through a fake manager store. No real bot is created.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.OperatorsLib
local function ops()
    return must(PW.Operators)
end

---@return PW.BotsManagerLib
local function bots()
    return must(PW.BotsManager)
end

local stock = {
    kleiner = "models/player/kleiner.mdl", alyx = "models/player/alyx.mdl",
    css_swat = "models/player/swat.mdl", male_07 = "models/player/Group01/male_07.mdl"
}

---@return PW.OperatorEconomyInput[]
local function economy()
    return {
        { id = "swat", name = "SWAT Operator", path = "models/player/swat.mdl", price = 600 },
        { id = "elite", name = "Combine Elite", path = "models/player/combine_super_soldier.mdl", price = 2000 },
        { id = "riot", name = "Riot", path = "models/player/riot.mdl", unlock = 12 },
        { id = "free", name = "Free Model", path = "models/player/barney.mdl" }
    }
end

---@param owned table<string, boolean>
---@return PW.OperatorEntry[]
local function listWith(owned)
    return ops().List({
        stock = stock, economy = economy(),
        unlocked = function(id) return owned[id] == true or id == "free" end
    })
end

---@param entries PW.OperatorEntry[]
---@param id string
---@return PW.OperatorEntry?
local function find(entries, id)
    for _, entry in ipairs(entries) do
        if entry.id == id then return entry end
    end
    return nil
end

---A fake player: records SetModel and SetPlayerColor.
---@class PW.Test.OperatorPlayer
---@field bot boolean
---@field team integer
---@field info table<string, string>
---@field model? string
---@field colour? Vector
---@field alive boolean

---@param over? table<string, any>
---@return PW.Test.OperatorPlayer, Player
local function fakePlayer(over)
    ---@type PW.Test.OperatorPlayer
    local state = { bot = false, team = 1000, info = { cl_playermodel = "alyx", cl_playercolor = "1 0 0" },
        alive = false }
    for key, value in pairs(over or {}) do (state --[[@as table<string, any>]])[key] = value end
    local ply = {
        IsBot = function() return state.bot end,
        Team = function() return state.team end,
        GetInfo = function(_, name) return state.info[name] or "" end,
        SetModel = function(_, path) state.model = path end,
        SetPlayerColor = function(_, colour) state.colour = colour end,
        Alive = function() return state.alive end,
        Nick = function() return "Tester" end
    }
    return state, ply --[[@as Player]]
end

---@param over? PW.OperatorsStoreOptions
---@param owned? table<string, boolean>
---@return PW.OperatorsStore, string[]
local function storeWith(over, owned)
    ---@type string[]
    local logs = {}
    owned = owned or {}
    ---@type PW.OperatorsStoreOptions
    local opts = {
        log = function(message) logs[#logs + 1] = message end,
        stock = function() return stock end,
        economy = economy,
        unlocked = function(_, id) return owned[id] == true or id == "free" end,
        teams = function() return 0 end,
        teamColour = function() return nil end,
        phase = function() return "LIVE" end,
        roll = function() return 0.5 end
    }
    ---@type table<string, any>
    local overrides = over or {}
    for key, value in pairs(overrides) do (opts --[[@as table<string, any>]])[key] = value end
    return must(ops()._NewStore)(opts), logs
end

---@param a Vector?
---@param r number
---@param g number
---@param b number
---@return boolean
local function colourIs(a, r, g, b)
    if a == nil then return false end
    return math.abs(a.x - r) < 0.01 and math.abs(a.y - g) < 0.01 and math.abs(a.z - b) < 0.01
end

---A fake bots manager store whose players have names; create records the names.
---@param names string[]
---@return PW.BotsStore, string[]
local function nameStore(names)
    ---@type PW.BotsEntry[]
    local entries = {}
    for index, name in ipairs(names) do
        entries[index] = { ent = { label = name }, team = 1001, bot = false, id = index, name = name }
    end
    ---@type string[]
    local created = {}
    local store = must(bots()._NewStore)({
        log = function() end, singlePlayer = function() return false end, maxPlayers = function() return 128 end,
        players = function() return entries end,
        create = function(name)
            created[#created + 1] = name
            local ent = setmetatable({ label = name }, { __index = { IsValid = function() return true end } })
            entries[#entries + 1] = { ent = ent, team = 1001, bot = true, id = #entries + 1, name = name }
            return ent --[[@as Player]]
        end,
        kick = function() end, phase = function() return "LIVE" end, fill = function() return 120 end,
        generating = function() return false end, teams = function() return 0 end, smallest = function() return nil end,
        clock = function() return 0 end, tier = function() return "regular" end, roll = math.random
    })
    return store, created
end

return {
    groupName = "PW operators and bot names",
    cases = {
        {
            name = "The list has the stock models and the economy models; owned and free ones open, others locked",
            func = function()
                local entries = listWith({ swat = true })
                expect(find(entries, "kleiner") ~= nil).to.beTrue()
                expect(find(entries, "male_07") ~= nil).to.beTrue()
                expect(must(find(entries, "models:swat")).locked).to.beFalse()
                expect(must(find(entries, "models:free")).locked).to.beFalse()
                local elite = must(find(entries, "models:elite"))
                expect(elite.locked).to.beTrue()
                expect(elite.price).to.equal(2000)
                local riot = must(find(entries, "models:riot"))
                expect(riot.locked).to.beTrue()
                expect(riot.unlock).to.equal(12)
                expect(entries[1].source).to.equal("store")
            end
        },
        {
            name = "A stock model with the path of an economy model is governed by the economy entry",
            func = function()
                expect(find(listWith({}), "css_swat")).to.beNil()
                expect(find(ops().List({ stock = stock }), "css_swat") ~= nil).to.beTrue()
            end
        },
        {
            name = "Picker cards: Auto first, locked cards show the price or level and cannot be selected",
            func = function()
                local cards, selected = ops().Cards(listWith({}), "models:elite", "alyx")
                expect(cards[1].id).to.equal("auto")
                expect(selected).to.equal("auto")
                for _, card in ipairs(cards) do
                    if card.id == "models:elite" then
                        expect(card.locked).to.beTrue()
                        expect(card.lockText).to.equal("2000 CR")
                    end
                    if card.id == "models:riot" then expect(card.lockText).to.equal("LV 12") end
                end
                local _, owned = ops().Cards(listWith({ elite = true }), "models:elite", "alyx")
                expect(owned).to.equal("models:elite")
            end
        },
        {
            name = "Resolve: a usable choice wins; locked or unknown falls back to cl_playermodel, then to the stock",
            func = function()
                local entries = listWith({ swat = true })
                expect(must(ops().Resolve(entries, "models:swat", "alyx")).id).to.equal("models:swat")
                local own, reason = ops().Resolve(entries, "models:elite", "alyx")
                expect(must(own).id).to.equal("alyx")
                expect(reason).to.equal("locked")
                local _, unknown = ops().Resolve(entries, "nope", "alyx")
                expect(unknown).to.equal("unknown")
                expect(must(ops().Resolve(entries, "auto", "alyx")).id).to.equal("alyx")
                expect(must(ops().Resolve(entries, "auto", "css_swat")).id).to.equal("kleiner")
                expect(must(ops().Resolve(entries, "auto", "")).id).to.equal("kleiner")
            end
        },
        {
            name = "The setting's options are auto plus every entry id",
            func = function()
                local ids = ops().OptionIds(listWith({}))
                expect(ids[1]).to.equal("auto")
                expect(table.HasValue(ids, "models:elite")).to.beTrue()
                expect(table.HasValue(ids, "kleiner")).to.beTrue()
                local def = PW.Settings._CurrentIndex()[ops().Setting]
                expect(def ~= nil and def.scope == "client" and def.default == "auto").to.beTrue()
            end
        },
        {
            name = "Settings: an enum with an options function validates against the current list",
            func = function()
                local list = { "a", "b" }
                local def = must(PW.Settings._CheckDef("pwt", "modules", "pick",
                    { scope = "client", type = "enum", default = "a", options = function() return list end }))
                local okB = PW.Settings._Validate(def, "b")
                local okC = PW.Settings._Validate(def, "c")
                expect(okB).to.beTrue()
                expect(okC).to.beFalse()
                list = { "a", "c" }
                local okLater = PW.Settings._Validate(def, "c")
                expect(okLater).to.beTrue()
                local _, err = PW.Settings._CheckDef("pwt", "modules", "bad",
                    { type = "enum", default = "a", options = function() return {} end })
                expect(err ~= nil).to.beTrue()
            end
        },
        {
            name = "Wire check: a choice is a short printable string",
            func = function()
                expect(ops().CheckChoice("models:swat")).to.beTrue()
                expect(ops().CheckChoice("")).to.beFalse()
                expect(ops().CheckChoice(5)).to.beFalse()
                expect(ops().CheckChoice(string.rep("a", ops().MaxChoiceBytes + 1))).to.beFalse()
                expect(ops().CheckChoice("a\nb")).to.beFalse()
            end
        },
        {
            name = "Server: a malformed request is dropped; an unowned economy model is rejected at spawn",
            func = function()
                local store, logs = storeWith()
                local state, ply = fakePlayer()
                local malformed = must(ops()._OnRequest)(store, ply, "a\0b")
                expect(malformed).to.beFalse()
                expect(store.requested[ply]).to.beNil()
                local stored, reason = must(ops()._OnRequest)(store, ply, "models:elite")
                expect(stored).to.beTrue()
                expect(reason).to.equal("locked")
                expect(#logs).to.equal(1)
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal("models/player/alyx.mdl")
                local _, unknown = must(ops()._OnRequest)(store, ply, "models/player/whatever.mdl")
                expect(unknown).to.equal("unknown")
            end
        },
        {
            name = "PlayerSetModel applies the chosen model; an owned economy model is used",
            func = function()
                local store = storeWith(nil, { elite = true })
                local state, ply = fakePlayer()
                must(ops()._OnRequest)(store, ply, "models:elite")
                expect(must(ops()._OnSetModel)(store, ply)).to.equal("models/player/combine_super_soldier.mdl")
                expect(state.model).to.equal("models/player/combine_super_soldier.mdl")
                must(ops()._OnRequest)(store, ply, "male_07")
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal("models/player/Group01/male_07.mdl")
            end
        },
        {
            name = "Outside LIVE an alive player gets a new choice at once; during LIVE from the next spawn",
            func = function()
                local phase = "LIVE"
                local store = storeWith({ phase = function() return phase end })
                local state, ply = fakePlayer({ alive = true })
                must(ops()._OnRequest)(store, ply, "kleiner")
                expect(state.model).to.beNil()
                phase = "LOBBY"
                must(ops()._OnRequest)(store, ply, "male_07")
                expect(state.model).to.equal("models/player/Group01/male_07.mdl")
            end
        },
        {
            name = "Bots get a valid model from the list (locks ignored) and keep it",
            func = function()
                local rolls = { 0.01, 0.3, 0.99 }
                for _, value in ipairs(rolls) do
                    local store = storeWith({ roll = function() return value end })
                    local state, ply = fakePlayer({ bot = true })
                    local path = must(ops()._OnSetModel)(store, ply)
                    local valid = false
                    for _, entry in ipairs(ops().List({ stock = stock, economy = economy() })) do
                        if entry.path == path then valid = true end
                    end
                    expect(valid).to.beTrue()
                    expect(must(ops()._OnSetModel)(store, ply)).to.equal(state.model)
                end
                local real = ops().List(ops().LiveInput())
                expect(#real > 0).to.beTrue()
                expect(util.IsValidModel(must(ops().BotPick(real, math.random)).path)).to.beTrue()
            end
        },
        {
            name = "The team colour applies in team modes; FFA uses cl_playercolor, bots a colour of their own",
            func = function()
                local store = storeWith({
                    teams = function() return 2 end, teamColour = function() return Color(0, 255, 0) end
                })
                local human, ply = fakePlayer({ team = 2 })
                must(ops()._OnSetModel)(store, ply)
                expect(colourIs(human.colour, 0, 1, 0)).to.beTrue()
                local bot, botPly = fakePlayer({ team = 1, bot = true })
                must(ops()._OnSetModel)(store, botPly)
                expect(colourIs(bot.colour, 0, 1, 0)).to.beTrue()
                local ffa = storeWith()
                local free, freePly = fakePlayer({ team = 1000 })
                must(ops()._OnSetModel)(ffa, freePly)
                expect(colourIs(free.colour, 1, 0, 0)).to.beTrue()
                local ffaBot, ffaBotPly = fakePlayer({ team = 1000, bot = true })
                must(ops()._OnSetModel)(ffa, ffaBotPly)
                local first = must(ffaBot.colour)
                must(ops()._OnSetModel)(ffa, ffaBotPly)
                expect(colourIs(ffaBot.colour, first.x, first.y, first.z)).to.beTrue()
            end
        },
        {
            name = "The bot name pool is non-empty and has no duplicates",
            func = function()
                local pool = bots().NamePool
                expect(#pool >= 90).to.beTrue()
                ---@type table<string, boolean>
                local seen = {}
                for _, name in ipairs(pool) do
                    local key = string.lower(name)
                    expect(seen[key]).to.beNil()
                    expect(string.match(name, "^Bot%s*%d+$")).to.beNil()
                    seen[key] = true
                end
            end
        },
        {
            name = "Bot names are unique among the players and never BotNN, also past the pool size",
            func = function()
                ---@type table<string, boolean>
                local taken = { mike = true }
                for _ = 1, #bots().NamePool + 30 do
                    local name = bots()._PickName(bots().NamePool, taken, math.random)
                    expect(taken[string.lower(name)]).to.beNil()
                    expect(string.match(name, "^[Bb]ot%s*%d+$")).to.beNil()
                    taken[string.lower(name)] = true
                end
            end
        },
        {
            name = "The manager creates bots with unique pool names, never a human's name",
            func = function()
                local store, created = nameStore({ "Mike", "Viper" })
                local made = must(bots()._Step)(store)
                expect(made).to.equal(#created)
                expect(#created > 50).to.beTrue()
                ---@type table<string, boolean>
                local seen = { mike = true, viper = true }
                for _, name in ipairs(created) do
                    expect(seen[string.lower(name)]).to.beNil()
                    expect(string.match(name, "^Bot%s*%d+$")).to.beNil()
                    seen[string.lower(name)] = true
                end
            end
        },
        {
            name = "The choice message is registered through PW.Net.Receive",
            func = function()
                expect(net.Receivers[ops().NetName] ~= nil).to.beTrue()
            end
        }
    }
}
