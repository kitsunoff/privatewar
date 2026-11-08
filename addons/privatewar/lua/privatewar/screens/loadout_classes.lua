-- Class selection, root of the LOADOUT tab (T-4.7, T-7.4; 05-loadout.md d.12, d.13; 10-frontend.md d.1, d.3). Left:
-- only the player's custom classes from classes.json as cards; selecting one shows its
-- contents on the right and, when it is available, asks the server to use it from the next spawn
-- (PW.Loadout.SendPick). An unavailable class shows N/A and the reason (budget, attachment cap, empty after repair).
-- Under the contents: EDIT, COPY, RENAME, DELETE and NEW CLASS (PW.LoadoutUI.ClassActions). A custom class opens
-- the class editor (screens/loadout_editor.lua; RENAME starts in its name field). COPY duplicates its saved contents.
-- OPERATOR opens the operator picker (screens/loadout_operator.lua, 06-progression.md d.7).
-- Thin glue over PW.Loadout._ClassCards and _ClassRows (sh_classes_repair.lua) and the loadout_ui module.

SCREEN.Tab = "loadout"
SCREEN.Root = true
SCREEN.Order = 10
SCREEN.Title = "Classes"
SCREEN.Hints = {
    { action = "accept", label = "Use class" }, { action = "secondary", label = "Edit class" },
    { action = "tertiary", label = "New class" }, { action = "back", label = "Back" }
}

---@class PWLoadoutClassesView : Panel
---@field cardList PWCardList
---@field details PWInfoCard
---@field note Panel the result line of the last action
---@field buttons table<string, PWButton>
---@field order string[] action ids in display order
---@field viewing? string the ref of the card the details show
---@field asked? boolean the upload was sent again because no state had arrived
---@field message? string the result of the last action (a lock reason)
---@field OnAction fun(self: PWLoadoutClassesView, action: string)

---@return PW.LoadoutLib
local function loadout()
    return PW.Loadout --[[@as PW.LoadoutLib]]
end

---@return PW.LoadoutUILib?
local function editors()
    return rawget(PW, "LoadoutUI") --[[@as PW.LoadoutUILib?]]
end

---@param state? PW.LoadoutClassState
---@param ref? string
---@return PW.LoadoutClassEntry?
local function entryOf(state, ref)
    for _, entry in ipairs(state ~= nil and state.entries or {}) do
        if entry.ref == ref then return entry end
    end
    return nil
end

---@return PW.LoadoutClassState?
local function classState()
    local get = loadout().GetClassState
    local state = get ~= nil and get() or nil
    return state ~= nil and loadout().HumanClassState(state, true) or nil
end

---@param ref? string
---@return integer?
local function customIndex(ref)
    return tonumber(string.match(ref or "", "^custom:(%d+)$") or "")
end

