-- Gunsmith (T-7.4; 05-loadout.md d.3, d.15; 06-progression.md d.2; 10-frontend.md d.1 "GUNSMITH weapon + attachment
-- slots"). Pushed from the class editor for one weapon slot of PW.LoadoutUI.Draft. Left: the adapter's build slots
-- with the installed option; centre: the options of the focused slot (a curated option above the weapon level shows
-- "LV <n>", one past a limit "FULL"); right: the attachment count against the cap and the weapon level, the
-- client-side preview of the save-time check and SAVE. A weapon whose adapter offers no slots (the HL2 fallback)
-- shows a clear "no gunsmith" card. Leaving with unsaved changes saves them, so the server's answer shows in the
-- editor. Thin glue over PW.LoadoutUI.Gunsmith and SetOption (modules/loadout_ui/sh_gunsmith.lua).

SCREEN.Tab = "loadout"
SCREEN.Title = "Gunsmith"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "tertiary", label = "Save" },
    { action = "back", label = "Back (saves)" }
}

local defaultId = "@default"

---@class PWLoadoutGunsmithView : Panel
---@field draft PW.LoadoutUIDraft
---@field input? PW.LoadoutUIGunsmithInput
---@field model? PW.LoadoutUIGunsmith
---@field rowsPanel DScrollPanel
---@field rows table<string, PWLoadoutRow>
---@field rowIds string[]
---@field slotId? string the build slot whose options the centre shows
---@field pickerTitle Panel
---@field picker PWCardList
---@field empty PWInfoCard the "no gunsmith" card
---@field meter Panel
---@field info PWInfoCard
---@field save PWButton
---@field OnAction fun(self: PWLoadoutGunsmithView, action: string)

---@return PW.LoadoutUILib
local function ui()
    return PW.LoadoutUI --[[@as PW.LoadoutUILib]]
end

---@return PW.UILib
local function kit()
    return PW.UI --[[@as PW.UILib]]
end

---@param view PWLoadoutGunsmithView
---@return PW.LoadoutUIGunsmithSlot?
local function currentSlot(view)
    local model = view.model
    if model == nil then return nil end
    for _, slot in ipairs(model.slots) do
        if slot.id == view.slotId then return slot end
    end
    return model.slots[1]
end

