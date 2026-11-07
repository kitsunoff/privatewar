-- Lobby hub and custom game models (U-5, T-8.1, T-8.2; notes/16-frontend-d1-proposal.md §4a, §4b; 10-frontend.md
-- d.8-d.10; 08-lobby.md d.2, d.3). Pure and shared, so the server-side test runner covers them: the lobby state
-- (pw_lobby_state), the playlist state (pw_playlist_list), the player records and the seen-set in; what the hub and
-- the custom game screen draw out. Actions the player may not use are locked with a reason (focusable, explained in
-- the hint bar); the server checks every request again.

local lib = (rawget(PW, "Lobby") or {}) --[[@as PW.LobbyLib]]
PW.Lobby = lib

local customId = "@custom" -- PW.Playlist.CustomRow; repeated so the model works without the playlists module
local fillId = "bots.fill"
local matchRows = 3

local reasons = {
    waiting = "Waiting for the server",
    start = "Only the host can start the match",
    navgen = "A navmesh is being generated: the map reloads when it is done",
    nothing = "No mode is offered on any installed map",
    modeMap = "Only the host can pick the mode and the map",
    setup = "Only the host can change Game Setup",
    content = "Only the host and superadmins can switch content",
    navmesh = "Only the host can generate the navmesh",
    playlist = "Only the host can pick the playlist"
}

function lib._SlotWarning(fill, maxPlayers)
    if fill == nil or fill <= maxPlayers then return nil end
    return string.format("Bots fill to %d players, the server has %d slots", fill, maxPlayers)
end

function lib._SeenKey(id)
    return "playlist:" .. id
end

