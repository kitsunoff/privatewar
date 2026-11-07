-- Class picker during a match (T-7.6; 10-frontend.md d.1 "class picker on death"; 05-loadout.md d.12). Root of the
-- in-match tab CLASS: the compact root that opens on death in LIVE (ui_kit/cl_match.lua). The pause menu pushes the
-- same screen (CHANGE CLASS), where Back returns to the menu. The cards are the player's classes (presets, then
-- custom), the current one marked CURRENT, an unavailable one locked with its reason. Choosing an available class
-- sends the class pick (PW.Loadout.SendPick); it applies from the next spawn. Thin glue over PW.UI.Match.ClassCards
-- and Choose (sh_match.lua).

SCREEN.Tab = "class"
SCREEN.Root = true
SCREEN.Title = "Choose class"
SCREEN.Hints = { { action = "accept", label = "Use class" }, { action = "back", label = "Close" } }

---@class PWMatchClassesView : Panel
---@field cardList PWCardList
---@field root PWRoot
---@field heading boolean the view draws its own heading (the compact root has no title)
---@field asked? boolean the upload was sent again because no state had arrived

local headingHeight = 96

---@return PW.LoadoutLib?
local function loadout()
    return rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
end

---@return PW.LoadoutClassState?
local function classState()
    local lib = loadout()
    return lib ~= nil and lib.GetClassState ~= nil and lib.GetClassState() or nil
end

---Leaves the picker: back to the pause menu when it was pushed there, else the compact root closes.
---@param view PWMatchClassesView
local function leave(view)
    local kit = PW.UI --[[@as PW.UILib]]
    local router = kit.Router --[[@as PW.UIRouterLib]]
    if router.Pop(view.root.model) then return view.root:Rebuild() end
    view.root:Remove()
end

---@param view PWMatchClassesView
---@param ref string
local function choose(view, ref)
    local lib = loadout()
    if lib == nil then return end
    local result = (PW.UI --[[@as PW.UILib]]).Match.Choose(classState(), ref, lib.SendPick)
    if result == "sent" or result == "current" then leave(view) end
end

---@param view PWMatchClassesView
local function refresh(view)
    local lib = loadout()
    local state = classState()
    if state == nil and not view.asked and lib ~= nil and lib.UploadClasses ~= nil then
        view.asked = true -- the join upload or its answer was lost
        lib.UploadClasses()
    end
    local cards, current = (PW.UI --[[@as PW.UILib]]).Match.ClassCards(state)
    view.cardList:SetCards(cards, current)
    for index, card in ipairs(view.cardList.panels) do
        card.DoClick = function() choose(view, cards[index].id) end
    end
    view.root.focusDirty = 2
end

---@param view PWMatchClassesView
---@param w number
local function paint(view, w)
    if not view.heading then return end
    local kit = PW.UI --[[@as PW.UILib]]
    local s, draw_ = kit.Style --[[@as PW.UIStyle]], kit.Draw
    draw_.Rect(0, 0, w, draw_.Px(headingHeight - 16), s.bg_panel)
    draw_.EdgeBar(draw_.Px(headingHeight - 16))
    local pad = draw_.Px(20)
    draw.SimpleText("CHOOSE CLASS", kit.Font("h2"), pad, draw_.Px(10), s.text)
    local note = classState() == nil and "Waiting for the server" or "Used from your next spawn"
    draw.SimpleText(note, kit.Font("small"), pad, draw_.Px(48), s.text_muted)
end

function SCREEN:Build(ctx)
    local root = ctx.root --[[@as PWRoot]]
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWMatchClassesView]]
    view:Dock(FILL)
    view.root, view.heading = root, root.compact == true
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h)
        local px = (PW.UI --[[@as PW.UILib]]).Draw.Px
        local top = view.heading and px(headingHeight) or 0
        local side = view.heading and 0 or px(96)
        view.cardList:SetPos(side, top)
        view.cardList:SetSize(math.min(w - 2 * side, px(640)), h - top - px(16))
    end
    hooks.Paint = function(_, w) paint(view, w) end
    view.PWRefresh = function() refresh(view) end
    refresh(view)
    return view
end
