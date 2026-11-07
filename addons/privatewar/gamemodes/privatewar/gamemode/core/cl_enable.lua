-- Enable snapshot, client part (01-extensibility.md d.11, d.16). The client reads the NW2 values the server wrote
-- (sh_enable.lua) and applies them to its own registries, so a module disabled for the match is disabled here too:
-- its PW_* methods and PW.HookFor hooks stop, GetEnabledList and IsValid match the server. _Sync runs on every
-- client Boot and before every PW_PhaseChanged (cl_phase.lua); the server changes the snapshot only when a new
-- match enters PREMATCH and writes it before the phase globals of that transition.

local enable = PW.Enable --[[@as PW.EnableLib]]

---@param key string
---@return boolean
local function readFlag(key)
    return GetGlobal2Bool(key, false)
end

function enable._Sync()
    local registries = PW.Registries or {}
    enable._Apply(registries, enable._ReadSnapshot(registries, readFlag))
end

function enable._OnBoot()
    enable._Sync()
end

function enable._OnRegistered() end
