-- Held in-match board: policy, public-data projection and geometry; no entity, net or drawing calls.
local lib = PW.UI --[[@as PW.UILib]]
local sb = (rawget(lib, "Scoreboard") or {}) --[[@as PW.UIScoreboardLib]]
lib.Scoreboard = sb

local moduleTable = rawget(_G, "MODULE")
if moduleTable ~= nil then
    moduleTable.Settings = moduleTable.Settings or {}
    moduleTable.Settings.scoreboard = {
        scope = "client", type = "bool", default = true, label = "In-match scoreboard in the results style"
    }
end

function sb.Allowed(facts)
    return facts.phase == "LIVE" and facts.enabled and facts.playerValid and facts.focused and not facts.gameUI
        and (facts.rootId == nil or facts.rootId == "class")
end

---@param row PW.UIBoardRow
---@return PW.UIBoardRow
local function publicRow(row)
    return { id = row.id, name = row.name, team = row.team, kills = row.kills, deaths = row.deaths,
        score = row.score, bot = row.bot, me = row.me, spectator = row.spectator }
end

function sb.Sections(rows, opts)
    ---@type PW.UIBoardRow[], PW.UIBoardRow[]
    local active, observers = {}, {}
    for _, row in ipairs(rows) do
        local copy = publicRow(row)
        if copy.spectator or (opts.teams > 0 and (copy.team < 1 or copy.team > opts.teams)) then
            copy.spectator = true
            observers[#observers + 1] = copy
        else
            active[#active + 1] = copy
        end
    end
    local sections = assert(lib.Postmatch).Board(active, opts)
    for index, section in ipairs(sections) do
        if section.id == opts.ownTeam and index > 1 then
            table.insert(sections, 1, table.remove(sections, index))
            break
        end
    end
    if #observers > 0 then
        table.sort(observers, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
        sections[#sections + 1] = { id = -1, title = "SPECTATORS", relation = "neutral", rows = observers }
    end
    return sections
end

function sb.Layout(width, height, scale)
    local margin = 64 * scale
    local w = math.min(1600 * scale, width - 2 * margin)
    local h = height - 2 * margin
    return { x = (width - w) / 2, y = margin, w = w, h = h, boardY = 112 * scale,
        boardH = h - (112 + 64) * scale }
end

function sb.Scroll(code, viewport, scale)
    if code == KEY_DOWN or code == KEY_XBUTTON_DOWN then return 120 * scale end
    if code == KEY_UP or code == KEY_XBUTTON_UP then return -120 * scale end
    if code == KEY_PAGEDOWN then return viewport end
    if code == KEY_PAGEUP then return -viewport end
    return nil
end
