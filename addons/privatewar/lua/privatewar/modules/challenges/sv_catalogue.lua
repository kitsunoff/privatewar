-- Resolve enabled content at selection boundaries, never while matching score events.
local lib = assert(PW.Challenges)

---@type table<PW.Entity, PW.ChallengeTemplate|false>
local compiled = setmetatable({}, { __mode = "k" })

---@param set table<string, boolean>
---@return string[]
local function keys(set)
    local out = table.GetKeys(set) --[[@as string[] ]]
    table.sort(out)
    return out
end

---@return table<PW.ChallengeParamSource, table<string, boolean>>
local function availability()
    ---@type table<PW.ChallengeParamSource, table<string, boolean>>
    local out = { modes = {}, playlists = {}, weapons = {}, categories = {} }
    for _, mode in ipairs(PW.Modes.GetEnabledList()) do out.modes[mode.ClassName] = true end
    local playlist = PW.Playlist
    if playlist ~= nil and playlist.GetList ~= nil then
        for _, entry in ipairs(playlist.GetList()) do out.playlists[entry.id] = true end
    end
    local registry = PW.Weapons
    for _, entry in ipairs(registry ~= nil and registry.GetEnabledList() or {}) do
        local weapon = entry --[[@as PW.Weapon]]
        if weapon.Kind == "gun" then out.weapons[weapon.ClassName] = true end
        local category = weapon.Category
        if category ~= nil then out.categories[category] = true end
    end
    return out
end

---@param ids string[]?
---@param available table<string, boolean>
---@return boolean
local function any(ids, available)
    if ids == nil then return true end
    for _, id in ipairs(ids) do if available[id] then return true end end
    return false
end

---@param kinds table<string, string[]>?
---@return boolean
local function hasKinds(kinds)
    local registries = PW.Registries
    for kind, ids in pairs(kinds or {}) do
        local registry = registries ~= nil and registries[kind] or nil
        if registry == nil then return false end
        local available = false
        for _, id in ipairs(ids) do
            local entity = registry.Get(id)
            if entity ~= nil and entity:IsValid() then available = true break end
        end
        if not available then return false end
    end
    return true
end

---@param requires PW.ChallengeRequires?
---@param available table<PW.ChallengeParamSource, table<string, boolean>>
---@return boolean
local function eligible(requires, available)
    if requires == nil then return true end
    for _, id in ipairs(requires.events or {}) do
        if not lib._KnownEvent(id, lib._CustomEventTypes) then return false end
    end
    return any(requires.modes, available.modes) and any(requires.playlists, available.playlists)
        and any(requires.categories, available.categories) and hasKinds(requires.kinds)
end

---@param param PW.ChallengeParam
---@param available table<PW.ChallengeParamSource, table<string, boolean>>
---@return string[]
local function valuesFor(param, available)
    local source = param.source ~= nil and available[param.source] or nil
    local values = param.values
    if type(values) == "function" then
        local ok, result = pcall(values)
        if not ok or lib._ArrayLength(result) == nil then return {} end
        values = result
    end
    if values == nil then return source ~= nil and keys(source) or {} end
    if source == nil then return values end
    ---@type string[]
    local resolved = {}
    for _, value in ipairs(values) do
        if source[value] then resolved[#resolved + 1] = value end
    end
    return resolved
end

---@param entity PW.Entity
---@return PW.ChallengeTemplate|false
local function compiledOf(entity)
    local parsed = compiled[entity]
    if parsed ~= nil then return parsed end
    local template, reason = lib._Compile(entity.ClassName, entity, lib._CustomEventTypes)
    if template == nil then
        print("[PW] challenge " .. entity.ClassName .. " rejected: " .. (reason or "invalid template"))
    end
    compiled[entity] = template or false
    return compiled[entity]
end

function lib._ChallengeCatalogue()
    local registry = PW.Registries ~= nil and PW.Registries.challenges or nil
    if registry == nil then return {} end
    local available = availability()
    ---@type PW.ChallengeCandidate[]
    local candidates = {}
    for _, entity in ipairs(registry.GetEnabledList()) do
        local template = compiledOf(entity)
        if template == false or template.filterFailed or not eligible(template.definition.Requires, available) then
            continue
        end
        ---@type table<string, string[]>
        local values = {}
        for key, param in pairs(template.params) do values[key] = valuesFor(param, available) end
        candidates[#candidates + 1] = { template = template, values = values }
    end
    return candidates
end
