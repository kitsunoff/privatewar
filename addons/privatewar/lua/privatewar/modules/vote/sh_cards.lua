-- Vote screen models (U-7, T-7.7; notes/16-frontend-d1-proposal.md §4d; 10-frontend.md VOTE). Shared and pure: the
-- cards (one per option, the own vote marked), the turnout, the timer text and the whole screen model with the
-- "Pick myself" action (hidden without canPick). Drawing: cl_init.lua and ui_kit PWVoteCard.

local lib = PW.Vote --[[@as PW.VoteLib]]

local warningSeconds = 10

---@param mode string
---@param name string
---@param shortOf? fun(id: string): string?
---@return string
local function badgeOf(mode, name, shortOf)
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    if kit == nil or kit.Monogram == nil then return "?" end
    return kit.Monogram({ Name = name, Short = shortOf ~= nil and shortOf(mode) or nil })
end

---@param map string
---@return string?
local function thumbOf(map)
    local lobby = rawget(PW, "Lobby") --[[@as PW.LobbyLib?]]
    if lobby == nil or lobby._ThumbPath == nil then return nil end
    return lobby._ThumbPath(map)
end

function lib._Cards(state, opts)
    ---@type PW.VoteCard[]
    local cards = {}
    for index, option in ipairs(state.options) do
        cards[index] = {
            index = index, mode = option.mode, modeName = option.name, map = option.map, votes = option.votes,
            badge = badgeOf(option.mode, option.name, opts.shortOf), thumb = thumbOf(option.map),
            mine = state.mine == index
        }
    end
    return cards
end

function lib._Turnout(state, humans)
    ---@type integer
    local voted = 0
    for _, option in ipairs(state.options) do voted = voted + option.votes end
    ---@type string
    local text = string.format("%d/%d voted", voted, humans)
    ---@type PW.VoteTurnout
    local turnout = { voted = voted, total = humans, text = text }
    return turnout
end

function lib._Timer(remaining)
    if remaining == nil then return { text = "", warning = false } end
    local kit = rawget(PW, "UI") --[[@as PW.UILib]]
    return { text = kit.FormatTime(remaining), warning = math.ceil(remaining) <= warningSeconds }
end

function lib._Screen(state, opts)
    local visible = state.canPick and opts.pickReady ~= false
    ---@type PW.UIHintEntry[]
    local hints = { { action = "left", label = "Previous" }, { action = "right", label = "Next" },
        { action = "accept", label = "Vote" } }
    if visible then hints[#hints + 1] = { action = "secondary", label = "Pick myself" } end
    return {
        title = "VOTE FOR THE NEXT MATCH", cards = lib._Cards(state, opts),
        turnout = lib._Turnout(state, opts.humans or 0), timer = lib._Timer(opts.remaining),
        pick = { visible = visible, label = "PICK MYSELF" }, hints = hints
    }
end
