-- Addons declare custom event data on both realms; only the server accepts reports.
local lib = assert(PW.Challenges)
lib._CustomEventTypes = lib._CustomEventTypes or {}

function lib.RegisterEventType(id, def)
    if type(id) ~= "string" or #id > 48 or not id:match("^[%l%d_]+:[%l%d_]+$") then return false end
    if type(def) ~= "table" or (def.label ~= nil and type(def.label) ~= "string") then return false end
    if def.fields ~= nil and type(def.fields) ~= "table" then return false end
    ---@type PW.ChallengeEventType
    local copy = { label = def.label, fields = {} }
    local fields = assert(copy.fields)
    for key, value in pairs(def.fields or {}) do
        if type(key) ~= "string" or key == "" then return false end
        if value ~= "string" and value ~= "number" and value ~= "boolean" then return false end
        fields[key] = value
    end
    lib._CustomEventTypes[id] = copy
    return true
end
