-- Cooperative generation over injected discovery APIs. No entities, Give, network messages or match settings.
local lib = PW.Arc9BotLoadouts --[[@as PW.Arc9BotLoadoutsLib]]

---@generic T
---@param list T[]
---@param api PW.Arc9BotGenerationApi
---@return T?
local function choose(list, api)
    return #list > 0 and list[api.random(#list)] or nil
end

---@param class string
---@param api PW.Arc9BotGenerationApi
---@return PW.Build
local function buildFor(class, api)
    coroutine.yield()
    local slots = api.slots(class)
    ---@type PW.Build
    local build = {}
    local functional, camo = 0, false
    for _, slot in ipairs(slots) do
        coroutine.yield()
        local options = api.options(class, slot.id)
        ---@type string[]
        local accessories = {}
        ---@type string[]
        local camos = {}
        for _, option in ipairs(options) do
            coroutine.yield()
            local role = api.role(option.id)
            if role == "camo" then
                camos[#camos + 1] = option.id
            elseif role ~= nil and not slot.cosmetic and slot.default == nil and slot.parent == nil then
                accessories[#accessories + 1] = option.id
            end
        end
        if not camo and #camos > 0 then
            build[slot.id], camo = choose(camos, api), true
        elseif functional < 2 and #accessories > 0 then
            build[slot.id], functional = choose(accessories, api), functional + 1
        end
    end
    coroutine.yield()
    local clean = api.validate(class, build)
    return clean
end

---@param category string
---@param class string
---@param pistol string?
---@param knife string?
---@param api PW.Arc9BotGenerationApi
---@return PW.Loadout
local function loadoutFor(category, class, pistol, knife, api)
    local perks = lib.Perks[category]
    local slot = category == "pistol" and "secondary" or "primary"
    ---@type PW.Loadout
    local loadout = { lethal = "frag", tactical = "flash", perk1 = perks[1], perk2 = perks[2],
        perk3 = perks[3], streak1 = "uav", streak2 = "counter_uav", streak3 = "airstrike" }
    loadout[slot] = class
    if knife ~= nil then loadout.melee = knife end
    if category ~= "pistol" and pistol ~= nil then loadout.secondary = pistol end
    loadout.builds = { [slot] = buildFor(class, api) }
    return loadout
end

---@param state PW.Arc9BotGenerationState
---@param api PW.Arc9BotGenerationApi
local function generate(state, api)
    coroutine.yield()
    local weapons = api.weapons()
    ---@type table<string, string[]>
    local groups = {}
    ---@type string[]
    local knives = {}
    for _, weapon in ipairs(weapons) do
        coroutine.yield()
        if weapon.knife then knives[#knives + 1] = weapon.class end
        if weapon.category ~= nil then
            local category = weapon.category --[[@as string]]
            ---@type string[]
            local group = groups[category] or {}
            group[#group + 1] = weapon.class
            groups[category] = group
        end
    end
    ---@type PW.BotClassEntry[]
    local entries = {}
    for _, category in ipairs(lib.Archetypes) do
        local group = groups[category] or {}
        for variant = 1, 3 do
            coroutine.yield()
            local class, knife = choose(group, api), choose(knives, api)
            if class ~= nil and (category ~= "pistol" or knife ~= nil) then
                entries[#entries + 1] = {
                    ref = "generated:arc9:" .. category .. ":" .. variant, source = "generated", category = category,
                    name = "ARC9 " .. category .. " " .. variant,
                    loadout = loadoutFor(category, class, choose(groups.pistol or {}, api), knife, api)
                }
            end
        end
    end
    state.entries, state.status = entries, "ready" -- atomic publication; never an unfinished partial pool
end

function lib.New(map, api)
    ---@type PW.Arc9BotGenerationState
    local state = { map = map, version = lib.Version, status = "working", entries = {}, frames = 0,
        totalSeconds = 0, maxFrameSeconds = 0, resumes = 0 }
    state.job = coroutine.create(function() generate(state, api) end)
    return state
end

function lib.Step(state, now, seconds, limit)
    if state.status ~= "working" or state.job == nil then return 0 end
    local started, count = now(), 0
    repeat
        local ok, problem = coroutine.resume(state.job)
        count = count + 1
        if not ok then
            state.status, state.error, state.entries = "failed", tostring(problem), {}
        end
    until state.status ~= "working" or count >= limit or now() - started >= seconds
    local elapsed = now() - started
    state.frames, state.resumes = state.frames + 1, state.resumes + count
    state.totalSeconds = state.totalSeconds + elapsed
    state.maxFrameSeconds = math.max(state.maxFrameSeconds, elapsed)
    if state.status ~= "working" then state.job = nil end
    return count
end
