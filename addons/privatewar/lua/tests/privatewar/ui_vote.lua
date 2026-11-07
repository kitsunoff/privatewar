-- U-7 Vote restyle (TASKS.md, "Mandatory test cases" U-7, T-7.7; notes/16-frontend-d1-proposal.md §4d; 10-frontend.md
-- VOTE). Pure models of the vote screen (PW.Vote._Cards, _Turnout, _Timer, _Screen in vote/sh_cards.lua): one card
-- per option with the own vote marked, the turnout, the timer text and the "Pick myself" action that canPick hides.
-- The drawing and the keys on the real screen are checkpoint items; the existing vote.lua cases cover the rules.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.VoteLib
local function lib()
    return must(PW.Vote)
end

---@param overrides? table<string, any>
---@return PW.VoteState
local function sampleState(overrides)
    ---@type table<string, any>
    local state = {
        options = {
            { mode = "tdm", name = "Team Deathmatch", map = "gm_a", votes = 2 },
            { mode = "ffa", name = "Free for all", map = "gm_b", votes = 1 },
            { mode = "dom", name = "Domination", map = "gm_c", votes = 0 }
        },
        mine = 2, canPick = true
    }
    for key, value in pairs(overrides or {}) do state[key] = value end
    return state
end

---@param id string
---@return string?
local function shortOf(id)
    return id == "tdm" and "TDM" or nil
end

return {
    groupName = "PW ui vote",
    cases = {
        {
            name = "The card model has one card per option with the votes and the own vote marked",
            func = function()
                local cards = lib()._Cards(sampleState(), { shortOf = shortOf })
                expect(#cards).to.equal(3)
                expect(cards[1].modeName).to.equal("Team Deathmatch")
                expect(cards[1].map).to.equal("gm_a")
                expect(cards[1].badge).to.equal("TDM")
                expect(cards[2].badge).to.equal("FFA")
                expect(cards[3].badge).to.equal("D")
                expect({ cards[1].votes, cards[2].votes, cards[3].votes }).to.deepEqual({ 2, 1, 0 })
                expect({ cards[1].mine, cards[2].mine, cards[3].mine }).to.deepEqual({ false, true, false })
                expect({ cards[1].index, cards[3].index }).to.deepEqual({ 1, 3 })
                expect(cards[1].thumb).to.equal("maps/thumb/gm_a.png")
            end
        },
        {
            name = "No own vote marks no card",
            func = function()
                local cards = lib()._Cards(sampleState({ mine = 0 }), {})
                for _, card in ipairs(cards) do expect(card.mine).to.beFalse() end
            end
        },
        {
            name = "The turnout counts the votes against the humans",
            func = function()
                local turnout = lib()._Turnout(sampleState(), 4)
                expect({ turnout.voted, turnout.total }).to.deepEqual({ 3, 4 })
                expect(turnout.text).to.equal("3/4 voted")
                expect(lib()._Turnout(sampleState({ options = {} }), 1).text).to.equal("0/1 voted")
                expect(lib()._Turnout(sampleState(), 2).voted).to.equal(3)
            end
        },
        {
            name = "The timer is minutes and seconds, and warns in the last 10 seconds",
            func = function()
                expect(lib()._Timer(65).text).to.equal("1:05")
                expect(lib()._Timer(65).warning).to.beFalse()
                expect(lib()._Timer(10).warning).to.beTrue()
                expect(lib()._Timer(11).warning).to.beFalse()
                expect(lib()._Timer(9.2).text).to.equal("0:10")
                expect(lib()._Timer(0).text).to.equal("0:00")
                expect(lib()._Timer(-3).text).to.equal("0:00")
                expect(lib()._Timer(nil).text).to.equal("")
                expect(lib()._Timer(nil).warning).to.beFalse()
            end
        },
        {
            name = "canPick hides the Pick myself action and its hint",
            func = function()
                local allowed = lib()._Screen(sampleState(), { remaining = 30, humans = 2 })
                expect(allowed.pick.visible).to.beTrue()
                local hinted = false
                for _, hint in ipairs(allowed.hints) do hinted = hinted or hint.action == "secondary" end
                expect(hinted).to.beTrue()
                local denied = lib()._Screen(sampleState({ canPick = false }), { remaining = 30, humans = 2 })
                expect(denied.pick.visible).to.beFalse()
                for _, hint in ipairs(denied.hints) do expect(hint.action).toNot.equal("secondary") end
                local noMaps = lib()._Screen(sampleState(), { remaining = 30, humans = 2, pickReady = false })
                expect(noMaps.pick.visible).to.beFalse()
            end
        },
        {
            name = "The screen model joins the cards, the turnout and the timer",
            func = function()
                local screen = lib()._Screen(sampleState(), { remaining = 8, humans = 3 })
                expect(#screen.cards).to.equal(3)
                expect(screen.turnout.text).to.equal("3/3 voted")
                expect(screen.timer.text).to.equal("0:08")
                expect(screen.timer.warning).to.beTrue()
                expect(screen.title).to.equal("VOTE FOR THE NEXT MATCH")
            end
        }
    }
}
