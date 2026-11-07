-- Settings schema (T-1.5, 01-extensibility.md d.17). Shared, pure: declarations of modes and modules (Settings
-- tables) become validated definitions with full ids "<owner id>.<key>"; values are validated (wrong type
-- rejected, numbers clamped to min/max, int rounded, enum and set members checked against options); a mode
-- inherits the settings of its Base chain and may redeclare an inherited key partially ({ default = 65 }); a
-- mode's SettingDefaults (full ids) override the defaults of module match settings for that mode. The store,
-- the getters and the ConVar glue are in sh_settings_store.lua; the match snapshot and the net messages in
-- sv_settings.lua.

local settingsLib = (rawget(PW, "Settings") or {}) --[[@as PW.SettingsLib]]
PW.Settings = settingsLib

local keyPattern = "^[a-z0-9_]+$"

---@type table<string, true>
local knownTypes = { int = true, float = true, bool = true, enum = true, set = true }
---@type table<string, true>
local knownScopes = { match = true, server = true, client = true }
---@type table<string, boolean>
local boolWords = { ["1"] = true, ["true"] = true, ["0"] = false, ["false"] = false }

---@param value any
---@return boolean
local function isFinite(value)
    return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

---@param def PW.SettingDef
---@param value number
---@return boolean ok
---@return number value
---@return string? note
local function clampNumber(def, value)
    local result = value
    if def.type == "int" then result = math.floor(result + 0.5) end
    local clamped = result
    local min, max = def.min, def.max
    if min ~= nil and clamped < min then clamped = min end
    if max ~= nil and clamped > max then clamped = max end
    if clamped ~= result then return true, clamped, "clamped" end
    return true, clamped
end

---A set is a list of ids or a lookup { [id] = true }; members are non-empty strings without commas (the wire
---and ConVar form is comma-separated). With options, every member must be one of them; otherwise the whole value
---is rejected, like an unknown enum option.
---@param def PW.SettingDef
---@param value any
---@return boolean ok
---@return table<string, true>? value
---@return string? reason
local function normalizeSet(def, value)
    if not istable(value) then return false, nil, "expected a set (table), got " .. type(value) end
    ---@type table<string, true>
    local set = {}
    local options = settingsLib._OptionSet(def)
    for key, member in pairs(value --[[@as table<any, any>]]) do
        ---@type any
        local id = nil
        if isnumber(key) then id = member elseif member == true then id = key end
        if not isstring(id) or id == "" or string.find(id, ",", 1, true) then
            return false, nil, string.format("invalid set member %s", tostring(id ~= nil and id or key))
        end
        if options ~= nil and not options[id] then
            return false, nil, string.format("unknown set member %q", id)
        end
        set[id --[[@as string]]] = true
    end
    return true, set
end

