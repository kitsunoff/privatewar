-- Bots objectives, server glue (T-5.10): reads the engine into the plain facts the objective and roam behaviours use
-- (PW.BotObjectives.Gather) and records deaths for the hunt hot spots. Shared per server tick and team: the mode's
-- objectives (MODE:BotObjectives through PW.Call, else the fallback from flags or tags) and the alive players. Per
-- bot: its position and a few random navmesh points. No ents.Find*: flags and tags come from their modules' lists.
--
-- Decisions of the lane agent (to confirm):
--   7. Roam candidates: 6 random points of random navmesh areas (PW.Map.GetNavAreas) per gather, at least 48 x 48
--      units, so roaming covers the whole map over time without a precomputed table.
--   8. Deaths: every player death is recorded with the victim's team; a bot sees only its own team's deaths
--      (DeathMemory, 45 s). In FFA (no team) no deaths are used.

local lib = PW.BotObjectives --[[@as PW.BotObjectivesLib]]

local candidateCount, minArea = 6, 48

---@class PW.BotObjectivesCache
---@field at number
---@field players { pos: Vector, team: integer, ent: Player }[]
---@field objectives table<integer, PW.BotObjective[]>

---@type PW.BotObjectivesCache
local cache = { at = -1, players = {}, objectives = {} }

---@param now number
local function refresh(now)
    if cache.at == now then return end
    cache.at, cache.objectives = now, {}
    ---@type { pos: Vector, team: integer, ent: Player }[]
    local list = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then list[#list + 1] = { pos = ply:GetPos(), team = ply:Team(), ent = ply } end
    end
    cache.players = list
end

---@return PW.BotFlagInfo[]
local function flagInfos()
    local module = rawget(PW, "DomFlags") --[[@as PW.DomFlagsLib?]]
    ---@type PW.BotFlagInfo[]
    local out = {}
    if module == nil then return out end
    for _, flag in ipairs(module.GetAll()) do
        if IsValid(flag) then
            out[#out + 1] = { letter = flag:GetLetter(), pos = flag:GetPos(), owner = flag:GetOwnerTeam(),
                value = flag:GetValue() }
        end
    end
    return out
end

---@return PW.BotTagInfo[]
local function tagInfos()
    local module = rawget(PW, "KCTags") --[[@as PW.KCTagsLib?]]
    ---@type PW.BotTagInfo[]
    local out = {}
    if module == nil then return out end
    for _, tag in ipairs(module.GetAll()) do
        if IsValid(tag) then
            local victim = tag:GetVictim() --[[@as Player]]
            local team = IsValid(victim) and victim:Team() or nil
            out[#out + 1] = { id = "tag_" .. tag:EntIndex(), pos = tag:GetPos(), team = team }
        end
    end
    return out
end

---@param modeId string?
---@param team integer?
---@return PW.BotObjective[]
local function objectivesFor(modeId, team)
    local key = team or 0
    local cached = cache.objectives[key]
    if cached ~= nil then return cached end
    local mode = rawget(PW, "ActiveMode") --[[@as table<string, any>?]]
    ---@type PW.BotObjective[]?
    local own = nil
    if mode ~= nil and mode.ClassName == modeId and isfunction(mode.BotObjectives) and team ~= nil then
        local answer = PW.Call(mode --[[@as PW.Entity]], "BotObjectives", team)
        own = istable(answer) and answer --[[@as PW.BotObjective[] ]] or {}
    end
    local flags = modeId == "dom" and flagInfos() or {}
    local tags = modeId == "kc" and tagInfos() or {}
    local list = lib.Derive(modeId, own, flags, tags, team)
    cache.objectives[key] = list
    return list
end

---@return Vector[]
local function candidates()
    local map = rawget(PW, "Map") --[[@as PW.MapLib?]]
    local areas = map ~= nil and map.GetNavAreas ~= nil and map.GetNavAreas() or {}
    ---@type Vector[]
    local out = {}
    if #areas == 0 then return out end
    for _ = 1, candidateCount * 2 do
        local area = areas[math.random(#areas)]
        if IsValid(area) and area:GetSizeX() >= minArea and area:GetSizeY() >= minArea then
            out[#out + 1] = area:GetRandomPoint()
            if #out >= candidateCount then break end
        end
    end
    return out
end

---@param bot Player
---@param team integer?
---@param now number
---@return Vector[] mates, PW.BotDeathInfo[] deaths
local function teamFacts(bot, team, now)
    ---@type Vector[]
    local mates = {}
    ---@type PW.BotDeathInfo[]
    local deaths = {}
    if team == nil then return mates, deaths end
    for _, p in ipairs(cache.players) do
        if p.team == team and p.ent ~= bot then mates[#mates + 1] = p.pos end
    end
    for _, death in ipairs(lib._Deaths) do
        if death.team == team and now - death.time < lib.DeathMemory then deaths[#deaths + 1] = death end
    end
    return mates, deaths
end

function lib.Gather(ctx)
    local bot = ctx.bot --[[@as Player]]
    local board = ctx.board
    local now = CurTime()
    refresh(now)
    local api = ctx._api or {}
    local active = rawget(PW, "ActiveMode") --[[@as table<string, any>?]]
    local modeId = api.mode or (active ~= nil and active.ClassName or nil)
    local team = board.team
    local mates, deaths = teamFacts(bot, team, now)
    local personality = istable(board.personality) and board.personality or {}
    ---@type PW.BotFacts
    return {
        pos = bot:GetPos(), team = team, mode = modeId, objectives = objectivesFor(modeId, team), mates = mates,
        authoritative = active ~= nil and active.ClassName == modeId,
        deaths = deaths, candidates = candidates(), stationary = personality.type == "stationary",
        teamwork = PW.BotProfiles.Pick({ "teamwork" }, board.difficulty).teamwork, streak = lib.ReadyStreak(bot)
    }
end

function lib.RecordDeath(pos, team, now)
    local list = lib._Deaths
    list[#list + 1] = { pos = pos, team = team, time = now }
    while #list > 32 or (list[1] ~= nil and now - list[1].time > lib.DeathMemory) do table.remove(list, 1) end
end

PW.HookFor(MODULE, "PlayerDeath", function(_, victim)
    if not IsValid(victim) then return end
    lib.RecordDeath(victim:GetPos(), victim:Team(), CurTime())
end)