---@param view PWLoadoutGunsmithView
local function showInfo(view)
    local model, input = view.model, view.input
    local result = ui().DraftResult ~= nil and ui().DraftResult() or nil
    view.info:SetTitle(result ~= nil and result.title or (view.draft.dirty and "Unsaved changes" or "Preview"))
    ---@type { [1]: string, [2]: string }[]
    local rows = {}
    if input ~= nil then
        rows[1] = { "WEAPON", input.weaponName }
        rows[2] = { "WEAPON LEVEL", input.unlockAll and "everything unlocked" or tostring(input.weaponLevel) }
    end
    view.info:SetRows(rows)
    local lines = result ~= nil and result.lines or {}
    local note = model ~= nil and model.gunsmith and model.note or nil -- without a gunsmith the big card says it
    view.info:SetText(#lines > 0 and table.concat(lines, ", ") or note)
    local problems = model ~= nil and model.problems or {}
    view.info:SetWarning(#problems > 0 and table.concat(problems, ", ") or nil)
    view:InvalidateLayout()
end

---@param view PWLoadoutGunsmithView
local function updateRows(view)
    for _, slot in ipairs(view.model ~= nil and view.model.slots or {}) do
        local panel = view.rows[slot.id]
        panel.pwLabel, panel.pwValue = string.upper(slot.name), slot.currentName
        panel.pwSide = slot.cosmetic and "COSMETIC" or ""
        panel.pwChosen = slot.id == view.slotId
    end
end

---@param view PWLoadoutGunsmithView
local function showPicker(view)
    local slot = currentSlot(view)
    if slot == nil then return view.picker:SetCards({}, nil) end
    view.slotId = slot.id
    ---@type PW.UICard[]
    local cards = {}
    local selected = defaultId
    for index, option in ipairs(slot.options) do
        ---@type PW.UICard
        local card = { id = option.id == "" and defaultId or option.id, title = option.name }
        card.badge = option.costText ~= "" and option.costText or nil
        card.locked, card.reason, card.lockText = option.locked, option.reason, option.lockText
        card.text = option.reason
        if option.selected then selected = card.id end
        cards[index] = card
    end
    view.picker:SetCards(cards, selected)
    updateRows(view)
    local root = kit().CurrentRoot() --[[@as PWRoot?]]
    if root ~= nil then root.focusDirty = 2 end
end

---@param view PWLoadoutGunsmithView
local function rebuildRows(view)
    view.rowsPanel:Clear()
    view.rows, view.rowIds = {}, {}
    for index, slot in ipairs(view.model ~= nil and view.model.slots or {}) do
        local id = slot.id
        local panel = ui().RowButton(view.rowsPanel, "gunsmith_rows", "slot:" .. id)
        panel:Dock(TOP)
        panel:DockMargin(0, 0, 0, kit().Draw.Px(6))
        view.rowsPanel:AddItem(panel)
        panel.PWOnFocus = function()
            if view.slotId == id then return end
            view.slotId = id
            showPicker(view)
        end
        panel.DoClick = function()
            view.slotId = id
            showPicker(view)
            ui().FocusLater(view.picker:FocusIndex(view.picker.focusIndex, 1))
        end
        view.rows[id], view.rowIds[index] = panel, id
    end
end

---@param view PWLoadoutGunsmithView
local function refresh(view)
    view.input = ui().LiveGunsmith(view.draft)
    view.model = view.input ~= nil and ui().Gunsmith(view.input --[[@as PW.LoadoutUIGunsmithInput]]) or nil
    local model = view.model
    local has = model ~= nil and model.gunsmith
    for _, panel in ipairs({ view.rowsPanel, view.pickerTitle, view.picker }) do panel:SetVisible(has) end
    view.empty:SetVisible(not has)
    view.empty:SetTitle(model ~= nil and ("No gunsmith: " .. model.title) or "No weapon in this slot")
    view.empty:SetText(model ~= nil and model.note or "Pick a weapon in the class editor first.")
    local same = model ~= nil and #view.rowIds == #model.slots
    for index, slot in ipairs(model ~= nil and model.slots or {}) do
        if view.rowIds[index] ~= slot.id then same = false end
    end
    if not same then rebuildRows(view) end
    showPicker(view)
    showInfo(view)
end

---@param view PWLoadoutGunsmithView
---@param cardId string
local function choose(view, cardId)
    local input, slot = view.input, currentSlot(view)
    local weaponSlot = view.draft.weaponSlot
    if input == nil or slot == nil or weaponSlot == nil then return end
    local build = ui().SetOption(input.build, slot.id, cardId ~= defaultId and cardId or nil)
    local copy = table.Copy(view.draft.loadout) --[[@as table<string, any>]]
    local builds = istable(copy.builds) and copy.builds --[[@as table<string, any>]] or {}
    builds[weaponSlot] = next(build) ~= nil and build or nil
    copy.builds = next(builds) ~= nil and builds or nil
    view.draft.loadout, view.draft.dirty, view.draft.saved = copy --[[@as PW.Loadout]], true, false
    refresh(view)
    ui().FocusLater(view.rows[slot.id])
end

---@param view PWLoadoutGunsmithView
---@param w number
---@param h number
local function paintMeter(view, w, h)
    local model = view.model
    if model == nil or not model.gunsmith then return end
    local state = (model.over and "over") or (model.count == model.cap and "full") or "ok"
    local fraction = model.cap > 0 and model.count / model.cap or 0
    local note = model.levelLimit ~= nil
        and ("Weapon level allows " .. model.levelLimit .. " (" .. model.levelCount .. " used)")
        or "Everything unlocked"
    ui().PaintMeter(w, h, "ATTACHMENTS", model.countText, fraction, state, note)
end

---@param view PWLoadoutGunsmithView
---@param w number
---@param h number
local function layout(view, w, h)
    local px = kit().Draw.Px
    local columns = kit().Layout.Columns(w, h, { margin = 96, left = 560, right = 460, gap = 40, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    local gap = px(12)
    view.rowsPanel:SetPos(left.x, left.y)
    view.rowsPanel:SetSize(left.w, left.h)
    view.pickerTitle:SetPos(centre.x, centre.y)
    view.pickerTitle:SetSize(centre.w, px(48))
    view.picker:SetPos(centre.x, centre.y + px(48) + gap)
    view.picker:SetSize(centre.w, centre.h - px(48) - gap)
    view.empty:SetPos(left.x, left.y)
    view.empty:SetSize(left.w + centre.w + px(40), math.min(view.empty:WantedHeight(left.w + centre.w), left.h))
    local meterH, buttonH = px(170), px(52)
    view.meter:SetPos(right.x, right.y)
    view.meter:SetSize(right.w, meterH)
    local infoH = math.min(view.info:WantedHeight(right.w), right.h - meterH - buttonH - 2 * gap)
    view.info:SetPos(right.x, right.y + meterH + gap)
    view.info:SetSize(right.w, infoH)
    view.save:SetPos(right.x, right.y + meterH + infoH + 2 * gap)
    view.save:SetSize(right.w, buttonH)
end

---@param view PWLoadoutGunsmithView
local function buildPanels(view)
    view.rowsPanel = vgui.Create("DScrollPanel", view) --[[@as DScrollPanel]]
    view.rows, view.rowIds = {}, {}
    view.pickerTitle = vgui.Create("Panel", view) --[[@as Panel]]
    local titleHooks = view.pickerTitle --[[@as PANEL]]
    titleHooks.Paint = function(_, w, h)
        local s, slot = kit().Style --[[@as PW.UIStyle]], currentSlot(view)
        draw.SimpleText(slot ~= nil and string.upper(slot.name) or "", kit().FontName("h2"), 0, h / 2, s.text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        kit().Draw.Rect(0, h - 1, w, 1, s.border)
    end
    view.picker = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.picker.OnSelect = function(_, id) choose(view, id) end
    view.empty = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.meter = vgui.Create("Panel", view) --[[@as Panel]]
    local meterHooks = view.meter --[[@as PANEL]]
    meterHooks.Paint = function(_, w, h) paintMeter(view, w, h) end
    view.info = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.save = vgui.Create("PWButton", view) --[[@as PWButton]]
    view.save:SetText("SAVE")
    view.save:SetPrimary(true)
    view.save.DoClick = function()
        ui().SaveDraft()
        showInfo(view)
    end
    kit().Focusable(view.save, "gunsmith_buttons")
end

function SCREEN:Build(ctx)
    local draft = rawget(PW, "LoadoutUI") ~= nil and ui().Draft or nil
    if draft == nil or draft.weaponSlot == nil then return nil end
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWLoadoutGunsmithView]]
    view:Dock(FILL)
    view.draft = draft
    buildPanels(view)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.OnRemove = function()
        if ui().Draft == draft and draft.dirty then ui().SaveDraft() end
    end
    view.PWRefresh = function() if IsValid(view) then showInfo(view) end end
    view.OnAction = function(_, action)
        if action ~= "tertiary" then return end
        ui().SaveDraft()
        showInfo(view)
    end
    refresh(view)
    return view
end
