local lib = PW.Infection --[[@as PW.InfectionLib]]
include("privatewar/modules/pw_infection_rules/sv_round.lua")
include("privatewar/modules/pw_infection_rules/sv_snapshot.lua")
include("privatewar/modules/pw_infection_rules/sv_results.lua")

local dependencies = { pw_infection_rules = true, teams = true, loadout = true, operators = true,
    player_overrides = true, match_rules = true, lobby = true }

-- A stable cleanup-only listener survives the rules module's own unsubscription on disable.
---@param kind string
---@param id string
---@param definition table
hook.Add("PW_EntityDisabled", "PW.Infection.DisableCleanup", function(kind, id, definition)
    local s = lib.State
    local ownModule = kind == "modules" and id == "pw_infection_rules" and PW.Modules.Get(id) == definition
    if s == nil and not ownModule then return end
    local ownMode = s ~= nil and kind == "modes" and definition == s.mode
    local dependency = kind == "modules" and dependencies[id] and PW.Modules.Get(id) == definition
    if not ownMode and not dependency then return end
    local ok, err = pcall(lib.Clear)
    if not ok then print("[PW] infection disable cleanup: " .. tostring(err)) end
    SetGlobal2Bool("pw_infection_results", false)
    local reset, why = pcall(lib.ResetResults)
    if not reset then print("[PW] infection terminal cleanup: " .. tostring(why)) end
end)

---@param phase PW.PhaseName
function MODULE:PW_PhaseChange(phase)
    if phase == "LOBBY" or phase == "PREMATCH" then
        SetGlobal2Bool("pw_infection_results", false)
        lib.ResetResults()
    end
end

PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply)
    if lib.Active() then lib.Disconnect(ply) end
end)

PW.HookFor(MODULE, "PlayerInitialSpawn", function(_, ply)
    local generation = lib.State
    timer.Simple(1, function()
        if IsValid(ply) and lib.Active() and lib.State == generation then lib.Publish() end
        if IsValid(ply) and assert(PW.Match).GetPhase() == "POSTMATCH" then lib.SendResults(ply) end
    end)
end)

PW.HookFor(MODULE, "PlayerCanPickupWeapon", function(_, ply, wep)
    if not lib.Active() then return end
    if lib.Role(ply) == nil then return false end
    if lib.Role(ply) == "infected" and wep:GetClass() ~= "weapon_fists" then return false end
end)

PW.HookFor(MODULE, "PlayerCanPickupItem", function(_, ply)
    if lib.Active() and lib.Role(ply) ~= "survivor" then return false end
end)

---@param target Entity
---@param damage CTakeDamageInfo
PW.HookFor(MODULE, "EntityTakeDamage", function(_, target, damage)
    if not lib.Active() or not target:IsPlayer() then return end
    local ply = target --[[@as Player]]
    local s = assert(lib.State)
    if not s.playing or lib.Role(ply) == nil then return true end
    local attacker = damage:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply
        and (lib.Role(attacker --[[@as Player]]) == nil
            or not assert(PW.IsEnemy)(ply, attacker --[[@as Player]])) then return true end
end)

-- Only human commands here; bots retain the sole generic bots_input writer.
PW.HookFor(MODULE, "StartCommand", function(_, ply, cmd)
    if ply:IsBot() or not lib.Active() then return end
    if not assert(lib.State).playing or lib.Role(ply) == nil then cmd:ClearButtons() cmd:ClearMovement() end
end)
