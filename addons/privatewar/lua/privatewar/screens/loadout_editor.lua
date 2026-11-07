-- Class editor (T-7.4; 05-loadout.md d.1-d.5, d.12; 10-frontend.md d.1 "class list -> class editor (slots, Pick X
-- budget)"). Pushed from the class list (EDIT, RENAME, COPY, NEW CLASS) over PW.LoadoutUI.Draft. Left: the name and
-- one row per position of the effective slot set (a wildcard adds or changes rows at once); centre: the choices of
-- the focused row (locked items greyed with their unlock level, the cost on each); right: the budget meter, the
-- server's answer to the last save and GUNSMITH (weapon rows) and SAVE. Leaving with unsaved changes saves them.
-- Thin glue over PW.LoadoutUI.Editor, Options, SetItem and ValidateName (modules/loadout_ui/sh_*.lua).

SCREEN.Tab = "loadout"
SCREEN.Title = "Edit class"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "secondary", label = "Gunsmith" },
    { action = "tertiary", label = "Save" }, { action = "back", label = "Back (saves)" }
}

local noneId = "@none"

---@class PWLoadoutEditorView : Panel
---@field draft PW.LoadoutUIDraft
---@field input PW.LoadoutUIEditorInput
---@field model PW.LoadoutUIEditor
---@field nameRow Panel
---@field entry DTextEntry
---@field nameError? string
---@field rowsPanel DScrollPanel
---@field rows table<string, PWLoadoutRow>
---@field rowIds string[]
---@field rowId? string the row whose choices the centre shows
---@field pickerTitle Panel
---@field picker PWCardList
---@field meter Panel
---@field info PWInfoCard
---@field gunsmith PWButton
---@field save PWButton
---@field OnAction fun(self: PWLoadoutEditorView, action: string)

---@return PW.LoadoutUILib
local function ui()
    return PW.LoadoutUI --[[@as PW.LoadoutUILib]]
end

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@param view PWLoadoutEditorView
---@return PW.LoadoutUIRow?
local function currentRow(view)
    for _, row in ipairs(view.model.rows) do
        if row.id == view.rowId then return row end
    end
    return view.model.rows[1]
end

---The weapon slot GUNSMITH opens: the current row when it holds a weapon, else the primary.
---@param view PWLoadoutEditorView
---@return string?
local function gunsmithSlot(view)
    local row = currentRow(view)
    if row ~= nil and row.gunsmith then return row.slot end
    for _, candidate in ipairs(view.model.rows) do
        if candidate.gunsmith then return candidate.slot end
    end
    return nil
end

