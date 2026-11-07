-- PW.Instance (T-1.9, 00-core.md d.11): per-owner instances of a definition (perks, streaks, equipment) with
-- hooks and timers that end with the instance. Callbacks run through PW.Call; an instance has no own _Registry,
-- so an error lands it in PW._Call.failed: IsValid turns false, GMod drops its hooks, and it is ended.
-- The core ends every live instance on PW_MatchEnd (00-core.md d.3); PW_MatchEnd is server only, so the client ends
-- its instances when the phase leaves LIVE (cl_phase.lua, T-1.13).

---@type PW.InstanceStore
PW._Instances = PW._Instances or { live = {}, count = 0 }

---@type table<string, function> copied onto every instance
local methods = {}

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
    return not self._Dead and not PW._Call.failed[self]
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
    PW.Call(self, "OnUnequip", self._Owner)
    self._Dead = true
    PW._Instances.live[self] = nil
    for name in pairs(self._Hooks) do hook.Remove(name, self) end
    for name in pairs(self._Timers) do timer.Remove(name) end
end

---@param def table
---@param owner any
---@return PW.Instance
function PW.Instance(def, owner)
    local fields = { _Owner = owner, _Hooks = {}, _Timers = {} }
    local instance = setmetatable(fields, { __index = def }) --[[@as PW.Instance]]
    for name, fn in pairs(methods) do instance[name] = fn end
    PW._Instances.live[instance] = true
    PW.Call(instance, "OnEquip", owner)
    return instance
end

function PW._EndInstances()
    ---@type PW.Instance[]
    local live = {}
    for instance in pairs(PW._Instances.live) do live[#live + 1] = instance end
    for _, instance in ipairs(live) do instance:Remove() end
end

hook.Add("PW_MatchEnd", "PW.Instance", function() PW._EndInstances() end)
