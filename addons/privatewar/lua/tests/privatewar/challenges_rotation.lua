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
        }
    }
}
