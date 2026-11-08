-- Installed-source regressions, never an implementation-registration skip.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "installed Infection runtime is missing")
    return value
end

---@return boolean
local function absent() return not file.Exists("privatewar/types/pw_infection.lua", "LUA") end

return {
    groupName = "PW Infection runtime contracts",
    cases = {
        {
            name = "Infection final presentation: round wins alone rank and tie;"
                .. " infections never break a shared top",
            skip = absent,
            func = function()
                local presentation = must(PW.InfectionPresentation)
                ---@type PW.InfectionResultRow[]
                local input = { { id = 1, name = "Host", wins = 0, infections = 99 },
                    { id = 2, name = "Alpha", wins = 1, infections = 0 },
                    { id = 3, name = "Bravo", wins = 1, infections = 8 } }
                local result = must(presentation.Results(input, 1))
                expect(result.draw).to.beTrue()
                expect(result.winner).to.beNil()
                expect(result.personalWins).to.equal(0)
                expect(result.place).to.equal(3)
                expect({ result.rows[1].id, result.rows[2].id, result.rows[3].id }).to.deepEqual({ 2, 3, 1 })
                expect({ result.rows[1].place, result.rows[2].place, result.rows[3].place }).to.deepEqual({ 1, 1, 3 })
                expect(input[1].place).to.beNil()
                input[3].wins = 2
                result = must(presentation.Results(input, 3))
                expect(result.draw).to.beFalse()
                expect(result.winner).to.equal(3)
                expect(result.personalWins).to.equal(2)
                expect(result.place).to.equal(1)
            end
        },
        {
            name = "Infection preset: separate optional mode uses fixed-total common rounds, 3 default and 1 allowed",
            skip = absent,
            func = function()
                local mode = must(PW.Modes.Get("pw_infection"))
                expect(mode.Base).to.equal("round_base")
                expect(mode.TeamPolicy).to.equal("managed")
                expect(mode.SwapSidesEvery).to.equal(0)
                expect(mode.Settings.rounds.default).to.equal(3)
                expect(mode.Settings.rounds.min).to.equal(1)
                expect(mode.Settings.roundtime.default).to.equal(120)
                local ok, value = PW.Settings._Validate(mode.Settings.rounds, 1)
                expect(ok).to.beTrue()
                expect(value).to.equal(1)
                expect(mode.PW_RespawnDelay(mode)).to.equal(3)
            end
        },
        {
            name = "Infection native fists: adapter requests repeated legal usercmd taps without changing stock damage",
            skip = absent,
            func = function()
                expect(weapons.GetStored("weapon_fists")).to.exist()
                local adapter = must(PW.WeaponAdapters.Get("pw_infection_fists")) --[[@as PW.Adapter]]
                expect(PW.Call(adapter, "Claims", "weapon_fists")).to.beTrue()
                expect(PW.Call(adapter, "Claims", "weapon_crowbar")).to.beFalse()
                local rules = PW.Adapters.Call(adapter, "GetInputRules")
                expect(rules.releaseBetweenShots).to.beTrue()
                expect(adapter.Damage).to.beNil()
            end
        },
        {
            name = "Infection pure roster: duplicate identities invalid seed and nonfinite deadline fail closed",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionRules)
                expect(lib.NewRound({ { id = "a", bot = false, life = 1 },
                    { id = "a", bot = true, life = 2 } }, "a", 120)).to.beNil()
                local roster = { { id = "a", bot = false, life = 1 }, { id = "b", bot = true, life = 1 } }
                expect(lib.NewRound(roster, "unknown", 120)).to.beNil()
                expect(lib.NewRound(roster, "a", math.huge)).to.beNil()
                expect(lib.NewRound(roster, "a", 0 / 0)).to.beNil()
            end
        },
        {
            name = "Infection presentation: round intermission waiting and cleanup tombstone never retain stale state",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                local current = must(lib.Accept(nil, { revision = 4, round = 1, survivors = 1, infected = 1,
                    deadline = 120, role = "waiting", personalWins = 0, active = true, intermission = true }))
                local model = lib.Model(current, 130)
                expect(model.role).to.equal("WAITING FOR NEXT ROUND")
                expect(model.remaining).to.equal(0)
                expect(lib.Accept(current, { revision = 3, active = false })).to.beNil()
                local cleared = must(lib.Accept(current, { revision = 5, active = false }))
                expect(cleared.active).to.beFalse()
                expect(lib.Model(cleared, 131).visible).to.beFalse()
            end
        },
        {
            name = "Infection wire: bounded allowlisted codec round trips and a cleanup tombstone has only two fields",
            skip = absent,
            func = function()
                local lib = must(PW.InfectionPresentation)
                ---@type { value: any, bits: integer?, kind: string }[]
                local queue = {}
                local index = 0
                local function put(kind, value, bits)
                    queue[#queue + 1] = { kind = kind, value = value, bits = bits }
                end
                local function take(kind, bits)
                    index = index + 1
                    local entry = must(queue[index])
                    expect({ entry.kind, entry.bits }).to.deepEqual({ kind, bits })
                    return entry.value
                end
                local writer = { uint = function(v, b) put("uint", v, b) end,
                    bool = function(v) put("bool", v) end, float = function(v) put("float", v) end }
                local reader = { uint = function(b) return take("uint", b) end,
                    bool = function() return take("bool") end, float = function() return take("float") end }
                local snapshot = { revision = 1, active = true, round = 1, survivors = 2, infected = 1,
                    deadline = 120, role = "infected", personalWins = 1, infections = 2, intermission = false }
                expect(lib.Encode(writer, snapshot)).to.beTrue()
                expect(#queue).to.equal(10)
                expect(lib.Accept(nil, lib.Decode(reader))).to.deepEqual(snapshot)
                queue, index = {}, 0
                expect(lib.Encode(writer, { revision = 2, active = false })).to.beTrue()
                expect(#queue).to.equal(2)
                expect(must(lib.Accept(nil, lib.Decode(reader))).active).to.beFalse()
                queue, index = {}, 0
                expect(lib.Encode(writer, { revision = 3, survivors = math.huge })).to.beFalse()
                expect(#queue).to.equal(0)
            end
        },
        {
            name = "Infection behavior: real pursuit releases weapon drive sprint target and goal when it ends",
            skip = absent,
            func = function()
                local behavior = must(must(PW.BotBehaviors).Get("pw_infection_pursuit")) --[[@as PW.BotBehavior]]
                local role, ai = must(PW.Infection), must(PW.InfectionAI)
                local enemy = { IsValid = function() return true end,
                    GetPos = function() error("pursuit must use the observed contact") end } --[[@as Entity]]
                local bot = { GetPos = function() return Vector() end,
                    GetWalkSpeed = function() return 230 end } --[[@as Player]]
                local intent = { buttons = 0 } --[[@as PW.BotIntent]]
                local contact = { ent = enemy, pos = Vector(600, 0, 0), vel = Vector(), visible = true,
                    time = 0, source = "sight" } --[[@as PW.BotContact]]
                ---@type Entity?
                local selected
                ---@type Vector?
                local goal
                local cleared = 0
                local ctx = { bot = bot, board = { bot = bot }, now = 0, memory = {}, _api = {},
                    contacts = { contact }, Intent = function() return intent end,
                    GoalStatus = function() return nil end, Contact = function() return contact end,
                    SearchPlan = function() return nil end,
                    SetTarget = function(_, target) selected = target end,
                    SetGoal = function(_, point) goal = point return true end,
                    ClearGoal = function() goal, cleared = nil, cleared + 1 end } --[[@as PW.BotBrainCtx]]
                stub(role, "Role").with(function() return "infected" end)
                expect(PW.Call(behavior, "Rank", bot, ctx)).to.equal("combat")
                PW.Call(behavior, "Update", bot, ctx)
                expect(goal).to.equal(contact.pos)
                expect(intent.weapon).to.equal("weapon_fists")
                expect(intent.sprint).to.beTrue()
                expect(selected).to.beNil()
                contact.pos = Vector(60, 0, 0)
                PW.Call(behavior, "Update", bot, ctx)
                expect(selected).to.equal(enemy)
                expect(intent.drive).to.equal(Vector(230, 0, 0))
                expect(intent.sprint).to.beFalse()
                expect(ai.Contact(ctx.contacts)).to.equal(contact)
                PW.Call(behavior, "OnEnd", bot, ctx)
                expect(intent.weapon).to.beNil()
                expect(intent.drive).to.beNil()
                expect(intent.sprint).to.beNil()
                expect(goal).to.beNil()
                expect(selected).to.beNil()
                expect(cleared >= 2).to.beTrue()
            end
        },
        {
            name = "Infection pursuit: uses visible contacts, loses admission outside role, no hidden target positions",
            skip = absent,
            func = function()
                local ai = must(PW.InfectionAI)
                local enemy = { IsValid = function() return true end,
                    GetPos = function() error("hidden live coordinates are forbidden") end } --[[@as Entity]]
                local remembered = { ent = enemy, pos = Vector(500, 0, 0), vel = Vector(), visible = false,
                    time = 0, source = "sight" }
                expect(ai.Contact({ remembered })).to.beNil()
                remembered.visible = true
                expect(ai.Contact({ remembered })).to.equal(remembered)
                local chase = ai.Plan(Vector(), remembered, 230)
                expect(chase.sprint).to.beTrue()
                expect(chase.point).to.equal(remembered.pos)
                remembered.pos = Vector(60, 0, 0)
                local close = ai.Plan(Vector(), remembered, 230)
                expect(close.sprint).to.beFalse()
                expect(close.forward).to.equal(230)
                expect(close.target).to.equal(enemy)
            end
        }
    }
}
