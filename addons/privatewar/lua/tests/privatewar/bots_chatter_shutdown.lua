-- Server transition and client callbacks with explicit engine stand-ins; no native audio or Deck access.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "chatter dependency must load")
    return value
end

---@type PW.SettingStore?
local savedSettings
---@type any
local savedModule
---@type any
local savedPlayFile
---@type any
local savedStop
local clientLoaded = false

---@param human? boolean
---@return Player
local function bot(human)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return not human end, Alive = function() return true end,
        GetNW2Bool = function() return false end, GetObserverMode = function() return OBS_MODE_NONE end,
        GetPos = function() return Vector() end, WorldSpaceCenter = function() return Vector() end,
        Nick = function() return "Bot" end, Say = function() end
    } --[[@as Player]]
end

---@return table<string, any>
local function client()
    clientLoaded = true
    ---@type {receivers: table<string, function>, callbacks: function[], speaker: Player, now: number, all: boolean}
    local world = { receivers = {}, callbacks = {}, speaker = bot(), now = 0, all = true }
    savedModule, savedPlayFile = rawget(_G, "MODULE"), rawget(sound, "PlayFile")
    savedStop = rawget(PW, "_StopBotChatter")
    rawset(PW, "_StopBotChatter", nil)
    rawset(_G, "MODULE", { IsValid = function() return true end })
    rawset(sound, "PlayFile", function(_, _, callback) world.callbacks[#world.callbacks + 1] = callback end)
    stub(net, "Receive").with(function(name, callback) world.receivers[name] = callback end)
    stub(hook, "Add").with(function() end)
    stub(net, "ReadEntity").with(function() return world.speaker end)
    stub(net, "ReadString").with(function() return "lambdaplayers/vo/idle/test.mp3" end)
    stub(net, "ReadBool").with(function() return world.all end)
    stub(file, "Exists").with(function() return true end)
    stub(PW, "Setting").with(function() return 1 end)
    stub(_G, "CurTime").with(function() return world.now end)
    include("privatewar/modules/bots_chatter/cl_init.lua")
    return world
end

---@return table<string, any>
local function channel()
    ---@type table<string, any>
    local counts = { stops = 0, plays = 0 }
    counts.IsValid = function() return true end
    counts.Stop = function() counts.stops = counts.stops + 1 end
    counts.Play = function() counts.plays = counts.plays + 1 end
    counts.SetPos, counts.SetVolume, counts.Set3DFadeDistance = function() end, function() end, function() end
    return counts
end

return {
    groupName = "PW bot chatter shutdown",
    afterEach = function()
        if savedSettings ~= nil then
            local module = must(must(PW.Registries.modules).Get("bots_chatter"))
            PW.Call(module, "PW_PhaseChange", "LOBBY")
            PW._Settings, savedSettings = savedSettings, nil
        end
        if clientLoaded then
            local cleanup = rawget(PW, "_StopBotChatter")
            if isfunction(cleanup) then cleanup() end
            rawset(sound, "PlayFile", savedPlayFile)
            rawset(_G, "MODULE", savedModule)
            rawset(PW, "_StopBotChatter", savedStop)
            savedPlayFile, savedModule, savedStop = nil, nil, nil
            clientLoaded = false
        end
    end,
    cases = {
        {
            name = "Chatter shutdown: Settings.Set false stops active playback before the next scheduled scan",
            func = function()
                local module = must(must(PW.Registries.modules).Get("bots_chatter"))
                local lib = must(PW.BotChatter)
                local now = CurTime()
                local messages, stops = 0, 0
                local current = ""
                local speaker = bot()
                ---@type PW.ChatterState?
                local active
                ---@type table<string, string>
                local values = {}
                savedSettings = PW._Settings
                PW._Settings = PW.Settings._NewStore({ convars = {
                    read = function(name) return values[name] end,
                    write = function(name, value) values[name] = value return true end,
                    create = function() end
                } })
                stub(module, "IsValid").with(function() return true end)
                stub(must(PW.Match), "GetPhase").with(function() return "LIVE" end)
                stub(must(PW.Bot), "Get").with(function() return {} end)
                stub(player, "GetBots").with(function() return {} end)
                stub(PW, "IsEnemy").with(function() return true end)
                stub(lib, "_Line").with(function() return "lambdaplayers/vo/kill/test.mp3" end)
                stub(file, "Exists").with(function() return true end)
                stub(_G, "CurTime").with(function() return now end)
                stub(net, "Start").with(function(name) current = name end)
                stub(net, "WriteBool").with(function(all)
                    if current == "pw_bot_voice_stop" then assert(all, "shutdown must stop every stream") end
                end)
                stub(net, "WriteEntity").with(function() end)
                stub(net, "WriteString").with(function() end)
                stub(net, "SendPAS").with(function() messages = messages + 1 end)
                stub(net, "Broadcast").with(function() if current == "pw_bot_voice_stop" then stops = stops + 1 end end)
                ---@param states table<any, PW.ChatterState>
                ---@param ply any
                local function identity(states, ply)
                    states[ply] = states[ply] or { next = 0, speaking = 0, seen = true }
                    active = states[ply]
                    return states[ply]
                end
                stub(lib, "_Identity").with(identity)
                module:PW_PhaseChange("LOBBY")
                expect(PW.Settings.Set("bots_chatter.enabled", true)).to.beTrue()
                expect(PW.Settings.Set("bots_chatter.chat", false)).to.beTrue()
                local hooks = must(rawget(module, "_EngineHooks")) --[[@as table<string, function>]]
                local think = hooks.Think
                think(module)
                module:PW_PlayerKilled(bot(true), speaker)
                expect(messages).to.equal(1)
                expect(must(active).speaking > now).to.beTrue()
                stops = 0
                expect(PW.Settings.Set("bots_chatter.enabled", false)).to.beTrue()
                now = now + 0.01
                think(module)
                expect(stops).to.equal(1)
                expect(must(active).speaking).to.equal(0)
                expect(must(active).seen).to.beFalse()
                think(module)
                module:PW_PlayerKilled(bot(true), speaker)
                expect(stops).to.equal(1)
                expect(messages).to.equal(1)
                expect(PW.Settings.Set("bots_chatter.enabled", true)).to.beTrue()
                now = now + 60
                module:PW_PlayerKilled(bot(true), speaker)
                expect(messages).to.equal(2)
                expect(PW.Settings.Set("bots_chatter.enabled", false)).to.beTrue()
                think(module)
                expect(stops).to.equal(2)
                expect(must(active).speaking).to.equal(0)
            end
        },
        {
            name = "Chatter shutdown: stop-all closes playing audio and invalidates pending open callbacks",
            func = function()
                local world = client()
                world.receivers.pw_bot_voice()
                local playing = channel()
                world.callbacks[1](playing)
                expect(playing.plays).to.equal(1)
                world.speaker = bot()
                world.receivers.pw_bot_voice()
                world.receivers.pw_bot_voice_stop()
                expect(playing.stops).to.equal(1)
                local pending = channel()
                world.callbacks[2](pending)
                expect(pending.stops).to.equal(1)
                expect(pending.plays).to.equal(0)
            end
        },
        {
            name = "Chatter shutdown: per-player stop invalidates its pending callback without stopping another bot",
            func = function()
                local world = client()
                local first = world.speaker
                world.receivers.pw_bot_voice()
                world.speaker = bot()
                world.receivers.pw_bot_voice()
                local other = channel()
                world.callbacks[2](other)
                world.speaker, world.all = first, false
                world.receivers.pw_bot_voice_stop()
                local pending = channel()
                world.callbacks[1](pending)
                expect(pending.plays).to.equal(0)
                expect(pending.stops).to.equal(1)
                expect(other.plays).to.equal(1)
                expect(other.stops).to.equal(0)
            end
        },
        {
            name = "Chatter shutdown: reload closes old channels and cancels old pending callbacks",
            func = function()
                local world = client()
                world.receivers.pw_bot_voice()
                local playing = channel()
                world.callbacks[1](playing)
                world.speaker = bot()
                world.receivers.pw_bot_voice()
                include("privatewar/modules/bots_chatter/cl_init.lua")
                expect(playing.stops).to.equal(1)
                local pending = channel()
                world.callbacks[2](pending)
                expect(pending.plays).to.equal(0)
                expect(pending.stops).to.equal(1)
            end
        },
        {
            name = "Chatter shutdown: stale callback after stop cannot restore or remove a newer stream",
            func = function()
                local world = client()
                world.receivers.pw_bot_voice()
                world.receivers.pw_bot_voice_stop()
                world.receivers.pw_bot_voice()
                local old, newer = channel(), channel()
                world.callbacks[1](old)
                world.callbacks[2](newer)
                expect(old.plays).to.equal(0)
                expect(old.stops).to.equal(1)
                expect(newer.plays).to.equal(1)
                world.receivers.pw_bot_voice_stop()
                expect(newer.stops).to.equal(1)
            end
        }
    }
}
