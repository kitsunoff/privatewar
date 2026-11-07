-- Bots objectives: pure roam rules (T-5.10; 07-bots.md d.13 hunt and camp). Hot spots from the contact memory and
-- the teammates' recent deaths; a natural roam point; a camp spot.
--
-- Decisions of the lane agent (to confirm):
--   4. Hot spots: a remembered contact that is not visible now (heard, lost, shared, damage) is fresh for 20 s; a
--      teammate's death for DeathMemory (45 s). A spot hunt reached is skipped for 30 s (checked list).
--   5. Roam point: candidates closer than 300 units are dropped; 600..2500 units score best; a candidate near the
--      recent points (800 units) or near teammates (500 units) scores lower; jitter x0.75..1.25 keeps bots apart.
--   6. Camp spot: a candidate 250..900 units from an objective the team defends, else 400..1500 units from the bot,
--      the fewest teammates near it.

local lib = PW.BotObjectives --[[@as PW.BotObjectivesLib]]

local contactFresh, checkedFor, checkedNear = 20, 30, 250
local roamMin, roamGood, roamFar, recentNear, mateNear = 300, 600, 2500, 800, 500

function lib.HotSpots(memory, deaths, now)
    ---@type PW.BotHotSpot[]
    local spots = {}
    for _, contact in pairs(memory) do
        local age = now - contact.time
        if not contact.visible and age < contactFresh and isvector(contact.pos) then
            spots[#spots + 1] = { pos = contact.pos, time = contact.time, kind = contact.source,
                fresh = 1 - age / contactFresh }
        end
    end
    for _, death in ipairs(deaths) do
        local age = now - death.time
        if age < lib.DeathMemory then
            local fresh = 1 - age / lib.DeathMemory
            spots[#spots + 1] = { pos = death.pos, time = death.time, kind = "death", fresh = fresh }
        end
    end
    return spots
end

---@param checked { pos: Vector, time: number }[]?
---@param pos Vector
---@param now number
---@return boolean
local function wasChecked(checked, pos, now)
    for _, c in ipairs(checked or {}) do
        if now - c.time < checkedFor and c.pos:Distance(pos) < checkedNear then return true end
    end
    return false
end

function lib.PickHotSpot(spots, pos, checked, now)
    ---@type PW.BotHotSpot?
    local best, bestScore = nil, 0
    for _, spot in ipairs(spots) do
        if not wasChecked(checked, spot.pos, now) then
            local score = spot.fresh * lib.Closeness(pos:Distance(spot.pos))
            if score > bestScore then best, bestScore = spot, score end
        end
    end
    return best, bestScore
end

---@param points Vector[]
---@param pos Vector
---@return number
local function nearest(points, pos)
    local best = math.huge
    for _, p in ipairs(points) do best = math.min(best, p:Distance(pos)) end
    return best
end

function lib.PickRoamPoint(pos, candidates, recent, mates, random)
    ---@type Vector?
    local best, bestScore = nil, 0
    for _, c in ipairs(candidates) do
        local d = pos:Distance(c)
        if d >= roamMin then
            local score = math.min(1, d / roamGood) * (d > roamFar and roamFar / d or 1)
            score = score * math.min(1, nearest(recent, c) / recentNear)
            score = score / (1 + lib.CountNear(mates, c, mateNear))
            score = score * (0.75 + 0.5 * random())
            if score > bestScore then best, bestScore = c, score end
        end
    end
    return best
end

---@param pos Vector
---@param candidates Vector[]
---@param mates Vector[]
---@param center Vector
---@param lo number
---@param hi number
---@return Vector?
local function quietest(pos, candidates, mates, center, lo, hi)
    ---@type Vector?
    local best, bestScore = nil, -math.huge
    for _, c in ipairs(candidates) do
        local d = center:Distance(c)
        if d >= lo and d <= hi then
            local score = -lib.CountNear(mates, c, mateNear) - pos:Distance(c) / 10000
            if score > bestScore then best, bestScore = c, score end
        end
    end
    return best
end

function lib.PickCampSpot(pos, candidates, objectives, mates)
    for _, obj in ipairs(objectives) do
        if obj.action == "defend" then
            local spot = quietest(pos, candidates, mates, obj.pos, 250, 900)
            if spot ~= nil then return spot end
        end
    end
    return quietest(pos, candidates, mates, pos, 400, 1500)
end
