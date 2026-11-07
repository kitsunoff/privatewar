-- Vote module (T-2.13; 08-lobby.md d.5; 00-core.md d.2, d.5; 02-modes.md d.2, d.5b; docs/api/modes.md "Vote
-- module"). Shared and pure: candidate selection over the active playlist, the recent-maps list, casting, tally,
-- the early-end decision, the random tie break, the wire form of pw_vote_state and the model of the vote screen.
-- Server glue (sessions, messages, the PW_NextMatch answer): init.lua. The vote screen: cl_init.lua.
--
-- Messages (server module vote owns them):
--   pw_vote_cast     any human, VOTE: uint8 option index; a new vote replaces the previous one
--   pw_vote_pick     pw.vote.pick, VOTE: mode id, map -> the next match, the vote ends ("Pick myself")
--   pw_vote_request  any player, VOTE: the server answers with pw_vote_state
--   pw_vote_state    server -> client: PW.VoteState

MODULE.Name = "Vote"

MODULE.Settings = {
    options = { scope = "server", type = "int", default = 3, min = 1, max = 8, label = "Vote options" },
    allowrepeat = { scope = "server", type = "bool", default = false, label = "Offer the same map and mode again" }
}

local lib = (rawget(PW, "Vote") or {}) --[[@as PW.VoteLib]]
PW.Vote = lib

lib.Privilege = "pw.vote.pick"
lib.RecentCount = 2

-- The rule "exclude recent maps" switches itself off below this many maps in the playlist (08-lobby.md d.5).
local minMapsForRecent = 3

---@param name any
---@return boolean
local function validMap(name)
    return isstring(name) and #name > 0 and #name <= 64 and string.match(name, "^[%w_%-]+$") ~= nil
end

---The maps of the input the mode fits; each is also added to seen.
---@param input PW.VoteCandidateInput
---@param modeId string
---@param seen table<string, true>
---@return string[]
local function fittingMaps(input, modeId, seen)
    ---@type string[]
    local list = {}
    for _, map in ipairs(input.maps) do
        if input.fits == nil or input.fits(modeId, map) then
            list[#list + 1] = map
            seen[map] = true
        end
    end
    return list
end

---Every (mode, map) pair of the input that fits, by mode; and the number of distinct fitting maps.
---@param input PW.VoteCandidateInput
---@return table<string, string[]>
---@return integer
local function fittingPairs(input)
    ---@type table<string, string[]>
    local byMode = {}
    ---@type table<string, true>
    local maps = {}
    for modeId, weight in pairs(input.modes) do
        if isnumber(weight) and weight > 0 then byMode[modeId] = fittingMaps(input, modeId, maps) end
    end
    return byMode, table.Count(maps)
end

---Pair weights ("mode@map" -> weight): the mode's weight shared by its allowed maps, so modes keep their weights.
---@param input PW.VoteCandidateInput
---@param byMode table<string, string[]>
---@param blocked table<string, true> maps excluded as recent
---@param noRepeat boolean
---@return table<string, number>
local function pairWeights(input, byMode, blocked, noRepeat)
    local current = input.current
    ---@type table<string, number>
    local weights = {}
    for modeId, maps in pairs(byMode) do
        ---@type string[]
        local allowed = {}
        for _, map in ipairs(maps) do
            local repeated = current ~= nil and current.mode == modeId and current.map == map
            if not blocked[map] and not (noRepeat and repeated) then allowed[#allowed + 1] = map end
        end
        for _, map in ipairs(allowed) do weights[modeId .. "@" .. map] = input.modes[modeId] / #allowed end
    end
    return weights
end

function lib.Candidates(input)
    local byMode, mapCount = fittingPairs(input)
    ---@type table<string, true>
    local blocked = {}
    if mapCount >= minMapsForRecent then
        for index = 1, math.min(lib.RecentCount, #input.recent) do blocked[input.recent[index]] = true end
    end
    local noRepeat = not input.allowRepeat
    local weights = pairWeights(input, byMode, blocked, noRepeat)
    if next(weights) == nil then weights = pairWeights(input, byMode, {}, noRepeat) end
    if next(weights) == nil then weights = pairWeights(input, byMode, {}, false) end
    ---@type PW.VoteOption[]
    local options = {}
    while #options < input.count do
        local key = PW.Playlist.PickWeighted(weights, input.rng)
        if key == nil then break end
        weights[key] = nil
        local modeId, map = string.match(key, "^(.-)@(.+)$")
        options[#options + 1] = { mode = modeId, map = map }
    end
    return options
end

function lib.PushRecent(list, map)
    local out = { map }
    for _, name in ipairs(list) do
        if #out >= lib.RecentCount then break end
        if name ~= map then out[#out + 1] = name end
    end
    return out
end

function lib.FormatRecent(list)
    return table.concat(list, ",")
end

function lib.ParseRecent(text)
    ---@type string[]
    local list = {}
    for part in string.gmatch(text or "", "[^,]+") do
        local name = string.Trim(part)
        if validMap(name) and #list < lib.RecentCount then list[#list + 1] = name end
    end
    return list
end

function lib.NewSession(options)
    return { options = options, votes = {}, ended = false }
end

function lib.Cast(session, voter, isBot, index)
    if isBot then return false, "bot" end
    if session.ended then return false, "ended" end
    if not isnumber(index) or session.options[index] == nil then return false, "index" end
    session.votes[voter] = index
    return true
end

function lib.Tally(votes, count)
    ---@type integer[]
    local counts = {}
    for index = 1, count do counts[index] = 0 end
    for _, index in pairs(votes) do
        if counts[index] ~= nil then counts[index] = counts[index] + 1 end
    end
    return counts
end

function lib.Winner(counts, rng)
    local best = -1
    ---@type integer[]
    local tied = {}
    for index, votes in ipairs(counts) do
        if votes > best then
            best, tied = votes, { index }
        elseif votes == best then
            tied[#tied + 1] = index
        end
    end
    if #tied == 0 then return nil end
    return tied[math.min(#tied, math.floor(rng() * #tied) + 1)]
end

function lib.Humans(players)
    ---@type table[]
    local list = {}
    for _, ply in ipairs(players) do
        if not ply:IsBot() then list[#list + 1] = ply end
    end
    return list
end

function lib.AllVoted(humans, votes)
    if #humans == 0 then return false end
    for _, ply in ipairs(humans) do
        if votes[ply] == nil then return false end
    end
    return true
end

-- Wire format of pw_vote_state (DESIGN.md global rule 4: explicit writes, no net.WriteTable).
local countBits = 8

function lib._Encode(state, writer)
    local count = math.min(#state.options, 2 ^ countBits - 1)
    writer.uint(count, countBits)
    for index = 1, count do
        local option = state.options[index]
        writer.string(option.mode)
        writer.string(option.name)
        writer.string(option.map)
        writer.uint(math.Clamp(option.votes, 0, 2 ^ countBits - 1), countBits)
    end
    writer.uint(math.Clamp(state.mine, 0, count), countBits)
    writer.bool(state.canPick)
end

function lib._Decode(reader)
    ---@type PW.VoteStateOption[]
    local options = {}
    for index = 1, reader.uint(countBits) do
        local mode, name, map = reader.string(), reader.string(), reader.string()
        options[index] = { mode = mode, name = name, map = map, votes = reader.uint(countBits) }
    end
    local mine = reader.uint(countBits)
    return { options = options, mine = mine, canPick = reader.bool() }
end

function lib._Model(state, remaining)
    local title = "VOTE FOR THE NEXT MATCH"
    if remaining ~= nil then title = title .. "  " .. math.ceil(remaining) end
    ---@type PW.VoteRow[]
    local rows = {}
    for index, option in ipairs(state.options) do
        rows[index] = { index = index, label = option.name .. " on " .. option.map, votes = option.votes,
            mine = state.mine == index }
    end
    return { title = title, rows = rows, canPick = state.canPick }
end

-- Vote screen models (U-7).
if SERVER then AddCSLuaFile("privatewar/modules/vote/sh_cards.lua") end
include("privatewar/modules/vote/sh_cards.lua")
