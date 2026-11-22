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

---@class PW.CardTestActor
---@field Nick fun(): string
---@field IsBot fun(): boolean
---@field GetNW2String fun(self: table, key: string): string
---@field SetNW2String fun(self: table, key: string, value: string)

---@param name string
---@param bot boolean
---@param initial? string
---@return Player, { value: string, writes: integer }
local function actor(name, bot, initial)
    local nw = { value = initial or "", writes = 0 }
    ---@type PW.CardTestActor
    local entity = {
        Nick = function() return name end,
        IsBot = function() return bot end,
        GetNW2String = function(_, key)
            assert(key == "pw_card", "unexpected card key")
            return nw.value
        end,
        SetNW2String = function(_, key, value)
            assert(key == "pw_card", "unexpected card key")
            nw.value, nw.writes = value, nw.writes + 1
        end
    }
    return entity --[[@as Player]], nw
end

---@class PW.CardServerFixture
---@field locked boolean
---@field enemy boolean
---@field phase string
---@field sends { channel: string, to: Player, state: PW.KillCardState }[]
---@field rolls integer

---@return PW.CallingCardsStore, PW.CardServerFixture
local function serverFixture()
    ---@type PW.CardServerFixture
    local facts = { locked = false, enemy = true, phase = "LIVE", sends = {}, rolls = 0 }
    local lib = cards()
    local known = { IsValid = function() return true end }
    local store = assert(lib._NewStore, "calling card server store not loaded")({
        find = function(id) return (id == "level_20" or id == "bomb") and known --[[@as PW.CallingCard]] or nil end,
        enabledIds = function() return { "bomb", "level_20" } end,
        unlocked = function() return not facts.locked end,
        phase = function() return facts.phase end,
        isPlayer = function(entity)
            return istable(entity) and isfunction(rawget(entity --[[@as table]], "IsBot"))
        end,
        isEnemy = function() return facts.enemy end,
        rng = function()
            facts.rolls = facts.rolls + 1
            return facts.rolls == 1 and 0 or 0.9
        end,
        send = function(channel, killer, state)
            facts.sends[#facts.sends + 1] = { channel = channel, to = killer, state = state }
        end
    })
    return store, facts
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
        },
        {
            name = "Spawn re-check falls back when the card became locked",
            func = function()
                local lib = cards()
                local human, nw = actor("Human", false)
                local store, facts = serverFixture()
                local request, spawn = assert(lib._OnChoice), assert(lib._OnSpawn)
                request(store, human, "level_20")
                expect(nw.value).to.equal("level_20")
                facts.locked = true
                spawn(store, human)
                expect(nw.value).to.equal("default")
            end
        },
        {
            name = "Choice publishes pw_card only on change",
            func = function()
                local lib = cards()
                local ply, nw = actor("Human", false)
                local store = serverFixture()
                local request, spawn = assert(lib._OnChoice), assert(lib._OnSpawn)
                request(store, ply, "level_20")
                expect(nw.writes).to.equal(1)
                expect(nw.value).to.equal("level_20")
                request(store, ply, "level_20")
                request(store, ply, "level_20\000junk")
                spawn(store, ply)
                expect(nw.writes).to.equal(1)
                request(store, ply, "")
                spawn(store, ply)
                expect(nw.writes).to.equal(2)
                expect(nw.value).to.equal("default")
            end
        },
        {
            name = "Bot picks once across spawns and cannot send a choice",
            func = function()
                local lib = cards()
                local bot, nw = actor("Bot", true)
                local store, facts = serverFixture()
                local request, spawn = assert(lib._OnChoice), assert(lib._OnSpawn)
                facts.locked = true
                request(store, bot, "level_20")
                expect(nw.writes).to.equal(0)
                spawn(store, bot)
                spawn(store, bot)
                expect(nw.value).to.equal("bomb")
                expect(nw.writes).to.equal(1)
                expect(facts.rolls).to.equal(1)
            end
        },
        {
            name = "Kill sends pw_kill_card to a human attacker only, with the victim name and card",
            func = function()
                local lib = cards()
                local store, facts = serverFixture()
                local victim = actor("Bot victim", true, "level_20")
                local killer = actor("Human killer", false, "default")
                assert(lib._OnKill)(store, victim, killer)
                expect(#facts.sends).to.equal(1)
                local send = facts.sends[1]
                expect(send.channel).to.equal("pw_kill_card")
                expect(send.to).to.equal(killer)
                expect(send.state.name).to.equal("Bot victim")
                expect(send.state.card).to.equal("level_20")
                expect(send.state.bot).to.beTrue()
            end
        },
        {
            name = "No pw_kill_card for suicide, world kill, bot attacker or outside LIVE",
            func = function()
                local lib = cards()
                local store, facts = serverFixture()
                local bot, human = actor("Bot", true), actor("Human", false)
                local kill = assert(lib._OnKill)
                kill(store, human, human)
                kill(store, human, game.GetWorld())
                kill(store, human, bot)
                kill(store, human, {} --[[@as Entity]])
                facts.phase = "POSTMATCH"
                kill(store, bot, human)
                expect(#facts.sends).to.equal(0)
            end
        },
        {
            name = "Team kills do not send a card banner",
            func = function()
                local store, facts = serverFixture()
                facts.enemy = false
                local victim, killer = actor("Victim", false), actor("Killer", false)
                assert(cards()._OnKill)(store, victim, killer)
                expect(#facts.sends).to.equal(0)
            end
        },
        {
            name = "pw_card_choice over maxLen or above the rate limit is dropped",
            func = function()
                local def = assert(PW._Net.defs.pw_card_choice, "pw_card_choice receiver is missing")
                local wrapper = assert(PW.Net)
                expect(def.who).to.equal("any")
                expect(def.rate).to.equal(2)
                expect(def.maxLen).to.equal(34)
                local owner = assert(PW.Modules.GetStored("calling_cards"), "the registered owner is missing")
                expect(def.owner).to.equal(owner)
                expect(IsValid(owner)).to.beTrue()
                local facts = { active = true, allowed = true, phase = "LIVE", len = 273 }
                local why = wrapper._Decide(def, facts, nil, 100)
                expect(why).to.equal("length")
                facts.len = 8
                local first, bucket = wrapper._Decide(def, facts, nil, 100)
                local second, empty = wrapper._Decide(def, facts, bucket, 100)
                local third = wrapper._Decide(def, facts, empty, 100)
                expect(first).to.beNil()
                expect(second).to.beNil()
                expect(third).to.equal("rate")
            end
        },
        {
            name = "Calling cards wire the live spawn and kill hooks to their module owner",
            func = function()
                local module = assert(PW.Modules.Get("calling_cards"))
                local hooks = hook.GetTable() --[[@as table<string, table<any, function>>]]
                expect(isfunction(hooks.PlayerSpawn and hooks.PlayerSpawn[module])).to.beTrue()
                expect(isfunction(hooks.PW_PlayerKilled and hooks.PW_PlayerKilled[module])).to.beTrue()
                expect(util.NetworkStringToID("pw_kill_card") > 0).to.beTrue()
                local playerTable = {
                    IsValid = function() return true end,
                    IsPlayer = function() return true end
                }
                local admission = assert(cards()._Store).io.isPlayer
                expect(admission(playerTable --[[@as Entity]])).to.beFalse()
                expect(admission(game.GetWorld())).to.beFalse()
            end
        }
    }
}
