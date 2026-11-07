-- T-6.1 HUD (TASKS.md, "Mandatory test cases" T-6.1; 09-hud.md d.3): element order and visibility by phase, an
-- erroring element is disabled without breaking the others. Pure: plain elements and isolated registries; drawing is a
-- checkpoint.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HudLib
local function hud()
    return must(PW.HUD)
end

---@param elements PW.HudElement[]
---@param phase PW.PhaseName
---@param flags? PW.HudFlags
---@return string[]
local function ids(elements, phase, flags)
    ---@type PW.HudElement[]
    local out = {}
    local count = hud()._Select(elements, phase, flags, out)
    ---@type string[]
    local names = {}
    for i = 1, count do names[i] = must(out[i]).ClassName end
    return names
end

---@param id string
---@param order? number
---@param phases? PW.PhaseName[]
---@return PW.HudElement
local function plain(id, order, phases)
    return { ClassName = id, Order = order, Phases = phases, Draw = function() end }
end

---@param state table<string, any>
---@param kind string
---@return PW.Registry
local function newRegistry(state, kind)
    local registry = PW.Registry.New(kind, { log = function() end, preRegister = function() end })
    local registries = state.registries --[[@as PW.Registry[] ]]
    registries[#registries + 1] = registry
    return registry
end

---Rounds to four decimals so float scale factors compare equal.
---@param value number
---@return number
local function r4(value)
    return math.Round(value, 4)
end

return {
    groupName = "PW HUD",
    beforeEach = function(state)
        state.registries = {}
        state.previousStore = PW._Call
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Call = {
            log = function(message) logged[#logged + 1] = message end,
            failed = setmetatable({}, { __mode = "k" }),
            profile = {}
        }
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Call = state.previousStore
    end,
    cases = {
        {
            name = "The hud kind is declared and the built-in element is registered",
            func = function()
                local registry = must(PW.Registries["hud"])
                expect(registry.Get("match_status")).to.exist()
                expect(PW.Hud).to.equal(registry)
            end
        },
        {
            name = "A hud element without Draw is rejected",
            func = function()
                local ok = PW.Registry.ValidateRequired({ Order = 1 }, { Draw = "function" })
                expect(ok).to.beFalse()
            end
        },
        {
            name = "Element registry order: by Order ascending, then by id; a missing Order is 100",
            func = function()
                local elements = {
                    plain("c", 50), plain("b", 100), plain("z", 10), plain("a", 100), plain("d")
                }
                expect(ids(elements, "LIVE")).to.deepEqual({ "z", "c", "a", "b", "d" })
            end
        },
        {
            name = "Visibility by phase: Phases lists the phases; a missing Phases means every phase",
            func = function()
                local elements = {
                    plain("always", 1), plain("live", 2, { "LIVE" }), plain("pre_post", 3, { "PREMATCH", "POSTMATCH" })
                }
                expect(ids(elements, "LOBBY")).to.deepEqual({ "always" })
                expect(ids(elements, "LIVE")).to.deepEqual({ "always", "live" })
                expect(ids(elements, "POSTMATCH")).to.deepEqual({ "always", "pre_post" })
                expect(ids(elements, "VOTE")).to.deepEqual({ "always" })
            end
        },
        {
            name = "The hidden flag hides everything and the output holds no stale entries",
            func = function()
                local elements = { plain("a"), plain("b") }
                ---@type PW.HudElement[]
                local out = {}
                expect(hud()._Select(elements, "LIVE", nil, out)).to.equal(2)
                expect(hud()._Select(elements, "LIVE", { hidden = true }, out)).to.equal(0)
                expect(out[1]).to.beNil()
                expect(hud()._Select({ plain("only") }, "LIVE", nil, out)).to.equal(1)
                expect(out[2]).to.beNil()
            end
        },
        {
            name = "Scale at the design size is the identity",
            func = function()
                local sx, sy, s = hud()._Scale(1920, 1080)
                expect(sx).to.equal(1)
                expect(sy).to.equal(1)
                expect(s).to.equal(1)
            end
        },
        {
            name = "Scale at 1280x720 is two thirds on every axis",
            func = function()
                local sx, sy, s = hud()._Scale(1280, 720)
                expect(r4(sx)).to.equal(r4(2 / 3))
                expect(r4(sy)).to.equal(r4(2 / 3))
                expect(r4(s)).to.equal(r4(2 / 3))
            end
        },
        {
            name = "Scale on an ultrawide screen stretches x and keeps the uniform scale at the smaller axis",
            func = function()
                local sx, sy, s = hud()._Scale(2560, 1080)
                expect(r4(sx)).to.equal(r4(2560 / 1920))
                expect(sy).to.equal(1)
                expect(s).to.equal(1)
            end
        },
        {
            name = "The paint loop draws visible elements in order and skips those hidden by phase or ShouldDraw",
            func = function(state)
                local registry = newRegistry(state, "test_hud")
                ---@type string[]
                local drawn = {}
                ---@param id string
                ---@param extra table
                local function add(id, extra)
                    extra.Draw = function(self) drawn[#drawn + 1] = self.ClassName end
                    registry.Register(extra, id)
                end
                add("second", { Order = 20 })
                add("first", { Order = 10 })
                add("live_only", { Order = 30, Phases = { "LIVE" } })
                add("vetoed", { Order = 40, ShouldDraw = function() return false end })
                add("shown", { Order = 50, ShouldDraw = function() return true end })
                registry.ResolveAll()
                local loop = hud()._NewState()
                hud()._Paint(loop, registry, "LOBBY")
                expect(drawn).to.deepEqual({ "first", "second", "shown" })
                drawn = {}
                hud()._Paint(loop, registry, "LIVE")
                expect(drawn).to.deepEqual({ "first", "second", "live_only", "shown" })
            end
        },
        {
            name = "An erroring element is disabled without breaking the others",
            func = function(state)
                local registry = newRegistry(state, "test_hud_err")
                ---@type string[]
                local drawn = {}
                registry.Register({ Order = 1, Draw = function() drawn[#drawn + 1] = "before" end }, "before")
                registry.Register({ Order = 2, Draw = function() error("hud boom") end }, "bad")
                registry.Register({ Order = 3, Draw = function() drawn[#drawn + 1] = "after" end }, "after")
                registry.Register({
                    Order = 4,
                    ShouldDraw = function() error("veto boom") end,
                    Draw = function() drawn[#drawn + 1] = "never" end
                }, "bad_veto")
                registry.ResolveAll()
                local loop = hud()._NewState()
                hud()._Paint(loop, registry, "LIVE")
                expect(drawn).to.deepEqual({ "before", "after" })
                expect(must(registry.Get("bad")):IsValid()).to.beFalse()
                expect(must(registry.Get("bad_veto")):IsValid()).to.beFalse()
                expect(#state.logged).to.equal(2)
                drawn = {}
                hud()._Paint(loop, registry, "LIVE")
                expect(drawn).to.deepEqual({ "before", "after" })
                expect(#state.logged).to.equal(2)
                expect(#registry.GetEnabledList()).to.equal(2)
            end
        },
        {
            name = "An element disabled between frames leaves the cached list",
            func = function(state)
                local registry = newRegistry(state, "test_hud_off")
                local drawn = 0
                registry.Register({ Draw = function() drawn = drawn + 1 end }, "one")
                registry.ResolveAll()
                local loop = hud()._NewState()
                hud()._Paint(loop, registry, "LIVE")
                expect(drawn).to.equal(1)
                registry._Disable("one", "test")
                hud()._Paint(loop, registry, "LIVE")
                expect(drawn).to.equal(1)
            end
        }
    }
}
