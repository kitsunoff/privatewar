-- Shared stock-footstep eligibility, independent of engine listener order.
local lib = PW.Perks --[[@as PW.PerksLib]]

function lib.FootstepsAudible(ply)
    local module = PW.Modules ~= nil and PW.Modules.Get("perks") or nil
    if module == nil or not module:IsValid() then return true end
    if SERVER then
        local s = PW._Perks
        if s ~= nil and s.silent ~= nil then return s.silent[ply] ~= true end
    end
    return not ply:GetNW2Bool("pw_silent_steps", false)
end

function lib._RetaliationEligible(facts)
    return facts.now >= facts.nextAt and facts.enemy and facts.living and facts.direct and facts.los
end

PW.HookFor(MODULE, "PlayerFootstep", function(_, ply)
    if not lib.FootstepsAudible(ply) then return true end
end)
