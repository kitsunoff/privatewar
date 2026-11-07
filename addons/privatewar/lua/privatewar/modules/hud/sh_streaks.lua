-- Pure rules of the killstreak element (T-4.6 HUD redesign; 05-loadout.md d.9): three squares on the right edge, the
-- cheapest at the bottom, and a progress bar beside them. The bar reaches the centre of a square exactly at its cost
-- (linear between two squares) and stays full after the last one, because the counter does not loop. Shared, plain
-- data in and out, so the server-side test runner covers it; the drawing is hud/streaks.lua. Loaded by shared.lua.
--
-- Square states: "locked" (counter below the cost, none held), "spent" (counter past the cost, none held: it was
-- used), "ready" (held), "selected" (held and selected for the use key). Nothing here allocates once `out` holds
-- its tables; the element calls _StreakSquares only when its inputs change.

local lib = PW.HUD --[[@as PW.HudLib]]

lib.Streaks = {
    -- Right edge, above the equipment lines (hud/equipment.lua, baselines 900 and 870).
    right = 1880,
    bottom = 828,
    size = 60,
    gap = 12,
    bar = 6,
    barGap = 10,
    max = 3,
    -- No icons among the stock materials fit; the squares carry short labels.
    short = { uav = "UAV", counter_uav = "CUAV", airstrike = "AIR" }
}

---Whether entry a sorts before square b (cost, then id).
---@param a PW.StreakSetEntry
---@param b PW.StreakSquare
---@return boolean
local function before(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.id < b.id
end

---Inserts entry into out[1..count] in order, keeping at most max; returns the new count.
---@param out PW.StreakSquare[]
---@param count integer
---@param entry PW.StreakSetEntry
---@param max integer
---@return integer
local function insert(out, count, entry, max)
    local at = count + 1
    for i = 1, count do
        if before(entry, out[i] --[[@as PW.StreakSquare]]) then
            at = i
            break
        end
    end
    if at > max then return count end
    local last = math.min(count + 1, max)
    local spare = out[last]
    if spare == nil then
        spare = { id = entry.id, cost = entry.cost, state = "locked", held = 0 }
    else
        spare.id, spare.cost, spare.state, spare.held = entry.id, entry.cost, "locked", 0
    end
    for i = last, at + 1, -1 do out[i] = out[i - 1] end
    out[at] = spare
    return last
end

---The selected inventory id (the index wraps like PW.Streaks._Select), or nil for an empty inventory.
---@param view PW.StreakView
---@return string?
local function selectedId(view)
    local size = #view.inventory
    if size == 0 then return nil end
    return view.inventory[(math.floor(tonumber(view.selected) or 1) - 1) % size + 1]
end

function lib._StreakSquares(view, out)
    local count = 0
    for _, entry in ipairs(view.set) do count = insert(out, count, entry, lib.Streaks.max) end
    for i = #out, count + 1, -1 do out[i] = nil end
    local chosen = selectedId(view)
    for i = 1, count do
        local square = out[i] --[[@as PW.StreakSquare]]
        local held = 0
        for _, id in ipairs(view.inventory) do
            if id == square.id then held = held + 1 end
        end
        square.held = held
        if held > 0 then
            square.state = square.id == chosen and "selected" or "ready"
        else
            square.state = view.progress >= square.cost and "spent" or "locked"
        end
    end
    return count
end

function lib._StreakAnchor(index, size, gap)
    return (index - 1) * (size + gap) + size / 2
end

function lib._StreakFill(squares, count, progress, cfg)
    if count < 1 or progress <= 0 then return 0 end
    local length = lib._StreakAnchor(count, cfg.size, cfg.gap)
    local lastCost, lastAt = 0, 0
    for i = 1, count do
        local cost = (squares[i] --[[@as PW.StreakSquare]]).cost
        local at = lib._StreakAnchor(i, cfg.size, cfg.gap) / length
        if progress < cost then
            return lastAt + (at - lastAt) * (progress - lastCost) / (cost - lastCost)
        end
        lastCost, lastAt = cost, at
    end
    return 1
end

function lib._StreakHint(state, keys)
    ---@type string, string
    local action, key
    if state == "selected" then
        action, key = "streak", keys.use
    elseif state == "ready" then
        action, key = "streak_next", keys.next
    else
        return ""
    end
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local pad = ui ~= nil and ui.Gamepad or nil
    local glyph = pad ~= nil and pad.Glyph(action, keys.hints, keys.pad) or nil
    return "[" .. (glyph or string.upper(key)) .. "]"
end

function lib._StreakShort(id, name)
    local known = lib.Streaks.short[id]
    if known ~= nil then return known end
    local letters = string.gsub(name or id, "[^%w]", "")
    return string.upper(string.sub(letters, 1, 4))
end

function lib._StreakOrphan(squares, count, view)
    local chosen = selectedId(view)
    if chosen == nil then return nil end
    for i = 1, count do
        if (squares[i] --[[@as PW.StreakSquare]]).id == chosen then return nil end
    end
    return chosen
end
