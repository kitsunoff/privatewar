-- Map picker (U-6, T-8.2; notes/16-frontend-d1-proposal.md §4c; 10-frontend.md d.3). Pushed from Custom game, MODE &
-- MAP. Left: the mode strip (Q and E cycle the mode) and the paged list of the maps the mode is offered on; centre:
-- a large preview of the focused map (maps/thumb/<map>.png, else a placeholder with the map name) and the summary
-- (mode monogram, mode, map). Enter on a map selects it and goes back, Esc goes back without changes. Pick mode
-- (PW.Lobby.OpenPicker{ pick = fn }): Enter gives (mode, map) to the callback and leaves the lobby selection alone
-- (the vote's "Pick myself", U-7). Thin glue over PW.Lobby._Picker* (lobby_ui/sh_picker.lua).

SCREEN.Tab = "play"
SCREEN.Title = "Mode & map"
SCREEN.OwnsTabKeys = true -- Q and E cycle the mode here, not the tabs
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "tab_prev", label = "Previous mode" },
    { action = "tab_next", label = "Next mode" }, { action = "back", label = "Back" }
}

---@class PWMapPickerView : Panel
---@field opts PW.LobbyPickerOpts
---@field pick PW.LobbyPick
---@field model PW.LobbyPicker
---@field strip Panel
---@field list PWCardList
---@field preview Panel
---@field summary PWSummary
---@field shown? integer the list row the preview shows
---@field focusIn integer frames left before the focus is put on the selected row (0: none pending)
---@field OnAction fun(self: PWMapPickerView, action: string)

---@return PW.LobbyLib
local function lobby()
    return PW.Lobby --[[@as PW.LobbyLib]]
end

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@param view PWMapPickerView
---@return PW.LobbyHubInput
local function inputOf(view)
    local source = view.opts.input or lobby().Input
    return (source --[[@as fun(): PW.LobbyHubInput]])()
end

---The map under the focus (the one Enter would pick), else the selection.
---@param view PWMapPickerView
---@return string?
local function focusedMap(view)
    return view.model.maps[view.list.focusIndex] or view.model.map
end

-- Preview -----------------------------------------------------------------------------------------------------------

---@type table<string, IMaterial|false>
local thumbs = {}

---The thumbnail of a map, false when the file does not exist (looked up once per path).
---@param path string?
---@return IMaterial|false
local function thumbOf(path)
    if path == nil then return false end
    local cached = thumbs[path]
    if cached == nil then
        cached = file.Exists(path, "GAME") and Material(path) or false
        thumbs[path] = cached
    end
    return cached
end

