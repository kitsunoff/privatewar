-- Server-only copied public final data; late viewers receive the same generation, never live entity references.
local lib = PW.Infection --[[@as PW.InfectionLib]]
local presentation = PW.InfectionPresentation --[[@as PW.InfectionPresentationLib]]
local writer = { uint = net.WriteUInt, bool = net.WriteBool, float = net.WriteFloat, string = net.WriteString }
util.AddNetworkString("pw_infection_results")

---@param value number
---@return integer
local function counter(value) return math.Clamp(math.floor(value), 0, 65535) end

function lib.CaptureResultMetadata(ply)
    local s = lib.State
    if s == nil or not IsValid(ply) then return end
    local id = s.identities[ply]
    if id == nil then return end
    if s.deathBaselines[id] == nil then s.deathBaselines[id] = ply:Deaths() end
    local name = ply:Nick()
    if #name > 256 then name = "Player " .. ply:UserID() end -- no UTF-8 byte splitting
    s.metadata[id] = { id = ply:UserID(), name = name, bot = ply:IsBot(), wins = 0,
        infections = counter(s.infections[id] or 0),
        kills = counter(PW.MatchRules ~= nil and PW.MatchRules.GetKills(ply) or 0),
        deaths = counter(ply:Deaths() - s.deathBaselines[id]) }
end

---@param ply Player
---@param chunk PW.InfectionResultChunk
local function send(ply, chunk)
    net.Start("pw_infection_results")
    assert(presentation.EncodeResults(writer, chunk), "invalid server Infection results")
    net.Send(ply)
end

function lib.SendResults(ply)
    local cache = lib.ResultCache
    if cache == nil then
        send(ply, { revision = lib.ResultRevision or 0, active = false, ownId = 0, rows = {} })
        return
    end
    local ownId = cache.identities[lib.Identity(ply)] or 0
    for offset = 0, #cache.rows - 1, 64 do
        ---@type PW.InfectionResultRow[]
        local rows = {}
        for index = offset + 1, math.min(offset + 64, #cache.rows) do rows[#rows + 1] = cache.rows[index] end
        send(ply, { revision = cache.revision, active = true, ownId = ownId,
            total = #cache.rows, offset = offset, rows = rows })
    end
end

function lib.ResetResults()
    lib.ResultRevision = (lib.ResultRevision or 0) + 1
    lib.ResultCache = nil
    for _, ply in ipairs(player.GetHumans()) do lib.SendResults(ply) end
end

function lib.PublishResults(summary)
    local s = assert(lib.State)
    for _, ply in pairs(s.history) do lib.CaptureResultMetadata(ply) end
    ---@type PW.InfectionResultRow[]
    local rows = {}
    ---@type table<string, integer>
    local identities = {}
    for _, row in ipairs(summary.standings) do
        local metadata = assert(s.metadata[row.id], "missing admitted participant metadata")
        identities[row.id] = metadata.id
        rows[#rows + 1] = { id = metadata.id, name = metadata.name, bot = metadata.bot, wins = row.score,
            infections = metadata.infections, kills = metadata.kills, deaths = metadata.deaths }
    end
    lib.ResultRevision = (lib.ResultRevision or 0) + 1
    lib.ResultCache = { revision = lib.ResultRevision, rows = rows, identities = identities }
    for _, ply in ipairs(player.GetHumans()) do lib.SendResults(ply) end
end
