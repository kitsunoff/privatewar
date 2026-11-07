-- T-1.6 hook dispatch (TASKS.md, "Mandatory test cases"; 01-extensibility.md d.9, d.18).
-- Every case uses its own PW_Test* hook names, removes its listeners, and restores PW.ActiveMode,
-- the hook store (capturing logger) and the pw_debug ConVar.

local listenerId = "PW_Test_Hooks"
local testHooks = { "PW_TestQuestion", "PW_TestNotification", "PW_TestOrder", "PW_TestSwitch" }

---@return ConVar
local function debugVar()
    local var = GetConVar("pw_debug")
    assert(var ~= nil, "pw_debug ConVar is missing")
    return var
end

return {
    groupName = "PW hook dispatch",
    beforeEach = function(state)
        state.previousMode = PW.ActiveMode
        state.previousStore = PW._Hooks
        state.previousDebug = debugVar():GetString()
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Hooks = { log = function(message) logged[#logged + 1] = message end }
    end,
    afterEach = function(state)
        for _, name in ipairs(testHooks) do hook.Remove(name, listenerId) end
        PW.ActiveMode = state.previousMode
        PW._Hooks = state.previousStore
        debugVar():SetString(state.previousDebug)
    end,
    cases = {
        {
            name = "The active mode's method runs after the listeners",
            func = function()
                ---@type string[]
                local order = {}
                hook.Add("PW_TestOrder", listenerId, function(value)
                    order[#order + 1] = "listener:" .. value
                end)
                PW.ActiveMode = {
                    PW_TestOrder = function(_, value) order[#order + 1] = "mode:" .. value end
                }
                PW.Notify("PW_TestOrder", "x")
                expect(#order).to.equal(2)
                expect(order[1]).to.equal("listener:x")
                expect(order[2]).to.equal("mode:x")
            end
        },
        {
            name = "A listener's non-nil answer wins over the mode for a question hook",
            func = function()
                local modeCalls = 0
                PW.ActiveMode = {
                    PW_TestQuestion = function()
                        modeCalls = modeCalls + 1
                        return "mode"
                    end
                }
                expect(PW.Ask("PW_TestQuestion")).to.equal("mode")
                expect(modeCalls).to.equal(1)

                hook.Add("PW_TestQuestion", listenerId, function() return "listener" end)
                expect(PW.Ask("PW_TestQuestion")).to.equal("listener")
                expect(modeCalls).to.equal(1)
            end
        },
        {
            name = "A listener's nil answer falls through to the mode's default",
            func = function()
                hook.Add("PW_TestQuestion", listenerId, function() end)
                PW.ActiveMode = { PW_TestQuestion = function(_, a, b) return a + b end }
                expect(PW.Ask("PW_TestQuestion", 2, 3)).to.equal(5)
            end
        },
        {
            name = "A question with no active mode and no listener answers nil",
            func = function()
                PW.ActiveMode = nil
                expect(PW.Ask("PW_TestQuestion")).to.beNil()
            end
        },
        {
            name = "In debug mode a notification listener returning a value logs one warning naming the hook",
            func = function(state)
                debugVar():SetBool(true)
                hook.Add("PW_TestNotification", listenerId, function() return true end)
                PW.ActiveMode = nil
                PW.Notify("PW_TestNotification")
                expect(#state.logged).to.equal(1)
                expect(string.find(state.logged[1] or "", "PW_TestNotification", 1, true)).to.exist()
            end
        },
        {
            name = "Without debug mode a notification listener returning a value logs nothing",
            func = function(state)
                debugVar():SetBool(false)
                hook.Add("PW_TestNotification", listenerId, function() return true end)
                PW.Notify("PW_TestNotification")
                expect(#state.logged).to.equal(0)
            end
        },
        {
            name = "In debug mode a notification whose listeners return nothing logs nothing",
            func = function(state)
                debugVar():SetBool(true)
                local calls = 0
                hook.Add("PW_TestNotification", listenerId, function() calls = calls + 1 end)
                PW.Notify("PW_TestNotification")
                expect(calls).to.equal(1)
                expect(#state.logged).to.equal(0)
            end
        },
        {
            name = "After switching modes the old mode's methods are no longer called",
            func = function()
                ---@type string[]
                local calls = {}
                local old = { PW_TestSwitch = function() calls[#calls + 1] = "old" end }
                local new = { PW_TestSwitch = function() calls[#calls + 1] = "new" end }
                PW.ActiveMode = old
                PW.Notify("PW_TestSwitch")
                PW.ActiveMode = new
                PW.Notify("PW_TestSwitch")
                PW.Notify("PW_TestSwitch")
                expect(#calls).to.equal(3)
                expect(calls[1]).to.equal("old")
                expect(calls[2]).to.equal("new")
                expect(calls[3]).to.equal("new")
            end
        },
        {
            name = "The mode's method receives the mode as self",
            func = function()
                local mode = {}
                local seenSelf = nil
                mode.PW_TestQuestion = function(self) seenSelf = self end
                PW.ActiveMode = mode
                PW.Ask("PW_TestQuestion")
                expect(seenSelf).to.equal(mode)
            end
        }
    }
}
