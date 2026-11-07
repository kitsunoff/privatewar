-- T-5.12 bot profiles (TASKS.md, "Mandatory test cases" T-5.12; 07-bots.md d.10, d.15; docs/api/bots-blackboard.md
-- "Kinds"). The difficulty tiers and the personalities are data files; the rules are pure functions over plain data.
-- The manager cases run on a fake store (create and kick only record), so they never create a bot.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.BotProfilesLib
local function profiles()
    return must(PW.BotProfiles)
end

---@param kind PW.BotProfileKind
---@return PW.Entity[]
local function allFiles(kind)
    local registry = must(kind == "difficulty" and PW.BotDifficulties or PW.BotPersonalities)
    return registry.GetList()
end

---@param id string
---@return table<string, any>
local function tier(id)
    return must(PW.BotDifficulties).Get(id) --[[@as table<string, any>]]
end

local tierIds = { "recruit", "regular", "hardened", "veteran" }

---@param roll number
---@return fun(): number
local function fixed(roll)
    return function() return roll end
end

---A fake engine for a manager store: players are plain entries, create and kick only record.
---@class PW.Test.ProfilesWorld
---@field entries PW.BotsEntry[]
---@field teams integer
---@field tier string
---@field roll number
---@field nextId integer

---@param teams integer
---@param tierId string
---@return PW.Test.ProfilesWorld
local function newWorld(teams, tierId)
    return { entries = {}, teams = teams, tier = tierId, roll = 0, nextId = 1 }
end