---@param def table
---@param value table<string, boolean>
---@return string
local function showSet(def, value)
    ---@type string[]
    local names = {}
    local options = def.options --[[@as string[]?]]
    if options == nil then
        options = {}
        for key in pairs(value) do options[#options + 1] = key end
        table.sort(options)
    end
    for _, option in ipairs(options) do
        if value[option] then names[#names + 1] = string.upper(option) end
    end
    return #names == 0 and "None" or table.concat(names, ", ")
end

function lib._ShowValue(def, value)
    local kind = def.type --[[@as string]]
    if kind == "bool" then return value and "On" or "Off" end
    if kind == "enum" then return string.upper(tostring(value)) end
    if kind == "set" then return showSet(def, istable(value) and value or {}) end
    if kind == "float" then return string.format("%g", tonumber(value) or 0) end
    return tostring(value)
end

---@param id string
---@param title string
---@param text? string
---@param reason? string nil: the action is open
---@return PW.LobbyAction
local function action(id, title, text, reason)
    return { id = id, title = title, text = text, locked = reason ~= nil, reason = reason }
end

---@param state PW.LobbyState?
---@param allowed boolean
---@param denied string
---@return string?
local function lockReason(state, allowed, denied)
    if state == nil then return reasons.waiting end
    if not allowed then return denied end
    return nil
end

---@param state PW.LobbyState
---@param id? string
---@return PW.LobbyMode?
local function modeEntry(state, id)
    for _, mode in ipairs(state.modes) do
        if mode.id == id then return mode end
    end
    return nil
end

---@param mode? PW.LobbyMode
---@return integer?
local function fillOf(mode)
    if mode == nil then return nil end
    for _, group in ipairs(mode.groups) do
        for _, field in ipairs(group.fields) do
            if field.def.id == fillId and isnumber(field.value) then return math.floor(field.value) end
        end
    end
    return nil
end

---@param mode? PW.LobbyMode
---@return { [1]: string, [2]: string }[]
local function settingRows(mode)
    ---@type { [1]: string, [2]: string }[]
    local rows = {}
    if mode == nil then return rows end
    for _, group in ipairs(mode.groups) do
        if group.ownerKind == "modes" then
            for index = 1, math.min(matchRows, #group.fields) do
                local field = group.fields[index]
                rows[#rows + 1] = { field.def.label, lib._ShowValue(field.def, field.value) }
            end
        end
    end
    local fill = fillOf(mode)
    if fill ~= nil then rows[#rows + 1] = { "Bots fill", tostring(fill) } end
    return rows
end

---@param input PW.LobbyHubInput
---@param mode? PW.LobbyMode
---@param map? string
---@return PW.LobbySummary
local function summaryOf(input, mode, map)
    if mode == nil or map == nil then return { badge = "?", mode = "", map = map or "", text = "" } end
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    local short = input.shortOf ~= nil and input.shortOf(mode.id) or nil
    local badge = kit ~= nil and kit.Monogram({ Name = mode.name, Short = short }) or "?"
    return { badge = badge, mode = mode.name, map = map, text = mode.name .. " on " .. map }
end

---@param input PW.LobbyHubInput
---@return PW.PlaylistSummary?
local function activePlaylist(input)
    local playlists = input.playlists or nil
    if playlists == nil or playlists.active == "" then return nil end
    for _, item in ipairs(playlists.list) do
        if item.id == playlists.active then return item end
    end
    return nil
end

---@param input PW.LobbyHubInput
---@param canPick boolean
---@return PW.UICard[]
---@return string[]
local function playlistCards(input, canPick)
    ---@type PW.UICard[]
    local cards = {}
    ---@type string[]
    local keys = {}
    local playlists = input.playlists or nil
    for _, item in ipairs(playlists ~= nil and playlists.list or {}) do
        local key = lib._SeenKey(item.id)
        keys[#keys + 1] = key
        cards[#cards + 1] = {
            id = item.id, title = item.name, text = item.summary, new = input.seen[key] ~= true,
            footer = item.fill > 0 and string.format("Fills to %d with bots", item.fill) or nil,
            locked = not canPick, reason = not canPick and reasons.playlist or nil
        }
    end
    cards[#cards + 1] = {
        id = customId, title = "Custom game", new = false, locked = false,
        text = "Pick the mode and the map yourself and change Game Setup."
    }
    return cards, keys
end

---@param state PW.LobbyState?
---@param model PW.LobbyModel?
---@param active PW.PlaylistSummary?
---@param summary PW.LobbySummary
---@param entryReason? string the entry hint's reason (Singleplayer): wins over every other reason
---@return PW.LobbyAction
local function startAction(state, model, active, summary, entryReason)
    local reason = lockReason(state, state ~= nil and state.canStart, reasons.start)
    if reason == nil and state ~= nil and state.nav ~= nil and state.nav.generating then reason = reasons.navgen end
    local missing = model == nil or model.mode == nil or model.map == nil
    if reason == nil and active == nil and missing then reason = reasons.nothing end
    reason = entryReason or reason
    if active ~= nil then
        local start = action("start", "Start playlist", "Start the playlist " .. active.name .. ".", reason)
        start.label, start.request = "START PLAYLIST", { playlist = active.id }
        return start
    end
    local start = action("start", "Start match", summary.text ~= "" and "Start " .. summary.text .. "." or nil, reason)
    start.label = "START MATCH"
    start.request = { mode = model ~= nil and model.mode or nil, map = model ~= nil and model.map or nil }
    return start
end

---@param active PW.PlaylistSummary?
---@param mode PW.LobbyMode?
---@return { [1]: string, [2]: string }[]
---@return integer?
local function matchRowsOf(active, mode)
    if active == nil then return settingRows(mode), fillOf(mode) end
    ---@type { [1]: string, [2]: string }[]
    local rows = { { "Playlist", active.name } }
    local fill = active.fill > 0 and active.fill or nil
    if fill ~= nil then rows[#rows + 1] = { "Bots fill", tostring(fill) } end
    return rows, fill
end

---@param input PW.LobbyHubInput
---@param fill integer?
---@return PW.UIPlayerSection[]
local function partyOf(input, fill)
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    if kit == nil or kit.PlayerList == nil then return {} end
    return kit.PlayerList(input.players, { phase = "LOBBY", maxPlayers = input.maxPlayers, botsFill = fill })
end

function lib._Hub(input)
    local state = input.state or nil
    local model = state ~= nil and lib._Model(state, input.selection, input.fits) or nil
    local mode = (state ~= nil and model ~= nil) and modeEntry(state, model.mode) or nil
    local summary = summaryOf(input, mode, model ~= nil and model.map or nil)
    local active = activePlaylist(input)
    local cards, keys = playlistCards(input, state ~= nil and state.canStart)
    local rows, fill = matchRowsOf(active, mode)
    local canStart = state ~= nil and state.canStart
    local entry = input.entry ~= nil and lib._Entry(input.entry) or nil
    return {
        ready = state ~= nil, cards = cards, selected = active ~= nil and active.id or customId, seenKeys = keys,
        start = lib._ApplyFlow(startAction(state, model, active, summary, entry ~= nil and entry.startReason or nil),
            input.flow),
        hint = entry ~= nil and entry.hints[1] or nil,
        modeMap = action("modemap", "Mode & map", "Choose the mode and the map.",
            lockReason(state, canStart, reasons.modeMap)),
        setup = action("setup", "Game setup", "Score, time, bots and the other match settings.",
            lockReason(state, state ~= nil and state.canEdit, reasons.setup)),
        summary = summary, rows = rows, warning = lib._SlotWarning(fill, input.maxPlayers),
        party = partyOf(input, fill), note = not canStart and "waiting for host" or nil, model = model
    }
end

---@param state PW.LobbyState?
---@return PW.LobbyAction?
local function navAction(state)
    local nav = state ~= nil and state.nav or nil
    if state == nil or nav == nil then return nil end
    local reason = not nav.canGenerate and reasons.navmesh or (nav.generating and reasons.navgen or nil)
    return action("navmesh", "Navmesh", lib._NavLine(nav), reason)
end

---@param state PW.LobbyState?
---@param model PW.LobbyModel?
---@param input PW.LobbyHubInput
---@return PW.UICard[]
---@return PW.UICard[]
local function choiceCards(state, model, input)
    ---@type PW.UICard[]
    local modes = {}
    ---@type PW.UICard[]
    local maps = {}
    if state == nil or model == nil then return modes, maps end
    local reason = not state.canStart and reasons.modeMap or nil
    local kit = rawget(PW, "UI") --[[@as PW.UILib?]]
    for _, mode in ipairs(state.modes) do
        local short = input.shortOf ~= nil and input.shortOf(mode.id) or nil
        modes[#modes + 1] = {
            id = mode.id, title = mode.name, locked = reason ~= nil, reason = reason,
            badge = kit ~= nil and kit.Monogram({ Name = mode.name, Short = short }) or nil
        }
    end
    for _, entry in ipairs(model.maps) do
        maps[#maps + 1] = { id = entry.id, title = entry.label, locked = reason ~= nil, reason = reason }
    end
    return modes, maps
end

function lib._Custom(input)
    local custom = lib._Hub(input) --[[@as PW.LobbyCustom]]
    local state = input.state or nil
    local model = custom.model
    custom.actions = {
        custom.start, custom.modeMap, custom.setup,
        action("content", "Enabled content", "Switch modes, modules and other content for the next match.",
            lockReason(state, state ~= nil and state.canToggle, reasons.content))
    }
    custom.actions[#custom.actions + 1] = navAction(state)
    custom.modeCards, custom.mapCards = choiceCards(state, model, input)
    custom.modeSelected = model ~= nil and model.mode or nil
    custom.mapSelected = model ~= nil and model.map or nil
    custom.sections = model ~= nil and model.sections or {}
    custom.canEdit = state ~= nil and state.canEdit
    custom.canToggle = state ~= nil and state.canToggle
    custom.toggles = state ~= nil and state.toggles or {}
    custom.nav = state ~= nil and state.nav or nil
    custom.navLine = lib._NavLine(custom.nav)
    return custom
end
