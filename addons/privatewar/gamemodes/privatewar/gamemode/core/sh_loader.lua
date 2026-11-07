-- Kind loader (T-1.1, 01-extensibility.md d.8, d.15, d.16). Pure helpers (listing, names; required fields are
-- checked by the registry on the resolved entity)
-- plus thin engine glue: file.Find, CompileFile, AddCSLuaFile and the SWEP-style global class table.
-- Auto-subscription (T-1.7, d.18): modules subscribe "always", the kinds registry never, a declared kind
-- as its KIND.Subscribe says (omitted: "never"). Boot releases the registries it replaces.
-- Hot reload (T-1.15, d.12): every Boot is a full rescan (_Rescan); file access goes through an injectable
-- PW.LoaderFs (default _EngineFs), so tests can add or change files the game itself cannot write.

PW.Loader = PW.Loader or {}

local idPattern = "^[a-z0-9_]+$"

---The two built-in kinds; every other kind is declared by a file in kinds/.
---@type PW.KindDef
local kindsDef = { ClassName = "kinds", Folder = "kinds", Global = "KIND",
    Required = { Folder = "string", Global = "string" } }
---@type PW.KindDef
local modulesDef = { ClassName = "modules", Folder = "modules", Global = "MODULE", Subscribe = "always" }

---Kinds whose entities own settings (01-extensibility.md d.17) and get self:Setting(key).
---@type table<string, true>
local settingOwners = { modules = true, modes = true }

---@param kindDef PW.KindDef
---@param log PW.LogFn
---@return PW.RegistryOptions
local function registryOptions(kindDef, log)
    local settingsLib = rawget(PW, "Settings") --[[@as PW.SettingsLib?]]
    local methods = nil
    if settingOwners[kindDef.ClassName] and settingsLib ~= nil then methods = settingsLib.EntityMethods end
    return { log = log, subscribe = kindDef.Subscribe, methods = methods, required = kindDef.Required }
