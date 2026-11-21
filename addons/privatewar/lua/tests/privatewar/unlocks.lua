-- Unlock authority: pure rules over definitions and player views (06-progression.md d.8).

---@return PW.UnlocksLib
local function lib()
    local unlocks = PW.Unlocks
    assert(unlocks ~= nil, "expected the shared unlock authority to be available")
    return unlocks
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
