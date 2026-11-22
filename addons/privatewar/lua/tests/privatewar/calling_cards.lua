-- Calling-card policy and the bounded wire (calling-card-kill-banner.md §7).
---@return PW.CallingCardsLib
local function cards()
    return assert(rawget(PW, "CallingCards"), "calling card module not loaded") --[[@as PW.CallingCardsLib]]
end

---@return PW.CardChoiceFacts
local function choiceFacts()
    return {
        previous = "level_20",
        registered = function(id) return id == "level_20" or id == "disabled" or id == "locked" end,
        enabled = function(id) return id ~= "disabled" end,
        unlocked = function(id) return id ~= "locked" end
    }
end

---@param bytes string
---@param bot? boolean
---@return PW.CardReader
local function reader(bytes, bot)
    local offset = 0
    return {
        ReadUInt = function(bits)
            assert(bits == 8, "expected a string byte")
            offset = offset + 1
            return assert(bytes:byte(offset), "read past the supplied bytes")
        end,
        ReadBool = function()
            assert(offset == #bytes, "bot flag must follow both strings")
            return bot == true
        end
    }
end

return {
    groupName = "PW calling cards",
    cases = {
        {
            name = "Personal settings expose a dynamic card enum with Recruit as the default",
            func = function()
                local settings = assert(PW.Settings)
                ---@type table<string, PW.SettingDef>
                local fields = {}
                for _, group in ipairs(settings.GetGroups("client")) do
                    if group.owner == "calling_cards" then
                        for _, field in ipairs(group.fields) do fields[field.def.key] = field.def end
                    end
                end
                local selected = assert(fields.selected, "calling_cards.selected is missing from Personal settings")
                expect(selected.type).to.equal("enum")
                expect(selected.default).to.equal("default")
                local options = assert(selected.optionsFn, "card options must follow the registry")()
                expect(options[1]).to.equal("default")
                for _, id in ipairs({ "default", "bomb", "gold_medal", "lightning" }) do
                    expect(table.HasValue(options, id)).to.beTrue()
                    local valid = settings._Validate(selected, id)
                    expect(valid).to.beTrue()
                end
                local empty = settings._Validate(selected, "")
                local unknown = settings._Validate(selected, "unregistered_test_card")
                expect(empty).to.beFalse()
                expect(unknown).to.beFalse()
                local banner = assert(fields.banner, "calling_cards.banner is missing from Personal settings")
                expect(banner.type).to.equal("bool")
                expect(banner.default).to.beTrue()
            end
        },
        {
            name = "Resolve: a registered, enabled, unlocked card is accepted",
            func = function()
                expect(cards()._Resolve("level_20", choiceFacts())).to.equal("level_20")
            end
        },
        {
            name = "Resolve: unknown, disabled or locked cards fall back to the default card",
            func = function()
                for _, id in ipairs({ "unknown", "disabled", "locked", "" }) do
                    expect(cards()._Resolve(id, choiceFacts())).to.equal("default")
                end
            end
        },
        {
            name = "Resolve: malformed input keeps the previous choice",
            func = function()
                local facts = choiceFacts()
                for _, value in ipairs({ false, 123, {}, "LEVEL", "level 20", "level-20", "level\000",
                    string.rep("x", 33) }) do
                    expect(cards()._Resolve(value, facts)).to.equal("level_20")
                end
                expect(cards()._Resolve(nil, facts)).to.equal("level_20")
            end
        },
        {
            name = "BotCard: deterministic for the same rng and id list, nil for an empty list",
            func = function()
                local ids = { "a", "b", "c" }
                local rng = function() return 0.5 end
                expect(cards()._BotCard(ids, rng)).to.equal("b")
                expect(cards()._BotCard(ids, rng)).to.equal("b")
                expect(cards()._BotCard({}, function() error("empty list must not roll") end)).to.beNil()
            end
        },
        {
            name = "Victim name is truncated to 32 bytes",
            func = function()
                local sent = ""
                local value = string.rep("x", 32)
                cards()._Encode({ name = value .. "extra", card = "", bot = false }, {
                    WriteString = function(text) if sent == "" then sent = text end end,
                    WriteBool = function() end
                })
                expect(sent).to.equal(value)
                local prefix = string.rep("a", 31)
                expect(cards()._VictimName(prefix .. utf8.char(0x416))).to.equal(prefix)
                expect(cards()._VictimName("line\nnew\000name")).to.equal("line new name")
            end
        },
        {
            name = "Encode and decode round-trip the banner state",
            func = function()
                local original = { name = "Player 2", card = "bomb", bot = true }
                local bytes, bot = "", false
                cards()._Encode(original, {
                    WriteString = function(value) bytes = bytes .. value .. "\000" end,
                    WriteBool = function(value) bot = value end
                })
                expect(bytes).to.equal("Player 2\000bomb\000")
                local copy = assert(cards()._Decode(reader(bytes, bot), #bytes * 8 + 1))
                expect(copy.name).to.equal(original.name)
                expect(copy.card).to.equal(original.card)
                expect(copy.bot).to.equal(original.bot)
            end
        },
        {
            name = "Card wire rejects truncation, trailing fields, bad ids and over-limit strings",
            func = function()
                for _, bytes in ipairs({ "name\000bomb", "name\000bomb\000\000", "name\000BAD\000",
                    string.rep("n", 33) .. "\000\000", "name\000" .. string.rep("c", 33) .. "\000" }) do
                    expect(cards()._Decode(reader(bytes), #bytes * 8 + 1)).to.beNil()
                end
                local valid = "name\000bomb\000"
                expect(cards()._Decode(reader(valid), #valid * 8)).to.beNil()
                local plain = "name\000\000"
                expect(assert(cards()._Decode(reader(plain), #plain * 8 + 1)).card).to.equal("")
                expect(cards()._ReadChoice(reader("\000"), 8)).to.equal("")
                local longest = string.rep("c", 32)
                expect(cards()._ReadChoice(reader(longest .. "\000"), 264)).to.equal(longest)
                expect(cards()._ReadChoice(reader("valid"), 40)).to.beNil()
                expect(cards()._ReadChoice(reader("valid\000\000"), 56)).to.beNil()
                expect(cards()._ReadChoice(reader("valid\000"), 49)).to.beNil()
                expect(cards()._ReadChoice(reader("invalid\000"), 0)).to.beNil()
                expect(cards()._ReadChoice(reader(string.rep("c", 33) .. "\000"), 272)).to.beNil()
            end
        }
    }
}
