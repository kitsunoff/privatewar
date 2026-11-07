-- Pure rules of the Domination points element (T-6.5; 09-hud.md d.2): what one flag looks like to the local team,
-- the order of the letters and when the element is visible at all. Shared plain data in and out, so the server-side
-- test runner covers it; the drawing is hud/dom.lua. Loaded by shared.lua through include.
--
-- Input is only what every client already has: the flag's network vars (letter, owner, capture scalar, contested)
-- and the local team. A frame allocates nothing: _Display fills a table the caller reuses.

local lib = PW.DomFlags --[[@as PW.DomFlagsLib]]

-- Design units (1920x1080), top centre (the match status moved to the top left under the radar in T-11.5).
lib.Hud = {
    top = 100,
    tile = 56,
    gap = 12,
    bar = 6
}

---@param team integer the team the flag value leans to (1 or 2)
---@param viewer integer the local team
---@return "friendly"|"enemy"
local function relationOf(team, viewer)
    -- A local team outside 1..2 (spectator, unassigned) reads team 1 as friendly.
    local mine = (viewer == 1 or viewer == 2) and viewer or 1
    return team == mine and "friendly" or "enemy"
end

local tokens = { friendly = "team_friendly", enemy = "team_enemy", neutral = "text_muted", none = "text_muted" }

function lib._NewDisplay(letter)
    return {
        letter = letter or "", relation = "neutral", token = tokens.neutral, lean = "none", leanToken = tokens.none,
        progress = 0, capturing = false, contested = false
    }
end

function lib._Visible(flagCount)
    return flagCount > 0
end

function lib._Display(flag, team, out)
    out.letter = flag.letter
    out.relation = flag.owner > 0 and relationOf(flag.owner, team) or "neutral"
    out.token = tokens[out.relation]
    local value = flag.value
    out.lean = value == 0 and "none" or relationOf(value > 0 and 1 or 2, team)
    out.leanToken = tokens[out.lean]
    out.progress = math.min(1, math.abs(value) / 100)
    -- Settled: the owner's side at its end, or untouched. Anything else is a capture in flux.
    local settled = value == 0 or (out.progress >= 1 and (value > 0 and 1 or 2) == flag.owner)
    out.capturing = not settled
    out.contested = flag.contested == true
end

function lib._OrderDisplays(list, count)
    for i = 2, count do
        local item = list[i] --[[@as PW.DomFlagDisplay]]
        local at = i
        while at > 1 and (list[at - 1] --[[@as PW.DomFlagDisplay]]).letter > item.letter do
            list[at] = list[at - 1]
            at = at - 1
        end
        list[at] = item
    end
end
