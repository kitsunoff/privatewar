-- A fixture boundary must return to the engine, not recurse through another zero-delay timer in the same tick.
local resources = include("privatewar_fixtures/resource_lifecycle.lua") --[[@as PW.TestFixtureResources]]

return {
    groupName = "Dev fixture frame boundary",
    cases = {
        {
            name = "A fixture coroutine resumes only through a positive-delay scheduled callback",
            func = function()
                local resumed = false
                ---@type number?
                local delay
                ---@type (fun())?
                local callback
                local thread = coroutine.create(function()
                    resources.Yield(function(seconds, run)
                        delay, callback = seconds, run
                    end)
                    resumed = true
                end)
                local ok, reason = coroutine.resume(thread)
                expect(ok).to.beTrue()
                expect(reason).to.beNil()
                expect(resumed).to.beFalse()
                expect(delay).to.equal(0.05)
                expect(coroutine.status(thread)).to.equal("suspended")
                assert(callback, "expected a scheduled resumption")()
                expect(resumed).to.beTrue()
                expect(coroutine.status(thread)).to.equal("dead")
            end
        },
        {
            name = "The native fixture boundary advances engine TickCount and CurTime",
            coroutine = true,
            func = function()
                local tick, now = engine.TickCount(), CurTime()
                resources.Yield(timer.Simple)
                expect(engine.TickCount() > tick).to.beTrue()
                expect(CurTime() > now).to.beTrue()
            end
        },
        {
            name = "Every synchronous phase fixture case admits a post-cleanup coroutine boundary",
            func = function()
                local group = include("tests/privatewar/core_phases.lua") --[[@as GLuaTest_TestGroup]]
                expect(#group.cases > 1).to.beTrue()
                for _, case in ipairs(group.cases) do
                    expect(case.coroutine).to.beTrue()
                    expect(case.async == true).to.beFalse()
                end
            end
        }
    }
}
