-- Streaks module, server glue (T-4.6). Per-player state: the counter, the inventory of earned and unused streaks and
-- the streak set of the loadout. Score events in LIVE feed the counter (PW_ScoreEvent); death resets it unless
-- streaks.persist or the question PW_StreaksPersist keeps it; the inventory stays until the match ends. Use (the key
-- message, or a bot directly) takes a streak out of the inventory and makes a PW.Instance of it (OnEquip is the
-- activation) that ends after Duration. Engine calls are fields of the store, so the tests drive it with fakes.

local lib = PW.Streaks --[[@as PW.StreaksLib]]

include("privatewar/modules/streaks/sv_reveal.lua")

---@param id string
---@return PW.Streak?
local function defaultLookup(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.streaks or nil
    if registry == nil then return nil end
    local def = registry.Get(id)
    if def == nil or not def:IsValid() then return nil end
    return def --[[@as PW.Streak]]
end

---@param ply Player
---@return PW.Loadout
local function defaultResolve(ply)
    local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
    if loadout == nil then return {} end
    return (loadout.Resolve(ply))
end

---@param ply Player
---@param key string
---@param value any
local function defaultPublish(ply, key, value)
    if not isentity(ply) or not IsValid(ply) then return end
    if isnumber(value) then
        ply:SetNW2Int(key, math.floor(value --[[@as number]]))
    else
        ply:SetNW2String(key, tostring(value))
    end
end

---@return string
local function defaultPhase()
    local match = rawget(PW, "Match") --[[@as PW.MatchLib?]]
    if match == nil then return "LOBBY" end
    return match.GetPhase()
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        players = setmetatable({}, { __mode = "k" }),
        depth = 0,
        lookup = opts.lookup or defaultLookup,
        resolve = opts.resolve or defaultResolve,
        publish = opts.publish or defaultPublish,
        phase = opts.phase or defaultPhase,
        alive = opts.alive or function(ply) return IsValid(ply) and ply:Alive() end,
        setting = opts.setting or function(key) return PW.Setting("streaks." .. key) end,
        persist = opts.persist or function(ply) return PW.Ask("PW_StreaksPersist", ply) == true end,
        read = opts.read or function() return net.ReadUInt(lib.WireBits) end
    }
end

PW._Streaks = PW._Streaks or lib._NewStore()
lib._Instances = lib._Instances or setmetatable({}, { __mode = "k" })

---@return PW.StreaksStore
local function store()
    return PW._Streaks --[[@as PW.StreaksStore]]
end

---@param s PW.StreaksStore
---@param ply Player
---@return PW.StreakPlayer
local function stateOf(s, ply)
    local st = s.players[ply]
    if st == nil then
        st = { progress = 0, inventory = {}, set = {} }
        s.players[ply] = st
    end
    return st
end

---@param s PW.StreaksStore
---@param ply Player
---@param st PW.StreakPlayer
local function publishAll(s, ply, st)
    s.publish(ply, lib.ProgressKey, st.progress)
    s.publish(ply, lib.InventoryKey, lib._EncodeInventory(st.inventory))
    s.publish(ply, lib.SetKey, lib._EncodeSet(st.set))
end

---@param s PW.StreaksStore
---@param ply Player
---@param st PW.StreakPlayer
local function refreshSet(s, ply, st)
    local earn = s.setting("earn") == "score" and "score" or "kills"
    st.set = lib._Set(s.resolve(ply), s.lookup, earn)
    s.publish(ply, lib.SetKey, lib._EncodeSet(st.set))
end

function lib._OnSpawn(ply)
    if PW.Ask("PW_CanUseLoadoutKind", ply, "streaks") == false then return false end
    local s = store()
    if s.phase() ~= "LIVE" then return false end
    local st = stateOf(s, ply)
    refreshSet(s, ply, st)
    publishAll(s, ply, st)
    return true
end

function lib._OnScore(ply, eventId, points)
    local s = store()
    if PW.Ask("PW_CanUseLoadoutKind", ply, "streaks") == false then return {} end
    if s.phase() ~= "LIVE" then return {} end
    if not lib._Counts(s.setting("chain") == true, s.depth > 0) then return {} end
    local gain = lib._Gain(s.setting("earn") == "score" and "score" or "kills", eventId, points)
    if gain <= 0 then return {} end
    local st = stateOf(s, ply)
    if #st.set == 0 then refreshSet(s, ply, st) end
    local before = st.progress
    st.progress = before + gain
    local earned = lib._Crossed(st.set, before, st.progress)
    for _, id in ipairs(earned) do lib._Push(st.inventory, id, lib.MaxInventory) end
    s.publish(ply, lib.ProgressKey, st.progress)
    if #earned > 0 then s.publish(ply, lib.InventoryKey, lib._EncodeInventory(st.inventory)) end
    return earned
end

function lib._OnDeath(ply)
    local s = store()
    local st = s.players[ply]
    if st == nil then return end
    local persist = s.setting("persist") == true or s.persist(ply)
    st.progress = lib._AfterDeath(st.progress, persist)
    s.publish(ply, lib.ProgressKey, st.progress)
end

function lib._Clear(ply)
    local s = store()
    if s.players[ply] == nil then return end
    s.players[ply] = nil
    publishAll(s, ply, { progress = 0, inventory = {}, set = {} })
end

function lib._Reset()
    for ply in pairs(store().players) do lib._Clear(ply) end
end

function lib.Progress(ply)
    local st = store().players[ply]
    return st ~= nil and st.progress or 0
end

function lib.Inventory(ply)
    local st = store().players[ply]
    return st ~= nil and st.inventory or {}
