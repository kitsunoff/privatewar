-- Differential coverage for precise selected-option metadata, never a player verdict cache.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@param class string
---@param id string
---@param option string
---@return boolean
local function legacy(class, id, option)
    local slots = PW.Adapters.CallFor(class, "GetSlots", class, nil) --[[@as PW.Slot[]?]]
    for _, slot in ipairs(slots or {}) do
        if slot.id == id and slot.cosmetic == true then return true end
    end
    local options = PW.Adapters.CallFor(class, "GetOptions", class, id) --[[@as PW.Option[]?]]
    for _, entry in ipairs(options or {}) do
        if entry.id == option and entry.cosmetic == true then return true end
    end
    return false
end

---@param entry PW.BotClassEntry
---@param selected table[]
local function appendSelected(entry, selected)
    for slot, build in pairs(entry.loadout.builds --[[@as table<string, PW.Build>]]) do
        local class = entry.loadout[slot] --[[@as string]]
        for id, option in pairs(build) do
            if isstring(option) then
                selected[#selected + 1] = { class, id, option, legacy(class, id, option --[[@as string]]) }
            end
        end
    end
end

local cases = {
    {
        name = "Selection metadata: definitive false is used without enumerating lists; nil keeps legacy fallback",
        func = function()
            ---@type boolean?
            local answer = false
            local precise, lists = 0, 0
            stub(PW.Adapters, "CallFor").with(function(_, method)
                if method == "IsSelectionCosmetic" then precise = precise + 1 return answer end
                lists = lists + 1
                if method == "GetSlots" then return { { id = "1", cosmetic = true } } end
                return {}
            end)
            local lib = must(PW.Loadout)
            local check = must(lib._LiveContext(lib._RegistryLookup).isCosmetic)
            expect(check("fixture", "1", "camo")).to.beFalse()
            expect(precise).to.equal(1)
            expect(lists).to.equal(0)
            answer = nil
            expect(check("fixture", "1", "camo")).to.beTrue()
            expect(lists).to.equal(1)
        end
    },
    {
        name = "Selection metadata: missing adapter and legacy adapter retain the exact list-based answer",
        func = function()
            ---@type PW.Adapter?
            local old = nil
            stub(PW.Adapters, "For").with(function() return old end)
            local lib = must(PW.Loadout)
            local check = must(lib._LiveContext(lib._RegistryLookup).isCosmetic)
            expect(check("missing", "1", "anything")).to.beFalse()
            old = { ClassName = "legacy", GetSlots = function() return {} end,
                GetOptions = function() return { { id = "camo", cosmetic = true } } end } --[[@as any]]
            expect(check("legacy", "1", "camo")).to.beTrue()
            expect(check("legacy", "1", "other")).to.beFalse()
        end
    },
    {
        name = "Selection metadata: mounted ARC9 selected builds agree with legacy without discovery-list calls",
        skip = function() return PW.Arc9 == nil or ARC9 == nil end,
        func = function()
            ---@type table[]
            local selected = {}
            for _, entry in ipairs(must(PW._Arc9BotLoadouts).entries) do
                appendSelected(entry, selected)
            end
            expect(#selected > 30).to.beTrue()
            local calls, call = 0, PW.Adapters.Call
            stub(PW.Adapters, "Call").with(function(owner, method, ...)
                if method == "GetSlots" or method == "GetOptions" then calls = calls + 1 end
                return call(owner, method, ...)
            end)
            local lib = must(PW.Loadout)
            local check = must(lib._LiveContext(lib._RegistryLookup).isCosmetic)
            for _, row in ipairs(selected) do expect(check(row[1], row[2], row[3])).to.equal(row[4]) end
            expect(calls).to.equal(0)
        end
    },
    {
        name = "Selection metadata: live blacklist swaps, in-place attachment/category/slot mutations and memo reset",
        skip = function() return PW.Arc9 == nil or ARC9 == nil end,
        cleanup = function(test)
            if test.blacklist ~= nil then must(ARC9).Blacklist = test.blacklist end
            if test.memo ~= nil then must(PW._Arc9).memo = test.memo end
        end,
        func = function(test)
            local arc, lib = must(ARC9), must(PW.Arc9)
            local arcAdapter = must(PW.WeaponAdapters.Get("arc9")) --[[@as PW.Adapter]]
            stub(PW.Adapters, "For").with(function() return arcAdapter end)
            test.blacklist, test.memo = arc.Blacklist, must(PW._Arc9).memo
            local slotCategory = { "fixture" }
            ---@type PW.Arc9SlotTable[]
            local slots = { { Category = slotCategory }, { Category = "universal_camo" },
                { Category = "fixture", Installed = "parent" } }
            ---@type table<string, table<string, any>>
            local atts = { camo = { Category = "fixture", CosmeticOnly = true },
                other = { Category = "fixture" }, parent = { Attachments = { { Category = "fixture" } } } }
            local blacklist = { other = true }
            arc.Blacklist = blacklist
            stub(arc, "GetAttTable").with(function(id) return atts[id] end)
            stub(arc, "GetAttsForCats").with(function(category)
                return table.HasValue(istable(category) and category or { category }, "fixture")
                    and { "camo", "other" } or {}
            end)
            stub(weapons, "GetStored").with(function() return { Attachments = slots } end)
            stub(lib, "ClassSlots").with(function() return slots end)
            -- Legacy is the reference with fresh discovery for each mutation, not stale revision/count verdicts.
            local loadout = must(PW.Loadout)
            local check = must(loadout._LiveContext(loadout._RegistryLookup).isCosmetic)
            local function compare(id, option, expected)
                -- Ask before refreshing the reference memo: same-count mutations must be seen immediately.
                expect(check("fixture", id, option)).to.equal(expected)
                must(PW._Arc9).memo = { values = {} }
                local old = legacy("fixture", id, option)
                expect(old).to.equal(expected)
                expect(check("fixture", id, option)).to.equal(old)
            end
            compare("1", "camo", true)
            blacklist.other, blacklist.camo = nil, true -- same count, same identity
            compare("1", "camo", false)
            blacklist.camo, blacklist.other = nil, true
            compare("1", "camo", true)
            atts.camo.Ignore = true
            compare("1", "camo", false)
            atts.camo.Ignore, atts.camo.AdminOnly = nil, true
            compare("1", "camo", false)
            atts.camo.AdminOnly, atts.camo.CosmeticOnly = nil, false
            compare("1", "camo", false)
            atts.camo.Category = "universal_camo"
            compare("1", "camo", true)
            slotCategory[1] = "unmatched"
            compare("1", "camo", false)
            compare("2", "missing", true)
            slots[2].Hidden = true
            compare("2", "missing", false)
            compare("3.1", "camo", true)
            compare("missing", "camo", false)
            -- Same reset used by shared.lua on reload.
            must(PW._Arc9).memo = { values = {} }
            compare("3.1", "camo", true)
        end
    },
    {
        name = "Selection metadata differential: dynamic owner permissions/costs, wildcard, bans/caps, weighted order",
        cleanup = function(test)
            if test.slots ~= nil then PW._Loadout.slots = test.slots end
        end,
        func = function(test)
            local lib = must(PW.Loadout)
            local optimized, owner, price, cap, allowed = false, 1, 1, 2, true
            local costCalls, wildcardCalls, permissionCalls = 0, 0, 0
            local defs = { primary = { id = "primary", kind = "weapons" },
                wildcard = { id = "wildcard", kind = "wildcards" } }
            local weapon = { Category = "ar" }
            local wildcard = { ModifySlots = function(_, effective)
                wildcardCalls = wildcardCalls + 1
                effective.primary.maxattachments = cap
            end }
            local function lookup(kind) return kind == "wildcards" and wildcard or weapon end
            stub(PW.Adapters, "CallFor").with(function(_, method)
                if method == "IsSelectionCosmetic" then
                    if optimized then return false end
                    return nil
                end
                return {}
            end)
            local ask = PW.Ask
            stub(PW, "Ask").with(function(name, ...)
                if name == "PW_LoadoutCost" then costCalls = costCalls + 1 return price end
                if name == "PW_ValidateLoadout" then
                    permissionCalls = permissionCalls + 1
                    ---@type any
                    local ply = ...
                    return allowed and ply == owner
                end
                return ask(name, ...)
            end)
            local setting = PW.Setting
            local budget, bans = 10, {}
            stub(PW, "Setting").with(function(id)
                if id == "loadout.budget" then return budget end
                if id == "loadout.bannedattachments" then return bans end
                return setting(id)
            end)
            test.slots, PW._Loadout.slots = PW._Loadout.slots, defs
            local loadout = { primary = "fixture", wildcard = "fixture",
                builds = { primary = { ["1"] = "optic" } } }
            local function run(fast)
                optimized = fast
                costCalls, wildcardCalls, permissionCalls = 0, 0, 0
                local ctx = lib._LiveContext(lookup)
                local cost = lib._Cost(defs, loadout, ctx)
                ---@type table[]
                local verdicts = {}
                ---@type PW.BotClassEntry[]
                local pool = {}
                for bot = 1, 2 do
                    local ok, err = lib.Validate(bot --[[@as Player]], table.Copy(loadout), lookup)
                    verdicts[#verdicts + 1] = { ok, err }
                    if ok then pool[#pool + 1] = { ref = tostring(bot), source = "generated", name = "Fixture",
                        loadout = table.Copy(loadout) } end
                end
                ---@type string[]
                local picks = {}
                for _, roll in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
                    local entry = must(PW.BotLoadouts).Pick(pool, { ar = 3 }, roll, function() return "ar" end)
                    picks[#picks + 1] = entry ~= nil and entry.ref or "none"
                end
                return { cost, verdicts, picks, costCalls, wildcardCalls, permissionCalls }
            end
            local function compare() expect(run(true)).to.deepEqual(run(false)) end
            compare()
            expect(run(true)[6]).to.equal(2)
            owner, price = 2, 2
            compare()
            allowed = false
            compare()
            allowed, budget = true, 2
            compare()
            budget, cap = 10, 0
            compare()
            cap, bans = 2, { optic = true }
            compare()
        end
    }
}

return { groupName = "PW selected attachment metadata", cases = cases }
