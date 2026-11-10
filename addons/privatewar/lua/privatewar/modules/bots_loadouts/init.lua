-- Bots loadouts, server glue (T-5.13; 05-loadout.md d.14). Thin wrappers around the pure part (shared.lua):
--   the pool of a bot: presets (PW.Classes) and the players' pool, each checked with PW.Loadout.Validate under the
--     current match settings (no progression: a bot is not a player with unlocks);
--   the players' pool: the available custom classes of every human (PW.Loadout.ClassState), taken whenever a pool
--     is built and when a human leaves, kept until the map changes;
--   the class: PW.Loadout.SetClass(bot, loadout), so PW.Loadout.Resolve gives it on spawn (a mode's
--     PW_PlayerLoadout still wins) and the equipment and streaks modules read the same loadout.
-- When a class is given (it must be set before the PlayerSpawn listeners of equipment and streaks run, whose order
-- is not defined):
--   PW_PhaseChange LIVE  every bot gets a fresh class (before PW_MatchStart spawns everybody);
--   PostPlayerDeath      in LIVE, the class for the next life (re-pick by bots.classrepick);
--   PlayerInitialSpawn   a bot that joins during LIVE;
--   PlayerSpawn          in LIVE, a bot that still has no class (fallback);
--   PW_PhaseChange LOBBY or PREMATCH  the classes of the last match are dropped.
-- Like the bots manager, the module is paused during a GLuaTest run (store.paused): other groups' in-game cases
-- expect a bot with the default loadout; the T-5.13 smoke unpauses it for its own match.

local lib = PW.BotLoadouts --[[@as PW.BotLoadoutsLib]]

do -- a reload keeps the players' pool and the picks
    local previous = rawget(PW, "_BotLoadouts") --[[@as PW.BotLoadoutsStore?]]
    PW._BotLoadouts = previous or { players = {}, picks = setmetatable({}, { __mode = "k" }), paused = false }
end

---@param ply Player
---@return boolean
local function active(ply)
    return not PW._BotLoadouts.paused and IsValid(ply) and ply:IsBot()
end

---@return PW.LoadoutLib?
local function loadoutLib()
    return rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
end

---@return string?
local function phase()
    local match = rawget(PW, "Match") --[[@as PW.MatchLib?]]
    return match ~= nil and match.GetPhase() or nil
end

---@param id string
---@return string?
local function categoryOf(id)
    local loadout = loadoutLib()
    local entity = loadout ~= nil and loadout._RegistryLookup("weapons", id) or nil
    if entity == nil then return nil end
    local category = (entity --[[@as table<string, any>]]).Category
    return isstring(category) and category --[[@as string]] or nil
end

function lib.Harvest(ply)
    local loadout = loadoutLib()
    local classes = rawget(PW, "_LoadoutClasses") --[[@as PW.LoadoutClassStore?]]
    if loadout == nil or classes == nil then return end
    for _, human in ipairs(ply ~= nil and { ply } or player.GetHumans()) do
        if IsValid(human) and not human:IsBot() and classes.uploads[human] ~= nil then
            local owner = human:SteamID64() or tostring(human:UserID())
            PW._BotLoadouts.players[owner] = lib._HarvestEntries(owner, loadout.ClassState(human))
        end
    end
end

---@return PW.BotPresetClass[]
local function presets()
    local registry = rawget(PW, "Classes") --[[@as PW.Registry?]]
    ---@type PW.BotPresetClass[]
    local out = {}
    if registry == nil then return out end
    for _, preset in ipairs(registry.GetEnabledList() --[[@as PW.ClassPreset[] ]]) do
        out[#out + 1] = { id = preset.ClassName, name = preset.Name, loadout = preset.Loadout }
    end
    return out
end

---@return PW.BotPlayerClass[]
local function playerClasses()
    ---@type PW.BotPlayerClass[]
    local out = {}
    for _, list in pairs(PW._BotLoadouts.players) do
        for _, class in ipairs(list) do out[#out + 1] = class end
    end
    return out
end

function lib.PoolFor(bot)
    local loadout = loadoutLib()
    if loadout == nil then return {} end
    lib.Harvest(nil)
    local pool = lib.BuildPool({
        sources = lib.Sources(PW.Setting("bots.classes")),
        presets = presets(),
        players = playerClasses(),
        check = function(value) return (loadout.Validate(bot, value)) end
    })
    ---@type PW.BotClassEntry[]
    local candidates = {}
    -- Notification: providers append bot-only candidates; the owner still enforces current match validation.
    PW.Notify("PW_BotLoadoutCandidates", bot, candidates)
    lib.AppendCandidates(pool, candidates, function(value) return (loadout.Validate(bot, value)) end)
    return pool
end

---@param bot Player
---@return table<string, number>?
local function weightsOf(bot)
    local botLib = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    local board = botLib ~= nil and botLib.Get ~= nil and botLib.Get(bot) or nil
    if board == nil then return nil end
    return lib.WeightsOf(board)
end

---@return number
local function repickChance()
    local value = PW.Setting("bots.classrepick")
    return isnumber(value) and value --[[@as number]] or 0.25
end

function lib.Assign(bot, chance)
    local loadout = loadoutLib()
    if loadout == nil then return nil end
    local store = PW._BotLoadouts
    local pool = lib.PoolFor(bot)
    local entry = lib.Find(pool, store.picks[bot])
    if lib.ShouldRepick(store.picks[bot], pool, chance, math.random()) then
        entry = lib.Pick(pool, weightsOf(bot), math.random(), categoryOf)
    end
    store.picks[bot] = entry ~= nil and entry.ref or nil
    loadout.SetClass(bot, entry ~= nil and table.Copy(entry.loadout) or nil)
    return entry
end

function lib.Clear(bot)
    PW._BotLoadouts.picks[bot] = nil
    local loadout = loadoutLib()
    if loadout ~= nil then loadout.SetClass(bot, nil) end
end

function lib.PickOf(bot)
    return PW._BotLoadouts.picks[bot]
end

function MODULE:PW_PhaseChange(to)
    for _, bot in ipairs(player.GetBots()) do
        if PW._BotLoadouts.paused then
            if to ~= "LIVE" then lib.Clear(bot) end
        elseif to == "LIVE" then
            lib.Clear(bot)
            lib.Assign(bot, 1)
        elseif to == "LOBBY" or to == "PREMATCH" then
            lib.Clear(bot)
        end
    end
end

PW.HookFor(MODULE, "PlayerInitialSpawn", function(_, ply)
    if active(ply) and phase() == "LIVE" then lib.Assign(ply, 1) end
end)

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    if active(ply) and phase() == "LIVE" and lib.PickOf(ply) == nil then lib.Assign(ply, 1) end
end)

PW.HookFor(MODULE, "PostPlayerDeath", function(_, ply)
    if active(ply) and phase() == "LIVE" then lib.Assign(ply, repickChance()) end
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    if IsValid(ply) and not ply:IsBot() then lib.Harvest(ply) end
end)

-- Plain hooks, not PW.HookFor (as in the bots manager): the pause must hold even if the module is toggled meanwhile.
hook.Add("GLuaTest_StartedTestRun", "PW.BotLoadouts", function() PW._BotLoadouts.paused = true end)
hook.Add("GLuaTest_Finished", "PW.BotLoadouts", function() PW._BotLoadouts.paused = false end)