end

function lib.Set(ply)
    local st = store().players[ply]
    return st ~= nil and st.set or {}
end

function lib.Give(ply, id)
    if PW.Ask("PW_CanUseLoadoutKind", ply, "streaks") == false then return false end
    local s = store()
    if s.lookup(id) == nil then return false end
    local st = stateOf(s, ply)
    lib._Push(st.inventory, id, lib.MaxInventory)
    s.publish(ply, lib.InventoryKey, lib._EncodeInventory(st.inventory))
    return true
end

---@param inst PW.StreakInstance
local function finish(inst)
    lib._Instances[inst] = nil
    inst:Remove()
end

function lib.EndEffects(ply)
    for inst in pairs(lib._Instances) do
        if inst._Owner == ply then finish(inst) end
    end
    lib._RemoveEffects(ply)
end

function lib.Revoke(ply)
    lib.EndEffects(ply)
    lib._Clear(ply)
end

---Makes the activation instance and ends it after Duration.
---@param ply Player
---@param def PW.Streak
---@param plan? table
---@return boolean
local function activate(ply, def, plan)
    local source = def
    if plan ~= nil then
        -- The bridge installs data before construction without changing the registered definition.
        source = setmetatable({ IsValid = function()
            return not isfunction(def.IsValid) or def:IsValid()
        end, OnEquip = function(self, owner)
            self.Activation, self._Definition, self.OnEquip = plan, def, def.OnEquip
            PW.Call(self, "OnEquip", owner)
        end }, { __index = def }) --[[@as PW.Streak]]
    end
    local inst = PW.Instance(source, ply) --[[@as PW.StreakInstance]]
    if not inst:IsValid() then inst:Remove() return false end
    lib._Instances[inst] = true
    local duration = tonumber(def.Duration) or lib.DefaultDuration
    inst:Timer(math.max(0, duration), 1, function(self) finish(self --[[@as PW.StreakInstance]]) end)
    return true
end

---@type table<Player, true>
local activating = setmetatable({}, { __mode = "k" })

---@param ply Player
---@param id string
---@return boolean
local function use(ply, id)
    if PW.Ask("PW_CanUseLoadoutKind", ply, "streaks") == false then return false end
    local s = store()
    if s.phase() ~= "LIVE" or not s.alive(ply) then return false end
    local st = s.players[ply]
    local index = st ~= nil and lib._Find(st.inventory, id) or nil
    if st == nil or index == nil then return false end
    local def = s.lookup(id)
    if def == nil then return false end
    local plan = nil
    if def.Prepare ~= nil then
        plan = PW.Call(def, "Prepare", ply)
        if not istable(plan) then
            if PW.Devices ~= nil then PW.Devices.Feedback(ply, "DEPLOYMENT BLOCKED - FIND CLEAR LEVEL GROUND") end
            return false
        end
    end
    if not activate(ply, def, plan) then return false end
    table.remove(st.inventory, index)
    s.publish(ply, lib.InventoryKey, lib._EncodeInventory(st.inventory))
    return true
end

function lib.Use(ply, id)
    if activating[ply] then return false end
    activating[ply] = true
    local ok, result = pcall(use, ply, id)
    activating[ply] = nil
    if not ok then print("[PW] streak activation failed: " .. tostring(result)) return false end
    return result
end

function lib.Ready(bot)
    if PW.Ask("PW_CanUseLoadoutKind", bot, "streaks") == false then return nil end
    local s = store()
    local st = s.players[bot]
    if st == nil then return nil end
    for _, id in ipairs(st.inventory) do
        local def = s.lookup(id)
        if def ~= nil and (def.BotShouldUse == nil or PW.Call(def, "BotShouldUse", bot) == true) then return id end
    end
    return nil
end

function lib.StreakDamage(fn, ...)
    local s = store()
    s.depth = s.depth + 1
    local ok, err = pcall(fn, ...)
    s.depth = s.depth - 1
    if not ok then print("[PW] streaks: streak damage failed: " .. tostring(err)) end
end

function lib._Receive(ply)
    local s = store()
    local index = s.read()
    local st = s.players[ply]
    local id = st ~= nil and st.inventory[index] or nil
    if id == nil then return false end
    return (lib.Use --[[@as fun(ply: Player, id: string): boolean]])(ply, id)
end

function lib._RegisterNet(owner)
    local netLib = assert(PW.Net)
    netLib.Receive(lib.NetName, { who = "any", phases = { "LIVE" }, rate = 4, maxLen = 1, owner = owner or MODULE },
        function(ply) lib._Receive(ply) end)
end

lib._RegisterNet()

function MODULE:PW_ScoreEvent(ply, eventId, points)
    lib._OnScore(ply, eventId, points)
end

function MODULE:PW_PhaseChange(phase, oldPhase)
    if phase == "LIVE" and oldPhase == "PREMATCH" then lib._Reset() end
end

function MODULE:PW_MatchEnd()
    for inst in pairs(lib._Instances) do finish(inst) end
    lib._Reset()
    local reveal = PW._Reveal
    if reveal ~= nil then reveal.jams = {} end
end

function MODULE:PW_RoundPreparing()
    for inst in pairs(lib._Instances) do finish(inst) end
    lib._ResetEffects()
end

function MODULE:PW_PlayerTeamChanged() lib._ResetEffects() end

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    lib._OnSpawn(ply)
end)

PW.HookFor(MODULE, "PostPlayerDeath", function(_, ply)
    lib._OnDeath(ply)
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    lib.Revoke(ply)
end)
