---@param utc number
---@return integer?
local function weekIndex(utc)
    local lib = PW.Challenges
    return lib and lib.WeekIndex(utc)
end

---@param index integer
---@return string?
local function weekLabel(index)
    local lib = PW.Challenges
    return lib and lib.WeekLabel(index)
end

return {
    groupName = "PW challenges rotation",
    cases = {
        {
            name = "Kind: the challenges declaration registers a fixture without taking the shared namespace",
            func = function()
                local kind = PW.Kinds.Get("challenges")
                expect(kind and kind.Global).to.equal("CHALLENGE")
                assert(kind ~= nil)
                expect(kind.Folder).to.equal("challenges")
                expect(kind.Subscribe).to.equal("never")
                expect(PW.Enable.ConVarName("challenges", "fixture")).to.equal("pw_challenge_fixture_enabled")
                expect(rawget(PW, "Challenges") ~= PW.Registries.challenges).to.beTrue()
                expect(PW.Modules.Get("challenges")).to.exist()
                expect(PW.Registries.challenges).to.exist()

                local engine = PW.Loader._EngineFs
                local ctx = PW.Loader.LoadRoot("fixture", {
                    fs = {
                        find = function(path)
                            if path == "fixture/kinds/*" then return { "challenges.lua" }, {} end
                            if path == "fixture/challenges/*" then return { "fixture.lua", "invalid.lua" }, {} end
                            return {}, {}
                        end,
                        exists = function() return false end,
                        send = function() end,
                        run = function(path)
                            if path == "fixture/kinds/challenges.lua" then
                                return engine.run("privatewar/kinds/challenges.lua")
                            end
                            local def = rawget(_G, "CHALLENGE") --[[@as PW.Challenge]]
                            def.Name, def.Event, def.Target = "Fixture", "kill", 1
                            if path == "fixture/challenges/fixture.lua" then def.Description = "Description" end
                            return true
                        end
                    },
                    log = function() end
                })
                local def = ctx.registries.challenges.Get("fixture")
                expect(def and def.Event).to.equal("kill")
                expect(def and def.Target).to.equal(1)
                expect(ctx.registries.challenges.Get("invalid")).to.beNil()
            end
        },
        {
            name = "Week: index and ISO label for the verified vectors including 2026-W53 and 2027-W01",
            func = function()
                local vectors = {
                    { utc = 1795219200, index = 2967, label = "2026-W47" }, -- 2026-11-21
                    { utc = 1798416000, index = 2973, label = "2026-W53" }, -- 2026-12-28
                    { utc = 1798934400, index = 2973, label = "2026-W53" }, -- 2027-01-03
                    { utc = 1799020800, index = 2974, label = "2027-W01" }, -- 2027-01-04
                    { utc = 1609632000, index = 2660, label = "2020-W53" }, -- 2021-01-03
                    { utc = 1766966400, index = 2921, label = "2026-W01" }, -- 2025-12-29
                    { utc = 1735516800, index = 2869, label = "2025-W01" }, -- 2024-12-30
                    { utc = 0, index = -1, label = "1970-W01" },
                    { utc = 345600, index = 0, label = "1970-W02" }
                }
                for _, row in ipairs(vectors) do
                    expect(weekIndex(row.utc)).to.equal(row.index)
                    expect(weekLabel(row.index)).to.equal(row.label)
                end
            end
        },
        {
            name = "Week: bounds start Monday 00:00 UTC and last seven days",
            func = function()
                local lib = PW.Challenges
                ---@type integer?, integer?
                local startsAt, endsAt
                if lib then startsAt, endsAt = lib.WeekBounds(2967) end
                expect(startsAt).to.equal(1794787200)
                expect(endsAt).to.equal(1795392000)
                assert(startsAt ~= nil and endsAt ~= nil)
                expect(endsAt - startsAt).to.equal(7 * 86400)
                expect(weekIndex(startsAt - 1)).to.equal(2966)
                expect(weekIndex(startsAt)).to.equal(2967)
                expect(weekIndex(endsAt - 1)).to.equal(2967)
                expect(weekIndex(endsAt)).to.equal(2968)
            end
        }
    }
}
