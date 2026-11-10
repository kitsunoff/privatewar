local lib = PW.BotChatter --[[@as PW.BotChatterLib]]
local getContent = include("privatewar/modules/bots_chatter/sv_content.lua") --[[@as fun(): PW.ChatterContent]]
util.AddNetworkString("pw_bot_voice")
util.AddNetworkString("pw_bot_voice_stop")

---@type table<Player, PW.ChatterState>
local states = setmetatable({}, { __mode = "k" })
local nextGlobal, nextTick = 0, 0
local roundActive = true
local playbackPending = false
local definition = MODULE

---@return boolean
local function enabled()
    return roundActive and definition:IsValid() and PW.Setting("bots_chatter.enabled") == true
        and PW.Match ~= nil and PW.Match.GetPhase() == "LIVE"
end

---@param ply Player
---@return boolean
local function managed(ply)
    return IsValid(ply) and ply:IsBot() and PW.Bot ~= nil and PW.Bot.Get(ply) ~= nil
        and not ply:GetNW2Bool("pw_spectating", false) and ply:GetObserverMode() == OBS_MODE_NONE
end

---@param ply Player
---@return PW.ChatterState
local function identity(ply)
    local state = states[ply]
    if state ~= nil then return state end
    local data = getContent()
    return lib._Identity(states, ply, data.voiceIds, data.textIds, math.random(), CurTime())
end

---@param now number
---@return integer
local function activeCount(now)
    local count = 0
    for ply, state in pairs(states) do
        if IsValid(ply) and state.speaking > now then count = count + 1 end
    end
    return count
end

---@param ply Player
---@param event string
---@param target Player?
local function speak(ply, event, target)
    if not enabled() or not managed(ply) then return end
    if event ~= "death" and not ply:Alive() then return end
    local now, state = CurTime(), identity(ply)
    local limit = math.Clamp(math.floor(tonumber(PW.Setting("bots_chatter.speakers")) or 2), 1, 4)
    if not lib._CanSpeak(state, now, nextGlobal, activeCount(now), limit) then return end
    local data = getContent()
    local voice = lib._Line(state.voice ~= nil and data.voices[state.voice] or nil, data.voice, event, math.random())
    local text = lib._Line(state.text ~= nil and data.texts[state.text] or nil, data.text, event, math.random())
    text = lib._Text(text, target ~= nil and IsValid(target) and target:Nick() or nil)
    local sent = false
    if voice ~= nil and PW.Setting("bots_chatter.voice") == true and file.Exists("sound/" .. voice, "GAME") then
        -- No duration feedback from clients. Both realms enforce a hard 12-second playback lease.
        state.speaking = now + 12
        playbackPending = true
        net.Start("pw_bot_voice")
        net.WriteEntity(ply)
        net.WriteString(voice)
        net.WriteBool(event == "death")
        net.SendPAS(ply:GetPos())
        sent = true
    end
    if text ~= nil and PW.Setting("bots_chatter.chat") == true then
        ply:Say(text, false)
        sent = true
    end
    if not sent then return end
    state.next = now + math.Clamp(tonumber(PW.Setting("bots_chatter.interval")) or 20, 5, 120)
    nextGlobal = now + 3
end

---@param victim Player
---@param attacker Entity
function MODULE:PW_PlayerKilled(victim, attacker)
    if not enabled() then return end
    local state = managed(victim) and identity(victim) or nil
    if state ~= nil and state.death then return end
    if state ~= nil then state.death = true end
    -- Death can occur inside DoPlayerDeath before Alive() changes. No queued post-respawn callbacks.
    local killer = IsValid(attacker) and attacker:IsPlayer() and attacker --[[@as Player?]] or nil
    if state ~= nil then speak(victim, "death", killer) end
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
        and PW.IsEnemy ~= nil and PW.IsEnemy(attacker --[[@as Player]], victim) then
        speak(attacker --[[@as Player]], "kill", victim)
    end
end

PW.HookFor(MODULE, "PlayerSpawn", function(_, ply)
    local state = states[ply]
    if state == nil then return end
    state.death, state.seen, state.speaking = false, false, 0
    net.Start("pw_bot_voice_stop")
    net.WriteBool(false)
    net.WriteEntity(ply)
    net.Broadcast()
end)

local function stop()
    playbackPending = false
    nextGlobal = 0
    for _, state in pairs(states) do state.speaking, state.seen = 0, false end
    net.Start("pw_bot_voice_stop")
    net.WriteBool(true)
    net.Broadcast()
end

---@param phase PW.PhaseName
function MODULE:PW_PhaseChange(phase)
    if phase ~= "LIVE" then stop() end
    if phase == "LOBBY" then
        states = setmetatable({}, { __mode = "k" })
        roundActive = true
    end
end

function MODULE:PW_RoundPreparing() roundActive = false stop() end
function MODULE:PW_RoundEnd() roundActive = false stop() end
function MODULE:PW_RoundStart() roundActive = true end

hook.Add("PW_EntityDisabled", "PW.BotChatter.Cleanup", function(kind, id)
    if kind == "modules" and id == "bots_chatter" then stop() end
end)

PW.HookFor(MODULE, "Think", function()
    -- Setting changes must retire playing and opening client streams before the low-rate chatter scan.
    if playbackPending and not enabled() then stop() end
    local now = CurTime()
    if now < nextTick then return end
    nextTick = now + 1
    if not enabled() then return end
    for _, ply in ipairs(player.GetBots()) do
        if managed(ply) and ply:Alive() then
            local state = identity(ply)
            local board = PW.Bot.Get(ply)
            local visible = lib._Visible(board ~= nil and board.contacts or {})
            if visible and not state.seen then speak(ply, "taunt", nil)
            elseif not visible and math.random() < 0.1 then speak(ply, "idle", nil) end
            state.seen = visible
        end
    end
end)
