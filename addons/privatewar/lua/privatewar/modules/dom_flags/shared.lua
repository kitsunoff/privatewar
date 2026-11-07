-- Domination flags (T-2.4; 02-modes.md d.5; 03-mapdata.md d.2, d.6; README.md "worth stealing": one signed scalar
-- per point, easy to network). Owns PW.DomFlags and the scripted entity pw_dom_flag. Shared: the API, the gameplay
-- values, the pure presence rules and the entity class, whose methods only call the per-realm parts:
--   init.lua (server): spawning and removal;
--   cl_init.lua (client): the client flag list and the markers (letter + owner colour).
-- Presence is one pass over the player list per capture step (the mode runs it at a low fixed rate, StepEvery): a
-- cylinder test per flag and player, no ents.Find* and no triggers (DESIGN.md performance rule 1). Dead players and
-- observers never count, and a teleport or a death needs no touch bookkeeping.
-- The module does not capture or score: the mode moves the scalar and writes it to the entity's network vars.

MODULE.Name = "Domination flags"

local lib = (rawget(PW, "DomFlags") or {}) --[[@as PW.DomFlagsLib]]
PW.DomFlags = lib

-- Gameplay values, reported for confirmation (T-2.4).
lib.Class = "pw_dom_flag"
lib.Radius = 160
lib.Above = 128
lib.Below = 64

lib._Flags = lib._Flags or {}

function lib._Inside(center, pos)
    local dz = pos.z - center.z
    if dz > lib.Above or dz < -lib.Below then return false end
    local dx, dy = pos.x - center.x, pos.y - center.y
    return dx * dx + dy * dy <= lib.Radius * lib.Radius
end

function lib._Infos(players)
    ---@type PW.DomPresenceInfo[]
    local infos = {}
    for _, ply in ipairs(players) do
        if IsValid(ply) and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE then
            infos[#infos + 1] = { who = ply, team = ply:Team(), pos = ply:GetPos() }
        end
    end
    return infos
end

function lib._Presence(points, infos)
    ---@type PW.DomPresence[]
    local out = {}
    for index, center in ipairs(points) do
        ---@type PW.DomPresence
        local presence = { counts = {}, members = {} }
        for _, info in ipairs(infos) do
            if lib._Inside(center, info.pos) then
                local team = info.team
                presence.counts[team] = (presence.counts[team] or 0) + 1
                local members = presence.members[team] or {}
                presence.members[team] = members
                members[#members + 1] = info.who
            end
        end
        out[index] = presence
    end
    return out
end

---@param flag PW.DomFlag
function lib._Forget(flag)
    for i, entry in ipairs(lib._Flags) do
        if entry == flag then
            table.remove(lib._Flags, i)
            return
        end
    end
end

function lib.GetAll()
    ---@type PW.DomFlag[]
    local list = {}
    for _, flag in ipairs(lib._Flags) do
        if IsValid(flag) then list[#list + 1] = flag end
    end
    return list
end

-- Pure rules of the points element (T-6.5): sh_hud.lua.
if SERVER then AddCSLuaFile("privatewar/modules/dom_flags/sh_hud.lua") end
include("privatewar/modules/dom_flags/sh_hud.lua")

-- The entity: methods are thin calls into the realm parts above, so a reload (pw_reload) replaces behaviour without
-- touching flags that already exist.
local flagClass = {} --[[@as PW.DomFlag]]
flagClass.Type = "anim"
flagClass.Base = "base_anim"
flagClass.PrintName = "Domination flag"
flagClass.Spawnable = false
flagClass.AdminOnly = true
flagClass.DisableDuplicator = true
flagClass.PhysgunDisabled = true

function flagClass:SetupDataTables()
    self:NetworkVar("String", 0, "Letter")
    self:NetworkVar("Float", 0, "Value")
    self:NetworkVar("Int", 0, "OwnerTeam")
    self:NetworkVar("Bool", 0, "Contested")
end

function flagClass:Initialize()
    local init = lib._Init
    if init ~= nil then init(self) end
end

function flagClass:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function flagClass:OnRemove()
    lib._Forget(self)
end

scripted_ents.Register(flagClass, lib.Class)
