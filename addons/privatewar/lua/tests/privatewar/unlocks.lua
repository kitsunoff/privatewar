-- Unlock authority: pure rules over definitions and player views (06-progression.md d.8).

---@return PW.UnlocksLib
local function lib()
    local unlocks = PW.Unlocks
    assert(unlocks ~= nil, "expected the shared unlock authority to be available")
    return unlocks
end

---@return PW.ProgressionView
local function view()
    ---@type table<string, table<string, table<string, any>>>
    local catalogue = {
        perks = {
            plain = {}, level = { Unlock = 20 }, reward = { Unlock = false },
            hinted = { Unlock = { level = false, hint = "Win a round" } },
            price = { Price = 600 }, reward_sale = { Unlock = { level = false, hint = "#pw.hint" }, Price = 600 }
        },
        weapons = {
            rifle = {
                Attachments = { optic = { Unlock = 12 }, hidden = { Hidden = true, Unlock = 2 } },
                Camos = { gold = { Unlock = 30 } }
            }
        }
    }
    return {
        level = 3, weaponLevel = function() return 5 end, unlockAll = false, maxAttachments = 6,
        lookup = function(kind, id)
            local entries = catalogue[kind]
            return entries ~= nil and entries[id] or nil
        end
    }
end

return {
    groupName = "PW unlock authority",
    cases = {
        {
            name = "Spec: nil, integer, { level = N }, false, { level = false } and hint normalise; "
                .. "anything else is open",
            func = function()
                local spec = lib()._Spec
                expect(spec(nil)).to.deepEqual({ level = 0, declared = false })
                expect(spec(12.8)).to.deepEqual({ level = 12, declared = true })
                expect(spec(-2)).to.deepEqual({ level = 0, declared = true })
                expect(spec({ level = 12 })).to.deepEqual({ level = 12, declared = true })
                expect(spec(false)).to.deepEqual({ level = false, declared = true })
                expect(spec({ level = false, hint = "#pw.reward", reward = "challenge" })).to.deepEqual({
                    level = false, hint = "#pw.reward", reward = "challenge", declared = true
                })
                expect(spec({ level = 20, hint = "Win a match" }).hint).to.equal("Win a match")
                expect(spec({ hint = "Win a match" }).level).to.equal(0)
                expect(spec({ level = 1, hint = string.rep("a", 129), reward = "Friday!" })).to.deepEqual({
                    level = 1, declared = true
                })
                for _, malformed in ipairs({ true, "20", {}, math.huge, -math.huge, 0 / 0, { level = "12" } }) do
                    expect(spec(malformed)).to.deepEqual({ level = 0, declared = true })
                end
            end
        },
        {
            name = "Decide: any source opens; the reason names the first source that did",
            func = function()
                local v, decide = view(), lib()._Decide
                v.level, v.unlockAll = 40, true
                v.override = function() return true end
                v.granted = function(key) return key == "perks:level" end
                v.owned = function(key) return key == "perks:level" end
                expect({ decide(v, "perks", "not_installed") }).to.deepEqual({ false, "unknown" })
                expect({ decide(v, "attachments", "rifle") }).to.deepEqual({ false, "unknown" })
                expect({ decide(v, "attachments", "missing:optic") }).to.deepEqual({ false, "unknown" })
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "override" })
                v.override = nil
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "unlockall" })
                v.unlockAll = false
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "grant" })
                v.granted = nil
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "purchase" })
                v.owned = nil
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "level" })
                expect({ decide(v, "perks", "plain") }).to.deepEqual({ true, "default" })
                expect({ decide(v, "attachments", "rifle:iron") }).to.deepEqual({ true, "default" })
                expect({ decide(v, "attachments", "rifle:optic") }).to.deepEqual({ false, "weapon_level" })
                v.weaponLevel = function() return 30 end
                expect({ decide(v, "camos", "rifle:gold") }).to.deepEqual({ true, "weapon_level" })
            end
        },
        {
            name = "Decide: Hidden beats every source, including unlockall, grants and the override hook",
            func = function()
                local v = view()
                local called = 0
                v.unlockAll = true
                v.granted, v.owned = function() return true end, function() return true end
                v.override = function()
                    called = called + 1
                    return true
                end
                expect({ lib()._Decide(v, "attachments", "rifle:hidden") }).to.deepEqual({ false, "hidden" })
                expect(called).to.equal(0)
            end
        },
        {
            name = "Decide: Unlock = false opens only through a grant or a purchase, never by level",
            func = function()
                local v, decide = view(), lib()._Decide
                v.level = 1000
                expect({ decide(v, "perks", "reward") }).to.deepEqual({ false, "grant_only" })
                expect({ decide(v, "perks", "hinted") }).to.deepEqual({ false, "grant_only" })
                v.owned = function(key) return key == "perks:reward" end
                expect({ decide(v, "perks", "reward") }).to.deepEqual({ true, "purchase" })
                v.granted = function(key) return key == "perks:reward" end
                expect({ decide(v, "perks", "reward") }).to.deepEqual({ true, "grant" })
            end
        },
        {
            name = "Decide: unlockall opens grant-only items and every level gate",
            func = function()
                local v, decide = view(), lib()._Decide
                v.unlockAll = true
                expect({ decide(v, "perks", "reward") }).to.deepEqual({ true, "unlockall" })
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "unlockall" })
                expect({ decide(v, "camos", "rifle:gold") }).to.deepEqual({ true, "unlockall" })
            end
        },
        {
            name = "Decide: grants count with the economy module disabled; purchases do not",
            func = function()
                local v, decide = view(), lib()._Decide
                v.owned = function(key) return key == "perks:level" end
                v.granted = function(key) return key == "perks:reward" end
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "purchase" })
                v.owned = nil
                expect({ decide(v, "perks", "level") }).to.deepEqual({ false, "level" })
                expect({ decide(v, "perks", "reward") }).to.deepEqual({ true, "grant" })
            end
        },
        {
            name = "Decide: a priced entity without Unlock stays for sale only; a grant opens it",
            func = function()
                local v, decide = view(), lib()._Decide
                v.level = 1000
                v.owned = function() return false end
                expect({ decide(v, "perks", "price") }).to.deepEqual({ false, "price" })
                v.granted = function(key) return key == "perks:price" end
                expect({ decide(v, "perks", "price") }).to.deepEqual({ true, "grant" })
                v.owned, v.granted = nil, nil
                expect({ decide(v, "perks", "price") }).to.deepEqual({ true, "default" })
            end
        },
        {
            name = "Hook: PW_UnlockOverride true opens and false locks after Hidden; nil keeps the rules",
            func = function()
                local v, decide = view(), lib()._Decide
                ---@type boolean?
                local answer
                v.override = function(kind, id)
                    local result = PW.Ask("PW_UnlockOverride", NULL, kind, id)
                    if type(result) == "boolean" then return result end
                    return nil
                end
                stub(PW, "Ask").with(function(hookName, ply, kind, id)
                    expect(hookName).to.equal("PW_UnlockOverride")
                    expect(ply).to.equal(NULL)
                    expect(kind).to.equal("perks")
                    expect(id).to.equal("level")
                    return answer
                end)
                expect({ decide(v, "perks", "level") }).to.deepEqual({ false, "level" })
                answer = true
                expect({ decide(v, "perks", "level") }).to.deepEqual({ true, "override" })
                answer, v.unlockAll = false, true
                expect({ decide(v, "perks", "level") }).to.deepEqual({ false, "override" })
                expect({ decide(v, "attachments", "rifle:hidden") }).to.deepEqual({ false, "hidden" })
            end
        },
        {
            name = "Requirement: level, weapon level, price, reward hint and the PW_UnlockHint answer, "
                .. "with their lock texts",
            func = function()
                local unlocks = lib()
                local static = unlocks._StaticRequirement
                expect({ unlocks.LockText(static({ Unlock = 20 }, false)) }).to.deepEqual({
                    "LV 20", "Unlocks at level 20"
                })
                expect({ unlocks.LockText(static({ Unlock = { level = 12 } }, true)) }).to.deepEqual({
                    "LV 12", "Unlocks at weapon level 12"
                })
                expect({ unlocks.LockText(static({ Price = 600 }, false)) }).to.deepEqual({
                    "600 CR", "Buy it in the STORE for 600 CR"
                })
                expect({ unlocks.LockText(static({ Unlock = false }, false)) }).to.deepEqual({
                    "REWARD", "Earned as a reward"
                })
                expect({ unlocks.LockText(static({ Unlock = { level = false, hint = "#pw.weekly" } }, true)) })
                    .to.deepEqual({ "REWARD", "#pw.weekly" })
                local sale = static({ Price = 600, Unlock = { level = false, hint = "Event reward" } }, false)
                expect({ sale.lockText, sale.text, sale.hint }).to.deepEqual({
                    "600 CR", "Buy it in the STORE for 600 CR", "Event reward"
                })
                local open = static({}, false)
                expect(open.unlocked).to.beTrue()
                expect(open.lockText).to.beNil()
                expect(open.text).to.beNil()
                local hidden = static({ Hidden = true, Unlock = 30 }, true)
                expect(hidden.unlocked).to.beFalse()
                expect(hidden.reason).to.equal("hidden")
                expect(hidden.lockText).to.beNil()
                expect(hidden.text).to.beNil()
                local v = view()
                ---@type string[]
                local asked = {}
                v.hint = function(kind, id)
                    local result = PW.Ask("PW_UnlockHint", kind, id)
                    if type(result) == "string" then return result end
                    return nil
                end
                stub(PW, "Ask").with(function(hookName, kind, id)
                    expect(hookName).to.equal("PW_UnlockHint")
                    asked[#asked + 1] = kind .. ":" .. id
                    if id == "hinted" then return "#pw.weekly.dynamic" end
                    return nil
                end)
                v.owned = function() return false end
                local requirement = unlocks._Requirement
                expect(requirement(v, "perks", "level")).to.deepEqual({
                    unlocked = false, reason = "level", level = 20, lockText = "LV 20", text = "Unlocks at level 20"
                })
                expect(requirement(v, "attachments", "rifle:optic")).to.deepEqual({
                    unlocked = false, reason = "weapon_level", weaponLevel = 12,
                    lockText = "LV 12", text = "Unlocks at weapon level 12"
                })
                expect(requirement(v, "perks", "price")).to.deepEqual({
                    unlocked = false, reason = "price", price = 600,
                    lockText = "600 CR", text = "Buy it in the STORE for 600 CR"
                })
                expect(requirement(v, "perks", "hinted")).to.deepEqual({
                    unlocked = false, reason = "grant_only", hint = "#pw.weekly.dynamic",
                    lockText = "REWARD", text = "#pw.weekly.dynamic"
                })
                local fallback = requirement(v, "perks", "reward_sale")
                expect(fallback.hint).to.equal("#pw.hint")
                expect(fallback.lockText).to.equal("600 CR")
                expect(requirement(v, "perks", "plain").text).to.beNil()
                expect(requirement(v, "attachments", "rifle:hidden").text).to.beNil()
                expect(asked).to.deepEqual({
                    "perks:level", "attachments:rifle:optic", "perks:price", "perks:hinted", "perks:reward_sale"
                })
            end
        },
        {
            name = "LockedOptions: a curated camo above the weapon level is locked on the server; "
                .. "an entitled one is open",
            func = function()
                local progression = assert(PW.Progression)
                local v = view()
                local build = { ["1"] = "gold", ["2"] = "hidden", ["3"] = "optic" }
                expect(progression._LockedOptions(v, "rifle", build)).to.deepEqual({
                    gold = true, hidden = true, optic = true
                })
                v.owned = function(key) return key == "camos:rifle:gold" or key == "attachments:rifle:optic" end
                expect(progression._LockedOptions(v, "rifle", build)).to.deepEqual({ hidden = true })
                v.owned = nil
                v.granted = function() return true end
                expect(progression._LockedOptions(v, "rifle", build)).to.deepEqual({ hidden = true })
            end
        },
        {
            name = "LockedOptions: an entitled uncurated attachment does not count toward the weapon level limit",
            func = function()
                local progression = assert(PW.Progression)
                local v = view()
                v.weaponLevel = function() return 1 end
                local build = { ["1"] = "reward", ["2"] = "owned", ["3"] = "ordinary", ["4"] = "overflow" }
                v.granted = function(key) return key == "attachments:rifle:reward" end
                v.owned = function(key) return key == "attachments:rifle:owned" end
                expect(progression._LockedOptions(v, "rifle", build)).to.deepEqual({ overflow = true })
                v.owned = nil
                expect(progression._LockedOptions(v, "rifle", build)).to.deepEqual({
                    ordinary = true, overflow = true
                })
            end
        },
        {
            name = "Gunsmith: entitled uncurated attachments do not consume the level allowance on save",
            func = function()
                local loadout = assert(PW.Loadout)
                local v = view()
                v.granted = function(key) return key == "attachments:rifle:reward" end
                local progression = assert(PW.Progression)
                local weapon = assert(v.lookup("weapons", "rifle"))
                ---@type PW.LoadoutContext
                local ctx = { lookup = v.lookup, budget = 0, maxattachments = 6,
                    attachmentLimit = function() return 1 end,
                    entitledOption = function(weaponId, option)
                        return progression._EntitledOption(v, weaponId, option)
                    end }
                local build = { ["1"] = "reward", ["2"] = "ordinary", ["3"] = "overflow" }
                local repaired, problems = loadout._ValidateBuild("rifle", weapon, build, ctx)
                expect(repaired).to.deepEqual({ ["1"] = "reward", ["2"] = "ordinary" })
                expect(problems).to.deepEqual({ { slot = "3", option = "overflow", why = "over the limit" } })
                expect(build["3"]).to.equal("overflow")
            end
        },
        {
            name = "Keys: KeyOf and ParseKey accept the bundle item shape, the camo alias and attachments; "
                .. "malformed items give nil",
            func = function()
                local unlocks = lib()
                expect(unlocks.KeyOf({ kind = "perks", id = "fast.reload" })).to.equal("perks:fast.reload")
                expect(unlocks.KeyOf({ kind = "camo", weapon = "pw_gun", id = "gold" })).to.equal("camos:pw_gun:gold")
                expect(unlocks.KeyOf({ kind = "attachments", weapon = "pw_gun", id = "optic-1" }))
                    .to.equal("attachments:pw_gun:optic-1")
                expect(unlocks.KeyOf("camos:pw_gun:gold")).to.equal("camos:pw_gun:gold")
                expect({ unlocks.ParseKey("perks:fast.reload") }).to.deepEqual({ "perks", "fast.reload" })
                expect({ unlocks.ParseKey("camos:pw_gun:gold") }).to.deepEqual({
                    "camos", "pw_gun:gold", "pw_gun", "gold"
                })
                expect({ unlocks.ParseKey("attachments:pw_gun:optic-1") }).to.deepEqual({
                    "attachments", "pw_gun:optic-1", "pw_gun", "optic-1"
                })
                local longest = "perks:" .. string.rep("x", 90)
                expect(unlocks.KeyOf(longest)).to.equal(longest)
                for _, key in ipairs({ "", "perks", "Perks:a", "perks:bad id", "perks:", longest .. "x",
                    "attachments:optic", "camos::gold", "camos:pw_gun:" }) do
                    expect(unlocks.KeyOf(key)).to.beNil()
                    local kind = unlocks.ParseKey(key)
                    expect(kind).to.beNil()
                end
                expect(unlocks.KeyOf({ kind = "camos", id = "gold" })).to.beNil()
                expect(unlocks.KeyOf({ kind = "attachments", weapon = "bad:weapon", id = "optic" })).to.beNil()
            end
        }
    }
}
