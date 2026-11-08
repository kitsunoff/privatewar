-- Prepared playtest-revision contracts. Execute the registered addon Action through public ctx boundaries.
-- No forced aim, private board writes, difficulty override or enemy world-position reads.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection survivor escape is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

---@class PW.InfectionEscapeFixture
---@field bot Player
---@field enemy Entity
---@field contact PW.BotContact
---@field ctx PW.BotBrainCtx
---@field intent PW.BotIntent
---@field facts PW.BotCombatFacts
---@field selected? Entity
---@field goal? Vector
---@field probes integer
---@field blocked boolean
---@field cleared integer

---@return PW.InfectionEscapeFixture
---@param expect fun(value: any): any
local function fixture(expect)
    local enemy = { IsValid = function() return true end,
        GetPos = function() error("escape must use the perceived snapshot, never live enemy coordinates") end }
        --[[@as Entity]]
    local bot = { IsValid = function() return true end, IsPlayer = function() return true end,
        Alive = function() return true end, GetPos = function() return Vector() end,
        GetWalkSpeed = function() return 200 end, GetRunSpeed = function() return 400 end,
        GetVelocity = function() return Vector() end,
        SetPos = function() error("no measured teleport") end,
        SetEyeAngles = function() error("no snap aim") end } --[[@as Player]]
    local contact = { ent = enemy, pos = Vector(200, 0, 0), vel = Vector(), visible = true,
        time = 10, source = "sight" } --[[@as PW.BotContact]]
    local facts = { at = 10, pos = Vector(), health = 100, maxHealth = 100, clip = 20, capacity = 30,
        reserve = 60, reloading = false, lethal = 0, active = "weapon_smg1", melee = "weapon_crowbar",
        runSpeed = 400, profile = must(PW.BotTactics).DefaultProfile } --[[@as PW.BotCombatFacts]]
    ---@type PW.InfectionEscapeFixture
    local f
    f = { bot = bot, enemy = enemy, contact = contact, intent = { buttons = 0 }, facts = facts,
        probes = 0, blocked = false, cleared = 0,
        ctx = { bot = bot, board = { bot = bot, tactics = facts }, now = 10, state = {}, memory = {},
        contacts = { contact }, Intent = function() return f.intent end,
        SetTarget = function(_, target) f.selected = target end,
        SetGoal = function(_, point, radius, priority)
            expect(radius > 0).to.beTrue()
            expect(priority).to.equal("tactical")
            f.goal = point
            return not f.blocked
        end,
        ClearGoal = function() f.goal, f.cleared = nil, f.cleared + 1 end,
        GoalStatus = function() return f.blocked and "unreachable" or nil end,
        Contact = function() return contact end, SearchPlan = function() return nil end,
        _api = { walkable = function(point)
            f.probes = f.probes + 1
            expect(point:Distance(Vector()) <= 600).to.beTrue()
            return not f.blocked
        end } } }
    return f
end

---@return PW.BotBehavior
local function behavior()
    return must(must(PW.BotBehaviors).Get("pw_infection_escape")) --[[@as PW.BotBehavior]]
end

---@param f PW.InfectionEscapeFixture
local function update(f)
    local action = behavior()
    if f.ctx.running == nil then
        f.ctx.running = "pw_infection_escape"
        PW.Call(action, "OnStart", f.bot, f.ctx)
    end
    PW.Call(action, "Update", f.bot, f.ctx)
end

