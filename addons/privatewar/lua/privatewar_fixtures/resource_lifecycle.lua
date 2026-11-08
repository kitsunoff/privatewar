-- Test-only async resource boundary. The caller supplies its GLuaTest-tracked timer, so timeout cleanup cancels it.
---@class PW.TestFixtureResources
local resources = {}

---Yield an owned fixture coroutine after restoring its stores, so queued engine work can drain.
---GLuaTest's public coroutine case flag keeps the original runner and all assertion handling intact.
---@param schedule fun(delay: number, callback: fun())
function resources.Yield(schedule)
    local thread = assert(coroutine.running(), "fixture frame boundary requires a coroutine case")
    schedule(0.05, function()
        local ok, reason = coroutine.resume(thread)
        if not ok then error(reason, 0) end
    end)
    coroutine.yield()
end

---Observe exact owned identities after a real tick; a queued Kick does not yet release an engine player slot.
---This helper never acquires or removes a player and never reads a global player list.
---@param players Player[]
---@param complete fun()
---@param schedule fun(delay: number, callback: fun())
---@param valid? fun(ply: Player): boolean
function resources.Disconnected(players, complete, schedule, valid)
    valid = valid or IsValid
    ---@type Player[]
    local owned = {}
    for index, ply in ipairs(players) do owned[index] = ply end
    local function check()
        for _, ply in ipairs(owned) do
            if valid(ply) then
                schedule(0.05, check)
                return
            end
        end
        complete()
    end
    schedule(0.05, check)
end

return resources
