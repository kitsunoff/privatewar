-- Author-owned shipped compositions and offline UTC calendars, not a shared schedule registry.
local lib = assert(PW.Playlist)
local hour, day, week = 3600, 86400, 604800

---@class PW.RotationSpec
---@field name string
---@field modes string[]
---@field pool string
---@field settings table<string, any>
---@field start number seconds after Monday UTC (or midnight for daily)
---@field duration number
---@field period? number defaults to one week

---@type table<string, PW.RotationSpec>
local specs = {
    shipment_weekends = { name = "Shipment 24/7 Weekends", modes = { "tdm", "kc", "dom", "hardpoint" },
        pool = "shipment", settings = { ["bots.fill"] = 12 }, start = 5 * day, duration = 2 * day },
    ground_war = { name = "Ground War TDM 32", modes = { "tdm" }, pool = "standard",
        settings = { ["bots.fill"] = 32, ["tdm.scorelimit"] = 150, ["tdm.timelimit"] = 900 },
        start = 4 * day + 18 * hour, duration = 2 * day + 6 * hour },
    infected = { name = "Infected", modes = { "pw_infection" }, pool = "standard",
        settings = { ["bots.fill"] = 12 }, start = 18 * hour, duration = 6 * hour, period = day },
    small_map_moshpit = { name = "Small Map Moshpit", modes = { "tdm", "kc", "dom", "hardpoint" },
        pool = "small", settings = { ["bots.fill"] = 8 }, start = 0, duration = 5 * day },
    objective_chaos = { name = "Objective Chaos", modes = { "dom", "hardpoint" }, pool = "standard",
        settings = { ["bots.fill"] = 12 }, start = day, duration = 3 * day },
    ffa_frenzy = { name = "Free-for-All Frenzy", modes = { "ffa" }, pool = "standard",
        settings = { ["bots.fill"] = 8, ["ffa.scorelimit"] = 25, ["ffa.timelimit"] = 300,
            ["ffa.respawndelay"] = 1 }, start = 0, duration = 6 * day }
}

---@param map string
---@return boolean
local function shipment(map)
    -- Only actual installed BSP names; an exact underscore/hyphen-delimited token, not "notshipment".
    return string.find("_" .. string.lower(map) .. "_", "[_%-]shipment[_%-]") ~= nil
end

---@param spec PW.RotationSpec
---@param facts PW.RotationFacts
---@param map string
---@param modes table<string, number>
---@return boolean
local function admitModes(spec, facts, map, modes)
    local fits = false
    for _, mode in ipairs(spec.modes) do
        if facts.modes[mode] and facts.fits(mode, map) then modes[mode], fits = 1, true end
    end
    return fits
end

---@param data PW.PlaylistData
---@param facts PW.RotationFacts
---@return boolean
local function hasPair(data, facts)
    for mode in pairs(data.Modes) do
        for _, map in ipairs(data.Maps or {}) do
            if facts.modes[mode] and facts.fits(mode, map) then return true end
        end
    end
    return false
end

---@param id string
---@param now number
---@return boolean, number
function lib._RotationWindow(id, now)
    local spec = assert(specs[id], "unknown shipped rotation")
    local period = spec.period or week
    -- Unix epoch was Thursday. This Monday anchor uses arithmetic, never local-time date conversion/DST.
    local anchor = period == day and 0 or -3 * day
    local offset = (now - anchor - spec.start) % period
    local start = now - offset
    if offset < spec.duration then return true, start + spec.duration end
    return false, start + period
end

---@param id string
---@param facts PW.RotationFacts
---@return PW.PlaylistData?, string?
function lib._BuildRotation(id, facts)
    local spec = assert(specs[id], "unknown shipped rotation")
    if id == "infected" and not facts.infection then
        return nil, "Infected: requires enabled Infection modules, native weapon_fists and at least two server slots"
    end
    ---@type table<string, number>
    local modes = {}
    ---@type string[]
    local maps = {}
    ---@type table<string, boolean>
    local seen = {}
    for _, map in ipairs(facts.maps) do
        local wanted = spec.pool == "standard" or shipment(map) or (spec.pool == "small" and map == "gm_construct")
        if wanted and not seen[map] then
            local fits = admitModes(spec, facts, map, modes)
            if fits then maps[#maps + 1], seen[map] = map, true end
        end
    end
    if #maps == 0 then
        return nil, spec.name .. ": no installed eligible map/mode pair (check required content and enablement)"
    end
    table.sort(maps)
    return { Name = spec.name, Modes = modes, Maps = maps, Settings = table.Copy(spec.settings) }
end

---@return boolean
local function infectionReady()
    if weapons.GetStored("weapon_fists") == nil or game.MaxPlayers() < 2 then return false end
    for _, id in ipairs({ "pw_infection_rules", "teams", "loadout", "operators", "player_overrides",
        "match_rules", "lobby" }) do
        local owner = PW.Modules.Get(id)
        if owner == nil or not owner:IsValid() then return false end
    end
    return true
end

---@return PW.RotationFacts
function lib._RotationFacts()
    local registry = (PW.Registries or {}).modes
    ---@type table<string, boolean>
    local modes = {}
    for _, mode in ipairs(registry ~= nil and registry.GetEnabledList() or {}) do
        if not mode.Abstract then modes[mode.ClassName] = true end
    end
    ---@type string[]
    local maps = table.Copy(PW.MapList ~= nil and PW.MapList.GetList() or {})
    -- Base-game fallback is deliberate, not an expansion of the host's curated map list.
    for _, map in ipairs({ "gm_construct", "gm_flatgrass" }) do
        if file.Exists("maps/" .. map .. ".bsp", "GAME") then maps[#maps + 1] = map end
    end
    local shipmentFiles = (file.Find("maps/*shipment*.bsp", "GAME") or {}) --[[@as string[] ]]
    for _, name in ipairs(shipmentFiles) do
        local map = string.sub(name, 1, -5)
        if shipment(map) then maps[#maps + 1] = map end
    end
    return { maps = maps, modes = modes, infection = infectionReady(), fits = function(id, map)
        if not modes[id] or not file.Exists("maps/" .. map .. ".bsp", "GAME") then return false end
        local mode = registry ~= nil and registry.Get(id) or nil
        -- Use the exact start-time checker: validity/failure state and declaration semantics belong to core.
        -- This is read-only and does not apply pending enable ConVars or bind a match dependency snapshot.
        if mode == nil or assert(PW.Match)._CheckDependencies(mode, PW.Registries or {}) == nil then return false end
        return mode ~= nil and PW.Map ~= nil and PW.Map.ModeFits(mode, map)
    end }
end

---@param id string
---@param data PW.PlaylistData
---@param now number
---@param facts PW.RotationFacts
---@return boolean, number?
function lib._RotationContentActive(id, data, now, facts)
    if id == "infected" and not facts.infection then return false end
    if hasPair(data, facts) then return lib._RotationWindow(id, now) end
    -- Do not announce a future card when content is missing, even if its calendar has a known start.
    return false
end

---@param definition PW.Playlist
---@param id string
---@return table<string, number>
function lib._ResolveRotation(definition, id)
    local data, reason = lib._BuildRotation(id, lib._RotationFacts())
    assert(data, reason)
    definition._RotationData = data
    return data.Modes
end

---@param definition PW.Playlist
---@param id string
---@param now number
---@return boolean, number?
function lib._ShippedActive(definition, id, now)
    local data = definition._RotationData
    if data == nil then return false end
    return lib._RotationContentActive(id, data, now, lib._RotationFacts())
end
