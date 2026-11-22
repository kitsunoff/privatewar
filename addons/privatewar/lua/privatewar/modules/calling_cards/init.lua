-- The server owns the published card and sends the victim snapshot only to the credited human killer.
---@class PW.CallingCardsModuleServer : PW.Module
local module = MODULE --[[@as PW.CallingCardsModuleServer]]
local lib = assert(PW.CallingCards)
local cardKey = "pw_card"

---@return string[]
local function enabledIds()
    local registry = PW.Registries.cards
    ---@type string[]
    local ids = {}
    if registry == nil then return ids end
    for _, card in ipairs(registry.GetEnabledList()) do
        local id = card.ClassName
        if id ~= "" and lib._ValidChoice(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

---@type PW.CardServerEdges
local engine = {
    find = lib._CardDefinition,
    enabledIds = enabledIds,
    unlocked = function(ply, id)
        local unlocks = PW.Unlocks
        if unlocks == nil then return id == lib.Default end
        local open = unlocks.IsUnlocked(ply, "cards", id)
        return open
    end,
    phase = function()
        local match = PW.Match
        return match ~= nil and match.GetPhase() or "LOBBY"
    end,
    isPlayer = function(entity) return isentity(entity) and IsValid(entity) and entity:IsPlayer() end,
    isEnemy = function(attacker, victim)
        local check = PW.IsEnemy
        if check ~= nil then return check(attacker, victim) end
        -- With no relationship provider, only a known FFA mode can safely treat all other players as enemies.
        local mode = PW.ActiveMode
        return mode ~= nil and mode.Teams == 0
    end,
    rng = math.random,
    send = function(channel, killer, state)
        net.Start(channel)
        lib._Encode(state, net --[[@as PW.CardWriter]])
        net.Send(killer)
    end
}

---@param io? PW.CardServerEdges
---@return PW.CallingCardsStore
local function newStore(io)
    return {
        io = io or engine,
        requested = setmetatable({}, { __mode = "k" }),
        bots = setmetatable({}, { __mode = "k" })
    }
end

lib._NewStore = newStore
local store = lib._Store or newStore()
store.io = engine -- retain choices on reload, not closures into the previous module
lib._Store = store

---@param state PW.CallingCardsStore
---@param ply Player
---@return string
local function botCard(state, ply)
    local id = state.bots[ply]
    if id == nil then
        id = lib._BotCard(state.io.enabledIds(), state.io.rng) or lib.Default
        state.bots[ply] = id
    end
    local card = state.io.find(id)
    return card ~= nil and card:IsValid() and id or lib.Default
end

---@param state PW.CallingCardsStore
---@param ply Player
---@return string
local function humanCard(state, ply)
    local id = state.requested[ply] or lib.Default
    local card = id ~= "" and state.io.find(id) or nil
    return lib._Resolve(id, {
        registered = function() return card ~= nil end,
        enabled = function() return card ~= nil and card:IsValid() end,
        unlocked = function(key) return state.io.unlocked(ply, key) end
    })
end

---@param state PW.CallingCardsStore
---@param ply Player
local function onSpawn(state, ply)
    local id = ply:IsBot() and botCard(state, ply) or humanCard(state, ply)
    if ply:GetNW2String(cardKey, "") ~= id then ply:SetNW2String(cardKey, id) end
end

---@param state PW.CallingCardsStore
---@param ply Player
---@param choice any
---@return boolean
local function onChoice(state, ply, choice)
    if not state.io.isPlayer(ply) or ply:IsBot() or not lib._ValidChoice(choice) then return false end
    state.requested[ply] = choice --[[@as string]]
    onSpawn(state, ply)
    return true
end

---@param state PW.CallingCardsStore
---@param victim Player
---@param attacker Entity
local function onKill(state, victim, attacker)
    local io = state.io
    if io.phase() ~= "LIVE" or attacker == victim or not io.isPlayer(attacker) or not io.isPlayer(victim) then
        return
    end
    local killer = attacker --[[@as Player]]
    if killer:IsBot() or not io.isEnemy(killer, victim) then return end
    io.send(lib.KillNet, killer, {
        name = victim:Nick(), card = victim:GetNW2String(cardKey, ""), bot = victim:IsBot()
    })
end

lib._OnSpawn, lib._OnChoice, lib._OnKill = onSpawn, onChoice, onKill

util.AddNetworkString(lib.KillNet)
assert(PW.Net).Receive(lib.ChoiceNet, { who = "any", rate = 2, maxLen = lib.ChoiceMaxLen, owner = module },
    function(ply, bits)
        local choice = lib._ReadChoice(net --[[@as PW.CardReader]], bits)
        if choice ~= nil then onChoice(store, ply, choice) end
    end)

PW.HookFor(module, "PlayerSpawn", function(_, ply)
    if engine.isPlayer(ply) then onSpawn(store, ply) end
end)

---@param victim Player
---@param attacker Entity
function module:PW_PlayerKilled(victim, attacker)
    onKill(store, victim, attacker)
end
