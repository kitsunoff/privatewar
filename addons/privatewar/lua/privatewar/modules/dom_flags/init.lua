-- Domination flags, server glue (T-2.4). Spawning and removal of the flag entities; every rule is in shared.lua.
-- A flag is not solid and has no trigger: presence is the mode's low-rate pass over the player list.

local lib = PW.DomFlags --[[@as PW.DomFlagsLib]]

function lib._Init(flag)
    flag:SetMoveType(MOVETYPE_NONE)
    flag:SetSolid(SOLID_NONE)
    flag:AddEffects(EF_NODRAW)
    flag:DrawShadow(false)
end

function lib.Spawn(letter, pos)
    local flag = ents.Create(lib.Class) --[[@as PW.DomFlag]]
    if not IsValid(flag) then return nil end
    flag:SetPos(pos)
    flag:Spawn()
    flag:SetLetter(letter)
    flag:SetValue(0)
    flag:SetOwnerTeam(0)
    local list = lib._Flags
    list[#list + 1] = flag
    return flag
end

function lib.RemoveAll()
    local list = lib._Flags
    lib._Flags = {}
    for _, flag in ipairs(list) do
        if IsValid(flag) then flag:Remove() end
    end
end