---Lists options as the list and its lookup; nil when it is not a non-empty list of non-empty strings.
---@param options any
---@return string[]?
---@return table<string, true>?
local function optionLists(options)
    if not istable(options) or #options == 0 then return nil end
    ---@type string[], table<string, true>
    local list, set = {}, {}
    for _, option in ipairs(options --[[@as any[] ]]) do
        if not isstring(option) or option == "" then return nil end
        list[#list + 1] = option
        set[option] = true
    end
    return list, set
end

---Calls a dynamic options function (pcall); nil when it fails or returns no valid list.
---@param fn function
---@return string[]?
---@return table<string, true>?
local function callOptions(fn)
    local ok, result = pcall(fn)
    if not ok then return nil end
    return optionLists(result)
end

function settingsLib._Options(def)
    local fn = def.optionsFn
    if fn ~= nil then
        local list, set = callOptions(fn)
        if list ~= nil then def.options, def.optionSet = list, set end
    end
    return def.options
end

function settingsLib._OptionSet(def)
    settingsLib._Options(def)
    return def.optionSet
end

function settingsLib._Validate(def, value)
    local kind = def.type
    if kind == "int" or kind == "float" then
        if not isFinite(value) then return false, nil, "expected a finite number, got " .. type(value) end
        return clampNumber(def, value --[[@as number]])
    elseif kind == "bool" then
        if not isbool(value) then return false, nil, "expected a boolean, got " .. type(value) end
        return true, value
    elseif kind == "enum" then
        if not isstring(value) then return false, nil, "expected an option (string), got " .. type(value) end
        local options = settingsLib._OptionSet(def)
        if options == nil or not options[value] then
            return false, nil, string.format("unknown option %q", value)
        end
        return true, value
    end
    return normalizeSet(def, value)
end

function settingsLib._Parse(def, text)
    if not isstring(text) then return false, nil, "expected a string, got " .. type(text) end
    local kind = def.type
    if kind == "int" or kind == "float" then
        local number = tonumber(text)
        if number == nil then return false, nil, string.format("%q is not a number", text) end
        return settingsLib._Validate(def, number)
    elseif kind == "bool" then
        local flag = boolWords[string.lower(string.Trim(text))]
        if flag == nil then return false, nil, string.format("%q is not 1, 0, true or false", text) end
        return true, flag
    elseif kind == "enum" then
        return settingsLib._Validate(def, text)
    end
    ---@type string[]
    local members = {}
    for _, part in ipairs(string.Explode(",", text)) do
        local member = string.Trim(part)
        if member ~= "" then members[#members + 1] = member end
    end
    return settingsLib._Validate(def, members)
end

function settingsLib._Format(def, value)
    local kind = def.type
    if kind == "bool" then return value and "1" or "0" end
    if kind == "int" then return string.format("%d", value) end
    if kind == "float" then return tostring(value) end
    if kind == "enum" then return value end
    ---@type string[]
    local members = {}
    for member in pairs(value --[[@as table<string, true>]]) do members[#members + 1] = member end
    table.sort(members)
    return table.concat(members, ",")
end

function settingsLib.Format(def, value)
    if isstring(def) then
        local found = settingsLib._CurrentIndex()[def --[[@as string]]]
        if found == nil then return nil end
        return settingsLib._Format(found, value)
    end
    return settingsLib._Format(def --[[@as PW.SettingDef]], value)
end

function settingsLib._SplitId(fullId)
    if not isstring(fullId) then return nil end
    local owner, key = string.match(fullId, "^([a-z0-9_]+)%.([a-z0-9_]+)$")
    return owner, key
end

function settingsLib._ConVarName(def)
    return "pw_" .. def.owner .. "_" .. def.key
end

---Checks options of an enum (required) or a set (optional): a non-empty list of non-empty strings, or a function
---that returns one (dynamic options, called again at every validation and form build).
---@param def PW.SettingDef
---@param options any
---@return string? err
local function checkOptions(def, options)
    if options == nil then
        if def.type == "enum" then return "an enum needs options" end
        return nil
    end
    if isfunction(options) then
        def.optionsFn = options --[[@as fun(): string[] ]]
        local list, set = callOptions(options --[[@as function]])
        if list == nil then return "the options function must return a non-empty list of strings" end
        def.options, def.optionSet = list, set
        return nil
    end
    local list, set = optionLists(options)
    if list == nil then return "options must be a non-empty list of strings" end
    def.options, def.optionSet = list, set
    return nil
end

---@param def PW.SettingDef
---@param decl table<string, any>
---@return string? err
local function checkRange(def, decl)
    for _, bound in ipairs({ "min", "max" }) do
        if decl[bound] ~= nil and not isFinite(decl[bound]) then return bound .. " must be a number" end
    end
    def.min, def.max = decl.min, decl.max
    if def.min ~= nil and def.max ~= nil and def.min > def.max then return "min is above max" end
    return nil
end

function settingsLib._CheckDef(owner, ownerKind, key, decl)
    if not isstring(key) or not string.match(key, keyPattern) then
        return nil, "the key must use lowercase letters, digits and _"
    end
    if not istable(decl) then return nil, "the declaration must be a table" end
    local fields = decl --[[@as table<string, any>]]
    local kind, scope = fields.type, fields.scope or "match"
    if not knownTypes[kind] then return nil, string.format("unknown type %q", tostring(kind)) end
    if not knownScopes[scope] then return nil, string.format("unknown scope %q", tostring(scope)) end
    if ownerKind == "modes" and scope ~= "match" then return nil, "a mode setting is always \"match\"" end
    if fields.description ~= nil and not isstring(fields.description) then
        return nil, "the description must be a string"
    end
    ---@type PW.SettingDef
    local def = {
        id = owner .. "." .. key, owner = owner, ownerKind = ownerKind, key = key, type = kind, scope = scope,
        label = isstring(fields.label) and fields.label or key,
        description = fields.description
    }
    local err = nil
    if kind == "int" or kind == "float" then err = checkRange(def, fields) end
    if kind == "enum" or kind == "set" then err = checkOptions(def, fields.options) end
    if err ~= nil then return nil, err end
    local ok, value, note = settingsLib._Validate(def, fields.default)
    if not ok then return nil, "invalid default: " .. tostring(note) end
    if note ~= nil then return nil, "the default is outside min/max" end
    def.default = value
    return def
end

function settingsLib._OwnChain(entity)
    local registry = entity._Registry --[[@as PW.Registry?]]
    if registry == nil then return { entity } end
    ---@type table[]
    local chain = {}
    ---@type table<string, true>
    local seen = {}
    local id = entity.ClassName --[[@as string?]]
    while id ~= nil and not seen[id] do
        seen[id] = true
        local own = registry.GetStored(id)
        if own == nil then break end
        table.insert(chain, 1, own)
        id = isstring(own.Base) and own.Base --[[@as string]] or nil
    end
    return chain
end

---Merges one declaration into the inherited one: the child's fields override per field.
---@param merged table<any, any>
---@param key any
---@param decl any
local function mergeDecl(merged, key, decl)
    local inherited = merged[key] --[[@as table<any, any>]]
    if not istable(decl) or not istable(inherited) then
        merged[key] = istable(decl) and table.Copy(decl) or decl
        return
    end
    for field, value in pairs(decl --[[@as table<any, any>]]) do inherited[field] = value end
end

---Declarations merged along a Base chain (root first).
---@param chain table[]
---@return table<any, any>
local function mergeDecls(chain)
    ---@type table<any, any>
    local merged = {}
    for _, own in ipairs(chain) do
        local decls = own.Settings --[[@as any]]
        if istable(decls) then
            for key, decl in pairs(decls --[[@as table<any, any>]]) do mergeDecl(merged, key, decl) end
        end
    end
    return merged
end

function settingsLib._Schema(entity, ownerKind, log)
    local owner = tostring(entity.ClassName)
    ---@type table<string, PW.SettingDef>
    local schema = {}
    for key, decl in pairs(mergeDecls(settingsLib._OwnChain(entity))) do
        local def, err = settingsLib._CheckDef(owner, ownerKind, key, decl)
        if def == nil then
            log(string.format("setting %s.%s skipped: %s", owner, tostring(key), tostring(err)))
        else
            schema[def.key] = def
        end
    end
    return schema
end

function settingsLib._SettingDefaults(mode)
    ---@type table<string, any>
    local merged = {}
    for _, own in ipairs(settingsLib._OwnChain(mode)) do
        if istable(own.SettingDefaults) then
            for id, value in pairs(own.SettingDefaults --[[@as table<string, any>]]) do merged[id] = value end
        end
    end
    return merged
end

function settingsLib._Index(modes, modules, log)
    ---@type PW.SettingIndex
    local index = {}
    for _, mode in ipairs(modes) do
        for _, def in pairs(settingsLib._Schema(mode, "modes", log)) do index[def.id] = def end
    end
    for _, module in ipairs(modules) do
        for _, def in pairs(settingsLib._Schema(module, "modules", log)) do
            if index[def.id] ~= nil then
                log(string.format("setting %s is declared by a mode and a module; the module's is used", def.id))
            end
            index[def.id] = def
        end
    end
    return index
end

function settingsLib._DefaultFor(def, mode, log)
    if mode == nil or def.ownerKind ~= "modules" or def.scope ~= "match" then return def.default end
    local override = settingsLib._SettingDefaults(mode)[def.id]
    if override == nil then return def.default end
    local ok, value, note = settingsLib._Validate(def, override)
    if not ok then
        log(string.format("mode %s: SettingDefaults[%q] ignored: %s", tostring(mode.ClassName), def.id,
            tostring(note)))
        return def.default
    end
    return value
end

---The match definitions of a mode and modules, in schema order (mode first).
---@param mode table?
---@param modules table[]
---@param log PW.LogFn
---@return PW.SettingDef[]
local function matchDefs(mode, modules, log)
    ---@type PW.SettingDef[]
    local defs = {}
    if mode ~= nil then
        for _, def in pairs(settingsLib._Schema(mode, "modes", log)) do defs[#defs + 1] = def end
    end
    for _, module in ipairs(modules) do
        for _, def in pairs(settingsLib._Schema(module, "modules", log)) do
            if def.scope == "match" then defs[#defs + 1] = def end
        end
    end
    return defs
end

function settingsLib._TakeSnapshot(mode, modules, pending, log)
    ---@type PW.SettingValues
    local values = {}
    for _, def in ipairs(matchDefs(mode, modules, log)) do
        local value = nil
        if pending[def.id] ~= nil then
            local ok, stored = settingsLib._Validate(def, pending[def.id])
            if ok then value = stored end
        end
        if value == nil then value = settingsLib._DefaultFor(def, mode, log) end
        values[def.id] = istable(value) and table.Copy(value) or value
    end
    return values
end

---@param input PW.SettingGroupsInput
---@param entity table
---@param ownerKind "modes"|"modules"
---@return PW.SettingGroup?
local function buildGroup(input, entity, ownerKind)
    local schema = settingsLib._Schema(entity, ownerKind, input.log)
    ---@type string[]
    local keys = {}
    for key, def in pairs(schema) do
        if def.scope == input.scope then keys[#keys + 1] = key end
    end
    if #keys == 0 then return nil end
    table.sort(keys)
    ---@type PW.SettingField[]
    local fields = {}
    for index, key in ipairs(keys) do
        local def = schema[key]
        fields[index] = { def = def, value = input.valueOf(def) }
    end
    return { owner = tostring(entity.ClassName), ownerKind = ownerKind, fields = fields }
end

function settingsLib._Groups(input)
    ---@type PW.SettingGroup[]
    local groups = {}
    if input.scope == "match" and input.mode ~= nil then
        groups[#groups + 1] = buildGroup(input, input.mode --[[@as table]], "modes")
    end
    for _, module in ipairs(input.modules) do
        local group = buildGroup(input, module, "modules")
        if group ~= nil then groups[#groups + 1] = group end
    end
    return groups
end
