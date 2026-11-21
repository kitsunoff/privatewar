local lib = PW.BotChatter --[[@as PW.BotChatterLib]]
local definition = MODULE
---@type table<Player, {channel: IGModAudioChannel?, expires: number, dead: boolean, token: table}>
local voices = {}

local function stop()
    for _, entry in pairs(voices) do
        if IsValid(entry.channel) then entry.channel:Stop() end
    end
    voices = {}
end

-- Reload must stop channels owned by the previous module instance as well.
local previous = rawget(PW, "_StopBotChatter")
if isfunction(previous) then previous() end
rawset(PW, "_StopBotChatter", stop)

---@return number
local function volume()
    return math.Clamp(tonumber(PW.Setting("bots_chatter.volume")) or 1, 0, 1)
end

net.Receive("pw_bot_voice_stop", function()
    if net.ReadBool() then stop() return end
    local ply = net.ReadEntity() --[[@as Player]]
    local entry = voices[ply]
    if entry ~= nil and IsValid(entry.channel) then entry.channel:Stop() end
    voices[ply] = nil
end)
net.Receive("pw_bot_voice", function()
    local ply = net.ReadEntity() --[[@as Player]]
    local path, dead = net.ReadString(), net.ReadBool()
    if not definition:IsValid() or volume() <= 0 or not IsValid(ply) or not ply:IsPlayer() or not ply:IsBot()
        or not lib._SoundPath(path) or not file.Exists("sound/" .. path, "GAME") then return end
    local count = 0
    for _ in pairs(voices) do count = count + 1 end
    if voices[ply] ~= nil or count >= 4 then return end
    local token = {}
    ---@type {channel: IGModAudioChannel?, expires: number, dead: boolean, token: table}
    local entry = { expires = CurTime() + 12, dead = dead, token = token }
    voices[ply] = entry
    -- Force mono for true spatial playback; never retry as map-wide stereo audio.
    sound.PlayFile("sound/" .. path, "3d mono noplay", function(channel)
        if not IsValid(channel) then
            if voices[ply] == entry then voices[ply] = nil end
            return
        end
        if voices[ply] ~= entry or CurTime() >= entry.expires or not IsValid(ply) then channel:Stop() return end
        entry.channel = channel
        channel:SetPos(ply:WorldSpaceCenter())
        channel:Set3DFadeDistance(200, 1800)
        channel:SetVolume(volume())
        channel:Play()
    end)
end)

-- Plain Think keeps cleanup active even after the module is disabled.
hook.Add("Think", "PW.BotChatter.Audio", function()
    for ply, entry in pairs(voices) do
        local invalid = not definition:IsValid() or not IsValid(ply) or CurTime() >= entry.expires or volume() <= 0
        -- Death messages can beat the replicated Alive() change. The reliable spawn-stop message owns respawn cleanup.
        if not invalid then invalid = not entry.dead and not ply:Alive() end
        if invalid then
            if IsValid(entry.channel) then entry.channel:Stop() end
            voices[ply] = nil
        elseif IsValid(entry.channel) then
            entry.channel:SetPos(ply:WorldSpaceCenter())
            entry.channel:SetVolume(volume())
        end
    end
end)
