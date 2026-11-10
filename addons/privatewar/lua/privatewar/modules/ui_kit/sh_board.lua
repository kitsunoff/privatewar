-- Shared visual model of the results table and the held in-match board. No engine or renderer dependency.
local lib = PW.UI --[[@as PW.UILib]]
local board = (rawget(lib, "Board") or {}) --[[@as PW.UIBoardLib]]
lib.Board = board

function board.Lines(sections)
    ---@type PW.UIBoardLine[]
    local lines = {}
    for _, section in ipairs(sections) do
        lines[#lines + 1] = {
            header = true, title = section.title, relation = section.relation, me = false, bot = false,
            score = section.score ~= nil and tostring(section.score) or "", place = "", kills = "", deaths = ""
        }
        for _, entry in ipairs(section.rows) do
            lines[#lines + 1] = {
                header = false, title = entry.name, relation = section.relation, me = entry.me, bot = entry.bot,
                score = not entry.spectator and tostring(entry.score) or "",
                place = not entry.spectator and tostring(entry.place or "") or "",
                kills = not entry.spectator and tostring(entry.kills) or "",
                deaths = not entry.spectator and tostring(entry.deaths) or ""
            }
        end
    end
    return lines
end

function board.Height(lines)
    local height = 36
    for index, line in ipairs(lines) do
        height = height + (line.header and (48 + (index > 1 and 12 or 0)) or 40)
    end
    return height
end

function board.Fit(text, width, measure)
    text = string.gsub(text, "[%c]", " ")
    if width <= 0 then return "" end
    if measure(text) <= width then return text end
    if measure("...") > width then return "" end
    ---@type number, number, string
    local low, high, best = 0, utf8.len(text) or 0, ""
    while low <= high do
        ---@type number
        local middle = math.floor((low + high) / 2)
        local candidate = utf8.sub(text, 1, middle) .. "..."
        if measure(candidate) <= width then
            best, low = candidate, middle + 1
        else
            high = middle - 1
        end
    end
    return best
end
