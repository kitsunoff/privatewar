-- Engine boundary: identities, admitted roster and authoritative use samples. Never reads foreign module stores.
local lib = PW.SND --[[@as PW.SNDLib]]
PW._SND = PW._SND or { generation = 0, serial = 0, nextSnapshot = 0 }

function lib.Identity(ply)
    return ply:IsBot() and ("bot:" .. ply:UserID()) or ("human:" .. ply:SteamID64())
end

function lib.NextGeneration()
    PW._SND.generation = PW._SND.generation + 1
    return PW._SND.generation
end

---@return Player[]
local function sortedPlayers()
    local list = player.GetAll()
    table.sort(list, function(a, b) return a:UserID() < b:UserID() end)
    return list
end

function lib.Roster()
    ---@type PW.SNDActor[]
    local out = {}
    local counts = { 0, 0 }
    local list = sortedPlayers()
    for _, ply in ipairs(list) do
        local team = ply:Team()
        if team == 1 or team == 2 then counts[team] = counts[team] + 1 end
    end
    for _, ply in ipairs(list) do
        local team = ply:Team()
        if team ~= 1 and team ~= 2 then
            team = counts[1] <= counts[2] and 1 or 2
            counts[team] = counts[team] + 1
        end
        out[#out + 1] = { id = lib.Identity(ply), userId = ply:UserID(), team = team, alive = true,
            pos = ply:GetPos(), use = false, clear = false, generation = 0 }
    end
    return out
end

function lib.AdmitRoster(state)
    for _, ply in ipairs(sortedPlayers()) do
        if PW.Jip ~= nil and PW.Jip.Admit ~= nil then PW.Jip.Admit(ply) end
        local member = state.roster[lib.Identity(ply)]
        if member ~= nil and ply:Team() ~= member.team then assert(assert(PW.Teams).PlaceLate)(ply) end
        ply:Freeze(false)
    end
end

---@param state PW.SNDState
---@param ply Player
---@return boolean
local function clear(state, ply)
    local point = state.pos
    if state.phase == "carried" then
        if state.carrier ~= lib.Identity(ply) or not ply:KeyDown(IN_USE) then return false end
        for _, site in ipairs(state.map.sites) do if lib.Inside(site, ply:GetPos()) then point = site.approach end end
    end
    if ply:GetPos():DistToSqr(point) > 256 * 256 then return false end
    local trace = util.TraceLine({ start = ply:EyePos(), endpos = point + Vector(0, 0, 8),
        filter = { ply, PW._SND.bomb }, mask = MASK_SOLID })
    return not trace.Hit or trace.Fraction >= 0.98
end

function lib.Actors(state)
    ---@type PW.SNDActor[]
    local out = {}
    for _, ply in ipairs(sortedPlayers()) do
        out[#out + 1] = { id = lib.Identity(ply), userId = ply:UserID(), team = ply:Team(), alive = ply:Alive()
            and ply:GetObserverMode() == OBS_MODE_NONE, pos = ply:GetPos(), use = ply:KeyDown(IN_USE),
            clear = clear(state, ply), generation = state.generation }
    end
    return out
end

function lib.Invalidate(state)
    for _, site in ipairs(state.map.sites) do
        for _, action in ipairs({ "plant", "hold", "defuse" }) do
            PW.Notify("PW_ObjectiveInvalidated", "snd_" .. site.id .. "_" .. action, state.generation)
        end
    end
    PW.Notify("PW_ObjectiveInvalidated", "snd_bomb", state.generation)
end

---@return PW.SNDMode?
local function active()
    local mode = PW.ActiveMode
    if mode == nil or mode.ClassName ~= "snd" or assert(PW.Match).GetPhase() ~= "LIVE" then return nil end
    return mode --[[@as PW.SNDMode]]
end

PW.HookFor(MODULE, "KeyRelease", function(_, ply, key)
    local mode = active()
    local state = mode ~= nil and mode._SND or nil
    if key ~= IN_USE or state == nil or state.interaction == nil then return end
    if state.interaction.id == lib.Identity(ply) then state.interaction = nil end
end)

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    local mode = active()
    local state = mode ~= nil and mode._SND or nil
    if state == nil then return end
    lib.Invalidate(state)
    lib.Disconnect(state, lib.Identity(ply), ply:UserID(), lib.DropPoint(state, ply), CurTime())
    lib.Physical(state)
end)

include("privatewar/modules/snd/sv_world.lua")
include("privatewar/modules/snd/sv_snapshot.lua")
