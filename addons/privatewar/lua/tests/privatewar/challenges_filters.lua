---@return table<string, any>
local function challenges()
    return rawget(PW, "Challenges") or {}
end

---@param fields table<string, any>
---@param custom? table<string, PW.ChallengeEventType>
---@param id? string
---@return PW.ChallengeTemplate?, string?
local function compile(fields, custom, id)
    local fn = challenges()._Compile
    if fn == nil then return nil end
    fields.Name, fields.Description = fields.Name or "Test", fields.Description or "Test challenge"
    return fn(id or "filter_test", fields, custom)
end

local customType = "fixture:survive"
---@type table<string, PW.ChallengeEventType>
local customTypes = { [customType] = { fields = { role = "string", alive = "boolean", time = "number" } } }

---@param eventType string
---@param filters table<string, any>
---@param event table<string, any>
---@return boolean?
local function matches(eventType, filters, event)
    local template = compile({ Event = eventType, Target = 1, Filters = filters }, customTypes)
    if template == nil then return nil end
    event.type = event.type or eventType
    return template.objectives[1].bind({})(event)
end

local invalidTemplates = {
    name = "Templates: unknown filter keys, bad targets, missing tiers and both Objectives and Event are rejected",
    func = function()
        local valid = compile({ Event = "kill", Target = 4 })
        expect(valid and valid.objectives[1].targets.easy).to.equal(4)
        assert(valid ~= nil)
        expect(valid.objectives[1].targets.medium).to.equal(4)
        expect(valid.objectives[1].targets.hard).to.equal(4)
        expect(valid.objectives[1].count).to.equal(1)
        expect(valid.objectives[1].scope).to.equal("cumulative")
        for _, invalid in ipairs({
            { Event = "kill", Target = 1, Filters = { headShot = true } },
            { Event = "kill", Target = 1, Filters = { won = false } },
            { Event = "kill", Target = 1, Filters = { ads = "no" } },
            { Event = "kill", Target = 1, Filters = { distanceMax = "close" } },
            { Event = "kill", Target = 0 },
            { Event = "kill", Target = 1.5 },
            { Event = "kill", Target = math.huge },
            { Event = "kill", Target = { easy = 1, medium = 2 } },
            { Event = "kill", Target = 1, Tiers = {} },
            { Event = "kill", Target = 1, Tiers = { "expert" } },
            { Event = "kill", Target = 1, Weight = 0 },
            { Event = "kill", Target = 1, Within = { count = 1, seconds = 5 } },
            { Event = "kill", Target = 1, Within = { count = 2, seconds = 0 } },
            { Event = "kill", Target = 1, ResetOn = { { Event = "unknown" } } },
            { Event = { "kill", "unknown" }, Target = 1 },
            { Event = "kill", Objectives = { { Event = "kill", Target = 1 } } },
            { Target = 1, Objectives = { { Event = "kill", Target = 1 } } },
            { Objectives = {} }
        }) do
            local got, reason = compile(invalid)
            expect(got).to.beNil()
            expect(type(reason)).to.equal("string")
        end
        expect(compile({ Event = "kill", Target = 1 }, nil, "bonus")).to.beNil()
        local predicate = function() error("compiling must not run custom predicates") end
        local def = compile({ Mode = "any", Tiers = { "hard" }, Objectives = {
            { Event = "kill", Target = { hard = 3 }, Scope = "life", Within = { count = 2, seconds = 5 },
                ResetOn = { { Event = "death", Filters = { suicide = true } } }, Filter = predicate },
            { Event = "time_played", Count = "value", Target = { hard = 60 } }
        } })
        assert(def ~= nil)
        expect(def.mode).to.equal("any")
        expect(def.objectives[1].scope).to.equal("life")
        local within = def.objectives[1].within
        expect(within and within.count).to.equal(2)
        local reset = def.objectives[1].reset[1].bind({})
        expect(reset({ type = "death", suicide = true })).to.beTrue()
        expect(reset({ type = "death", suicide = false })).to.beFalse()
        expect(def.objectives[2].count).to.equal("value")
    end
}

