-- T-6.5 Domination points element (09-hud.md d.2: the points A, B, C with the owner colour, drawn by the mode's own
-- element). Pure cases over plain data: the display state of a flag (owner and lean relative to the local team,
-- progress, capturing, contested, token colours), the ordering by letter, the visibility rule (only in Domination,
-- that is while flags exist) and the contested rule the mode publishes. The drawing is a manual check.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.DomFlagsLib
local function flags()
    return must(PW.DomFlags)
end

---@param a number
---@param b number
---@return boolean
local function near(a, b)
    return math.abs(a - b) < 1e-6
end

---@param letter string
---@param value number
---@param owner integer
---@param contested? boolean
---@return PW.DomFlagView
local function flag(letter, value, owner, contested)
    return { letter = letter, value = value, owner = owner, contested = contested == true }
end

---@param view PW.DomFlagView
---@param team integer
---@return PW.DomFlagDisplay
local function show(view, team)
    local out = flags()._NewDisplay()
    flags()._Display(view, team, out)
    return out
end

return {
    groupName = "PW HUD domination points",
    cases = {
        {
            name = "The dom element is registered, drawn in LIVE only and only while flags exist",
            func = function()
                local element = must(must(PW.Registries["hud"]).Get("dom")) --[[@as PW.HudElement]]
                expect(must(element.Phases)[1]).to.equal("LIVE")
                expect(#must(element.Phases)).to.equal(1)
                expect(isfunction(element.ShouldDraw)).to.beTrue()
            end
        },
        {
            name = "Visibility: shown only in Domination (flags exist), hidden in every other mode",
            func = function()
                expect(flags()._Visible(0)).to.beFalse()
                expect(flags()._Visible(1)).to.beTrue()
                expect(flags()._Visible(3)).to.beTrue()
            end
        },
        {
            name = "Owned by the local team: friendly relation and the friendly colour token, settled",
            func = function()
                local d = show(flag("A", 100, 1), 1)
                expect(d.relation).to.equal("friendly")
                expect(d.token).to.equal("team_friendly")
                expect(d.lean).to.equal("friendly")
                expect(near(d.progress, 1)).to.beTrue()
                expect(d.capturing).to.beFalse()
                expect(d.contested).to.beFalse()
                expect(d.letter).to.equal("A")
            end
        },
        {
            name = "Owned by the enemy: enemy relation and the enemy colour token",
            func = function()
                local d = show(flag("B", -100, 2), 1)
                expect(d.relation).to.equal("enemy")
                expect(d.token).to.equal("team_enemy")
                expect(d.lean).to.equal("enemy")
                expect(d.capturing).to.beFalse()
            end
        },
        {
            name = "Neutral: nobody owns it, muted token, no progress, not capturing",
            func = function()
                local d = show(flag("C", 0, 0), 1)
                expect(d.relation).to.equal("neutral")
                expect(d.token).to.equal("text_muted")
                expect(d.lean).to.equal("none")
                expect(near(d.progress, 0)).to.beTrue()
                expect(d.capturing).to.beFalse()
            end
        },
        {
            name = "The colour follows the local team: the same flag is friendly for team 2 and enemy for team 1",
            func = function()
                local held = flag("A", -100, 2)
                expect(show(held, 1).token).to.equal("team_enemy")
                expect(show(held, 2).token).to.equal("team_friendly")
                expect(show(held, 2).relation).to.equal("friendly")
            end
        },
        {
            name = "Capturing: a neutral flag leaning to a team shows progress in that team's colour",
            func = function()
                local mine = show(flag("A", 40, 0), 1)
                expect(mine.capturing).to.beTrue()
                expect(near(mine.progress, 0.4)).to.beTrue()
                expect(mine.lean).to.equal("friendly")
                expect(mine.leanToken).to.equal("team_friendly")
                expect(mine.relation).to.equal("neutral")
                local theirs = show(flag("A", 40, 0), 2)
                expect(theirs.lean).to.equal("enemy")
                expect(theirs.leanToken).to.equal("team_enemy")
            end
        },
        {
            name = "Capturing: an owned flag taken away keeps its owner colour until the owner changes",
            func = function()
                local d = show(flag("B", -30, 1), 1)
                expect(d.relation).to.equal("friendly")
                expect(d.lean).to.equal("enemy")
                expect(d.capturing).to.beTrue()
                expect(near(d.progress, 0.3)).to.beTrue()
                expect(show(flag("B", 60, 1), 1).capturing).to.beTrue()
            end
        },
        {
            name = "Contested: the published flag shows the contested state, even at rest in progress",
            func = function()
                local d = show(flag("A", 55, 0, true), 1)
                expect(d.contested).to.beTrue()
                expect(show(flag("A", 55, 0, false), 1).contested).to.beFalse()
            end
        },
        {
            name = "Progress is clamped to 0..1 and a local team outside 1..2 reads team 1 as friendly",
            func = function()
                expect(near(show(flag("A", 250, 1), 1).progress, 1)).to.beTrue()
                expect(near(show(flag("A", -250, 2), 1).progress, 1)).to.beTrue()
                expect(show(flag("A", 100, 1), 0).relation).to.equal("friendly")
                expect(show(flag("A", 100, 2), 0).relation).to.equal("enemy")
            end
        },
        {
            name = "Ordering: displays are sorted by letter, in place, keeping every entry",
            func = function()
                local list = { flags()._NewDisplay("C"), flags()._NewDisplay("A"), flags()._NewDisplay("B") }
                flags()._OrderDisplays(list, 3)
                expect(must(list[1]).letter).to.equal("A")
                expect(must(list[2]).letter).to.equal("B")
                expect(must(list[3]).letter).to.equal("C")
                -- Only the first count entries are sorted.
                local partial = { flags()._NewDisplay("B"), flags()._NewDisplay("A"), flags()._NewDisplay("0") }
                flags()._OrderDisplays(partial, 2)
                expect(must(partial[1]).letter).to.equal("A")
                expect(must(partial[3]).letter).to.equal("0")
            end
        },
        {
            name = "Contested rule of the mode: both teams inside with equal counts; one-sided or empty is not",
            func = function()
                local contested = must((must(PW.Modes.Get("dom")) --[[@as PW.DomMode]])._Contested)
                expect(contested(1, 1)).to.beTrue()
                expect(contested(2, 2)).to.beTrue()
                expect(contested(2, 1)).to.beFalse()
                expect(contested(1, 0)).to.beFalse()
                expect(contested(0, 0)).to.beFalse()
            end
        }
    }
}
