-- Focus graph (U-2; notes/16 Q1): pure logic over plain node data. Inside a group focus moves along the group's
-- axis (stops at the ends, or wraps in the tab bar); across groups it moves by geometry and restores the group's
-- last focused node. Disabled nodes are skipped; locked nodes are focusable but not activatable. No vgui.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local focus = (rawget(lib, "Focus") or {}) --[[@as PW.UIFocusLib]]
lib.Focus = focus

-- Sideways offset counts double against the distance along the direction (notes/16 Q1).
local sidewaysWeight = 2

---@type table<string, { axis: "x"|"y", sign: integer }>
local directions = {
    up = { axis = "y", sign = -1 }, down = { axis = "y", sign = 1 },
    left = { axis = "x", sign = -1 }, right = { axis = "x", sign = 1 }
}

function focus.New(nodes, groups)
    ---@type table<string, PW.UIFocusNode>
    local byId = {}
    for _, item in ipairs(nodes) do byId[item.id] = item end
    return { nodes = nodes, byId = byId, groups = groups or {}, last = {} }
end

function focus.Set(model, id)
    local item = model.byId[id]
    if item ~= nil then model.last[item.group] = id end
end

function focus.Activatable(model, id)
    local item = model.byId[id]
    return item ~= nil and not item.disabled and not item.locked
end

---@param rect PW.UIRect
---@param axis "x"|"y"
---@return number
local function centre(rect, axis)
    if axis == "x" then return rect.x + rect.w / 2 end
    return rect.y + rect.h / 2
end

---Distance from the near edge of the current rect to the facing edge of the other one, along the direction.
---Negative when the other rect overlaps or lies behind (it is not "in that direction").
---@param from PW.UIRect
---@param to PW.UIRect
---@param dir { axis: "x"|"y", sign: integer }
---@return number
local function edgeGap(from, to, dir)
    if dir.axis == "x" then
        if dir.sign > 0 then return to.x - (from.x + from.w) end
        return from.x - (to.x + to.w)
    end
    if dir.sign > 0 then return to.y - (from.y + from.h) end
    return from.y - (to.y + to.h)
end

---Focusable nodes of one group, ordered along the axis (ties keep the declaration order).
---@param model PW.UIFocusModel
---@param group string
---@param axis "x"|"y"
---@return PW.UIFocusNode[]
local function groupOrder(model, group, axis)
    ---@type PW.UIFocusNode[]
    local list = {}
    for _, item in ipairs(model.nodes) do
        if item.group == group and not item.disabled then list[#list + 1] = item end
    end
    ---@type table<string, integer>
    local index = {}
    for position, item in ipairs(list) do index[item.id] = position end
    table.sort(list, function(a, b)
        local ca, cb = centre(a.rect, axis), centre(b.rect, axis)
        if ca ~= cb then return ca < cb end
        return index[a.id] < index[b.id]
    end)
    return list
end

---Next node inside the group along the direction, or nil at the end (wrapping groups never end).
---@param model PW.UIFocusModel
---@param current PW.UIFocusNode
---@param dir { axis: "x"|"y", sign: integer }
---@return PW.UIFocusNode?
local function stepInGroup(model, current, dir)
    local spec = model.groups[current.group] or {}
    local groupAxis = spec.axis == "horizontal" and "x" or "y"
    if groupAxis ~= dir.axis then return nil end
    local list = groupOrder(model, current.group, groupAxis)
    for position, item in ipairs(list) do
        if item.id == current.id then
            local target = list[position + dir.sign]
            if target == nil and spec.wrap and #list > 1 then
                target = dir.sign > 0 and list[1] or list[#list]
            end
            return target
        end
    end
    return nil
end

---Best node of another group in the direction, as { score, node }; nil when no group lies that way.
---@param model PW.UIFocusModel
---@param current PW.UIFocusNode
---@param dir { axis: "x"|"y", sign: integer }
---@return PW.UIFocusNode?
local function crossGroup(model, current, dir)
    local other = dir.axis == "x" and "y" or "x"
    local fromSide = centre(current.rect, other)
    ---@type table<string, { score: number, node: PW.UIFocusNode }>
    local best = {}
    for _, item in ipairs(model.nodes) do
        local ahead = edgeGap(current.rect, item.rect, dir)
        local eligible = item.group ~= current.group and not item.disabled and ahead >= 0
        local score = ahead + sidewaysWeight * math.abs(centre(item.rect, other) - fromSide)
        local entry = best[item.group]
        if eligible and (entry == nil or score < entry.score) then best[item.group] = { score = score, node = item } end
    end
    ---@type { score: number, node: PW.UIFocusNode }?
    local winner = nil
    for _, entry in pairs(best) do
        if winner == nil or entry.score < winner.score then winner = entry end
    end
    if winner == nil then return nil end
    local remembered = model.byId[model.last[winner.node.group]]
    if remembered ~= nil and not remembered.disabled then return remembered end
    return winner.node
end

function focus.Move(model, current, dir)
    local item, spec = model.byId[current], directions[dir]
    if item == nil or spec == nil then return current end
    local target = stepInGroup(model, item, spec) or crossGroup(model, item, spec)
    if target == nil then return current end
    model.last[target.group] = target.id
    return target.id
end

function focus.Apply(model, current, action)
    if directions[action] ~= nil then return focus.Move(model, current, action --[[@as PW.UIDirection]]), "move" end
    if action == "accept" then
        return current, focus.Activatable(model, current) and "accept" or "locked"
    end
    return current, action
end
