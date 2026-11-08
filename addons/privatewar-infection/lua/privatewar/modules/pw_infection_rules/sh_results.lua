-- Bounded terminal metadata. No live roster, engine entity, SteamID, target or position crosses this channel.
local lib = PW.InfectionPresentation --[[@as PW.InfectionPresentationLib]]

---@param value any
---@param max integer
---@return boolean
local function uint(value, max)
    return isnumber(value) and value >= 0 and value <= max and value == math.floor(value)
end

---@param incoming PW.InfectionResultChunk
---@return PW.InfectionResultChunk?
local function cleanChunk(incoming)
    if not uint(incoming.revision, 4294967295) or not isbool(incoming.active) then return nil end
    if not incoming.active then return { revision = incoming.revision, active = false, ownId = 0, rows = {} } end
    local total, offset = incoming.total, incoming.offset
    if total == nil or offset == nil or not uint(incoming.ownId, 4294967295) or not uint(total, 4096) or total < 1
        or not uint(offset, 4096) or #incoming.rows < 1 or #incoming.rows > 64
        or offset + #incoming.rows > total then return nil end
    local model = lib.Results(incoming.rows, incoming.ownId)
    if model == nil then return nil end
    return { revision = incoming.revision, active = true, ownId = incoming.ownId, total = incoming.total,
        offset = incoming.offset, rows = model.rows }
end

function lib.ResultChunk(current, incoming)
    local clean = cleanChunk(incoming)
    if clean == nil or (current ~= nil and clean.revision < current.revision) then return nil end
    if not clean.active then
        if current ~= nil and clean.revision <= current.revision then return nil end
        return { revision = clean.revision, active = false, ownId = 0, rows = {}, total = 0, seen = {} }, clean
    end
    local nextState = current
    if current == nil or clean.revision > current.revision then
        if clean.offset ~= 0 then return nil end
        nextState = { revision = clean.revision, active = true, ownId = clean.ownId,
            total = assert(clean.total), rows = {}, seen = {} }
    end
    local state = assert(nextState)
    if not state.active or state.total ~= clean.total or state.ownId ~= clean.ownId
        or #state.rows ~= clean.offset then return nil end
    local associated = state.ownId == 0 or state.seen[state.ownId] == true
    for _, row in ipairs(clean.rows) do
        if state.seen[row.id] then return nil end
        if row.id == state.ownId then associated = true end
    end
    local complete = #state.rows + #clean.rows == state.total
    if complete and not associated then return nil end
    for _, row in ipairs(clean.rows) do
        state.rows[#state.rows + 1], state.seen[row.id] = row, true
    end
    if not complete then return state end
    return state, { revision = state.revision, active = true, ownId = state.ownId, rows = state.rows }
end

function lib.EncodeResults(writer, incoming)
    local clean = cleanChunk(incoming)
    if clean == nil then return false end
    writer.uint(clean.revision, 32)
    writer.bool(clean.active)
    if not clean.active then return true end
    writer.uint(clean.ownId, 32)
    writer.uint(assert(clean.total), 13)
    writer.uint(assert(clean.offset), 13)
    writer.uint(#clean.rows, 7)
    for _, row in ipairs(clean.rows) do
        writer.uint(row.id, 32)
        writer.string(row.name)
        writer.bool(row.bot == true)
        writer.uint(row.wins, 8)
        writer.uint(row.infections or 0, 16)
        writer.uint(row.kills or 0, 16)
        writer.uint(row.deaths or 0, 16)
    end
    return true
end

function lib.DecodeResults(reader)
    ---@type PW.InfectionResultChunk
    local incoming = { revision = reader.uint(32), active = reader.bool(), ownId = 0, rows = {} }
    if not incoming.active then return incoming end
    incoming.ownId, incoming.total, incoming.offset = reader.uint(32), reader.uint(13), reader.uint(13)
    local count = reader.uint(7)
    for _ = 1, count do
        incoming.rows[#incoming.rows + 1] = { id = reader.uint(32), name = reader.string(), bot = reader.bool(),
            wins = reader.uint(8), infections = reader.uint(16), kills = reader.uint(16), deaths = reader.uint(16) }
    end
    return incoming
end

function lib.ApplyPostmatch(data, terminal, _)
    if not terminal.active then return end
    local ui = PW.UI
    local pm = ui ~= nil and ui.Postmatch or nil
    local model = lib.Results(terminal.rows, terminal.ownId)
    if pm == nil or model == nil then return end
    ---@type PW.UIBoardRow[]
    local rows = {}
    for _, row in ipairs(model.rows) do
        rows[#rows + 1] = { id = row.id, name = row.name, team = 0, kills = row.kills or 0, deaths = row.deaths or 0,
            score = row.wins, bot = row.bot == true, me = row.id == terminal.ownId, place = row.place }
    end
    ---@type PW.UIPostmatchKind
    local kind = "over"
    if model.place ~= nil then
        kind = model.draw and "draw" or (model.winner == terminal.ownId and "victory" or "defeat")
    end
    data.result = { kind = kind, title = pm.Titles[kind], token = pm.Tokens[kind], placement = model.place,
        subtitle = model.place ~= nil and (pm.Ordinal(model.place) .. " OF " .. #rows) or "" }
    data.sections = { { id = 0, title = "PERSONAL ROUND WINS", relation = "neutral", rows = rows } }
    data.scoreLabel = "ROUND WINS"
end
