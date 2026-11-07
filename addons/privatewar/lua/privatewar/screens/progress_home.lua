-- Progress, root of the PROGRESS tab (T-7.5; 06-progression.md d.1, d.4; 10-frontend.md d.1 "PROGRESS: player level,
-- weapon levels, unlocks"). Left: the player level with the XP bar (NW2 pw_level, pw_xpin, pw_xpneed) and the last
-- match summary when one arrived (PW.Progression.MatchSummary). Centre: the weapon levels list (every weapon of the
-- registry and every class with XP in the local file, highest level first; the selected one shows its XP to the next
-- level). Right: the next unlocks (entities whose Unlock level is above the player's, the closest first). Thin glue
-- over PW.UI.Progress (ui_kit/sh_progress.lua); it shows data only and sends nothing.

SCREEN.Tab = "progress"
SCREEN.Root = true
SCREEN.Order = 10
SCREEN.Title = "Progress"
SCREEN.Hints = { { action = "accept", label = "Details" }, { action = "back", label = "Back" } }

local unlockCount = 8

---@class PWProgressHomeView : Panel
---@field level PWInfoCard
---@field bar PWProgressBar
---@field summary PWInfoCard
---@field weaponList PWCardList
---@field unlocks PWInfoCard
---@field weapon? string the selected weapon class
---@field nextTick number

---@return PW.UIProgressLib
local function progress()
    return PW.UI.Progress --[[@as PW.UIProgressLib]]
end

---@return PW.UIStoreLib
local function store()
    return PW.UI.Store --[[@as PW.UIStoreLib]]
end

---A display name: a "#token" (HL2 weapons) through the language files.
---@param name any
---@param fallback string
---@return string
local function display(name, fallback)
    if not isstring(name) then return fallback end
    local text = name --[[@as string]]
    if string.sub(text, 1, 1) == "#" then return language.GetPhrase(string.sub(text, 2)) end
    return text
end

---Every weapon of the registry, plus the classes with XP that the registry lacks (the SWEP PrintName); names are
---resolved for display.
---@param catalogue PW.EconomyCatalogue
---@param xp table<string, number>
---@return table<string, table<string, any>>
local function weaponsOf(catalogue, xp)
    ---@type table<string, table<string, any>>
    local out = {}
    for id, entity in pairs(catalogue.weapons or {}) do out[id] = { Name = display(entity.Name, id) } end
    for class in pairs(xp) do
        if out[class] == nil then
            local swep = weapons.GetStored(class)
            out[class] = { Name = display(swep ~= nil and swep.PrintName or nil, class) }
        end
    end
    return out
end

---@param lib PW.ProgressionLib
---@return fun(xp: number): integer, number, number
local function weaponCurve(lib)
    local params = lib._Params(function(id) return PW.Setting(id) end)
    return function(xp) return lib._WeaponLevel(params, xp) end
end

---@param view PWProgressHomeView
---@param lib PW.ProgressionLib
---@param catalogue PW.EconomyCatalogue
local function showWeapons(view, lib, catalogue)
    local file = lib.GetLocalFile()
    local xp = file ~= nil and file.weapons or {}
    local rows = progress().Weapons(weaponsOf(catalogue, xp), xp, weaponCurve(lib))
    view.weapon = view.weapon or (rows[1] ~= nil and rows[1].id or nil)
    store().UpdateCards(view.weaponList, progress().WeaponCards(rows), view.weapon)
end

---@param view PWProgressHomeView
---@param lib PW.ProgressionLib
---@param catalogue PW.EconomyCatalogue
local function showLevel(view, lib, catalogue)
    local me = LocalPlayer()
    local level = lib.GetLevel(me)
    local into, need = lib.GetProgress(me)
    local card = progress().LevelView(level, into, need)
    view.level:SetTitle(card.title)
    view.level:SetRows({ { "XP", card.xpText }, { "CREDITS", store().PriceText(lib.GetCurrency(me)) } })
    view.bar:SetProgress(card.fraction, card.maxed and "MAX" or string.format("%d%%", math.floor(card.fraction * 100)))
    local unlocks = progress().NextUnlocks(catalogue, level, unlockCount)
    view.unlocks:SetTitle("Next unlocks")
    view.unlocks:SetRows(progress().UnlockRows(unlocks))
    view.unlocks:SetText(#unlocks == 0 and "Everything is unlocked at your level." or nil)
    local rows = progress().SummaryRows(lib.MatchSummary(me), function(class)
        local weapon = (catalogue.weapons or {})[class]
        return display(weapon ~= nil and weapon.Name or nil, class)
    end)
    view.summary:SetTitle("Last match")
    view.summary:SetRows(rows or {})
    view.summary:SetText(rows == nil and "Play a match to see its summary here." or nil)
end

---@param view PWProgressHomeView
local function refresh(view)
    local lib = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if lib == nil or not IsValid(LocalPlayer()) then
        view.level:SetTitle("Progression is off")
        view.level:SetText("The progression module is not running on this server.")
        return
    end
    local catalogue = store().LiveCatalogue()
    showLevel(view, lib, catalogue)
    showWeapons(view, lib, catalogue)
    view:InvalidateLayout(true)
end

---@param view PWProgressHomeView
---@param w number
---@param h number
local function layout(view, w, h)
    local kit = PW.UI --[[@as PW.UILib]]
    local px = kit.Draw.Px
    local columns = kit.Layout.Columns(w, h, { margin = 96, left = 520, right = 560, gap = 40, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    local gap = px(20)
    local levelH = view.level:WantedHeight(left.w)
    view.level:SetPos(left.x, left.y)
    view.level:SetSize(left.w, levelH)
    view.bar:SetPos(left.x, left.y + levelH + px(8))
    view.bar:SetSize(left.w, px(36))
    local summaryY = left.y + levelH + px(8) + px(36) + gap
    view.summary:SetPos(left.x, summaryY)
    view.summary:SetSize(left.w, math.min(view.summary:WantedHeight(left.w), left.y + left.h - summaryY))
    view.weaponList:SetPos(centre.x, centre.y)
    view.weaponList:SetSize(centre.w, centre.h)
    view.unlocks:SetPos(right.x, right.y)
    view.unlocks:SetSize(right.w, math.min(view.unlocks:WantedHeight(right.w), right.h))
end

function SCREEN:Build(ctx)
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWProgressHomeView]]
    view:Dock(FILL)
    view.nextTick = 0
    view.level = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.bar = vgui.Create("PWProgressBar", view) --[[@as PWProgressBar]]
    view.summary = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.weaponList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.weaponList.OnSelect = function(_, id) view.weapon = id end
    view.unlocks = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if RealTime() < view.nextTick then return end
        view.nextTick = RealTime() + 2 -- XP, levels and the summary arrive through deltas and NW2 values
        refresh(view)
    end
    view.PWRefresh = function() refresh(view) end
    refresh(view)
    return view
end
