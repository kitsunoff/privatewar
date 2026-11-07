-- Settings store, getters and ConVar glue (T-1.5, 01-extensibility.md d.17). Shared. The pure schema logic is in
-- sh_settings.lua. PW.Setting(fullId) reads a match setting from the snapshot of the current match (taken by
-- sv_settings.lua on LOBBY -> PREMATCH), else the host's pending value, else the default; a server or client
-- setting from its archived ConVar pw_<owner>_<key> (created at Boot; server ConVars are replicated). Modes and
-- modules get self:Setting(key) through the registry (sh_loader.lua). The index is rebuilt from the registries
-- on every lookup outside the snapshot, so late registrations and pw_reload need no invalidation.

local settingsLib = PW.Settings

settingsLib.Privilege = "pw.settings.change"
PW.Privilege(settingsLib.Privilege, "superadmin")

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@param value any
---@return any
local function copyValue(value)
    if istable(value) then return table.Copy(value) end
    return value
end

---@param name string
---@return string?
local function readConVar(name)
    local convar = GetConVar(name)
    if convar == nil then return nil end
    return convar:GetString()
end

---@param name string
---@param text string
---@return boolean
local function writeConVar(name, text)
    local convar = GetConVar(name)
    if convar == nil then return false end
    convar:SetString(text)
    return true
end

---Server settings: a replicated ConVar on both realms (archived on the server); client settings: an archived
---client ConVar on the client only.
---@param def PW.SettingDef
local function createConVar(def)
    local name = settingsLib._ConVarName(def)
    if GetConVar(name) ~= nil then return end
    local text = settingsLib._Format(def, def.default)
    local help = "Private War setting " .. def.id
    if def.scope == "server" then
        local flags = SERVER and { FCVAR_ARCHIVE, FCVAR_REPLICATED } or { FCVAR_REPLICATED }
        CreateConVar(name, text, flags, help, def.min, def.max)
    elseif CLIENT then
        CreateClientConVar(name, text, true, false, help, def.min, def.max)
    end
end

---@return string id
---@return string value
local function readChange()
    return net.ReadString(), net.ReadString()
end

function settingsLib._NewStore(opts)
    opts = opts or {}
    return {
        registries = opts.registries or function() return rawget(PW, "Registries") or {} end,
        log = opts.log or defaultLog,
        convars = opts.convars or { read = readConVar, write = writeConVar, create = createConVar },
        readChange = opts.readChange or readChange,
        pending = {},
        reported = {}
    }
end

PW._Settings = PW._Settings or settingsLib._NewStore()

---Logs a message once per store (schema errors and unknown ids would repeat on every lookup).
---@param message string
local function logOnce(message)
    local store = PW._Settings
    if store.reported[message] then return end
    store.reported[message] = true
    store.log(message)
end

---@param registry PW.Registry?
---@return PW.Entity[]
local function listOf(registry)
    if registry == nil then return {} end
    return registry.GetList()
end

---@return PW.Entity[]
local function enabledModules()
    local registry = PW._Settings.registries().modules
    if registry == nil then return {} end
    return registry.GetEnabledList()
end

---@param a PW.Entity[]
---@param b PW.Entity[]
---@return boolean
local function sameEntities(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- The index is rebuilt only when the mode or module lists changed (T-10.4: PW.Setting outside the match snapshot
-- rebuilt it on every call, about 0.25 ms on the Deck). A re-registration, a re-resolution of a Base chain or a
-- reload gives an entity a new table, and a disable or release changes the list, so both lists compared by entity
-- identity tell whether the cached index still holds.
function settingsLib._CurrentIndex()
    local store = PW._Settings
    local registries = store.registries()
    local modes, modules = listOf(registries.modes), listOf(registries.modules)
    local cached = store.index
    if cached ~= nil and sameEntities(cached.modes, modes) and sameEntities(cached.modules, modules) then
        return cached.index
    end
    local index = settingsLib._Index(modes, modules, logOnce)
    store.index = { modes = modes, modules = modules, index = index }
    return index
end

---The match value outside the snapshot: the host's pending value, else the default for mode.
---@param def PW.SettingDef
---@param mode table?
---@return any
local function pendingOrDefault(def, mode)
    local pending = PW._Settings.pending[def.id]
    if pending ~= nil then return pending end
    return settingsLib._DefaultFor(def, mode, logOnce)
end

function settingsLib._Value(def)
    local store = PW._Settings
    if def.scope == "match" then
        local snapshot = store.snapshot
        if snapshot ~= nil and snapshot[def.id] ~= nil then return snapshot[def.id] end
        return pendingOrDefault(def, rawget(PW, "ActiveMode"))
    end
    local text = store.convars.read(settingsLib._ConVarName(def))
    if text == nil then return def.default end
    local ok, value = settingsLib._Parse(def, text)
    if ok then return value end
    return def.default
end

---@param fullId string
---@return any
function PW.Setting(fullId)
    local snapshot = PW._Settings.snapshot
    if snapshot ~= nil and snapshot[fullId] ~= nil then return copyValue(snapshot[fullId]) end
    local def = settingsLib._CurrentIndex()[fullId]
    if def == nil then
        logOnce(string.format("unknown setting %q", tostring(fullId)))
        return nil
    end
    return copyValue(settingsLib._Value(def))
end

settingsLib.EntityMethods = {
    ---@param self table
    ---@param key string
    ---@return any
    Setting = function(self, key)
        return PW.Setting(tostring(self.ClassName) .. "." .. tostring(key))
    end
}

---Scopes this realm may change: the server owns match and server settings, a client its client settings.
---@type table<string, true>
local ownScopes = SERVER and { match = true, server = true } or { client = true }

function settingsLib.Set(fullId, value)
    local store = PW._Settings
    local def = settingsLib._CurrentIndex()[fullId]
    if def == nil then return false, string.format("unknown setting %q", tostring(fullId)) end
    if not ownScopes[def.scope] then
        return false, string.format("%s is a %s setting and cannot be changed here", def.id, def.scope)
    end
    local ok, stored, note = settingsLib._Validate(def, value)
    if not ok then return false, note end
    if def.scope == "match" then
        store.pending[def.id] = stored
    elseif not store.convars.write(settingsLib._ConVarName(def), settingsLib._Format(def, stored)) then
        return false, string.format("the ConVar of %s does not exist", def.id)
    end
    return true, note
end

function settingsLib.GetGroups(scope, mode)
    return settingsLib._Groups({
        mode = mode, modules = enabledModules(), scope = scope, log = logOnce,
        valueOf = function(def)
            if def.scope == "match" then return copyValue(pendingOrDefault(def, mode)) end
            return copyValue(settingsLib._Value(def))
        end
    })
end

function settingsLib._LogOnce(message)
    logOnce(message)
end

function settingsLib._EnabledModules()
    return enabledModules()
end

function settingsLib._OnBoot()
    local store = PW._Settings
    for _, def in pairs(settingsLib._CurrentIndex()) do
        if def.scope ~= "match" then store.convars.create(def) end
    end
end
