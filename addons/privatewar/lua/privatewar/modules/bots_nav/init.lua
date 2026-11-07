-- Bots navigation, server glue (T-5.5): the CNavArea adapter (the only place that touches navmesh userdata), the
-- default service over PW.Map.GetNavAreas(), the position projection and the hooks. Everything else is in shared.lua.
--
-- Decisions of the lane agent:
--   1. The graph nodes are area ids. Neighbours come from CNavArea:GetAdjacentAreas, converted once per area and
--      cached; cost and heuristic are the distance between area centres.
--   2. The default service is built lazily and rebuilt when PW.Map.GetNavAreas() returns another list (a new map,
--      or the areas were dropped by PauseNav); the cost layers registered before survive a rebuild.
--   3. The sample layer "danger" (recent deaths) is registered by this module for the default service.

local lib = PW.BotNav

---@param areas CNavArea[]
---@return PW.NavGraph
function lib.AreaGraph(areas)
    ---@type table<integer, CNavArea>
    local byId = {}
    ---@type integer[]
    local ids = {}
    ---@type table<integer, Vector>
    local centers = {}
    for _, area in ipairs(areas) do
        local id = area:GetID()
        byId[id] = area
        ids[#ids + 1] = id
        centers[id] = area:GetCenter()
    end
    ---@type table<integer, integer[]>
    local neighbours = {}
    return {
        Neighbours = function(id)
            local cached = neighbours[id]
            if cached ~= nil then return cached end
            ---@type integer[]
            local list = {}
            local adjacents = byId[id]:GetAdjacentAreas() --[[@as CNavArea[] ]]
            for _, adjacent in ipairs(adjacents) do list[#list + 1] = adjacent:GetID() end
            neighbours[id] = list
            return list
        end,
        Cost = function(from, to) return centers[from]:Distance(centers[to]) end,
        Heuristic = function(node, goal) return centers[node]:Distance(centers[goal]) end,
        Nodes = function() return ids end,
        Position = function(id) return centers[id] end
    }
end

lib.Danger = lib.NewDanger()

---@type { areas: CNavArea[]?, service: PW.NavService?, layers: table<string, PW.NavCostLayer> }
local state = { layers = { danger = lib.Danger.Layer } }

---@return PW.NavService?
function lib.Service()
    local areas = PW.Map.GetNavAreas and PW.Map.GetNavAreas() or {}
    if #areas == 0 then
        state.areas, state.service = nil, nil
        return nil
    end
    if state.areas ~= areas or state.service == nil then
        state.areas = areas
        state.service = lib.NewService({ graph = lib.AreaGraph(areas) })
        for id, layer in pairs(state.layers) do state.service.RegisterCostLayer(id, layer) end
    end
    return state.service
end

---@param pos Vector
---@return integer?
local function areaId(pos)
    local area = navmesh.GetNearestNavArea(pos, false, 256, false, true)
    return area ~= nil and area:GetID() or nil
end

function lib.RequestPath(from, to, callback)
    local service = lib.Service()
    if service == nil then return nil end
    local start, goal = areaId(from), areaId(to)
    if start == nil or goal == nil then return nil end
    return service.RequestPath(start, goal, callback)
end

function lib.Cancel(handle)
    local service = lib.Service()
    if service ~= nil then service.Cancel(handle) end
end

function lib.RegisterCostLayer(id, layer)
    state.layers[id] = layer
    local service = lib.Service()
    if service ~= nil then service.RegisterCostLayer(id, layer) end
end

function lib.UnregisterCostLayer(id)
    state.layers[id] = nil
    local service = lib.Service()
    return service ~= nil and service.UnregisterCostLayer(id) or false
end

PW.HookFor(MODULE, "Think", function()
    local service = lib.Service()
    if service ~= nil then service.Tick() end
end)

PW.HookFor(MODULE, "PlayerDeath", function(_, victim)
    if IsValid(victim) then lib.Danger.Record(victim:GetPos()) end
end)
