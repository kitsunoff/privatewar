-- Deterministic tests of the native fixture's tracked async disconnect boundary. No players or timers allocated.
---@return { Disconnected: fun(players: Player[], complete: fun(), schedule: fun(delay: number, callback: fun()),
---valid?: fun(ply: Player): boolean) }
local function resources()
    return include("privatewar_fixtures/resource_lifecycle.lua")
end

---@return (fun())[]
---@return fun(delay: number, callback: fun())
local function scheduler()
    ---@type (fun())[]
    local callbacks = {}
    return callbacks, function(delay, callback)
        assert(delay > 0, "a disconnect boundary must yield beyond the current engine tick")
        callbacks[#callbacks + 1] = callback
    end
end

---@param callbacks (fun())[]
local function step(callbacks)
    assert(table.remove(callbacks, 1), "expected a scheduled disconnect observation")()
end

return {
    groupName = "PW owned fixture disconnect boundary",
    cases = {
        {
            name = "Disconnect boundary: even an empty owned set completes asynchronously exactly once",
            func = function()
                local callbacks, schedule = scheduler()
                local completions = 0
                resources().Disconnected({}, function() completions = completions + 1 end, schedule)
                expect(completions).to.equal(0)
                expect(#callbacks).to.equal(1)
                step(callbacks)
                expect(completions).to.equal(1)
                expect(#callbacks).to.equal(0)
            end
        },
        {
            name = "Disconnect boundary: a requested Kick is not release until every exact owned entity is invalid",
            func = function()
                local callbacks, schedule = scheduler()
                local first, second = {} --[[@as Player]], {} --[[@as Player]]
                local live = { [first] = true, [second] = true }
                local completions = 0
                resources().Disconnected({ first, second }, function() completions = completions + 1 end,
                    schedule, function(ply) return live[ply] == true end)
                step(callbacks)
                expect(completions).to.equal(0)
                live[first] = false
                step(callbacks)
                expect(completions).to.equal(0)
                live[second] = false
                step(callbacks)
                expect(completions).to.equal(1)
                expect(#callbacks).to.equal(0)
            end
        },
        {
            name = "Disconnect boundary: later mutation cannot replace owned identity with a foreign player",
            func = function()
                local callbacks, schedule = scheduler()
                local owned, foreign = {} --[[@as Player]], {} --[[@as Player]]
                local list = { owned }
                local completed = false
                resources().Disconnected(list, function() completed = true end, schedule,
                    function(ply) return ply == foreign end)
                list[1] = foreign
                step(callbacks)
                expect(completed).to.beTrue()
                expect(#callbacks).to.equal(0)
            end
        }
    }
}
