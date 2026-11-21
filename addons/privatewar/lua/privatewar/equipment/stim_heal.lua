EQUIPMENT.Name = "Heal Stim"
EQUIPMENT.Description = "Restores 60 health over 1.5 seconds. Cannot be used at full health."
EQUIPMENT.Category = "tactical"
EQUIPMENT.Count = 1
EQUIPMENT.Cost = 1
EQUIPMENT.Unlock = 1
EQUIPMENT.Sound = "items/smallmedkit1.wav"

local step = 0.25

---@param inst PW.Instance
---@param owner Player
local function finish(inst, owner)
    local lib = PW.Stims
    if inst._StimMarked and lib ~= nil and lib.Mark ~= nil then lib.Mark(owner, "heal", 0) end
    inst._StimBusy, inst._StimMarked = nil, nil
end

---@param inst PW.Instance
---@param owner Player
---@param lib PW.StimsLib
---@param amount number
---@param duration number
local function heal(inst, owner, lib, amount, duration)
    if not IsValid(owner) or not owner:Alive() then inst:Remove() return end
    local ticks = lib._Ticks(amount, duration, step)
    local index = 0
    local function tick(active)
        if not IsValid(owner) or not owner:Alive() then active:Remove() return end
        index = index + 1
        local current = owner:Health()
        local nextHealth = lib._Step(current, ticks[index], owner:GetMaxHealth())
        if nextHealth ~= current then owner:SetHealth(nextHealth) end
        if index == #ticks then finish(active, owner) end
    end
    if duration <= 0 then tick(inst) return end
    local mark = lib.Mark
    if mark ~= nil then
        inst._StimMarked = true
        mark(owner, "heal", CurTime() + duration)
    end
    local whole = math.floor(duration / step)
    if whole > 0 then inst:Timer(step, whole, tick) end
    if whole < #ticks then inst:Timer(duration, 1, tick) end
end

function EQUIPMENT:OnUse(owner)
    local lib = PW.Stims
    if lib == nil or lib.Played == nil or not IsValid(PW.Modules.Get("stims")) then return false end
    if not IsValid(owner) or not owner:Alive() or owner:Health() >= owner:GetMaxHealth() then return false end
    local inst = self --[[@as PW.Instance]]
    if inst._StimBusy then return false end
    local amount = lib.Param(inst, "Amount", "stims.heal_amount") --[[@as number]]
    local duration = lib.Param(inst, "Time", "stims.heal_time") --[[@as number]]
    local delay = lib.Param(inst, "UseTime", "stims.use_time") --[[@as number]]
    inst._StimBusy = true
    inst:Hook("PW_RoundEnd", function(active) active:Remove() end)
    inst:Hook("PW_EntityDisabled", function(active, kind, id)
        if kind == "modules" and (id == "stims" or id == "equipment") then active:Remove() end
    end)
    lib.Played(owner, inst)
    if delay <= 0 then heal(inst, owner, lib, amount, duration) else
        inst:Timer(delay, 1, function(active) heal(active, owner, lib, amount, duration) end)
    end
    return true
end

---@param owner Player
function EQUIPMENT:OnUnequip(owner)
    finish(self --[[@as PW.Instance]], owner)
end