return {
    groupName = "PW challenges filters",
    cases = {
        {
            name = "Filters: mode, modeBase and playlist match scalars, sets, lists and the playlist true/false forms",
            func = function()
                local event = { mode = "snd", modeBase = { "round_base", "tdm" }, playlist = "ranked" }
                expect(matches("kill", { mode = "snd", modeBase = "tdm", playlist = "ranked" }, event)).to.beTrue()
                expect(matches("kill", { mode = { snd = true, kc = false }, modeBase = { dom = true, tdm = true },
                    playlist = { ranked = true, mixed = true } }, event)).to.beTrue()
                expect(matches("kill", { mode = { "dom", "snd" }, modeBase = { "ffa", "round_base" },
                    playlist = { "mixed", "ranked" } }, event)).to.beTrue()
                expect(matches("kill", { mode = { snd = false } }, event)).to.beFalse()
                expect(matches("kill", { modeBase = { "dom", "ffa" } }, event)).to.beFalse()
                expect(matches("kill", { playlist = { "mixed" } }, event)).to.beFalse()
                expect(matches("kill", { playlist = true }, event)).to.beTrue()
                expect(matches("kill", { playlist = false }, event)).to.beFalse()
                expect(matches("kill", { playlist = true }, { playlist = "" })).to.beFalse()
                expect(matches("kill", { playlist = false }, { playlist = "" })).to.beTrue()
            end
        },
        {
            name = "Filters: weapon, category, weaponKind and attachment",
            func = function()
                local event = { weapon = "ak", weaponCategory = "ar", weaponKind = "gun",
                    attachments = { scope = true, laser = false } }
                expect(matches("kill", { weapon = "ak", category = { "ar", "smg" }, weaponKind = { gun = true },
                    attachment = "scope" }, event)).to.beTrue()
                expect(matches("kill", { attachment = { "laser", "scope" } }, event)).to.beTrue()
                expect(matches("kill", { attachment = { laser = true, scope = false } }, event)).to.beFalse()
                expect(matches("kill", { weapon = "m4" }, event)).to.beFalse()
                expect(matches("kill", { category = "pistol" }, event)).to.beFalse()
                expect(matches("kill", { weaponKind = "melee" }, event)).to.beFalse()
                expect(matches("kill", { attachment = "laser" }, event)).to.beFalse()
            end
        },
        {
            name = "Filters: headshot, ads, crouch, airborne, explosive, streakKill and streak",
            func = function()
                ---@type table<string, boolean|string>
                local filters = { headshot = true, ads = false, crouch = false, airborne = true, explosive = true,
                    streakKill = true, streak = "missile", victimBot = true }
                ---@type table<string, boolean|string>
                local event = table.Copy(filters)
                expect(matches("kill", filters, event)).to.beTrue()
                for field, value in pairs(filters) do
                    ---@type table<string, boolean|string>
                    local mismatch = table.Copy(event)
                    mismatch[field] = type(value) == "boolean" and not value
                    if field == "streak" then mismatch[field] = "uav" end
                    expect(matches("kill", filters, mismatch)).to.beFalse()
                end
                expect(matches("streak_earned", { streak = "uav" }, { streak = "uav" })).to.beTrue()
                expect(matches("streak_used", { streak = "uav" }, { streak = "missile" })).to.beFalse()
            end
        },
        {
            name = "Filters: distanceMin and distanceMax are inclusive and in metres",
            func = function()
                local filters = { distanceMin = 30, distanceMax = 50 }
                expect(matches("kill", filters, { distance = 30 })).to.beTrue()
                expect(matches("kill", filters, { distance = 50 })).to.beTrue()
                expect(matches("kill", filters, { distance = 29.999 })).to.beFalse()
                expect(matches("kill", filters, { distance = 50.001 })).to.beFalse()
                expect(matches("kill", filters, { distance = 2000 })).to.beFalse() -- raw Source units aren't meters
                expect(matches("kill", filters, { distance = 2000 * 0.01905 })).to.beTrue()
            end
        },
        {
            name = "Filters: lifeKillsMin, aliveTimeMax and valueMin",
            func = function()
                local filters = { lifeKillsMin = 5, aliveTimeMax = 10.5, valueMin = 20 }
                expect(matches("kill", filters, { lifeKills = 5, aliveTime = 10.5, value = 20 })).to.beTrue()
                expect(matches("kill", filters, { lifeKills = 4, aliveTime = 10, value = 20 })).to.beFalse()
                expect(matches("kill", filters, { lifeKills = 5, aliveTime = 10.6, value = 20 })).to.beFalse()
                expect(matches("kill", filters, { lifeKills = 5, aliveTime = 10, value = 19 })).to.beFalse()
                expect(matches("time_played", { valueMin = 60 }, { value = 60 })).to.beTrue()
            end
        },
        {
            name = "Filters: event, medal and objective",
            func = function()
                expect(matches("score", { event = "kill" }, { scoreEvent = "kill" })).to.beTrue()
                expect(matches("score", { event = "kill" }, { scoreEvent = "assist" })).to.beFalse()
                expect(matches("medal", { medal = { "double_kill", "triple_kill" } },
                    { medal = "triple_kill" })).to.beTrue()
                expect(matches("medal", { medal = { "double_kill", "triple_kill" } },
                    { medal = "revenge" })).to.beFalse()
                local filters = { objective = { confirm = true, deny = true } }
                expect(matches("objective", filters, { objective = "deny" })).to.beTrue()
                expect(matches("objective", filters, { objective = "capture" })).to.beFalse()
                expect(matches("objective", filters, { type = "score", objective = "deny" })).to.beFalse()
            end
        },
        {
            name = "Filters: won, draw and placementMax on match_end and round_end",
            func = function()
                local filters = { won = true, draw = false, placementMax = 2 }
                expect(matches("match_end", filters, { won = true, draw = false, placement = 2 })).to.beTrue()
                expect(matches("match_end", filters, { won = true, draw = false, placement = 3 })).to.beFalse()
                expect(matches("match_end", filters, { won = false, draw = false, placement = 1 })).to.beFalse()
                expect(matches("round_end", { won = false, draw = true }, { won = false, draw = true })).to.beTrue()
                expect(matches("round_end", { won = false, draw = true }, { won = false, draw = false })).to.beFalse()
                expect(compile({ Event = "round_end", Target = 1, Filters = { placementMax = 2 } })).to.beNil()
                local multi = compile({ Event = { "match_end", "round_end" }, Target = 1, Filters = { won = true } })
                assert(multi ~= nil)
                local predicate = multi.objectives[1].bind({})
                expect(predicate({ type = "match_end", won = true })).to.beTrue()
                expect(predicate({ type = "round_end", won = true })).to.beTrue()
                expect(predicate({ type = "kill", won = true })).to.beFalse()
            end
        },
        {
            name = "Filters: suicide on death and data on custom events",
            func = function()
                expect(matches("death", { suicide = false }, { suicide = false })).to.beTrue()
                expect(matches("death", { suicide = false }, { suicide = true })).to.beFalse()
                local filters = { data = { role = { human = true, infected = true }, alive = false, time = { 9, 12 } } }
                local event = { data = { role = "human", alive = false, time = 12 } }
                expect(matches(customType, filters, event)).to.beTrue()
                expect(matches(customType, filters, { data = { role = "human", alive = false } })).to.beFalse()
                event.data.role = "spectator"
                expect(matches(customType, filters, event)).to.beFalse()
                event.data.role, event.data.alive = "human", true
                expect(matches(customType, filters, event)).to.beFalse()
                expect(matches(customType, { data = { time = { [1] = true } } }, { data = { time = 1 } })).to.beTrue()
                expect(matches(customType, { data = { time = { [1] = true } } }, { data = { time = 2 } })).to.beFalse()
                expect(compile({ Event = "kill", Target = 1, Filters = filters }, customTypes)).to.beNil()
                expect(compile({ Event = customType, Target = 1, Filters = filters })).to.beNil()
            end
        },
        {
            name = "Filters: an absent event field never matches",
            func = function()
                for _, filters in ipairs({ { ads = false }, { headshot = false }, { distanceMax = 50 },
                    { mode = "tdm" }, { modeBase = "tdm" }, { playlist = false }, { playlist = true },
                    { attachment = "scope" }, { valueMin = 0 }, { weapon = "ak" }, { streak = "uav" } }) do
                    expect(matches("kill", filters, {})).to.beFalse()
                end
                expect(matches(customType, { data = { alive = false } }, {})).to.beFalse()
                expect(matches(customType, { data = { alive = false } }, { data = {} })).to.beFalse()
            end
        },
        invalidTemplates,
        {
            name = "Templates: reward arrays and strings must fit the wire without truncation",
            func = function()
                ---@type PW.ChallengeRewardItem[]
                local items = {}
                for i = 1, 7 do items[i] = { kind = "cards", id = "g" .. i } end
                local definition = { Event = "kill", Target = 1, Rewards = { items = items } }
                expect(compile(definition) ~= nil).to.beTrue()
                items[8] = { kind = "cards", id = "extra" }
                expect(compile(definition)).to.beNil()
                items[8] = nil
                items[7] = { kind = "cards", id = string.rep("x", 65) }
                expect(compile(definition)).to.beNil()
                items[7] = { kind = string.rep("x", 65), id = "card" }
                expect(compile(definition)).to.beNil()
                items[7] = { kind = "camos", id = "gold", weapon = string.rep("x", 65) }
                expect(compile(definition)).to.beNil()
                items[7] = { kind = "cards", id = "bad\0id" }
                expect(compile(definition)).to.beNil()
            end
        },
        {
            name = "Templates: parameter key counts and strings must fit the wire without truncation",
            func = function()
                ---@type table<string, PW.ChallengeParam>
                local params = {}
                for i = 1, 7 do params["p" .. i] = { values = { "v" } } end
                local definition = { Event = "kill", Target = 1, Params = params }
                expect(compile(definition) ~= nil).to.beTrue()
                params.extra = { values = { "v" } }
                expect(compile(definition)).to.beNil()
                definition.Params = { [string.rep("k", 65)] = { values = { "v" } } }
                expect(compile(definition)).to.beNil()
                definition.Params = { ["bad\0key"] = { values = { "v" } } }
                expect(compile(definition)).to.beNil()
            end
        },
        {
            name = "Templates: param placeholders are substituted in filters and text",
            func = function()
                local filters = { category = "{param.category}", weapon = { "{param.weapon}", "training" } }
                local description = "{target1}/{target2} with {param.category} and {param.weapon}; {param.unknown}"
                local template = compile({ Name = "{target} kills", Description = description, Tiers = { "hard" },
                    Params = { category = { source = "categories", names = { ar = "Assault % Rifle" } },
                        weapon = { source = "weapons" } }, Objectives = {
                        { Event = "kill", Target = { hard = 10 }, Filters = filters },
                        { Event = "kill", Target = 20 }
                    } })
                local params = { category = "ar", weapon = "ak" }
                local predicate = template and template.objectives[1].bind(params)
                local fact = { type = "kill", weaponCategory = "ar", weapon = "ak" }
                expect(predicate and predicate(fact)).to.beTrue()
                assert(template ~= nil and predicate ~= nil)
                fact.weapon = "training"
                expect(predicate(fact)).to.beTrue()
                fact.weaponCategory, fact.weapon = "smg", "ak"
                expect(predicate(fact)).to.beFalse()
                fact.weaponCategory, fact.weapon = "ar", "m4"
                expect(predicate(fact)).to.beFalse()
                local second = template.objectives[1].bind({ category = "smg", weapon = "mp5" })
                fact.weaponCategory, fact.weapon = "smg", "mp5"
                expect(second(fact)).to.beTrue()
                expect(predicate(fact)).to.beFalse()
                expect(filters.category).to.equal("{param.category}")
                expect(filters.weapon[1]).to.equal("{param.weapon}")
                local lib = PW.Challenges
                assert(lib ~= nil)
                local format = lib._FormatText
                local context = { targets = { 10, 20 }, params = params }
                expect(format(template.definition.Name, template, context)).to.equal("10 kills")
                expect(format("{param.weapon}", template, context)).to.equal("ak")
                context.names = { weapon = { ak = "AK" } }
                expect(format(template.definition.Description, template, context))
                    .to.equal("10/20 with Assault % Rifle and AK; {param.unknown}")
            end
        }
    }
}