---@param w number
---@param h number
---@param name string
local function paintPlaceholder(w, h, name)
    local s, draw_ = kit().Style --[[@as PW.UIStyle]], kit().Draw
    draw_.Rect(0, 0, w, h, s.bg_raised)
    draw_.Rect(0, math.floor(h * 0.62), w, math.ceil(h * 0.38), s.bg_panel)
    draw_.EdgeBar(h)
    draw.SimpleText(name, kit().FontName("h1"), w / 2, h / 2, s.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("NO PREVIEW", kit().FontName("small"), w / 2, h / 2 + draw_.Px(40), s.text_muted,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

---@param view PWMapPickerView
---@param w number
---@param h number
local function paintPreview(view, w, h)
    local name = focusedMap(view)
    local path = name ~= nil and lobby()._ThumbPath(name) or nil
    local material = thumbOf(path)
    if material then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(0, 0, w, h)
    else
        paintPlaceholder(w, h, name or "")
    end
    kit().Draw.Outline(0, 0, w, h, (kit().Style --[[@as PW.UIStyle]]).border)
end

-- Mode strip --------------------------------------------------------------------------------------------------------

---@param view PWMapPickerView
---@param w number
---@param h number
local function paintStrip(view, w, h)
    local s, draw_ = kit().Style --[[@as PW.UIStyle]], kit().Draw
    local model, pad = view.model, draw_.Px(16)
    draw_.Rect(0, 0, w, h, s.bg_panel)
    draw_.Outline(0, 0, w, h, s.border)
    local root = kit().CurrentRoot()
    local device = root ~= nil and kit().Input.Device((root --[[@as PWRoot]]).input) or "keyboard"
    local small = kit().FontName("small")
    local capW = draw_.KeyCap(kit().Input.Hint((root --[[@as PWRoot]]).input, "tab_prev").label, small, pad, h / 2,
        device == "controller" and "controller" or "keyboard")
    local center = pad + capW + pad
    local badge = model.summary.badge
    draw.SimpleText(badge, kit().FontName("h2"), center, h / 2, s.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    surface.SetFont(kit().FontName("h2"))
    local badgeW = surface.GetTextSize(badge)
    draw.SimpleText(string.upper(model.modeName), kit().FontName("h2"), center + badgeW + pad, h / 2, s.text,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local next = kit().Input.Hint((root --[[@as PWRoot]]).input, "tab_next").label
    surface.SetFont(small)
    local nextW = surface.GetTextSize(next) + draw_.Px(14)
    draw_.KeyCap(next, small, w - pad - math.max(nextW, draw_.Px(32)), h / 2,
        device == "controller" and "controller" or "keyboard")
end

-- Screen ------------------------------------------------------------------------------------------------------------

---Puts the focus on the selected row once the list is laid out (a few frames after a rebuild of the cards).
---@param view PWMapPickerView
local function focusSelected(view)
    local root = kit().CurrentRoot() --[[@as PWRoot?]]
    if root == nil then return end
    local panel = view.list:FocusIndex(view.model.focusIndex, 1)
    root:RefreshFocus()
    if panel ~= nil then root:FocusPanel(panel, "auto") end
end

---The cards the player may not pick are locked (a guest sees the list, only the host picks the lobby's map).
---@param view PWMapPickerView
---@return PW.UICard[]
local function cardsOf(view)
    local input = inputOf(view)
    local state = input.state or nil
    local locked = view.opts.pick == nil and (state == nil or not state.canStart)
    if not locked then return view.model.cards end
    for _, card in ipairs(view.model.cards) do
        card.locked, card.reason = true, "Only the host can pick the mode and the map"
    end
    return view.model.cards
end

---@param view PWMapPickerView
local function refreshSummary(view)
    local map = focusedMap(view)
    view.summary:SetSelection({ Name = view.model.modeName, Short = view.model.summary.badge }, map or "")
    view.shown = view.list.focusIndex
end

---@param view PWMapPickerView
local function rebuild(view)
    view.model = lobby()._Picker(inputOf(view), view.pick)
    view.pick = { mode = view.model.mode, map = view.model.map }
    view.list:SetCards(cardsOf(view), nil)
    view.list.focusIndex = view.model.focusIndex
    view.list:InvalidateLayout(true)
    view.focusIn = 3
    refreshSummary(view)
end

---@param view PWMapPickerView
---@param id string
local function choose(view, id)
    local mode = view.model.mode
    if mode == nil then return end
    if view.opts.pick ~= nil then
        view.opts.pick(mode, id)
    else
        lobby().Select({ mode = mode, map = id })
    end
    lobby().ClosePicker()
end

---@param view PWMapPickerView
---@param delta integer
local function cycle(view, delta)
    local step = lobby()._PickerStep(inputOf(view), view.pick, delta > 0 and "tab_next" or "tab_prev")
    if step == nil then return end
    view.pick = step
    rebuild(view)
end

---@param view PWMapPickerView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit().Draw.Px
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 560, gap = 48, bottom = 16 }, px)
    local left, centre = columns.left --[[@as PW.UIRect]], columns.centre
    local stripH, gap = px(72), px(16)
    view.strip:SetPos(left.x, left.y)
    view.strip:SetSize(left.w, stripH)
    view.list:SetPos(left.x, left.y + stripH + gap)
    view.list:SetSize(left.w, left.h - stripH - gap)
    local summaryH = view.summary:GetTall()
    local previewH = math.min(math.floor(centre.w * 9 / 16), centre.h - summaryH - gap)
    view.preview:SetPos(centre.x, centre.y)
    view.preview:SetSize(centre.w, previewH)
    view.summary:SetPos(centre.x, centre.y + previewH + gap)
    view.summary:SetWide(centre.w)
end

---@param view PWMapPickerView
local function think(view)
    if view.focusIn > 0 then
        view.focusIn = view.focusIn - 1
        if view.focusIn == 0 then focusSelected(view) end
    end
    if view.shown ~= view.list.focusIndex then refreshSummary(view) end
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWMapPickerView]]
    view:Dock(FILL)
    view.opts = lobby().TakePicker()
    view.pick = { mode = view.opts.mode, map = view.opts.map }
    view.focusIn = 0
    view.strip = vgui.Create("Panel", view) --[[@as Panel]]
    view.list = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.preview = vgui.Create("Panel", view) --[[@as Panel]]
    view.summary = vgui.Create("PWSummary", view) --[[@as PWSummary]]
    local strip, preview = view.strip --[[@as PANEL]], view.preview --[[@as PANEL]]
    strip.Paint = function(_, w, h) paintStrip(view, w, h) end
    strip.OnMousePressed = function(self_, code)
        if code ~= MOUSE_LEFT then return end
        cycle(view, self_:CursorPos() < self_:GetWide() / 2 and -1 or 1)
    end
    preview.Paint = function(_, w, h) paintPreview(view, w, h) end
    view.list.OnSelect = function(_, id) choose(view, id) end
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function() think(view) end
    view.OnAction = function(_, action)
        if action == "tab_prev" then cycle(view, -1) end
        if action == "tab_next" then cycle(view, 1) end
    end
    view.PWRefresh = function() end
    rebuild(view)
    return view
end