end

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---Turns a directory listing into entities: "<id>.lua" is the single-file form, "<id>/" the folder form.
---@param files string[]
---@param dirs string[]
---@return PW.ListingEntry[] entries sorted by id
---@return string[] errors one line per rejected name
function PW.Loader.ParseListing(files, dirs)
    ---@type table<string, "file"|"folder">
    local forms = {}
    ---@type string[]
    local errors = {}

    for _, name in ipairs(files) do
        local id = string.match(name, "^(.+)%.lua$")
        if id ~= nil and string.match(id, idPattern) then
            forms[id] = "file"
        elseif id ~= nil then
            errors[#errors + 1] = string.format("invalid id %q: use lowercase letters, digits and _", name)
        end
    end
    for _, name in ipairs(dirs) do
        if not string.match(name, idPattern) then
            errors[#errors + 1] = string.format("invalid id %q: use lowercase letters, digits and _", name)
        else
            if forms[name] == "file" then
                errors[#errors + 1] = string.format("%q exists as a file and a folder; the folder is used", name)
            end
            forms[name] = "folder"
        end
    end

    ---@type PW.ListingEntry[]
    local entries = {}
    for id, form in pairs(forms) do entries[#entries + 1] = { id = id, form = form } end
    table.sort(entries, function(a, b) return a.id < b.id end)
    return entries, errors
end

---Checks the required fields of a kind (01-extensibility.md d.15); the registry runs it on the resolved entity.
PW.Loader.ValidateRequired = PW.Registry.ValidateRequired

---"weapon_adapters" -> "WeaponAdapters": the PW.<Name> accessor of a kind's registry.
---@param kindId string
---@return string
function PW.Loader.AccessorName(kindId)
    local name = string.gsub(kindId, "(%w)(%w*)_?", function(first, rest)
        return string.upper(first) .. rest
    end)
    return name
end

---Compiles and runs one Lua file; syntax and runtime errors come back as a message instead of a throw.
---@param path string
---@return boolean ok
---@return string? err
local function runFile(path)
    -- With showError = false a failed compile returns the error message instead of a function.
    local fn = CompileFile(path, false) --[[@as function|string|nil]]
    if not isfunction(fn) then
        if isstring(fn) then return false, fn --[[@as string]] end
        return false, "failed to compile"
    end
    local ok, err = pcall(fn --[[@as function]])
    if not ok then return false, tostring(err) end
    return true
end

---The engine's LUA path. AddCSLuaFile at runtime (pw_reload) makes a new file downloadable; the listen server host
---picks it up on its next reload (sh_reload.lua: limits for remote clients).
---@type PW.LoaderFs
PW.Loader._EngineFs = {
    find = function(pattern)
        local files, dirs = file.Find(pattern, "LUA")
        return files or {}, dirs or {}
    end,
    exists = function(path) return file.Exists(path, "LUA") end,
    run = runFile,
    send = function(path)
        if SERVER then AddCSLuaFile(path) end
    end
}

---Collects the files of one entity for this realm and sends client files (SENT folder form rules).
---@param fs PW.LoaderFs
---@param dir string
---@param entry PW.ListingEntry
---@return string[] paths in run order
local function entityFiles(fs, dir, entry)
    if entry.form == "file" then
        local path = dir .. "/" .. entry.id .. ".lua"
        fs.send(path)
        return { path }
    end

    local base = dir .. "/" .. entry.id .. "/"
    ---@type string[]
    local paths = {}
    if fs.exists(base .. "shared.lua") then
        fs.send(base .. "shared.lua")
        paths[#paths + 1] = base .. "shared.lua"
    end
    local hasClient = fs.exists(base .. "cl_init.lua")
    if SERVER then
        if hasClient then fs.send(base .. "cl_init.lua") end
        if fs.exists(base .. "init.lua") then paths[#paths + 1] = base .. "init.lua" end
    elseif hasClient then
        paths[#paths + 1] = base .. "cl_init.lua"
    end
    return paths
end

---Loads one entity into a fresh global class table, then clears the global (SWEP-style).
---@param context PW.LoadContext
---@param kindDef PW.KindDef
---@param dir string
---@param entry PW.ListingEntry
local function loadEntity(context, kindDef, dir, entry)
    local label = string.format("%s %q (%s/%s)", kindDef.ClassName, entry.id, dir, entry.id)
    local paths = entityFiles(context.fs, dir, entry)
    if #paths == 0 then
        context.log(label .. ": no files for this realm")
        return
    end

    ---@type table<string, any>
    local tbl = {}
    local previous = rawget(_G, kindDef.Global)
    rawset(_G, kindDef.Global, tbl)
    local ok, err = true, nil
    for _, path in ipairs(paths) do
        ok, err = context.fs.run(path)
        if not ok then break end
    end
    rawset(_G, kindDef.Global, previous)

    if not ok then
        context.log(label .. ": " .. tostring(err))
        return
    end
    -- Required fields are checked by the registry after Base resolution (d.15: inherited fields count).
    context.registries[kindDef.ClassName].Register(tbl, entry.id)
end

---Scans one kind folder under the root and registers what it finds.
---@param context PW.LoadContext
---@param kindDef PW.KindDef
local function loadKind(context, kindDef)
    local dir = context.root .. "/" .. kindDef.Folder
    local files, dirs = context.fs.find(dir .. "/*")
    local entries, errors = PW.Loader.ParseListing(files, dirs)
    for _, message in ipairs(errors) do context.log(string.format("%s (%s): %s", kindDef.ClassName, dir, message)) end
    for _, entry in ipairs(entries) do loadEntity(context, kindDef, dir, entry) end
end

---Loads a whole tree in the order of 01-extensibility.md d.16: kinds/, modules/, every declared kind
---folder, then Base resolution for every registry.
---@param root string Lua path, e.g. "privatewar"
---@param opts? PW.LoadOptions
---@return PW.LoadContext
function PW.Loader.LoadRoot(root, opts)
    local log = (opts ~= nil and opts.log) or defaultLog
    local fs = (opts ~= nil and opts.fs) or PW.Loader._EngineFs
    ---@type PW.LoadContext
    local context = { root = root, registries = {}, log = log, fs = fs }
    context.registries.kinds = PW.Registry.New("kinds", registryOptions(kindsDef, log))
    context.registries.modules = PW.Registry.New("modules", registryOptions(modulesDef, log))

    loadKind(context, kindsDef)
    context.registries.kinds.ResolveAll()
    ---@type PW.KindDef[]
    local declared = {}
    for _, kind in ipairs(context.registries.kinds.GetList()) do
        ---@cast kind PW.KindDef
        if context.registries[kind.ClassName] ~= nil then
            log(string.format("kinds %q: the id is reserved by the core", kind.ClassName))
        else
            context.registries[kind.ClassName] = PW.Registry.New(kind.ClassName, registryOptions(kind, log))
            declared[#declared + 1] = kind
        end
    end

    loadKind(context, modulesDef)
    for _, kind in ipairs(declared) do loadKind(context, kind) end
    for _, registry in pairs(context.registries) do registry.ResolveAll() end
    return context
end

---@param previous table<string, PW.Registry>?
---@param active table[]
---@return table<string, table<string, true>>
function PW.Loader._KeepFor(previous, active)
    ---@type table<string, table<string, true>>
    local keep = {}
    if previous == nil then return keep end
    for _, entity in pairs(active) do
        local registry = rawget(entity, "_Registry") --[[@as PW.Registry?]]
        local id = rawget(entity, "ClassName")
        if registry ~= nil and isstring(id) and previous[registry.Kind] == registry then
            local ids = keep[registry.Kind] or {}
            ids[id] = true
            keep[registry.Kind] = ids
        end
    end
    return keep
end

---@param previous table<string, PW.Registry>?
---@param opts? PW.RescanOptions
---@return PW.LoadContext
function PW.Loader._Rescan(previous, opts)
    opts = opts or {}
    local context = PW.Loader.LoadRoot(opts.root or "privatewar", opts)
    local keep = PW.Loader._KeepFor(previous, opts.active or {})
    for kindId, registry in pairs(previous or {}) do registry._Release(keep[kindId]) end
    return context
end

---Loads the gamemode's tree and installs the registries as PW.Registries and PW.<Name> accessors. Every Boot
---rescans every kind folder (pw_reload, GM:OnReloaded: 01-extensibility.md d.12). The registries it replaces (an
---earlier Boot) are released: their entities stop receiving hooks; the active mode of a running match stays valid
---and keeps running until the match ends (d.12: a reload does not touch the running match).
---On the server the enable ConVar snapshot is applied to the new registries before PW_RegistriesLoaded (T-1.4);
---then the ConVars of server and client settings are created (T-1.5). After InitPostEntity a Boot also re-runs the
---weapon registration phase after PW_RegistriesLoaded (T-1.17, sh_weapon_phase.lua).
function PW.Loader.Boot()
    ---@type table[]
    local active = { rawget(PW, "ActiveMode") }
    ---@type PW.LoadContext
    local context = PW.Loader._Rescan(PW.Registries, { active = active })
    PW.Registries = context.registries
    for kindId, registry in pairs(context.registries) do
        local name = PW.Loader.AccessorName(kindId)
        local existing = rawget(PW, name)
        if existing == nil or (istable(existing) and existing.Kind == kindId) then
            rawset(PW, name, registry)
        else
            context.log(string.format("kinds %q: PW.%s is taken by the core; use PW.Registries.%s", kindId, name,
                kindId))
        end
    end
    local enableLib = rawget(PW, "Enable") --[[@as PW.EnableLib?]]
    if enableLib ~= nil then enableLib._OnBoot() end
    local settingsLib = rawget(PW, "Settings") --[[@as PW.SettingsLib?]]
    if settingsLib ~= nil then settingsLib._OnBoot() end
    PW.Notify("PW_RegistriesLoaded")
    local weaponPhase = rawget(PW, "WeaponPhase") --[[@as PW.WeaponPhaseLib?]]
    if weaponPhase ~= nil then weaponPhase._OnBoot() end
end
