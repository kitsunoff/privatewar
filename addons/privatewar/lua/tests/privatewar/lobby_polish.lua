-- Lobby polish: mode monograms (MODE.Short; 10-frontend.md d.10) and the party bot count, which follows the bots
-- manager's quota (one slot stays free; 08-lobby.md d.4).

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UILib
local function kit() return must(PW.UI) end

---@param name string
---@return PW.UIPlayerInfo
local function player(name)
    return { name = name, bot = false, host = false }
end

local expectedShort = { tdm = "TDM", ffa = "FFA", dom = "DOM", kc = "KC" }

return {
    groupName = "PW lobby polish",
    cases = {
        {
            name = "The real modes carry Short and PW.UI.Monogram uses it",
            func = function()
                for id, short in pairs(expectedShort) do
                    local mode = must(PW.Modes.Get(id)) --[[@as PW.Mode]]
                    expect(mode.Short).to.equal(short)
                    expect(kit().Monogram({ Name = mode.Name, Short = mode.Short })).to.equal(short)
                end
            end
        },
        {
            name = "Party bots follow the manager quota: fill 12, 12 slots, 1 human gives +10",
            func = function()
                local party = must(kit().PlayerList({ player("solo") },
                    { phase = "LOBBY", maxPlayers = 12, botsFill = 12 })[1])
                expect(party.bots).to.equal(10)
                expect(party.botsText).to.equal("+10 bots")
            end
        },
        {
            name = "Party bots: fill below the cap counts as is, never negative",
            func = function()
                local humans = { player("a"), player("b"), player("c") }
                expect(must(kit().PlayerList(humans, { phase = "LOBBY", maxPlayers = 12, botsFill = 5 })[1]).bots)
                    .to.equal(2)
                expect(must(kit().PlayerList(humans, { phase = "LOBBY", maxPlayers = 12, botsFill = 2 })[1]).bots)
                    .to.equal(0)
            end
        },
        {
            name = "Party bots without the bots manager fall back to fill - humans",
            func = function()
                local saved = rawget(PW, "BotsManager")
                PW.BotsManager = nil
                local ok, party = pcall(kit().PlayerList, { player("solo") },
                    { phase = "LOBBY", maxPlayers = 12, botsFill = 12 })
                PW.BotsManager = saved
                assert(ok, tostring(party))
                expect(must(party[1]).bots).to.equal(11)
            end
        }
    }
}
