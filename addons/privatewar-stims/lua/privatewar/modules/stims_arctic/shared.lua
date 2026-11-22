if not PW or PW.API ~= 1 then return end
MODULE.Name = "Arctic stims integration"

local lib = (rawget(PW, "StimsArctic") or {}) --[[@as PW.StimsArcticLib]]
PW.StimsArctic = lib
lib.Anims = {
    stim_heal = { anim = "arc_vm_medshot_inject", skin = 0 },
    stim_speed = { anim = "arc_vm_medshot_inject", skin = 1 }
}

function lib._PickBackend(hasGcal, hasVManip, gcalHas, vmanipHas)
    if hasGcal and gcalHas then return "gcal" end
    if hasVManip and vmanipHas then return "vmanip" end
    return nil
end

function lib._AnimFor(itemId, anims)
    local entry = anims[itemId]
    if isstring(entry) then return entry --[[@as string]] end
    if istable(entry) then return (entry --[[@as PW.StimAnimation]]).anim end
    return nil
end

function lib._ShouldSwap(current)
    return current ~= nil and current ~= "0"
end
