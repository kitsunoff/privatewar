-- Player list model (U-4; notes/16-frontend-d1-proposal.md §3 items 9-10, §4a/4b; 10-frontend.md d.9). Pure: plain
-- player records in, sections out. In LOBBY there is one PARTY section (teams are assigned when the match starts);
-- from PREMATCH on there is one section per active team, coloured relative to the local player. Humans are listed
-- host first, then by name; bots are collapsed to a "+N bots" row.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

---Host first, then by name (case-insensitive), then by the exact name so the order never depends on input order.
---@param a PW.UIPlayerInfo
---@param b PW.UIPlayerInfo
---@return boolean
local function before(a, b)
    if (a.host == true) ~= (b.host == true) then return a.host == true end
    local la, lb = string.lower(a.name), string.lower(b.name)
    if la ~= lb then return la < lb end
    return a.name < b.name
end

---@param bots integer
---@return string?
local function botsText(bots)
    if bots <= 0 then return nil end
    return string.format("+%d %s", bots, bots == 1 and "bot" or "bots")
end

---@param id string
---@param title string
---@param relation PW.UITeamRelation
---@param players PW.UIPlayerInfo[]
---@param accept fun(item: PW.UIPlayerInfo): boolean
---@return PW.UIPlayerSection
local function section(id, title, relation, players, accept)
    ---@type PW.UIPlayerInfo[]
    local rows = {}
    local bots = 0
    for _, item in ipairs(players) do
        if accept(item) then
            if item.bot then bots = bots + 1 else rows[#rows + 1] = item end
        end
    end
    table.sort(rows, before)
    return { id = id, title = title, relation = relation, rows = rows, humans = #rows, bots = bots }
end

---@param _ PW.UIPlayerInfo
---@return boolean
local function everyone(_)
    return true
end

---@param team integer
---@param localTeam? integer
---@return PW.UITeamRelation
local function relationOf(team, localTeam)
    if localTeam == nil then return "neutral" end
    return team == localTeam and "friendly" or "enemy"
end

---Bots the party will have: the bots manager's quota (one slot stays free), else fill - humans when the manager
---or the slot count is unknown.
---@param fill integer
---@param maxPlayers? integer
---@param humans integer
---@return integer
local function botsToFill(fill, maxPlayers, humans)
    local manager = rawget(PW, "BotsManager") --[[@as PW.BotsManagerLib?]]
    if manager == nil or maxPlayers == nil then return math.max(0, fill - humans) end
    return manager._Quota({ fill = fill, maxPlayers = maxPlayers, humans = humans })
end

---@param players PW.UIPlayerInfo[]
---@param opts PW.UIPlayerListOptions
---@return PW.UIPlayerSection
local function party(players, opts)
    local out = section("party", "PARTY", "neutral", players, everyone)
    out.capacity = opts.maxPlayers
    if opts.botsFill ~= nil then
        out.bots = math.max(out.bots, botsToFill(opts.botsFill, opts.maxPlayers, out.humans))
    end
    out.botsText = botsText(out.bots)
    return out
end

function lib.PlayerList(players, opts)
    if opts.phase == "LOBBY" then return { party(players, opts) } end
    local teams = opts.teams or {}
    if #teams == 0 then
        local all = section("players", "PLAYERS", "neutral", players, everyone)
        all.botsText = botsText(all.bots)
        return { all }
    end
    ---@type PW.UIPlayerSection[]
    local out = {}
    for _, team in ipairs(teams) do
        local id = team.id
        local item = section("team" .. id, team.name, relationOf(id, opts.localTeam), players,
            function(member) return member.team == id end)
        item.botsText = botsText(item.bots)
        out[#out + 1] = item
    end
    return out
end
