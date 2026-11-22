-- LOADOUT > CALLING CARD: the controller focuses the grid, and only activation changes the archived choice.
SCREEN.Tab = "loadout"
SCREEN.Title = "Calling Card"
SCREEN.Hints = { { action = "accept", label = "Equip card" }, { action = "back", label = "Back" } }

---@class PW.CardPickerTile
---@field button PWButton
---@field row PW.UICard
---@field plate PW.CardPlate
---@field bounds PW.UIRect
---@field name string

---@class PWLoadoutCardView : Panel
---@field grid DScrollPanel
---@field preview Panel
---@field root? PWRoot
---@field tiles PW.CardPickerTile[]
---@field selected? string
---@field focused? PW.CardPickerTile
---@field firstFocus? PW.CardPickerTile
---@field previewBounds PW.UIRect
---@field previewName string

local columns = 4

---@return PW.CallingCardsLib
local function cards()
    return assert(PW.CallingCards)
end

---@param view PWLoadoutCardView
local function fitPreview(view)
    local ply = LocalPlayer()
    local name = IsValid(ply) and cards()._VictimName(ply:Nick()) or "Player"
    view.previewName = assert(cards()._FitName)(name, view.previewBounds.w)
end

---@param view PWLoadoutCardView
---@param tile PW.CardPickerTile
local function bindTile(view, tile)
    local button, row = tile.button, tile.row
    button:SetText(row.title)
    local index = #view.tiles - 1
    local spec = PW.UI.Focusable(button, "calling_card_row_" .. math.floor(index / columns), "calling_card:" .. row.id)
    spec.axis = "horizontal"
    button:SetLocked(row.locked == true, row.reason)
    if row.reason ~= nil then button:SetTooltip(row.reason) end
    button.PWOnFocus = function() view.focused = tile end
    button.DoClick = function()
        if row.locked or row.disabled then return end
        if assert(cards().Choose)(row.id) then view.selected, view.focused = row.id, tile end
    end
    local hooks = button --[[@as PANEL]]
    hooks.Paint = function()
        local kit = PW.UI --[[@as PW.UILib]]
        assert(cards()._DrawPlate)(tile.plate, tile.name, row.lockText or "", tile.bounds, 1)
        local selected = view.selected == row.id
        local style = kit.Style --[[@as PW.UIStyle]]
        if not selected and not kit.IsFocused(button) then return end
        surface.SetDrawColor(style.accent)
        surface.DrawOutlinedRect(0, 0, tile.bounds.w, tile.bounds.h, selected and 2 or 1)
    end
end

---@param view PWLoadoutCardView
local function loadTiles(view)
    local lib = cards()
    local oldFocus = view.focused ~= nil and view.focused.row.id or nil
    for _, tile in ipairs(view.tiles) do tile.button:Remove() end
    view.tiles, view.focused, view.firstFocus, view.selected = {}, nil, nil, nil
    local saved = assert(lib.LocalChoice)()
    local canvas = view.grid:GetCanvas()
    local plateOf = assert(lib._PlateFor)
    ---@type PW.CardPickerTile?
    local firstOpen
    for _, row in ipairs(assert(lib._PickerCards)()) do
        local tile = {
            button = vgui.Create("PWButton", canvas) --[[@as PWButton]],
            row = row, plate = plateOf(row.id), bounds = { x = 0, y = 0, w = 0, h = 0 }, name = row.title
        }
        view.tiles[#view.tiles + 1] = tile
        bindTile(view, tile)
        if not row.locked then
            firstOpen = firstOpen or tile
            if row.id == saved then view.selected, view.focused = row.id, tile end
        end
        if row.id == oldFocus then view.firstFocus = tile end
    end
    if view.selected == nil and firstOpen ~= nil and firstOpen.row.id == lib.Default then
        view.selected = lib.Default
    end
    view.focused = view.firstFocus or view.focused or firstOpen or view.tiles[1]
    view.firstFocus = view.focused
    if view.root ~= nil then view.root.focusDirty = 2 end
    view:InvalidateLayout()
end

---@param view PWLoadoutCardView
---@param width number
---@param height number
local function layout(view, width, height)
    local px = PW.UI.Draw.Px
    local margin, gap, scrollbar = px(96), px(12), px(20)
    local previewW, previewH = px(400), px(100)
    local previewY = height - previewH - px(16)
    view.preview:SetPos(math.floor((width - previewW) / 2), previewY)
    view.preview:SetSize(previewW, previewH)
    view.previewBounds.w, view.previewBounds.h = previewW, previewH
    fitPreview(view)
    local gridW = math.max(1, width - 2 * margin)
    view.grid:SetPos(margin, gap)
    view.grid:SetSize(gridW, math.max(1, previewY - 2 * gap))
    local tw = math.max(1, math.floor((gridW - scrollbar - (columns - 1) * gap) / columns))
    local th = math.max(1, math.floor(tw / 4))
    local fit = assert(cards()._FitName)
    for index, tile in ipairs(view.tiles) do
        local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
        tile.button:SetPos(col * (tw + gap), row * (th + gap))
        tile.button:SetSize(tw, th)
        tile.bounds.w, tile.bounds.h, tile.name = tw, th, fit(tile.row.title, tw)
    end
    view.grid:GetCanvas():SetTall(math.ceil(#view.tiles / columns) * (th + gap))
    local focus = view.firstFocus
    if focus ~= nil and view.root ~= nil then
        view.firstFocus = nil
        view.root:FocusPanel(focus.button, "auto")
    end
end

function SCREEN:Build(ctx)
    local lib = PW.CallingCards
    if lib == nil or not lib._Active() then return nil end
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLoadoutCardView]]
    view:Dock(FILL)
    view.root = ctx.root --[[@as PWRoot?]]
    view.grid = vgui.Create("DScrollPanel", view) --[[@as DScrollPanel]]
    view.preview = vgui.Create("Panel", view) --[[@as Panel]]
    view.previewBounds, view.tiles, view.previewName = { x = 0, y = 0, w = 0, h = 0 }, {}, ""
    local preview = view.preview --[[@as PANEL]]
    preview.Paint = function()
        if view.focused ~= nil then
            assert(lib._DrawPlate)(view.focused.plate, view.previewName, "ELIMINATED", view.previewBounds, 1)
        end
    end
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    local refresh = function() loadTiles(view) end
    view.PWRefresh = refresh
    local store = PW.UI.Store
    if store ~= nil and store.WatchUnlockView ~= nil then store.WatchUnlockView(view, refresh) end
    refresh()
    return view
end
