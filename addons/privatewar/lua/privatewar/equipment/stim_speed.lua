EQUIPMENT.Name = "Speed Stim"
EQUIPMENT.Description = "Walk and run speed +20% for 6 seconds. Two per life."
EQUIPMENT.Category = "tactical"
EQUIPMENT.Count = 2
EQUIPMENT.Cost = 1
EQUIPMENT.Unlock = 1
EQUIPMENT.Sound = "items/battery_pickup.wav"

---@param inst PW.Instance
---@param owner Player
local function finish(inst, owner)
    if inst._StimApplied then
        local overrides = PW.PlayerOverrides
        if overrides ~= nil and overrides.MoveSource ~= nil then
            overrides.MoveSource(owner, inst.ClassName --[[@as string]], nil)
        end
        local lib = PW.Stims
        if lib ~= nil and lib.Mark ~= nil then lib.Mark(owner, "speed", 0) end
    end
    inst._StimBusy, inst._StimApplied = nil, nil
end

---@param inst PW.Instance
---@param owner Player
---@param lib PW.StimsLib
---@param multiplier number
---@param duration number
local function boost(inst, owner, lib, multiplier, duration)
    local overrides = PW.PlayerOverrides
    if overrides == nil or overrides.MoveSource == nil or not IsValid(owner) or not owner:Alive() then
        inst:Remove()
        return
    end
    inst._StimApplied = true
    overrides.MoveSource(owner, inst.ClassName --[[@as string]], multiplier)
    if lib.Mark ~= nil then lib.Mark(owner, "speed", CurTime() + duration) end
    inst:Timer(duration, 1, function(active) finish(active, owner) end)
end

function EQUIPMENT:OnUse(owner)
    local lib = PW.Stims
    if lib == nil or lib.Played == nil or not IsValid(PW.Modules.Get("stims")) then return false end
    local overrides = PW.PlayerOverrides
    if overrides == nil or overrides.MoveSource == nil
        or not IsValid(PW.Modules.Get("player_overrides")) then return false end
    local inst = self --[[@as PW.Instance]]
    if inst._StimBusy or not IsValid(owner) or not owner:Alive() then return false end
    local multiplier = lib.Param(inst, "Mult", "stims.speed_mult") --[[@as number]]
    local duration = lib.Param(inst, "Time", "stims.speed_time") --[[@as number]]
    local delay = lib.Param(inst, "UseTime", "stims.use_time") --[[@as number]]
    inst._StimBusy = true
    inst:Hook("PW_RoundEnd", function(active) active:Remove() end)
    inst:Hook("PW_EntityDisabled", function(active, kind, id)
        if kind == "modules" and (id == "stims" or id == "equipment" or id == "player_overrides") then
            active:Remove()
        end
    end)
    lib.Played(owner, inst)
    if delay <= 0 then boost(inst, owner, lib, multiplier, duration) else
        inst:Timer(delay, 1, function(active) boost(active, owner, lib, multiplier, duration) end)
    end
    return true
end

---@param owner Player
function EQUIPMENT:OnUnequip(owner)
    finish(self --[[@as PW.Instance]], owner)
end