---@param view PWLoadoutEditorView
local function showInfo(view)
    local result = ui().DraftResult ~= nil and ui().DraftResult() or nil
    local draft = view.draft
    local title = result ~= nil and result.title or (draft.dirty and "Unsaved changes" or "No changes")
    view.info:SetTitle(title)
    view.info:SetRows({ { "NAME", draft.name }, { "COST", view.model.meter.text } })
    view.info:SetText(result ~= nil and #result.lines > 0 and table.concat(result.lines, ", ") or nil)
    local check = view.model.check
    view.info:SetWarning(check ~= nil and ("Not usable: " .. check) or nil)
    local slot = gunsmithSlot(view)
    view.gunsmith:SetText(slot ~= nil and ("GUNSMITH: " .. string.upper(slot)) or "GUNSMITH")
    view.gunsmith:SetLocked(slot == nil, "Pick a weapon first")
    view:InvalidateLayout()
end

---@param view PWLoadoutEditorView
local function updateRows(view)
    for _, row in ipairs(view.model.rows) do
        local panel = view.rows[row.id]
        panel.pwLabel, panel.pwValue, panel.pwSide = row.label, row.itemName, row.costText
        panel.pwProblem, panel.pwChosen = row.problem, row.id == view.rowId
    end
end

---@param view PWLoadoutEditorView
local function showPicker(view)
    local row = currentRow(view)
    if row == nil then return end
    view.rowId = row.id
    ---@type PW.UICard[]
    local cards = {}
    local selected = noneId
    for index, option in ipairs(ui().Options(view.input, row, view.model.slots)) do
        ---@type PW.UICard
        local card = { id = option.id == "" and noneId or option.id, title = option.name }
        card.badge = option.costText ~= "" and option.costText or nil
        card.locked, card.reason, card.lockText = option.locked, option.reason, option.lockText
        card.text = option.description or option.reason
        if option.selected then selected = card.id end
        cards[index] = card
    end
    view.picker:SetCards(cards, selected)
    updateRows(view)
    local root = kit().CurrentRoot() --[[@as PWRoot?]]
    if root ~= nil then root.focusDirty = 2 end
end

---@param view PWLoadoutEditorView
---@param id string
local function chooseRow(view, id)
    view.rowId = id
    showPicker(view)
    showInfo(view)
end

---@param view PWLoadoutEditorView
local function rebuildRows(view)
    view.rowsPanel:Clear()
    view.rows, view.rowIds = {}, {}
    for index, row in ipairs(view.model.rows) do
        local id = row.id
        local panel = ui().RowButton(view.rowsPanel, "editor_rows", "row:" .. id)
        panel:Dock(TOP)
        panel:DockMargin(0, 0, 0, kit().Draw.Px(6))
        view.rowsPanel:AddItem(panel)
        panel.PWOnFocus = function()
            if view.rowId ~= id then chooseRow(view, id) end
        end
        panel.DoClick = function()
            chooseRow(view, id)
            ui().FocusLater(view.picker:FocusIndex(view.picker.focusIndex, 1))
        end
        view.rows[id], view.rowIds[index] = panel, id
    end
end

---After a change the row may have a new id (a wildcard turned "perk1" into "perk1#1"): the same slot's first row.
---@param view PWLoadoutEditorView
---@param slot string
local function keepRow(view, slot)
    if view.rows[view.rowId or ""] ~= nil then return end
    for _, row in ipairs(view.model.rows) do
        if row.slot == slot then
            view.rowId = row.id
            return
        end
    end
end

---@param view PWLoadoutEditorView
---@param slot? string keep the focus on this slot when its row id changed
local function refresh(view, slot)
    view.input = ui().LiveInput(view.draft.loadout)
    view.model = ui().Editor(view.input)
    local same = #view.rowIds == #view.model.rows
    for index, row in ipairs(view.model.rows) do
        if view.rowIds[index] ~= row.id then same = false end
    end
    if not same then rebuildRows(view) end
    if slot ~= nil then keepRow(view, slot) end
    showPicker(view)
    showInfo(view)
end

---@param view PWLoadoutEditorView
---@param cardId string
local function choose(view, cardId)
    local row = currentRow(view)
    if row == nil then return end
    local draft = view.draft
    draft.loadout = ui().SetItem(view.input, row.id, cardId ~= noneId and cardId or nil)
    draft.dirty, draft.saved = true, false
    refresh(view, row.slot)
    ui().FocusLater(view.rows[view.rowId or ""])
end

-- Name ------------------------------------------------------------------------------------------------------------

---Takes the name from the field: true when it is valid (and applied), else the reason is shown under it.
---@param view PWLoadoutEditorView
---@return boolean
local function applyName(view)
    ---@type string[]
    local others = {}
    for index, class in ipairs(ui().ReadClasses()) do
        if index ~= view.draft.index then others[#others + 1] = class.name end
    end
    local clean, why = ui().ValidateName(view.entry:GetValue(), others)
    view.nameError = why
    if clean == nil then return false end
    if clean ~= view.draft.name then
        view.draft.name, view.draft.dirty, view.draft.saved = clean, true, false
    end
    view.entry:SetValue(clean)
    return true
end

---@param view PWLoadoutEditorView
local function buildName(view)
    local row = vgui.Create("Panel", view) --[[@as Panel]]
    kit().Focusable(row, "editor_rows", "name")
    local entry = vgui.Create("DTextEntry", row) --[[@as DTextEntry]]
    entry:SetFont(kit().FontName("body"))
    entry:SetValue(view.draft.name)
    entry.OnEnter = function()
        applyName(view)
        showInfo(view)
    end
    local hooks, entryHooks = row --[[@as PANEL]], entry --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h)
        local px = kit().Draw.Px
        entry:SetPos(px(110), px(10))
        entry:SetSize(w - px(130), h - px(20))
    end
    hooks.Paint = function(_, w, h)
        local s, paint = kit().Style --[[@as PW.UIStyle]], kit().Draw
        paint.Rect(0, 0, w, h, row._pwFocused and s.bg_hover or s.bg_panel)
        if row._pwFocused then paint.EdgeBar(h) end
        draw.SimpleText("NAME", kit().FontName("small"), paint.Px(20), h / 2, s.text_muted, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end
    entryHooks.Paint = function(_, w, h)
        local s, paint = kit().Style --[[@as PW.UIStyle]], kit().Draw
        paint.Rect(0, 0, w, h, s.bg_raised)
        local edge = view.nameError ~= nil and s.negative or (entry:HasFocus() and s.accent or s.border_strong)
        paint.Outline(0, 0, w, h, edge, paint.Px(2))
        entry:DrawTextEntryText(s.text, s.bg_selected, s.text)
    end
    row.PWActivate = function() entry:RequestFocus() end
    view.nameRow, view.entry = row, entry
end

-- Screen ----------------------------------------------------------------------------------------------------------

---@param view PWLoadoutEditorView
local function save(view)
    if not applyName(view) then return showInfo(view) end
    ui().SaveDraft()
    showInfo(view)
end

---@param view PWLoadoutEditorView
local function openGunsmith(view)
    local slot = gunsmithSlot(view)
    if slot == nil then return end
    applyName(view)
    ui().OpenGunsmith(slot)
end

---@param view PWLoadoutEditorView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit().Draw.Px
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 560, right = 460, gap = 40, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    local gap, nameH = px(12), px(72)
    view.nameRow:SetPos(left.x, left.y)
    view.nameRow:SetSize(left.w, nameH)
    view.rowsPanel:SetPos(left.x, left.y + nameH + gap)
    view.rowsPanel:SetSize(left.w, left.h - nameH - gap)
    view.pickerTitle:SetPos(centre.x, centre.y)
    view.pickerTitle:SetSize(centre.w, px(48))
    view.picker:SetPos(centre.x, centre.y + px(48) + gap)
    view.picker:SetSize(centre.w, centre.h - px(48) - gap)
    local meterH, buttonH = px(170), px(52)
    view.meter:SetPos(right.x, right.y)
    view.meter:SetSize(right.w, meterH)
    local buttonsH = 2 * buttonH + gap
    local infoH = math.min(view.info:WantedHeight(right.w), right.h - meterH - buttonsH - 3 * gap)
    view.info:SetPos(right.x, right.y + meterH + gap)
    view.info:SetSize(right.w, infoH)
    view.gunsmith:SetPos(right.x, right.y + meterH + infoH + 2 * gap)
    view.gunsmith:SetSize(right.w, buttonH)
    view.save:SetPos(right.x, right.y + meterH + infoH + buttonH + 3 * gap)
    view.save:SetSize(right.w, buttonH)
end

---@param view PWLoadoutEditorView
local function paintMeter(view, w, h)
    local meter = view.model.meter
    local note = (meter.state == "over" and "Over the budget: the class is not usable")
        or (meter.state == "unlimited" and "No budget in this match") or "Streaks are outside the budget"
    ui().PaintMeter(w, h, "PICK X BUDGET", meter.text, meter.fraction, meter.state, note)
end

---@param view PWLoadoutEditorView
local function buildPanels(view)
    view.rowsPanel = vgui.Create("DScrollPanel", view) --[[@as DScrollPanel]]
    view.rows, view.rowIds = {}, {}
    view.pickerTitle = vgui.Create("Panel", view) --[[@as Panel]]
    local titleHooks = view.pickerTitle --[[@as PANEL]]
    titleHooks.Paint = function(_, w, h)
        local s, row = kit().Style --[[@as PW.UIStyle]], currentRow(view)
        draw.SimpleText(row ~= nil and row.label or "", kit().FontName("h2"), 0, h / 2, s.text, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        kit().Draw.Rect(0, h - 1, w, 1, s.border)
    end
    view.picker = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.picker.OnSelect = function(_, id) choose(view, id) end
    view.meter = vgui.Create("Panel", view) --[[@as Panel]]
    local meterHooks = view.meter --[[@as PANEL]]
    meterHooks.Paint = function(_, w, h) paintMeter(view, w, h) end
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.gunsmith = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.gunsmith:SetVariant("secondary")
    view.gunsmith.DoClick = function() openGunsmith(view) end
    view.save = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.save:SetText("SAVE")
    view.save:SetPrimary(true)
    view.save.DoClick = function() save(view) end
    for _, button in ipairs({ view.gunsmith, view.save }) do kit().Focusable(button, "editor_buttons") end
end

function SCREEN:Build(ctx)
    local draft = rawget(PW, "LoadoutUI") ~= nil and ui().Draft or nil
    if draft == nil then return nil end
    draft.navigating = false
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLoadoutEditorView]]
    view:Dock(FILL)
    view.draft = draft
    buildName(view)
    buildPanels(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.OnRemove = function()
        if ui().Draft ~= draft or draft.navigating then return end
        if applyName(view) and draft.dirty then ui().SaveDraft() end
    end
    view.PWRefresh = function() if IsValid(view) then showInfo(view) end end
    view.OnAction = function(_, action)
        if action == "tertiary" then save(view) elseif action == "secondary" then openGunsmith(view) end
    end
    refresh(view)
    if draft.focusName then
        draft.focusName = false
        timer.Simple(0, function() if IsValid(view.entry) then view.entry:RequestFocus() end end)
    end
    return view
end
