-- Thin glue: public PW catalogue/adapter and ARC9 attachment API only. Generation never creates a weapon.
local lib = PW.Arc9BotLoadouts --[[@as PW.Arc9BotLoadoutsLib]]
local map = game.GetMap()
PW._Arc9BotLoadouts = lib.Keep(rawget(PW, "_Arc9BotLoadouts"), map)

---@return PW.Adapter?
local function adapter()
    local registry = rawget(PW, "WeaponAdapters") --[[@as PW.Registry?]]
    local found = registry ~= nil and registry.Get("arc9") or nil
    return found --[[@as PW.Adapter?]]
end

---@param arcAdapter PW.Adapter
---@return PW.Arc9BotWeapon[]
local function weaponsFor(arcAdapter)
    local registry = rawget(PW, "Weapons") --[[@as PW.Registry?]]
    ---@type PW.Arc9BotWeapon[]
    local out = {}
    if registry == nil then return out end
    for _, entity in ipairs(registry.GetList()) do
        coroutine.yield()
        local class = entity.ClassName
        if PW.Adapters.For(class) == arcAdapter then
            local stored = weapons.GetStored(class) --[[@as table<string, any>?]]
            local data = entity --[[@as table<string, any>]]
            local info = stored ~= nil and lib.DescribeWeapon(class, data.Category, data.Kind, stored) or nil
            if info ~= nil then out[#out + 1] = info end
        end
    end
    table.sort(out, function(a, b) return a.class < b.class end)
    return out
end

---@param arcAdapter PW.Adapter
---@return PW.Arc9BotGenerationApi
local function generationApi(arcAdapter)
    ---@param method string
    ---@param ... any
    ---@return any
    ---@return any
    local function call(method, ...)
        assert(lib.Available(rawget(_G, "ARC9"), arcAdapter), "ARC9 adapter unavailable")
        local a, b = PW.Adapters.Call(arcAdapter, method, ...) --[[@as any, any]]
        assert(arcAdapter:IsValid(), "ARC9 adapter failed")
        return a, b
    end
    return {
        weapons = function() return weaponsFor(arcAdapter) end,
        slots = function(class) return call("GetSlots", class) end,
        options = function(class, slot) return call("GetOptions", class, slot) end,
        validate = function(class, build) return call("Validate", class, build) end,
        role = function(id) return lib.OptionRole(PW.Arc9.Offerable(id)) end,
        random = function(n) return math.random(n) end
    }
end

function lib.Start()
    if PW._Arc9BotLoadouts ~= nil then return end -- includes failed/unavailable: no same-map retries or rerolls
    local found = adapter()
    if not lib.Available(rawget(_G, "ARC9"), found) then
        PW._Arc9BotLoadouts = { map = map, version = lib.Version, status = "failed", entries = {},
            error = "ARC9 unavailable", frames = 0, resumes = 0, totalSeconds = 0, maxFrameSeconds = 0 }
        print("[PW] ARC9 bot loadouts: unavailable; keeping existing class sources")
        return
    end
    PW._Arc9BotLoadouts = lib.New(map, generationApi(found --[[@as PW.Adapter]]))
end

function lib.Legal(entry)
    local found = adapter()
    if found == nil or not lib.Available(rawget(_G, "ARC9"), found) then return false end
    local builds = (entry.loadout.builds or {}) --[[@as table<string, PW.Build>]]
    for slot, build in pairs(builds) do
        local class = entry.loadout[slot]
        if not isstring(class) or PW.Adapters.For(class) ~= found then return false end
        local clean, rejected = PW.Adapters.Call(found, "Validate", class, table.Copy(build)) --[[@as any, any]]
        if not found:IsValid() or not istable(clean) or not istable(rejected) then return false end
        if next(rejected) ~= nil then return false end
        for id, option in pairs(build) do
            if clean[id] ~= option then return false end
        end
    end
    return true
end

function MODULE:PW_WeaponsLoaded()
    -- The next Think is after every registration listener, regardless of GMod's hook order.
    timer.Simple(0, function() if self:IsValid() then lib.Start() end end)
end

---@param _ Player
---@param candidates PW.BotClassEntry[]
function MODULE:PW_BotLoadoutCandidates(_, candidates)
    if PW.Setting("bots_arc9_loadouts.generate") ~= true then return end
    for _, entry in ipairs(lib.Candidates(PW._Arc9BotLoadouts, game.GetMap(), true)) do
        if lib.Legal(entry) then candidates[#candidates + 1] = table.Copy(entry) end
    end
end

PW.HookFor(MODULE, "Think", function()
    local state = PW._Arc9BotLoadouts
    if state == nil or state.status ~= "working" then return end
    lib.Step(state, SysTime, 0.00075, 32)
    if state.status ~= "working" then
        print(string.format("[PW] ARC9 bot loadouts: %s, %d candidates, %d frames, %.2f ms total, %.2f ms max slice%s",
            state.status, #state.entries, state.frames, state.totalSeconds * 1000, state.maxFrameSeconds * 1000,
            state.error ~= nil and (", " .. state.error) or ""))
    end
end)
