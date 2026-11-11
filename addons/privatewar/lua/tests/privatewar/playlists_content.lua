-- Shipped content is tested separately from the mandatory availability/entitlement suites.
local function lib() return assert(PW.Playlist) end

---@return PW.RotationFacts
local function facts()
    return { maps = { "gm_construct", "gm_flatgrass", "mp_shipment" }, infection = true,
        modes = { tdm = true, ffa = true, kc = true, dom = true, hardpoint = true, pw_infection = true },
        fits = function(mode, map)
            return (mode ~= "dom" and mode ~= "hardpoint") or map == "gm_construct"
        end }
end

return {
    groupName = "PW shipped playlist content",
    beforeEach = function(state) state.originalFacts = lib()._RotationFacts end,
    afterEach = function(state) lib()._RotationFacts = state.originalFacts end,
    cases = {
        {
            name = "Registered rotations resolve startup data and their predicates recheck installed dependencies",
            func = function()
                local content = facts()
                lib()._RotationFacts = function() return content end
                local registry = assert(PW.Playlists)
                for _, id in ipairs({ "shipment_weekends", "ground_war", "infected", "small_map_moshpit",
                    "objective_chaos", "ffa_frenzy" }) do
                    local source = assert(registry.GetStored(id))
                    -- Do not mutate the real definition or its frozen session data.
                    local definition = { Name = source.Name, Modes = source.Modes, Maps = source.Maps,
                        Settings = source.Settings, IsActive = source.IsActive }
                    local data = assert(lib().Resolve(definition))
                    expect(data).to.deepEqual(assert(lib()._BuildRotation(id, content)))
                    local scheduled, boundary = lib()._RotationWindow(id, 1794355200)
                    local result = lib()._Evaluate(definition, 1794355200)
                    expect(result.active).to.equal(scheduled)
                    expect(result.nextChange).to.equal(boundary)
                    content.fits = function() return false end
                    expect(lib()._Evaluate(definition, 1794355200)).to.deepEqual({ active = false, valid = true })
                    content = facts()
                end
            end
        },
        {
            name = "Shipped rotations use real modes fitting installed maps and schema-valid match settings",
            func = function()
                local modes = assert(PW.Registries.modes)
                ---@type PW.SettingIndex
                local index = {}
                for _, mode in ipairs(modes.GetList()) do
                    for _, group in ipairs(PW.Settings.GetGroups("match", mode)) do
                        for _, field in ipairs(group.fields) do index[field.def.id] = field.def end
                    end
                end
                for _, group in ipairs(PW.Settings.GetGroups("match")) do
                    for _, field in ipairs(group.fields) do index[field.def.id] = field.def end
                end
                for _, id in ipairs({ "shipment_weekends", "ground_war", "small_map_moshpit",
                    "objective_chaos", "ffa_frenzy" }) do
                    local data = assert(lib()._BuildRotation(id, facts()))
                    local resolved, reason = lib().Normalize(data, { modes = facts().modes,
                        settings = index, validate = PW.Settings._Validate })
                    expect(reason).to.equal(nil)
                    expect(resolved ~= nil).to.beTrue()
                    for mode in pairs(data.Modes) do
                        expect(modes.Get(mode) ~= nil).to.beTrue()
                        local pick = lib().Sample(data, { rng = function() return 0 end,
                            fits = facts().fits })
                        expect(pick ~= nil).to.beTrue()
                    end
                end
            end
        },
        {
            name = "Host content inventory admits only installed BSPs and enabled mode pairs through the real map API",
            func = function()
                local installed = lib()._RotationFacts()
                for _, map in ipairs(installed.maps) do
                    expect(file.Exists("maps/" .. map .. ".bsp", "GAME")).to.beTrue()
                end
                for _, id in ipairs({ "shipment_weekends", "ground_war", "infected", "small_map_moshpit",
                    "objective_chaos", "ffa_frenzy" }) do
                    local data, reason = lib()._BuildRotation(id, installed)
                    if data == nil then
                        expect(isstring(reason) and #reason > 0).to.beTrue()
                    else
                        local pick = lib().Sample(data, { rng = function() return 0 end, fits = installed.fits })
                        expect(pick ~= nil).to.beTrue()
                        local chosen = assert(pick)
                        local mode = assert(PW.Registries.modes.Get(chosen.mode))
                        expect(installed.modes[chosen.mode]).to.beTrue()
                        expect(assert(PW.Map).ModeFits(mode, chosen.map)).to.beTrue()
                    end
                end
            end
        },
        {
            name = "Missing Shipment or Infection rejects only its own content instead of offering empty rotations",
            func = function()
                local content = facts()
                content.maps = { "gm_construct", "gm_flatgrass", "dm_notshipment" }
                expect(lib()._BuildRotation("shipment_weekends", content)).to.equal(nil)
                content.modes.pw_infection = nil
                expect(lib()._BuildRotation("infected", content)).to.equal(nil)
                content.modes.pw_infection = true
                content.infection = false
                expect(lib()._BuildRotation("infected", content)).to.equal(nil)
                content.infection = true
                expect(assert(lib()._BuildRotation("infected", content)).Modes).to.deepEqual({ pw_infection = 1 })
                expect(lib()._BuildRotation("small_map_moshpit", content) ~= nil).to.beTrue()
                content.fits = function() return false end
                expect(lib()._BuildRotation("objective_chaos", content)).to.equal(nil)
            end
        },
        {
            name = "Objective and small-map pools exclude unsupported modes and maps without inventing layouts",
            func = function()
                local content = facts()
                local small = assert(lib()._BuildRotation("small_map_moshpit", content))
                expect(small.Maps).to.deepEqual({ "gm_construct", "mp_shipment" })
                expect(small.Modes).to.deepEqual({ tdm = 1, kc = 1, dom = 1, hardpoint = 1 })
                content.fits = function(mode, map) return mode == "dom" and map == "gm_construct" end
                local objective = assert(lib()._BuildRotation("objective_chaos", content))
                expect(objective.Modes).to.deepEqual({ dom = 1 })
                expect(objective.Maps).to.deepEqual({ "gm_construct" })
                expect(assert(lib()._BuildRotation("ground_war", facts())).Settings["bots.fill"]).to.equal(32)
            end
        },
        {
            name = "Ground War fill uses existing reserved-slot quota and never requires changing maxplayers",
            func = function()
                local fill = assert(lib()._BuildRotation("ground_war", facts())).Settings["bots.fill"]
                local manager = assert(PW.BotsManager)
                expect(manager._Quota({ fill = fill, maxPlayers = 1, humans = 1 })).to.equal(0)
                expect(manager._Quota({ fill = fill, maxPlayers = 12, humans = 1 })).to.equal(10)
                expect(manager._Quota({ fill = fill, maxPlayers = 40, humans = 1 })).to.equal(31)
                expect(manager._Quota({ fill = fill, maxPlayers = 12, humans = 12 })).to.equal(0)
            end
        },
        {
            name = "Weekend UTC exact boundaries and repeated forward backward samples do not use local timezone",
            func = function()
                -- 2026-11-13 Friday 00:00 UTC; deliberately no os.time(local date table).
                local friday = 1794528000
                local active, boundary = lib()._RotationWindow("shipment_weekends", friday - 1)
                expect(active).to.beFalse() expect(boundary).to.equal(friday + 86400)
                for _, now in ipairs({ friday + 86400, friday + 2 * 86400, friday + 86400 }) do
                    active, boundary = lib()._RotationWindow("shipment_weekends", now)
                    expect(active).to.beTrue() expect(boundary).to.equal(friday + 3 * 86400)
                end
                active, boundary = lib()._RotationWindow("shipment_weekends", friday + 3 * 86400)
                expect(active).to.beFalse() expect(boundary).to.equal(friday + 8 * 86400)
            end
        },
        {
            name = "Every shipped UTC window includes its start excludes its end and reports the next actual boundary",
            func = function()
                local monday, day = 1794182400, 86400 -- 2026-11-09 00:00 UTC
                local windows = {
                    { id = "shipment_weekends", offset = 5 * day, duration = 2 * day, period = 7 * day },
                    { id = "ground_war", offset = 4 * day + 18 * 3600,
                        duration = 2 * day + 6 * 3600, period = 7 * day },
                    { id = "infected", offset = 18 * 3600, duration = 6 * 3600, period = day },
                    { id = "small_map_moshpit", offset = 0, duration = 5 * day, period = 7 * day },
                    { id = "objective_chaos", offset = day, duration = 3 * day, period = 7 * day },
                    { id = "ffa_frenzy", offset = 0, duration = 6 * day, period = 7 * day }
                }
                for _, window in ipairs(windows) do
                    local id = window.id
                    local start = monday + window.offset
                    local finish = start + window.duration
                    local active, boundary = lib()._RotationWindow(id, start - 1)
                    expect(active).to.beFalse() expect(boundary).to.equal(start)
                    active, boundary = lib()._RotationWindow(id, start)
                    expect(active).to.beTrue() expect(boundary).to.equal(finish)
                    active, boundary = lib()._RotationWindow(id, finish - 1)
                    expect(active).to.beTrue() expect(boundary).to.equal(finish)
                    active, boundary = lib()._RotationWindow(id, finish)
                    expect(active).to.beFalse() expect(boundary).to.equal(start + window.period)
                end
            end
        },
        {
            name = "Wednesday base content is immediately active and daily windows have exact UTC next changes",
            func = function()
                local wednesday = 1794355200 -- 2026-11-11 00:00 UTC
                expect(lib()._RotationWindow("small_map_moshpit", wednesday)).to.beTrue()
                expect(lib()._RotationWindow("ffa_frenzy", wednesday)).to.beTrue()
                expect(lib()._RotationWindow("objective_chaos", wednesday)).to.beTrue()
                local active, boundary = lib()._RotationWindow("infected", wednesday + 18 * 3600)
                expect(active).to.beTrue() expect(boundary).to.equal(wednesday + 86400)
                active, boundary = lib()._RotationWindow("infected", wednesday + 86400)
                expect(active).to.beFalse() expect(boundary).to.equal(wednesday + 42 * 3600)
            end
        },
        {
            name = "Content loss hides known upcoming cards instead of publishing an empty scheduled pool",
            func = function()
                local data = assert(lib()._BuildRotation("shipment_weekends", facts()))
                local content = facts()
                content.modes = {}
                local active, boundary = lib()._RotationContentActive("shipment_weekends", data, 1794355200, content)
                expect(active).to.beFalse() expect(boundary).to.equal(nil)
            end
        }
    }
}
