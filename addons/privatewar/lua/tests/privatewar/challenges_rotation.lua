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

---@param id string
---@param fields table<string, any>
---@return PW.ChallengeTemplate?
local function compile(id, fields)
    local lib = PW.Challenges
    fields.Name, fields.Description, fields.Event = id, "Test challenge", "kill"
    if fields.Target == nil then fields.Target = 10 end
    return lib and lib._Compile(id, fields)
end

---@param id string
---@param fields? table<string, any>
---@param values? table<string, string[]>
---@return PW.ChallengeCandidate
local function candidate(id, fields, values)
    local template = compile(id, fields or {})
    assert(template ~= nil, "test template rejected: " .. id)
    return { template = template, values = values }
end

---@return PW.ChallengeCandidate[]
local function pool()
    ---@type PW.ChallengeCandidate[]
    local out = {}
    for i = 1, 24 do out[i] = candidate("test_" .. i) end
    return out
end

---@param index integer
---@param candidates PW.ChallengeCandidate[]
---@param opts PW.ChallengeSelectOptions
---@return PW.ChallengeWeek?
local function selectWeek(index, candidates, opts)
    -- Before selection exists, the outcome assertions report the missing weekly result.
    local lib = PW.Challenges
    local fn = lib and rawget(lib, "_Select")
    return fn and fn(index, candidates, opts)
end

---@param week PW.ChallengeWeek?
local function signature(week)
    if week == nil then return "" end
    ---@type string[]
    local ids = {}
    for i, item in ipairs(week.items) do ids[i] = item.tier .. ":" .. item.id end
    return table.concat(ids, ",")
end

---@param week PW.ChallengeWeek?
local function itemSignature(week)
    if week == nil then return "" end
    ---@type string[]
    local ids = {}
    for i, item in ipairs(week.items) do ids[i] = item.id end
    table.sort(ids)
    return table.concat(ids, ",")
end

---@param week PW.ChallengeWeek
---@return integer
local function stateBits(week)
    local lib = PW.Challenges
    assert(lib ~= nil)
    local bits = 0
    lib._WriteWire("state", { week = week, items = {}, bonus = false }, function(_, width)
        bits = bits + width
    end)
    return bits
end

---For an 11-byte id and one objective, the two reward rows yield 161 or 162 bytes.
---@param id string
---@param rewardLength integer
---@return PW.ChallengeCandidate
local function edgeCandidate(id, rewardLength)
    return candidate(id, { Weight = 1000000000, Rewards = { items = {
        { kind = "cards", id = string.rep("a", rewardLength) },
        { kind = "cards", id = string.rep("b", 55) }
    } } })
end

