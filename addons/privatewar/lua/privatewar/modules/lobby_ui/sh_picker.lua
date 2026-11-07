-- Map picker model (U-6, T-8.2; notes/16-frontend-d1-proposal.md §4c; 10-frontend.md d.3). Pure and shared, so the
-- server-side test runner covers it: the maps a mode is offered on (PW.Lobby._PickerMaps, defined in shared.lua
-- next to the lobby model it shares the filter with), the selection rule, Q/E mode cycling, the pager position of
-- the focused row and the thumbnail path. The screen is screens/map_picker.lua.

local lib = (rawget(PW, "Lobby") or {}) --[[@as PW.LobbyLib]]
PW.Lobby = lib

local currentBadge = "CURRENT"

function lib._PickerKeep(maps, wanted)
    for _, name in ipairs(maps) do
        if name == wanted then return name end
    end
    return maps[1]
end

function lib._PickerCycle(ids, current, delta)
    if #ids == 0 then return nil end
    for index, id in ipairs(ids) do
        if id == current then return ids[(index - 1 + delta) % #ids + 1] end
    end
    return ids[1]
end

function lib._PickerPage(count, perPage, index)
    local kit = rawget(PW, "UI") --[[@as PW.UILib]]
    local state = kit.Pager.State(count, perPage, index)
    return { state = state, text = string.format("%d / %d", state.page, state.pages) }
end

function lib._ThumbPath(map)
    if not lib._ValidMapName(map) then return nil end
    return "maps/thumb/" .. map .. ".png"
end

---@param state PW.LobbyState
---@param wanted string?
---@return PW.LobbyMode?
local function modeOf(state, wanted)
    for _, mode in ipairs(state.modes) do
        if mode.id == wanted then return mode end
    end
    return state.modes[1]
end

---@param state PW.LobbyState
---@return string[]
local function modeIds(state)
    ---@type string[]
    local ids = {}
    for index, mode in ipairs(state.modes) do ids[index] = mode.id end
    return ids
end

---@param maps string[]
---@param map string?
---@return integer
local function indexOf(maps, map)
    for index, name in ipairs(maps) do
        if name == map then return index end
    end
    return 1
end

---@param maps string[]
---@param current string?
---@return PW.UICard[]
local function cardsOf(maps, current)
    ---@type PW.UICard[]
    local cards = {}
    for index, name in ipairs(maps) do
        cards[index] = { id = name, title = name, badge = name == current and currentBadge or nil }
    end
    return cards
end

---@param input PW.LobbyHubInput
---@param mode PW.LobbyMode?
---@param map string?
---@return PW.LobbySummary
local function summaryOf(input, mode, map)
    if mode == nil then return { badge = "?", mode = "", map = map or "", text = "" } end
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    local short = input.shortOf ~= nil and input.shortOf(mode.id) or nil
    local badge = kit ~= nil and kit.Monogram({ Name = mode.name, Short = short }) or "?"
    return { badge = badge, mode = mode.name, map = map or "", text = mode.name .. " on " .. (map or "") }
end

function lib._Picker(input, pick)
    local state = input.state or nil
    if state == nil then
        return {
            ready = false, modes = {}, modeName = "", maps = {}, cards = {}, focusIndex = 1,
            summary = summaryOf(input, nil, nil)
        }
    end
    local selection = input.selection
    local mode = modeOf(state, pick.mode or selection.mode)
    local maps = lib._PickerMaps(state, mode ~= nil and mode.id or nil, input.fits)
    local map = lib._PickerKeep(maps, pick.map or selection.map or state.map)
    return {
        ready = mode ~= nil, modes = modeIds(state), mode = mode ~= nil and mode.id or nil,
        modeName = mode ~= nil and mode.name or "", maps = maps, map = map,
        cards = cardsOf(maps, selection.map or state.map), focusIndex = indexOf(maps, map),
        thumb = map ~= nil and lib._ThumbPath(map) or nil, summary = summaryOf(input, mode, map)
    }
end

function lib._PickerStep(input, pick, action)
    if action ~= "tab_prev" and action ~= "tab_next" then return nil end
    if (input.state or nil) == nil then return nil end
    local model = lib._Picker(input, pick)
    local next = lib._PickerCycle(model.modes, model.mode, action == "tab_next" and 1 or -1)
    if next == nil then return nil end
    local stepped = lib._Picker(input, { mode = next, map = model.map })
    return { mode = stepped.mode, map = stepped.map }
end
