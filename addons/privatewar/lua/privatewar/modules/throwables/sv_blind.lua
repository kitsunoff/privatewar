-- Ordinary flash status has one resolved strength/duration for packets, DSP and bot impairment.
local lib = PW.Throwables --[[@as PW.ThrowablesLib]]
local owner = MODULE
---@type table<Player, { strength: number, at: number, dspOwned: boolean }>
local blinded = setmetatable({}, { __mode = "k" })

function lib.Impairment(ply, now)
    local status = blinded[ply]
    if status == nil then return 0 end
    return lib._BlindAlpha((now or CurTime()) - status.at, status.strength)
end

function lib.ClearBlind(ply)
    local status = blinded[ply]
    if status == nil then return end
    blinded[ply] = nil
    timer.Remove("PW.Blind." .. tostring(ply))
    if not IsValid(ply) then return end
    if status.dspOwned then ply:SetDSP(0, false) end
    if not ply:IsBot() then
        net.Start("pw_blind")
        net.WriteUInt(0, 8)
        net.Send(ply)
    end
end

function lib.ClearBlinds()
    for ply in pairs(blinded) do lib.ClearBlind(ply) end
end

function lib.Blind(ply, strength)
    if not owner:IsValid() or not IsValid(ply) then return false end
    local resolved = PW.Stat ~= nil and PW.Stat(ply, "flash_strength", strength) or strength
    if resolved ~= resolved or resolved < lib.Flash.minStrength then return false end
    resolved = lib._DecodeStrength(lib._EncodeStrength(math.Clamp(resolved, 0, 1)))
    local seconds = lib._BlindTime(resolved)
    local now = CurTime()
    local previous = blinded[ply]
    if previous ~= nil and previous.at + lib._BlindTime(previous.strength) >= now + seconds
        and lib.Impairment(ply, now) >= resolved then return true end
    local status = { strength = resolved, at = now, dspOwned = previous ~= nil and previous.dspOwned == true }
    blinded[ply] = status
    if not ply:IsBot() then
        net.Start("pw_blind")
        net.WriteUInt(lib._EncodeStrength(resolved), 8)
        net.Send(ply)
        if resolved >= 0.5 then
            ply:SetDSP(35, false)
            status.dspOwned = true
        end
    end
    timer.Create("PW.Blind." .. tostring(ply), seconds, 1, function()
        if lib.Impairment(ply) <= 0 then lib.ClearBlind(ply) end
    end)
    PW.Notify("PW_Blinded", ply, resolved, seconds)
    return true
end

PW.HookFor(MODULE, "PostPlayerDeath", function(_, ply) lib.ClearBlind(ply) end)
PW.HookFor(MODULE, "PlayerDisconnected", function(_, ply) lib.ClearBlind(ply) end)
hook.Add("PW_EntityDisabled", "PW.Throwables.Cleanup", function(kind, id)
    if kind == "modules" and id == "throwables" then lib.ClearBlinds() end
end)
