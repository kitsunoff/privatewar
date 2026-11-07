-- Streaks module, server: PW.Reveal, the deliberate reveal (DESIGN.md net rule) and Counter-UAV jamming (T-4.6).
-- PW.Reveal(viewer, targets, duration) sends the positions of the visible targets to the viewer's human players
-- ("pw_reveal", see sh_reveal.lua) and feeds them to the viewer's bots as "radar" stimuli (07-bots.md d.7). Nothing
-- else sends enemy positions. Engine calls are fields of the reveal store, so the tests drive it with fakes.

local lib = PW.Streaks --[[@as PW.StreaksLib]]

util.AddNetworkString(lib.RevealNet)

---@param list any[]
---@return Player[]
local function humans(list)
    ---@type Player[]
    local out = {}
    for _, ply in ipairs(list) do
        if IsValid(ply) and not ply:IsBot() then out[#out + 1] = ply end
    end
    return out
end

---@param recipients any[]
---@param blips PW.RevealBlip[]
---@param duration number
local function defaultSend(recipients, blips, duration)
    local to = humans(recipients)
    if #to == 0 then return end
    net.Start(lib.RevealNet)
    net.WriteUInt(0, 1)
    net.WriteUInt(lib._EncodeTime(duration), lib.TimeBits)
    net.WriteUInt(#blips, lib.CountBits)
    for _, blip in ipairs(blips) do
        net.WriteUInt(blip.index, lib.IndexBits)
        net.WriteInt(lib._Quantize(blip.pos.x), lib.PosBits)
        net.WriteInt(lib._Quantize(blip.pos.y), lib.PosBits)
        net.WriteInt(lib._Quantize(blip.pos.z), lib.PosBits)
    end
    net.Send(to)
end

---@param recipients any[]
---@param duration number
local function defaultJamSend(recipients, duration)
    local to = humans(recipients)
    if #to == 0 then return end
    net.Start(lib.RevealNet)
    net.WriteUInt(1, 1)
    net.WriteUInt(lib._EncodeTime(duration), lib.TimeBits)
    net.Send(to)
end

---@param a any
---@param b any
---@return boolean
local function defaultIsEnemy(a, b)
    local isEnemy = rawget(PW, "IsEnemy") --[[@as (fun(a: Player, b: Player): boolean)?]]
    if isEnemy == nil then return a ~= b end
    return isEnemy(a, b)
end

---@param viewer any
---@return any[]
local function defaultMembers(viewer)
    if isnumber(viewer) then return team.GetPlayers(viewer --[[@as integer]]) end
    if IsValid(viewer) then return { viewer } end
    return {}
end

---@param viewer any
---@param target any
---@param pos Vector
local function defaultStimulus(viewer, target, pos)
    local bot = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    if bot == nil or bot.AddStimulus == nil then return end
    bot.AddStimulus(viewer, "radar", { ent = target, pos = pos })
end

function lib._NewRevealStore(opts)
    opts = opts or {}
    return {
        jams = {},
        clock = opts.clock or CurTime,
        isEnemy = opts.isEnemy or defaultIsEnemy,
        members = opts.members or defaultMembers,
        players = opts.players or player.GetAll,
        send = opts.send or defaultSend,
        jamSend = opts.jamSend or defaultJamSend,
        stimulus = opts.stimulus or defaultStimulus
    }
end

PW._Reveal = PW._Reveal or lib._NewRevealStore()

---@return PW.RevealStore
local function store()
    return PW._Reveal --[[@as PW.RevealStore]]
end

---@param viewer integer|Player
---@param targets Player[]
---@param duration number
---@return integer
function PW.Reveal(viewer, targets, duration)
    local s = store()
    local now = s.clock()
    lib._Prune(s.jams, now)
    local recipients = s.members(viewer)
    local ref = isnumber(viewer) and recipients[1] or viewer
    if ref == nil then return 0 end
    ---@type PW.RevealBlip[]
    local blips = {}
    for _, target in ipairs(lib._Filter(targets, ref, s.jams, now, s.isEnemy)) do
        if IsValid(target) and #blips < lib.MaxBlips then
            blips[#blips + 1] = { index = target:EntIndex(), pos = target:GetPos() }
        end
    end
    if #blips == 0 then return 0 end
    s.send(recipients, blips, duration)
    for i, blip in ipairs(blips) do s.stimulus(viewer, targets[i] ~= nil and Entity(blip.index) or nil, blip.pos) end
    return #blips
end

function lib.Jam(owner, duration)
    local s = store()
    s.jams[#s.jams + 1] = { owner = owner, ends = s.clock() + duration }
    ---@type any[]
    local hostile = {}
    for _, ply in ipairs(s.players()) do
        if s.isEnemy(owner, ply) then hostile[#hostile + 1] = ply end
    end
    s.jamSend(hostile, duration)
end

function lib.Enemies(owner)
    local s = store()
    ---@type Player[]
    local out = {}
    for _, ply in ipairs(s.players()) do
        if IsValid(ply) and ply:Alive() and s.isEnemy(owner, ply) then out[#out + 1] = ply end
    end
    return out
end

function lib.Viewer(owner)
    local teams = rawget(PW, "Teams") --[[@as PW.TeamsLib?]]
    if teams == nil or not IsValid(owner) then return owner end
    local index = owner:Team()
    for _, active in ipairs(teams.GetActive()) do
        if active == index then return index end
    end
    return owner
end