---@param view PWLoadoutClassesView
local function showActions(view)
    local ui = editors()
    if ui == nil or ui.ClassActions == nil or ui.ReadClasses == nil then
        for id, button in pairs(view.buttons) do button:SetVisible(id == "operator") end
        return
    end
    for _, action in ipairs(ui.ClassActions(view.viewing, #ui.ReadClasses(), ui.MaxClasses())) do
        local button = view.buttons[action.id]
        button:SetVisible(true)
        button:SetLocked(action.locked, action.reason)
    end
end

---@param view PWLoadoutClassesView
---@param state? PW.LoadoutClassState
local function showDetails(view, state)
    local entry = entryOf(state, view.viewing)
    local details = view.details
    if entry == nil then
        local empty = state ~= nil and #state.entries == 0
        local title = empty and "No custom classes" or "No class selected"
        details:SetTitle(state == nil and "Waiting for the server" or title)
        details:SetRows({})
        details:SetText(empty and "Create a custom class with NEW CLASS." or
            (state ~= nil and "Pick a class on the left. It is used from your next spawn." or nil))
        details:SetWarning(nil)
    else
        details:SetTitle(entry.name)
        details:SetRows(loadout()._ClassRows(entry))
        local removed = #entry.removed > 0 and ("Removed by the server: " .. table.concat(entry.removed, ", ")) or nil
        details:SetText(removed)
        details:SetWarning(not entry.available and ("Not available: " .. (entry.reason or "")) or nil)
    end
    showActions(view)
    view:InvalidateLayout(true)
end

---@param view PWLoadoutClassesView
local function refresh(view)
    local state = classState()
    if state == nil and not view.asked and loadout().UploadClasses ~= nil then
        view.asked = true -- the join upload or its answer was lost
        loadout().UploadClasses()
    end
    local selected = state ~= nil and state.selected ~= "" and state.selected or nil
    if entryOf(state, view.viewing) == nil then
        view.viewing = selected or (state ~= nil and state.entries[1] ~= nil and state.entries[1].ref or nil)
    end
    view.cardList:SetCards(state ~= nil and loadout()._ClassCards(state, true) or {}, view.viewing)
    showDetails(view, state)
    local root = PW.UI.CurrentRoot() --[[@as PWRoot?]]
    if root ~= nil then root.focusDirty = 2 end
end

---@param view PWLoadoutClassesView
---@param ref string
local function select(view, ref)
    view.viewing, view.message = ref, nil
    local state = classState()
    local entry = entryOf(state, ref)
    if entry ~= nil and entry.available and loadout().SendPick ~= nil then loadout().SendPick(ref) end
    showDetails(view, state)
end

---Copy the custom class's saved data, not the repaired preview. There is no preset-id cloning path in this editor.
---@param ref string
---@param entry PW.LoadoutClassEntry
---@return PW.Loadout
local function sourceOf(ref, entry)
    local ui, index = editors(), customIndex(ref)
    local class = ui ~= nil and index ~= nil and ui.ReadClasses ~= nil and ui.ReadClasses()[index] or nil
    return class ~= nil and class.loadout or entry.loadout
end

---@param view PWLoadoutClassesView
---@param base string
---@param from PW.Loadout
local function create(view, base, from)
    local ui = editors() --[[@as PW.LoadoutUILib]]
    local index, why = (ui.Create --[[@as fun(base: string, value: PW.Loadout): integer?, string?]])(base, from)
    view.message = why
    if index ~= nil then (ui.Edit --[[@as fun(index: integer, focusName?: boolean): boolean]])(index, false) end
end

---@param view PWLoadoutClassesView
---@param id PW.LoadoutUIActionId|"operator"
local function run(view, id)
    if id == "operator" then
        local operators = rawget(PW, "Operators") --[[@as PW.OperatorsLib?]]
        if operators ~= nil and operators.OpenPicker ~= nil then operators.OpenPicker() end
        return
    end
    local ui = editors()
    local button = view.buttons[id]
    if ui == nil or ui.Edit == nil or button == nil or button._locked then return end
    local ref = view.viewing or ""
    local entry, index = entryOf(classState(), ref), customIndex(ref)
    if id == "new" then return create(view, "Class", loadout().Default()) end
    if id == "copy" and entry ~= nil then return create(view, entry.name, sourceOf(ref, entry)) end
    if index == nil then return end
    if id == "edit" or id == "rename" then return ui.Edit(index, id == "rename") end
    if id == "delete" then
        PW.UI.OpenDialog({
            title = "Delete class", confirm = "DELETE",
            text = "Delete " .. (entry ~= nil and entry.name or "this class") .. "? It is removed from classes.json " ..
                "on this computer.",
            onConfirm = function()
                (ui.Delete --[[@as fun(index: integer)]])(index)
                view.viewing = nil
            end
        })
    end
end

---@param view PWLoadoutClassesView
---@param action string
local function onAction(view, action)
    if action == "tertiary" then return run(view, "new") end
    if action ~= "secondary" then return end
    run(view, "edit")
end

---@param view PWLoadoutClassesView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 560, gap = 48, bottom = 16 }, px)
    local left, centre = columns.left --[[@as PW.UIRect]], columns.centre
    view.cardList:SetPos(left.x, left.y)
    view.cardList:SetSize(left.w, left.h)
    local buttonH, gap = px(52), px(12)
    local detailsH = math.min(view.details:WantedHeight(centre.w), centre.h - 2 * (buttonH + gap) - px(40))
    view.details:SetPos(centre.x, centre.y)
    view.details:SetSize(centre.w, detailsH)
    local count = 4
    local buttonW = math.floor((centre.w - (count - 1) * gap) / count)
    local y = centre.y + detailsH + gap
    for index, id in ipairs(view.order) do
        local button = view.buttons[id]
        local second = index > count
        local column = second and index - count - 1 or index - 1
        button:SetSize(buttonW, buttonH)
        button:SetPos(centre.x + column * (buttonW + gap), second and y + buttonH + gap or y)
    end
    view.note:SetPos(centre.x, y + 2 * (buttonH + gap))
    view.note:SetSize(centre.w, px(32))
end

---@param view PWLoadoutClassesView
local function buildButtons(view)
    view.buttons, view.order = {}, { "edit", "copy", "rename", "delete", "new", "operator" }
    local labels = {
        edit = "EDIT", copy = "COPY", rename = "RENAME", delete = "DELETE", new = "NEW CLASS", operator = "OPERATOR"
    }
    for _, id in ipairs(view.order) do
        local button = vgui.Create("PWButton", view) --[[@as PWButton]]
        button:SetText(labels[id])
        local second = id == "new" or id == "operator"
        button:SetVariant(id == "delete" and "danger" or (second and "secondary" or nil))
        local spec = PW.UI.Focusable(button, second and "class_new" or "class_actions")
        spec.axis = "horizontal"
        button.DoClick = function() run(view, id) end
        view.buttons[id] = button
    end
    view.note = vgui.Create("Panel", view) --[[@as Panel]]
    local hooks = view.note --[[@as PANEL]]
    hooks.Paint = function(_, _w, h)
        if view.message == nil then return end
        local kit = PW.UI --[[@as PW.UILib]]
        draw.SimpleText(view.message, kit.FontName("small"), 0, h / 2, (kit.Style --[[@as PW.UIStyle]]).warning,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLoadoutClassesView]]
    view:Dock(FILL)
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cardList.OnSelect = function(_, ref) select(view, ref) end
    view.details = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    buildButtons(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    view.PWRefresh = function() refresh(view) end
    view.OnAction = function(_, action) onAction(view, action) end
    refresh(view)
    return view
end
