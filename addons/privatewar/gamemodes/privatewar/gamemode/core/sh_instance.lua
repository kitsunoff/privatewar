-- PW.Instance (T-1.9, 00-core.md d.11): per-owner instances of a definition (perks, streaks, equipment) with
-- hooks and timers that end with the instance. Callbacks run through PW.Call; an instance has no own _Registry,
-- so an error lands it in PW._Call.failed: IsValid turns false, GMod drops its hooks, and it is ended.
-- Definition validity also blocks gameplay; the registry ends exact-definition instances before notifying disable.
-- Remove grants one private cleanup admission to PW.Call: failed/disabled instances still unequip and are profiled.
-- The core ends every live instance on PW_MatchEnd (00-core.md d.3); PW_MatchEnd is server only, so the client ends
-- its instances when the phase leaves LIVE (cl_phase.lua, T-1.13).

---@type PW.InstanceStore
PW._Instances = PW._Instances or { live = {}, count = 0 }

---@type table<string, function> copied onto every instance
local methods = {}

---@type table<table, true> private, single-use admissions created only inside actual Remove
local cleanupPending = setmetatable({}, { __mode = "k" })

---Only consumes existing admission; callers cannot create a cleanup bypass.
---@param entity table
---@param method string
---@return boolean
function PW._TakeInstanceCleanup(entity, method)
    if method ~= "OnUnequip" or not cleanupPending[entity] then return false end
    cleanupPending[entity] = nil
    return true
end

---@param self PW.Instance
---@param ... any
---@return any ...
local function settle(self, ...)
    if not self:IsValid() then self:Remove() end
    return ...
end

---@param self PW.Instance
---@param key string
---@param ... any
---@return any ...
local function run(self, key, ...)
    return settle(self, PW.Call(self, key, ...))
end

---@param self PW.Instance
---@return boolean
function methods.IsValid(self)
    if self._Dead or self._Ended or PW._Call.failed[self] then return false end
    local def = self._Definition --[[@as table<string, any>]]
    local valid = def.IsValid
    return not isfunction(valid) or not not valid(def)
end

---@param self PW.Instance
---@param name string
---@param fn fun(self: PW.Instance, ...: any): ...: any
function methods.Hook(self, name, fn)
    if not self:IsValid() then return end
    local key = "Hook:" .. name
    self[key] = fn
    self._Hooks[name] = true
    hook.Add(name, self, function(_, ...) return run(self, key, ...) end)
end

---@param self PW.Instance
---@param delay number
---@param reps integer
---@param fn fun(self: PW.Instance)
function methods.Timer(self, delay, reps, fn)
    if not self:IsValid() then return end
    local store = PW._Instances
    store.count = store.count + 1
    local name = "PW.Instance." .. store.count
    local key = "Timer:" .. name
    self[key] = fn
    self._Timers[name] = true
    timer.Create(name, delay, reps, function() run(self, key) end)
end

---@param self PW.Instance
function methods.Remove(self)
    if self._Ended then return end
    self._Ended = true
    self._Dead = true
    cleanupPending[self] = true
    local ok, err = pcall(PW.Call, self, "OnUnequip", self._Owner)
    cleanupPending[self] = nil
    PW._Instances.live[self] = nil
    for name in pairs(self._Hooks) do hook.Remove(name, self) end
    for name in pairs(self._Timers) do timer.Remove(name) end
    if not ok then
        local message = string.format("instance %q: OnUnequip cleanup failed: %s",
            tostring(self.ClassName or "?"), tostring(err))
        pcall(PW._Call.log, message)
    end
end

---@param def table
---@param owner any
---@return PW.Instance
function PW.Instance(def, owner)
    local fields = { _Owner = owner, _Definition = def, _Hooks = {}, _Timers = {} }
    local instance = setmetatable(fields, { __index = def }) --[[@as PW.Instance]]
    for name, fn in pairs(methods) do instance[name] = fn end
    PW._Instances.live[instance] = true
    PW.Call(instance, "OnEquip", owner)
    settle(instance)
    return instance
end

---@param definition? table nil ends every live instance
local function endInstances(definition)
    ---@type PW.Instance[]
    local live = {}
    for instance in pairs(PW._Instances.live) do
        if definition == nil or rawget(instance, "_Definition") == definition then live[#live + 1] = instance end
    end
    for _, instance in ipairs(live) do instance:Remove() end
end

function PW._EndInstances()
    endInstances()
end

---@param definition table
function PW._EndDefinitionInstances(definition)
    endInstances(definition)
end

hook.Add("PW_MatchEnd", "PW.Instance", function() PW._EndInstances() end)
