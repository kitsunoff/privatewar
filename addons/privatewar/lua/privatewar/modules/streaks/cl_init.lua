-- Streaks module, client (T-4.6). Keys: pw_key_streak (5) activates the selected streak, pw_key_streak_next (6)
-- selects the next one; the console commands pw_streak and pw_streak_next do the same for players who bind keys
-- themselves. A use sends one "pw_streak_use" message with the inventory index; the server checks phase, rate and the
-- rest. While the player holds a streak during LIVE, the engine binds of both keys are swallowed. The radar data
-- ("pw_reveal") is kept in PW.Streaks.Radar for the radar (T-6.6) and the HUD notice.

local lib = PW.Streaks --[[@as PW.StreaksLib]]

---@type table<string, ConVar>
local convars = {}
for action, key in pairs(lib.Keys) do
    convars[action] = CreateClientConVar(key.convar, key.default, true, false,
        "Key that " .. (action == "use" and "activates the selected killstreak" or "selects the next killstreak"))
end

---@type { use: integer?, next: integer? }
local codes = {}
---@type table<string, string>
local codeNames = {}

---@return { use: integer?, next: integer? }
local function currentCodes()
    for action, convar in pairs(convars) do
        local name = convar:GetString()
        if codeNames[action] ~= name then
            codeNames[action] = name
            codes[action] = input.GetKeyCode(name)
        end
    end
    return codes
end

lib.Selected = lib.Selected or 1
lib.Radar = lib.Radar or { blips = {}, jammedUntil = 0 }

---@type PW.RevealBlip[]
local live = {}

function lib.Blips()
    return lib._Live((lib.Radar --[[@as PW.RadarView]]).blips, CurTime(), live)
end

function lib.Jammed()
    return (lib.Radar --[[@as PW.RadarView]]).jammedUntil > CurTime()
end

---@param action string
local function act(action)
    local ply = LocalPlayer()
    if not IsValid(ply) or PW.Phase.GetPhase() ~= "LIVE" then return end
    local count = #lib.Inventory(ply)
    if count == 0 then return end
    if action == "next" then
        lib.Selected = lib._Select(lib.Selected or 1, count, 1)
        return
    end
    net.Start(lib.NetName)
    net.WriteUInt(lib._Select(lib.Selected or 1, count, 0), lib.WireBits)
    net.SendToServer()
end

concommand.Add(lib.Keys.use.command, function() act("use") end, nil, "Activate the selected killstreak")
concommand.Add(lib.Keys.next.command, function() act("next") end, nil, "Select the next killstreak")

PW.HookFor(MODULE, "PlayerButtonDown", function(_, ply, button)
    if not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
    local action = lib._KeyAction(button, currentCodes())
    if action ~= nil then act(action) end
end)

PW.HookFor(MODULE, "PlayerBindPress", function(_, ply, _, pressed, code)
    if not pressed or PW.Phase.GetPhase() ~= "LIVE" then return end
    if lib._KeyAction(code, currentCodes()) ~= nil and #lib.Inventory(ply) > 0 then return true end
end)

---Reads the blips of one "pw_reveal" message into the radar.
---@param radar PW.RadarView
local function readBlips(radar)
    local ends = CurTime() + lib._DecodeTime(net.ReadUInt(lib.TimeBits))
    local count = net.ReadUInt(lib.CountBits)
    lib._Live(radar.blips, CurTime(), radar.blips)
    for _ = 1, count do
        local index = net.ReadUInt(lib.IndexBits)
        local x = lib._Dequantize(net.ReadInt(lib.PosBits))
        local y = lib._Dequantize(net.ReadInt(lib.PosBits))
        local z = lib._Dequantize(net.ReadInt(lib.PosBits))
        radar.blips[#radar.blips + 1] = { index = index, pos = Vector(x, y, z), ends = ends }
    end
end

net.Receive(lib.RevealNet, function()
    local radar = lib.Radar --[[@as PW.RadarView]]
    if net.ReadUInt(1) == 0 then
        readBlips(radar)
    else
        radar.jammedUntil = CurTime() + lib._DecodeTime(net.ReadUInt(lib.TimeBits))
    end
end)

net.Receive("pw_reveal_reset", function()
    lib.Radar = { blips = {}, jammedUntil = 0 }
end)

function MODULE:PW_PhaseChanged(phase)
    if phase == "LIVE" then return end
    lib.Radar = { blips = {}, jammedUntil = 0 }
    lib.Selected = 1
end