local consecutiveWeeks = {
    name = "Rotation: a different week gives a different set (over 20 consecutive weeks at least 15 distinct sets)",
    func = function()
        local candidates = pool()
        ---@type table<string, boolean>
        local seen = {}
        for index = 2967, 2986 do
            local signatureOfWeek = itemSignature(selectWeek(index, candidates, { count = 5, seed = 0 }))
            if signatureOfWeek ~= "" then seen[signatureOfWeek] = true end
        end
        expect(table.Count(seen) >= 15).to.beTrue()
    end
}

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
        },
        {
            name = "Rotation: the same week, seed and pool give the same set regardless of registry order",
            func = function()
                local candidates, opts = pool(), { count = 5, seed = 47, bonusNeeded = 4 }
                local a, b = selectWeek(2967, candidates, opts), selectWeek(2967, table.Reverse(candidates), opts)
                expect(a and #a.items).to.equal(5)
                assert(a ~= nil and b ~= nil)
                expect(signature(a)).to.equal(signature(b))
                expect(a.seed).to.equal(b.seed)
                expect(a.seed).to.equal(1378849784)
                expect(a.index).to.equal(2967)
                expect(a.label).to.equal("2026-W47")
                expect(a.startsAt).to.equal(1794787200)
                expect(a.endsAt).to.equal(1795392000)
            end
        },
        consecutiveWeeks,
        {
            name = "Rotation: year boundary weeks 2026-W53 and 2027-W01 are distinct and deterministic",
            func = function()
                local candidates, opts = pool(), { count = 5, seed = 0 }
                local a, b = selectWeek(2973, candidates, opts), selectWeek(2974, candidates, opts)
                expect(a and a.label).to.equal("2026-W53")
                expect(b and b.label).to.equal("2027-W01")
                assert(a ~= nil and b ~= nil)
                expect(a.endsAt).to.equal(b.startsAt)
                expect(itemSignature(a) == itemSignature(b)).to.beFalse()
                expect(signature(a)).to.equal(signature(selectWeek(2973, candidates, opts)))
                expect(signature(b)).to.equal(signature(selectWeek(2974, candidates, opts)))
            end
        },
        {
            name = "Rotation: no template twice in a week and groups are not repeated unless a tier would stay empty",
            func = function()
                local candidates = {
                    candidate("hard", { Tiers = { "hard" }, Group = "shared" }),
                    candidate("medium_shared", { Tiers = { "medium" }, Weight = 10000, Group = "shared" }),
                    candidate("medium_unique", { Tiers = { "medium" }, Group = "other" }),
                    candidate("easy_shared", { Tiers = { "easy" }, Group = "shared" }),
                    candidate("outside", { Pool = "none" })
                }
                local week = selectWeek(2967, candidates, { count = 3 })
                expect(signature(week)).to.equal("easy:easy_shared,medium:medium_unique,hard:hard")
                week = selectWeek(2967, candidates, { count = 8, bonusNeeded = 8 })
                expect(signature(week)).to.equal("easy:easy_shared,medium:medium_shared,medium:medium_unique,hard:hard")
                assert(week ~= nil)
                expect(week.bonus.needed).to.equal(4)
            end
        },
        {
            name = "Rotation: tier mix for 1, 3, 5 and 8 challenges",
            func = function()
                local candidates = pool()
                local mixes = { [1] = "easy", [3] = "easy,medium,hard",
                    [5] = "easy,easy,medium,medium,hard", [8] = "easy,easy,easy,medium,medium,medium,hard,hard" }
                for _, count in ipairs({ 1, 3, 5, 8 }) do
                    ---@type string[]
                    local tiers = {}
                    local week = selectWeek(2967, candidates, { count = count })
                    ---@type PW.ChallengeInstance[]
                    local items = week and week.items or {}
                    for _, item in ipairs(items) do tiers[#tiers + 1] = item.tier end
                    expect(table.concat(tiers, ",")).to.equal(mixes[count])
                end
            end
        },
        {
            name = "Rotation: weights bias selection and a zero-candidate tier falls back to an easier tier",
            func = function()
                local heavy = candidate("z_heavy", { Weight = 9, Tiers = { "easy" } })
                local light = candidate("a_light", { Weight = 1, Tiers = { "easy" } })
                local hits = 0
                for index = 2967, 3066 do
                    local week = selectWeek(index, { heavy, light }, { count = 1 })
                    if week and week.items[1].id == "z_heavy" then hits = hits + 1 end
                end
                expect(hits >= 80 and hits < 100).to.beTrue()
                local medium = candidate("medium", { Tiers = { "medium" }, Target = { medium = 25 },
                    Rewards = { medium = { xp = 6 } } })
                local other = candidate("other", { Tiers = { "medium" }, Target = 4 })
                local week = selectWeek(2967, { medium, other, heavy }, { count = 3,
                    tierDefaults = { easy = { xp = 8 }, medium = { currency = 9 } } })
                expect(signature(week)).to.equal("easy:z_heavy,medium:medium,medium:other")
                assert(week ~= nil)
                expect(week.items[1].reward.xp).to.equal(8)
                expect(week.items[2].targets[1]).to.equal(25)
                expect(week.items[2].reward.xp).to.equal(6)
                expect(week.items[3].reward.currency).to.equal(9)
                week = selectWeek(2967, { heavy, light }, { count = 3 })
                expect(signature(week)).to.equal("easy:a_light,easy:z_heavy")
            end
        },
        {
            name = "Rotation: parameters bind deterministically and unavailable values are never chosen",
            func = function()
                local id = "a" .. string.rep("b", 30)
                local fields = { Params = { z = { source = "modes" }, a = { values = { "longlong", "ar", "smg",
                    "not_installed", "!" } } } }
                local values = { a = { "longlong", "smg", "ar", "!", "not_declared" }, z = { "tdm", "dom" } }
                local good = candidate(id, fields, values)
                local bad = candidate("bad", { Params = { weapon = { source = "weapons" } } }, { weapon = {} })
                for index = 2967, 2986 do
                    local week = selectWeek(index, { bad, good }, { count = 2 })
                    expect(week and #week.items).to.equal(1)
                    assert(week ~= nil)
                    local item = week.items[1]
                    expect(item.template).to.equal(id)
                    expect(item.params.a == "ar" or item.params.a == "smg").to.beTrue()
                    expect(item.params.z == "tdm" or item.params.z == "dom").to.beTrue()
                    expect(item.id).to.equal(id .. "." .. item.params.a .. "." .. item.params.z)
                    expect(#item.id <= 40).to.beTrue()
                    local reversed = candidate(id, fields, { a = table.Reverse(values.a), z = table.Reverse(values.z) })
                    expect(signature(week)).to.equal(signature(selectWeek(index, { reversed, bad }, { count = 2 })))
                end
                local dynamic = { values = function() error("must be resolved") end }
                local fn = candidate("dynamic", { Params = { mode = dynamic } },
                    { mode = { "tdm" } })
                expect(signature(selectWeek(2967, { fn }, { count = 1 }))).to.equal("easy:dynamic.tdm")
            end
        },
        {
            name = "Rotation: dots are reserved for instance id separators",
            func = function()
                expect(compile("dotted.template", {})).to.beNil()
                local fields = { Params = { a = { values = { "foo.bar", "foo" } }, b = { source = "modes" } } }
                local first = candidate("dots", fields, { a = { "foo.bar" }, b = { "baz" } })
                local second = candidate("dots", fields, { a = { "foo" }, b = { "bar.baz" } })
                local mixed = candidate("dots", fields, { a = { "foo.bar", "foo" }, b = { "bar.baz", "baz" } })
                local week = selectWeek(2967, { mixed }, { count = 1 })
                expect(signature(week)).to.equal("easy:dots.foo.baz")
                for index = 2967, 2986 do
                    week = selectWeek(index, { mixed }, { count = 1 })
                    expect(signature(week)).to.equal("easy:dots.foo.baz")
                    assert(week ~= nil)
                    expect(week.items[1].params.a).to.equal("foo")
                    expect(week.items[1].params.b).to.equal("baz")
                    local left = selectWeek(index, { first }, { count = 1 })
                    local right = selectWeek(index, { second }, { count = 1 })
                    expect(left and #left.items).to.equal(0)
                    expect(right and #right.items).to.equal(0)
                end
            end
        },
        {
            name = "Rotation: a different host seed changes the set",
            func = function()
                local candidates = pool()
                local a = selectWeek(2967, candidates, { count = 5, seed = 0 })
                local b = selectWeek(2967, candidates, { count = 5, seed = 137 })
                expect(a and b and a.seed ~= b.seed).to.beTrue()
                expect(itemSignature(a) == itemSignature(b)).to.beFalse()
                local zero = selectWeek(2967, candidates, { count = 5, seed = 768633910 })
                expect(zero and zero.seed).to.equal(1)
            end
        },
        {
            name = "Rotation: fitting twelve candidates preserve the legacy picks and bonus draw",
            func = function()
                local candidates = pool()
                ---@type PW.ChallengeSelectOptions
                local opts = { count = 12, seed = 47, bonusPool = {
                    { kind = "cards", id = "omega" }, { kind = "cards", id = "alpha" }
                } }
                local week = selectWeek(2967, candidates, opts)
                expect(week and #week.items).to.equal(12)
                assert(week ~= nil)
                expect(week.seed).to.equal(1378849784)
                expect(signature(week)).to.equal("easy:test_1,easy:test_11,easy:test_20,easy:test_4,easy:test_9,"
                    .. "medium:test_10,medium:test_13,medium:test_18,medium:test_7,"
                    .. "hard:test_21,hard:test_5,hard:test_8")
                local reward = week.bonus.reward.items
                expect(reward and reward[1].id).to.equal("omega")
                expect(stateBits(week) <= 2048 * 8).to.beTrue()
                local reversed = selectWeek(2967, table.Reverse(candidates), opts)
                expect(signature(reversed)).to.equal(signature(week))
            end
        },
        {
            name = "Rotation: twelve slots reserve the largest bonus before rejecting over-share candidates",
            func = function()
                local admitted = pool()
                admitted[#admitted + 1] = edgeCandidate("budget_fits", 54)
                local mixed = pool()
                mixed[#mixed + 1] = edgeCandidate("budget_fits", 54)
                mixed[#mixed + 1] = edgeCandidate("budget_edge", 55)
                ---@type PW.ChallengeRewardItem
                local small = { kind = "cards", id = "x" }
                ---@type PW.ChallengeRewardItem
                local large = { kind = "camos", id = string.rep("g", 40), weapon = string.rep("w", 40) }
                ---@type PW.ChallengeSelectOptions
                local opts = { count = 12, seed = 47, bonusPool = { small } }
                expect(signature(selectWeek(2967, mixed, opts)):find(":budget_edge", 1, true) ~= nil).to.beTrue()
                opts.bonusPool = { small, large }
                local smallDraws = 0
                for index = 2967, 2971 do
                    local week = selectWeek(index, mixed, opts)
                    local baseline = selectWeek(index, admitted, opts)
                    expect(week and #week.items).to.equal(12)
                    assert(week ~= nil and baseline ~= nil)
                    expect(signature(week)).to.equal(signature(baseline))
                    expect(signature(week):find(":budget_fits", 1, true) ~= nil).to.beTrue()
                    expect(week.bonus.reward.items).to.deepEqual(baseline.bonus.reward.items)
                    expect(stateBits(week) <= 2048 * 8).to.beTrue()
                    local reward = week.bonus.reward.items
                    if reward ~= nil and reward[1].id == small.id then smallDraws = smallDraws + 1 end
                end
                expect(smallDraws > 0).to.beTrue()
            end
        },
        {
            name = "Rotation: candidate admission budgets the longest available parameter binding",
            func = function()
                local fields = { Weight = 1000000000, Params = { category = { source = "categories" } },
                    Rewards = { items = { { kind = "cards", id = string.rep("a", 44) },
                        { kind = "cards", id = string.rep("b", 44) } } } }
                local short = pool()
                short[#short + 1] = candidate("budget_opts", fields, { category = { "a" } })
                local mixed = pool()
                mixed[#mixed + 1] = candidate("budget_opts", fields, { category = { "a", "long_value" } })
                ---@type PW.ChallengeSelectOptions
                local opts = { count = 12, seed = 47, bonusPool = {
                    { kind = "camos", id = string.rep("g", 40), weapon = string.rep("w", 40) }
                } }
                expect(signature(selectWeek(2967, short, opts)):find(":budget_opts.a", 1, true) ~= nil).to.beTrue()
                expect(signature(selectWeek(2967, mixed, opts))).to.equal(signature(selectWeek(2967, pool(), opts)))
            end
        },
        {
            name = "Rotation: invalid bonus strings do not reserve space or consume a bonus draw",
            func = function()
                local candidates = pool()
                candidates[#candidates + 1] = edgeCandidate("budget_edge", 55)
                local baseline = selectWeek(2967, candidates, { count = 12, seed = 47 })
                local week = selectWeek(2967, candidates, { count = 12, seed = 47, bonusPool = {
                    { kind = "cards", id = string.rep("z", 65) }, { kind = "cards", id = "bad\0id" }
                } })
                expect(week and #week.items).to.equal(12)
                assert(week ~= nil and baseline ~= nil)
                expect(signature(week)).to.equal(signature(baseline))
                expect(week.bonus.reward.items).to.beNil()
                expect(stateBits(week)).to.equal(stateBits(baseline))
            end
        },
        {
            name = "Rotation: the sorted bonus pool is sampled last and zero bonus need is preserved",
            func = function()
                ---@type PW.ChallengeRewardItem[]
                local items = { { kind = "models", id = "emblem" }, { kind = "camos", weapon = "b", id = "silver" },
                    { kind = "camos", weapon = "a", id = "gold" } }
                local candidates = pool()
                ---@type PW.ChallengeSelectOptions
                local opts = { count = 1, bonusNeeded = 0, seed = 47, bonusPool = items }
                local a = selectWeek(2967, candidates, opts)
                expect(a and a.bonus.needed).to.equal(0)
                assert(a ~= nil)
                expect(a.bonus.reward.xp).to.equal(10000)
                expect(a.bonus.reward.currency).to.equal(300)
                local awarded = a.bonus.reward.items
                expect(awarded and #awarded).to.equal(1)
                assert(awarded ~= nil)
                opts.bonusPool = table.Reverse(items)
                local b = selectWeek(2967, candidates, opts)
                assert(b ~= nil and b.bonus.reward.items ~= nil)
                expect(awarded[1].id).to.equal(b.bonus.reward.items[1].id)
                expect(signature(a)).to.equal(signature(b))
                opts.bonusPool = {}
                b = selectWeek(2967, candidates, opts)
                assert(b ~= nil)
                expect(b.bonus.reward.items).to.beNil()
                expect(signature(a)).to.equal(signature(b))
                opts.bonusPool = items
                ---@type table<string, boolean>
                local seen = {}
                for index = 2967, 2986 do
                    a = selectWeek(index, {}, opts)
                    b = selectWeek(index, candidates, opts)
                    assert(a ~= nil and b ~= nil and a.bonus.reward.items ~= nil and b.bonus.reward.items ~= nil)
                    local earlier, later = a.bonus.reward.items[1].id, b.bonus.reward.items[1].id
                    seen[earlier], seen[later] = true, true
                    if earlier ~= later then seen.drawOrder = true end
                end
                expect(seen.drawOrder).to.beTrue()
                expect(seen.gold and seen.silver and seen.emblem).to.beTrue()
            end
        }
    }
}