return {
    groupName = "PW Infection survivor distance",
    cases = {
        {
            name = "Infection survivor: close perceived infected selects escape not ordinary melee even with a gun",
            skip = absent,
            func = function()
                local f = fixture(expect)
                stub(must(PW.Infection), "Role").with(function() return "survivor" end)
                expect(PW.Call(behavior(), "Rank", f.bot, f.ctx)).to.equal("survival")
                update(f)
                expect(f.goal).to.exist()
                expect(must(f.goal):Distance(f.contact.pos) > f.facts.pos:Distance(f.contact.pos)).to.beTrue()
                expect(f.intent.weapon == "weapon_crowbar" or f.intent.weapon == "weapon_fists").to.beFalse()
                expect(bit.band(f.intent.buttons, IN_ATTACK)).to.equal(0) -- only the normal aim layer may fire
                expect(f.probes > 0 and f.probes <= 8).to.beTrue()
            end
        },
        {
            name = "Infection survivor: legal walking retreat retains aim target instead of blindly fleeing",
            skip = absent,
            func = function()
                local f = fixture(expect)
                stub(must(PW.Infection), "Role").with(function() return "survivor" end)
                update(f)
                expect(f.goal).to.exist()
                expect(f.selected).to.equal(f.enemy)
                expect(f.intent.sprint == true).to.beFalse()
                expect(bit.band(f.intent.buttons, IN_ATTACK)).to.equal(0)
                expect(f.intent.view).to.beNil() -- spring aim, not Action-owned view
                f.contact.pos = Vector(800, 0, 0)
                f.ctx.now = 11
                update(f)
                expect(f.goal).to.beNil()
                expect(f.selected).to.equal(f.enemy)
                expect(f.intent.sprint == true).to.beFalse()
            end
        },
        {
            name = "Infection survivor: dry or reloading weapon still escapes rather than closing for melee",
            skip = absent,
            func = function()
                local f = fixture(expect)
                stub(must(PW.Infection), "Role").with(function() return "survivor" end)
                f.facts.clip, f.facts.reserve, f.facts.reloading = 0, 0, true
                f.contact.pos = Vector(80, 0, 0)
                update(f)
                expect(f.goal).to.exist()
                expect(must(f.goal):Distance(f.contact.pos) > f.contact.pos:Length()).to.beTrue()
                expect(f.intent.weapon == "weapon_crowbar").to.beFalse()
                expect(bit.band(f.intent.buttons, IN_ATTACK)).to.equal(0)
            end
        },
        {
            name = "Infection survivor: blocked local navigation is bounded and never invents a forward melee charge",
            skip = absent,
            func = function()
                local f = fixture(expect)
                stub(must(PW.Infection), "Role").with(function() return "survivor" end)
                f.blocked = true
                update(f)
                expect(f.probes <= 8).to.beTrue()
                expect(f.goal).to.beNil()
                expect(f.intent.drive == nil or f.intent.drive.x <= 0).to.beTrue()
                expect(f.selected).to.equal(f.enemy) -- a blocked retreat does not suppress legal gunfire
                expect(f.intent.weapon == "weapon_crowbar").to.beFalse()
                expect(f.intent.sprint == true).to.beFalse()
            end
        },
        {
            name = "Infection survivor: hidden contact and infected role cannot admit escape or read enemy world state",
            skip = absent,
            func = function()
                local f, role = fixture(expect), "survivor"
                stub(must(PW.Infection), "Role").with(function() return role end)
                f.contact.visible = false
                expect(PW.Call(behavior(), "Rank", f.bot, f.ctx)).to.beFalse()
                f.contact.visible, role = true, "infected"
                expect(PW.Call(behavior(), "Rank", f.bot, f.ctx)).to.beFalse()
                local pursuit = must(must(PW.BotBehaviors).Get("pw_infection_pursuit"))
                expect(PW.Call(pursuit, "Rank", f.bot, f.ctx)).to.equal("combat")
            end
        },
        {
            name = "Infection survivor: Action end and suspension release target goal drive sprint and weapon",
            skip = absent,
            func = function()
                local f = fixture(expect)
                stub(must(PW.Infection), "Role").with(function() return "survivor" end)
                update(f)
                PW.Call(behavior(), "OnSuspend", f.bot, f.ctx)
                expect(f.goal).to.beNil()
                expect(f.selected).to.beNil()
                expect(f.intent.drive).to.beNil()
                expect(f.intent.sprint).to.beNil()
                expect(f.intent.weapon).to.beNil()
                update(f)
                PW.Call(behavior(), "OnEnd", f.bot, f.ctx)
                expect(f.goal).to.beNil()
                expect(f.selected).to.beNil()
                expect(f.intent.drive).to.beNil()
                expect(f.intent.sprint).to.beNil()
                expect(f.intent.weapon).to.beNil()
            end
        }
    }
}