---@param world PW.Test.ProfilesWorld
---@param team integer
---@param count integer
local function addBots(world, team, count)
    for _ = 1, count do
        local meta = { __index = { IsValid = function() return true end } }
        local ent = setmetatable({ label = "bot" .. world.nextId }, meta)
        world.entries[#world.entries + 1] = { ent = ent, team = team, bot = true, id = world.nextId }
        world.nextId = world.nextId + 1
    end
end

---@param world PW.Test.ProfilesWorld
---@return PW.BotsStore
local function storeFor(world)
    return must(PW.BotsManager and PW.BotsManager._NewStore)({
        log = function() end,
        singlePlayer = function() return false end,
        maxPlayers = function() return 64 end,
        players = function() return { unpack(world.entries) } end,
        create = function() return nil end,
        kick = function() end,
        phase = function() return "LIVE" end,
        fill = function() return #world.entries end,
        generating = function() return false end,
        teams = function() return world.teams end,
        smallest = function() return 1 end,
        clock = function() return 0 end,
        tier = function() return world.tier end,
        roll = function() return world.roll end
    })
end

---@param store PW.BotsStore
---@param world PW.Test.ProfilesWorld
---@param team integer?
---@return integer active, integer stationary
local function countTypes(store, world, team)
    local active, stationary = 0, 0
    for _, entry in ipairs(world.entries) do
        local board = must(store.boards[entry.ent])
        if team == nil or board.team == team then
            if must(board.personality).type == "stationary" then
                stationary = stationary + 1
            else
                active = active + 1
            end
        end
    end
    return active, stationary
end

return {
    groupName = "PW bot profiles",
    cases = {
        {
            name = "Mandatory (T-5.12): every field of every difficulty file is read somewhere",
            func = function()
                local files = allFiles("difficulty")
                expect(#files).to.equal(#tierIds)
                expect(profiles().Audit("difficulty", files)).to.deepEqual({})
                local readers = profiles().Declared.difficulty
                for _, consumer in ipairs({ "aim", "perception", "brain", "objectives" }) do
                    expect(readers[consumer] ~= nil).to.beTrue()
                end
            end
        },
        {
            name = "Mandatory (T-5.12): every field of every personality file is read somewhere",
            func = function()
                local files = allFiles("personality")
                expect(#files >= 3).to.beTrue()
                expect(profiles().Audit("personality", files)).to.deepEqual({})
                expect(profiles().Declared.personality.objectives ~= nil).to.beTrue()
            end
        },
        {
            name = "Profiles: the field audit fails for an unused field and for a declared field a file lacks",
            func = function()
                local lib = profiles()
                local regular = lib.Snapshot(tier("regular"))
                regular.never_read = 1
                local unused = lib.Audit("difficulty", { regular })
                expect(#unused).to.equal(1)
                expect(string.find(unused[1], "regular.never_read is read by nobody", 1, true) ~= nil).to.beTrue()
                local missing = lib.Snapshot(tier("veteran"))
                missing.teamwork = nil
                local lacking = lib.Audit("difficulty", { missing })
                expect(#lacking).to.equal(1)
                expect(string.find(lacking[1], "veteran lacks teamwork", 1, true) ~= nil).to.beTrue()
            end
        },
        {
            name = "Mandatory (T-5.12): the team personality ratio is 4:1",
            func = function()
                local lib = profiles()
                expect(lib.Ratio.active).to.equal(4)
                expect(lib.Ratio.stationary).to.equal(1)
                local active, stationary = 0, 0
                for bots = 1, 20 do
                    if lib.NextType(active, stationary) == "stationary" then stationary = stationary + 1
                    else active = active + 1 end
                    if bots % 5 == 0 then
                        expect(active).to.equal(4 * bots / 5)
                        expect(stationary).to.equal(bots / 5)
                    end
                    expect(stationary * 4 <= bots).to.beTrue()
                end
                expect(lib.NextType(0, 0)).to.equal("active")
                expect(lib.NextType(4, 0)).to.equal("stationary")
                expect(lib.NextType(4, 1)).to.equal("active")
            end
        },
        {
            name = "Mandatory (T-5.12): the manager gives each team 4 active : 1 stationary, and FFA bots too",
            func = function()
                local world = newWorld(2, "regular")
                addBots(world, 1, 10)
                addBots(world, 2, 5)
                local store = storeFor(world)
                must(PW.BotsManager)._Step(store)
                local a1, s1 = countTypes(store, world, 1)
                local a2, s2 = countTypes(store, world, 2)
                expect({ a1, s1, a2, s2 }).to.deepEqual({ 8, 2, 4, 1 })
                must(PW.BotsManager)._Step(store)
                expect({ countTypes(store, world, 1) }).to.deepEqual({ 8, 2 })

                local ffa = newWorld(0, "regular")
                addBots(ffa, 1001, 10)
                local ffaStore = storeFor(ffa)
                must(PW.BotsManager)._Step(ffaStore)
                expect({ countTypes(ffaStore, ffa) }).to.deepEqual({ 8, 2 })
            end
        },
        {
            name = "Manager: a bot whose team is not known yet waits for it, a replacement keeps the team ratio",
            func = function()
                local world = newWorld(2, "regular")
                addBots(world, 1001, 1)
                addBots(world, 1, 4)
                local store = storeFor(world)
                must(PW.BotsManager)._Step(store)
                expect(must(store.boards[world.entries[1].ent]).personality).to.equal(nil)
                expect(must(store.boards[world.entries[1].ent]).difficulty ~= nil).to.beTrue()
                world.entries[1].team = 1
                must(PW.BotsManager)._Step(store)
                expect({ countTypes(store, world, 1) }).to.deepEqual({ 4, 1 })
            end
        },
        {
            name = "Manager: board.difficulty is the full table of the setting's tier, board.personality a full table",
            func = function()
                local world = newWorld(2, "veteran")
                addBots(world, 1, 1)
                local store = storeFor(world)
                must(PW.BotsManager)._Step(store)
                local board = must(store.boards[world.entries[1].ent])
                local difficulty = must(board.difficulty)
                expect(difficulty.ClassName).to.equal("veteran")
                for _, field in ipairs(profiles().Fields(tier("veteran"))) do
                    expect(difficulty[field]).to.equal(tier("veteran")[field])
                end
                expect(difficulty ~= tier("veteran")).to.beTrue()
                local personality = must(board.personality)
                expect(personality.type).to.equal("active")
                expect(isstring(personality.ClassName)).to.beTrue()
            end
        },
        {
            name = "Manager: the setting mix gives each bot a tier by roll",
            func = function()
                local world = newWorld(2, "mix")
                world.roll = 0.99
                addBots(world, 1, 1)
                local store = storeFor(world)
                must(PW.BotsManager)._Step(store)
                expect(must(must(store.boards[world.entries[1].ent]).difficulty).ClassName).to.equal("veteran")
            end
        },
        {
            name = "Tiers: the four tiers hold the design values of 07 d.15 and get stronger in order",
            func = function()
                ---@type number[], number[], number[], number[], string[], number[]
                local reaction, focus, turn, share, headshots, teamwork = {}, {}, {}, {}, {}, {}
                for i, id in ipairs(tierIds) do
                    local data = tier(id)
                    reaction[i] = tonumber(data.reaction_mean) or 0
                    focus[i] = tonumber(data.aim_focus_initial) or 0
                    turn[i] = tonumber(data.turn_max_speed) or 0
                    share[i] = tonumber(data.share_delay) or 0
                    headshots[i] = tostring(data.headshot_allowed)
                    teamwork[i] = tonumber(data.teamwork) or 0
                end
                expect(reaction).to.deepEqual({ 0.60, 0.45, 0.32, 0.22 })
                expect(focus).to.deepEqual({ 20, 12, 6, 2 })
                expect(turn).to.deepEqual({ 180, 360, 540, 720 })
                expect(share).to.deepEqual({ 2.0, 1.5, 1.0, 0.5 })
                expect(headshots).to.deepEqual({ "no", "no", "rifles", "yes" })
                for i = 2, #tierIds do expect(teamwork[i] > teamwork[i - 1]).to.beTrue() end
            end
        },
        {
            name = "Tiers: the setting options are the tier files plus mix",
            func = function()
                ---@type string[]
                local options = {}
                for _, group in ipairs(must(PW.Settings).GetGroups("match")) do
                    for _, field in ipairs(group.fields) do
                        if field.def.id == "bots.difficulty" then options = must(field.def.options) end
                    end
                end
                expect(#options > 0).to.beTrue()
                ---@type string[]
                local expected = {}
                for i, entity in ipairs(allFiles("difficulty")) do expected[i] = entity.ClassName end
                table.sort(expected)
                table.sort(options)
                expected[#expected + 1] = "mix"
                table.sort(expected)
                expect(options).to.deepEqual(expected)
            end
        },
        {
            name = "Tiers: ResolveTier maps a setting value to a tier id; mix follows the weights",
            func = function()
                local lib = profiles()
                expect(lib.ResolveTier("hardened", 0.5)).to.equal("hardened")
                expect(lib.ResolveTier("nope", 0.5)).to.equal("regular")
                expect(lib.ResolveTier(nil, 0.5)).to.equal("regular")
                ---@type table<string, integer>
                local counts = {}
                for i = 0, 599 do
                    local id = lib.ResolveTier("mix", (i + 0.5) / 600)
                    counts[id] = (counts[id] or 0) + 1
                end
                expect(counts).to.deepEqual({ recruit = 100, regular = 200, hardened = 200, veteran = 100 })
            end
        },
        {
            name = "Tiers: a missing or unknown tier reads the regular tier, and a difficulty overrides by type",
            func = function()
                local lib = profiles()
                expect(lib.Tier(nil)).to.equal(tier("regular"))
                expect(lib.Tier("nope")).to.equal(tier("regular"))
                local picked = lib.Pick({ "teamwork", "headshot_allowed" }, { teamwork = 0.1, headshot_allowed = 5 },
                    "veteran")
                expect(picked).to.deepEqual({ teamwork = 0.1, headshot_allowed = "yes" })
                expect(lib.Pick({ "teamwork" }, nil, nil)).to.deepEqual({ teamwork = tier("regular").teamwork })
            end
        },
        {
            name = "Consumers: aim and perception read a board difficulty, brain defaults match the regular tier",
            func = function()
                local veteran = profiles().Snapshot(tier("veteran"))
                expect(must(PW.BotAim).ParamsFor(veteran, nil).turn_max_speed).to.equal(720)
                expect(must(PW.BotAim).ParamsFor(nil, "recruit").turn_max_speed).to.equal(180)
                expect(must(PW.BotPerception).ParamsFor(veteran, nil).share_delay).to.equal(0.5)
                expect(must(PW.BotPerception).ParamsFor(nil, nil).reaction_mean).to.equal(0.45)
                local defaults = must(PW.BotBrain).Defaults
                expect(defaults.screen).to.equal(tier("regular").decision_screen)
                expect(defaults.bonus).to.equal(tier("regular").commitment_bonus)
            end
        },
        {
            name = "Personalities: every type is active or stationary, the camper is the stationary one",
            func = function()
                local seen = { active = 0, stationary = 0 }
                for _, entity in ipairs(allFiles("personality")) do
                    local kind = (entity --[[@as table<string, any>]]).type
                    expect(seen[kind] ~= nil).to.beTrue()
                    seen[kind] = seen[kind] + 1
                end
                expect(seen.active >= 2).to.beTrue()
                expect(seen.stationary >= 1).to.beTrue()
                expect(must(profiles().PickPersonality("stationary", 0)).ClassName).to.equal("camper")
                local first, last = profiles().PickPersonality("active", 0), profiles().PickPersonality("active", 0.99)
                expect(first ~= last).to.beTrue()
                local roll = fixed(0.2)
                expect(must(profiles().PickPersonality("active", roll())).type).to.equal("active")
            end
        }
    }
}
