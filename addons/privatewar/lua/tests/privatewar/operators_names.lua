-- Operators and bot names (06-progression.md d.7; docs/api/operators.md, bots-blackboard.md "Bots manager"). Pure
-- cases over plain data: the operator list (stock and economy models, owned, free and locked ones), the choice
-- resolution and the wire check, the server glue on fake players and a fake store (the request, PlayerSetModel, the
-- team colour, bots), the bot name pool and the unique name pick through a fake manager store. The engine smoke
-- reuses an existing player, restores their model and colour, and never creates another bot.

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

---A local seeded roll stub; never changes the engine's global random state.
---@param seed integer
---@return fun(): number
local function seededRoll(seed)
    return function()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
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
---@return PW.BotsStore, string[], PW.BotsEntry[]
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
    return store, created, entries
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
                expect(must(ops().Resolve(entries, "auto", "css_swat")).id).to.equal("alyx")
                expect(must(ops().Resolve(entries, "auto", "")).id).to.equal("alyx")
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
            name = "Server: malformed, unknown and unowned requests preserve the previous choice and model",
            func = function()
                local store, logs = storeWith({ phase = function() return "LOBBY" end })
                local state, ply = fakePlayer({ alive = true })
                expect(must(ops()._OnRequest)(store, ply, 5)).to.beFalse()
                expect(store.requested[ply]).to.beNil()
                expect(must(ops()._OnRequest)(store, ply, "kleiner")).to.beTrue()
                for _, choice in ipairs({ 5, {}, "a\0b", "models/player/whatever.mdl", "models:elite" }) do
                    local accepted = must(ops()._OnRequest)(store, ply, choice)
                    expect(accepted).to.beFalse()
                    expect(store.requested[ply]).to.equal("kleiner")
                    expect(state.model).to.equal("models/player/kleiner.mdl")
                end
                local _, locked = must(ops()._OnRequest)(store, ply, "models:elite")
                expect(locked).to.equal("locked")
                local _, unknown = must(ops()._OnRequest)(store, ply, "missing")
                expect(unknown).to.equal("unknown")
                expect(#logs > 0).to.beTrue()
                expect(must(ops()._OnRequest)(store, ply, "auto")).to.beTrue()
                expect(store.requested[ply]).to.equal("auto")
                expect(state.model).to.equal("models/player/alyx.mdl")
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
            name = "The bot name pool has about 100 names, no empty entries and no duplicates",
            func = function()
                local pool = bots().NamePool
                expect(#pool >= 90 and #pool <= 110).to.beTrue()
                ---@type table<string, boolean>
                local seen = {}
                for _, name in ipairs(pool) do
                    expect(string.Trim(name) ~= "").to.beTrue()
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
            name = "Fallback uses the first stock entry, never an economy entry ahead of stock",
            func = function()
                local entries = ops().List({ stock = { barney = "models/player/barney.mdl" },
                    economy = { { id = "free", name = "A Free Model", path = "models/player/alyx.mdl" } } })
                expect(entries[1].source).to.equal("store")
                expect(must(ops().Resolve(entries, "auto", "missing")).id).to.equal("barney")
                local store = storeWith({ stock = function() return {} end })
                local state, ply = fakePlayer()
                expect(must(ops()._OnSetModel)(store, ply)).to.equal(ops().FallbackPath)
                expect(state.model).to.equal(ops().FallbackPath)
                expect(ops().Resolve({}, "auto", "")).to.beNil()
            end
        },
        {
            name = "A player without a choice gets cl_playermodel, otherwise the first stock model",
            func = function()
                local store = storeWith()
                local state, ply = fakePlayer({ info = { cl_playermodel = "male_07" } })
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal(stock.male_07)
                state.info.cl_playermodel = "missing"
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal(stock.alyx)
                expect(store.requested[ply]).to.beNil()
            end
        },
        {
            name = "Ownership is checked at each request and spawn; later unavailable choices safely fall back",
            func = function()
                local owned = { elite = true }
                local store = storeWith(nil, owned)
                local state, ply = fakePlayer()
                expect(must(ops()._OnRequest)(store, ply, "models:elite")).to.beTrue()
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal("models/player/combine_super_soldier.mdl")
                owned.elite = false
                expect(must(ops()._OnRequest)(store, ply, "models:elite")).to.beFalse()
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal(stock.alyx)
                owned.elite = true
                expect(must(ops()._OnRequest)(store, ply, "models:elite")).to.beTrue()
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal("models/player/combine_super_soldier.mdl")
                store.economy = function() return {} end
                must(ops()._OnSetModel)(store, ply)
                expect(state.model).to.equal(stock.alyx)
            end
        },
        {
            name = "LiveInput includes Workshop player_manager models without a hardcoded whitelist",
            func = function()
                stub(player_manager, "AllValidModels").with(function()
                    return { workshop_operator = "models/workshop/operator.mdl" }
                end)
                local entry = must(find(ops().List(ops().LiveInput()), "workshop_operator"))
                expect(entry.path).to.equal("models/workshop/operator.mdl")
                expect(entry.locked).to.beFalse()
            end
        },
        {
            name = "Seeded bot rolls keep the session model but choose different valid models across sessions",
            func = function()
                local first = storeWith({ roll = seededRoll(1) })
                local _, ply = fakePlayer({ bot = true })
                local path = must(ops()._OnSetModel)(first, ply)
                first.roll = seededRoll(123456)
                expect(must(ops()._OnSetModel)(first, ply)).to.equal(path)
                local second = storeWith({ roll = seededRoll(123456) })
                local other = must(ops()._OnSetModel)(second, ply)
                expect(other ~= path).to.beTrue()
                ---@type table<string, boolean>
                local valid = {}
                for _, entry in ipairs(listWith({})) do valid[entry.path] = true end
                expect(valid[path] and valid[other]).to.beTrue()
            end
        },
        {
            name = "Exhausted names use the first pool name and lowest unused suffix without RNG",
            func = function()
                local pool = { "Viper", "Mike" }
                local taken = { viper = true, mike = true, ["viper 2"] = true, ["viper 4"] = true }
                for _, value in ipairs({ 0, 0.5, 0.99 }) do
                    expect(bots()._PickName(pool, taken, function() return value end)).to.equal("Viper 3")
                end
                expect(bots()._PickName(pool, taken, function() error("exhausted pool must not roll") end))
                    .to.equal("Viper 3")
                local empty = bots()._PickName({}, { ["operator 2"] = true }, function()
                    error("empty pool must not roll")
                end)
                expect(empty).to.equal("Operator 3")
            end
        },
        {
            name = "The manager releases a departed bot name and reuses it on the next creation step",
            func = function()
                local store, created, entries = nameStore({ string.upper(bots().NamePool[1]) })
                store.fill = function() return 2 end
                store.roll = function() return 0 end
                expect(must(bots()._Step)(store)).to.equal(1)
                local departed = must(table.remove(entries))
                expect(departed.bot).to.beTrue()
                local name = created[1]
                expect(departed.name).to.equal(name)
                expect(name ~= bots().NamePool[1]).to.beTrue()
                expect(bots()._TakenNames(entries)[string.lower(name)]).to.beNil()
                expect(#entries).to.equal(1)
                expect(entries[1].bot).to.beFalse()
                expect(must(bots()._Step)(store)).to.equal(1)
                expect(created[2]).to.equal(name)
                expect(entries[2].name).to.equal(name)
                expect(entries[2].name ~= entries[1].name).to.beTrue()
            end
        },
        {
            name = "Engine smoke: PlayerSetModel applies a valid operator using a shared player without new slots",
            func = function(state)
                local ply = must(player.GetBots()[1] or player.GetHumans()[1])
                expect(ply).to.beValid()
                state.smokePlayer, state.smokeModel, state.smokeColour = ply, ply:GetModel(), ply:GetPlayerColor()
                state.previousOperators = PW._Operators
                local store = storeWith({ stock = function() return player_manager.AllValidModels() end,
                    economy = function() return {} end })
                PW._Operators = store
                store.requested[ply] = "alyx"
                if ply:IsBot() then store.bots[ply] = { path = stock.alyx, colour = { 1, 0, 0 } } end
                hook.Run("PlayerSetModel", ply)
                expect(ply:GetModel()).to.equal(stock.alyx)
                expect(util.IsValidModel(must(ply:GetModel()))).to.beTrue()
            end,
            cleanup = function(state)
                if state.previousOperators ~= nil then PW._Operators = state.previousOperators end
                local ply = state.smokePlayer --[[@as Player?]]
                if ply ~= nil and IsValid(ply) then
                    ply:SetModel(state.smokeModel)
                    ply:SetPlayerColor(state.smokeColour)
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
