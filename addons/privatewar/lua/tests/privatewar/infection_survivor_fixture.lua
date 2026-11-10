-- The native retreat measurement starts after ordinary sight and brain admission, not an unrelated hunt.
local fixture = include("privatewar_fixtures/infection_survivor.lua") --[[@as PW.TestInfectionSurvivor]]

---@param threat Player
---@param visible boolean
---@return PW.BotContact
local function contact(threat, visible)
    return { ent = threat, visible = visible, pos = Vector(), vel = Vector(), time = 0, source = "sight" }
end

return {
    groupName = "PW Infection survivor native acquisition boundary",
    cases = {
        {
            name = "Survivor fixture: pre-perception hunt remembered or unrelated sight cannot arm retreat measurement",
            func = function()
                local bot = { EyeAngles = function() return Angle(0, 90, 0) end } --[[@as Player]]
                local threat = {} --[[@as Player]]
                local board = { bot = bot, behavior = { id = "hunt" }, contacts = {} } --[[@as PW.BotBoard]]
                local now, waits, held = 0, 0, nil
                stub(_G, "CurTime").with(function() return now end)
                stub(assert(PW.Bot), "Get").with(function(who) assert(who == bot) return board end)
                stub(assert(PW.BotInput), "SetScripted").with(function(who, intent)
                    assert(who == bot)
                    held = intent
                end)
                fixture.Acquire(bot, threat, function()
                    expect(held ~= nil and held.buttons == 0 and held.view.y == 90).to.beTrue()
                    now, waits = now + 0.1, waits + 1
                    if waits == 1 then board.contacts = { contact(threat, false) }
                    elseif waits == 2 then board.contacts = { contact({} --[[@as Player]], true) }
                    elseif waits == 3 then board.contacts = { contact(threat, true) }
                    elseif waits == 4 then board.behavior = { id = "pw_infection_escape" }
                    else error("native acquisition boundary did not release") end
                end)
                expect(waits).to.equal(4)
                expect(held).to.beNil()
                expect(board.contacts[1].ent).to.equal(threat)
            end
        },
        {
            name = "Survivor fixture: absent native sight fails bounded setup and releases neutral input",
            func = function()
                local bot = { EyeAngles = function() return Angle() end } --[[@as Player]]
                local now, waits, held = 0, 0, nil
                stub(_G, "CurTime").with(function() return now end)
                stub(assert(PW.Bot), "Get").returns({ behavior = { id = "hunt" }, contacts = {} })
                stub(assert(PW.BotInput), "SetScripted").with(function(_, intent) held = intent end)
                local ok, reason = pcall(fixture.Acquire, bot, {} --[[@as Player]], function()
                    now, waits = now + 1, waits + 1
                    assert(waits <= 4, "setup timeout was extended")
                end)
                expect(ok).to.beFalse()
                expect(string.find(tostring(reason), "native infected sight", 1, true) ~= nil).to.beTrue()
                expect(waits).to.equal(4)
                expect(held).to.beNil()
            end
        }
    }
}
