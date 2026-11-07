-- Router (U-3; notes/16 Q1; 10-frontend.md d.1, d.8): one stack of screens per tab, Push / Pop / Replace /
-- SwitchTab, Back. Pure: plain screen tables (the screens kind), no vgui. Screens are built through PW.Call, so a
-- screen whose Build errors is skipped and the others keep working.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local router = (rawget(lib, "Router") or {}) --[[@as PW.UIRouterLib]]
lib.Router = router

-- Hub tabs (d.8). SETTINGS is a hint-bar action, not a tab. The in-match roots (T-7.6) open the router over
-- another tab set: the pause menu over MATCH and LOADOUT, the death class picker over CLASS alone.
router.TabOrder = { "play", "loadout", "progress", "store" }
router.TabLabels = {
    play = "PLAY", loadout = "LOADOUT", progress = "PROGRESS", store = "STORE", match = "MATCH", class = "CLASS"
}

local defaultOrder = 100

---Lowest Order wins; ties by id, so the choice does not depend on registry order.
---@param a PW.Screen
---@param b PW.Screen
---@return boolean
local function rootBefore(a, b)
    local oa, ob = a.Order or defaultOrder, b.Order or defaultOrder
    if oa ~= ob then return oa < ob end
    return a.ClassName < b.ClassName
end

---@param screens PW.Screen[]
---@param tab string
---@return PW.Screen?
local function rootOf(screens, tab)
    ---@type PW.Screen?
    local best = nil
    for _, item in ipairs(screens) do
        if item.Tab == tab and item.Root and (best == nil or rootBefore(item, best)) then best = item end
    end
    return best
end

function router.New(screens, tabs)
    local order = tabs or router.TabOrder
    ---@type PW.UIRouterModel
    local model = { tabs = {}, tabById = {}, stacks = {}, screens = {}, active = order[1] }
    for _, item in ipairs(screens) do model.screens[item.ClassName] = item end
    for _, id in ipairs(order) do
        local root = rootOf(screens, id)
        ---@type PW.UIRouterTab
        local tab = { id = id, label = router.TabLabels[id] or string.upper(id), locked = root == nil, root = root }
        if root == nil then tab.reason = "soon" end
        model.tabs[#model.tabs + 1] = tab
        model.tabById[id] = tab
        model.stacks[id] = root ~= nil and { root } or {}
    end
    for _, tab in ipairs(model.tabs) do
        if not tab.locked then
            model.active = tab.id
            break
        end
    end
    return model
end

function router.Top(model)
    local tab = model.tabById[model.active]
    if tab == nil or tab.locked then return nil end
    local stack = model.stacks[model.active]
    return stack[#stack]
end

function router.Depth(model)
    return #model.stacks[model.active]
end

---@param model PW.UIRouterModel
---@param screen PW.Screen|string
---@return PW.Screen?
local function resolve(model, screen)
    if type(screen) == "string" then return model.screens[screen] end
    return screen
end

function router.Push(model, screen)
    local item = resolve(model, screen)
    local stack = model.stacks[model.active]
    if item == nil or #stack == 0 then return false end
    stack[#stack + 1] = item
    return true
end

function router.Pop(model)
    local stack = model.stacks[model.active]
    if #stack <= 1 then return false end
    stack[#stack] = nil
    return true
end

function router.Replace(model, screen)
    local item = resolve(model, screen)
    local stack = model.stacks[model.active]
    if item == nil or #stack == 0 then return false end
    stack[#stack] = item
    return true
end

function router.SwitchTab(model, id)
    local tab = model.tabById[id]
    if tab == nil or tab.locked then return false end
    model.active = id
    return true
end

function router.Cycle(model, delta)
    local count = #model.tabs
    local from = 1
    for index, tab in ipairs(model.tabs) do
        if tab.id == model.active then from = index end
    end
    for step = 1, count - 1 do
        local tab = model.tabs[(from - 1 + delta * step) % count + 1]
        if tab ~= nil and not tab.locked then
            model.active = tab.id
            return true
        end
    end
    return false
end

function router.SetLocked(model, id, locked, reason)
    local tab = model.tabById[id]
    if tab == nil then return end
    tab.locked = locked
    tab.reason = locked and (reason or "locked") or nil
    if not locked then
        if #model.stacks[id] == 0 and tab.root ~= nil then model.stacks[id] = { tab.root } end
        return
    end
    if model.active ~= id then return end
    for _, other in ipairs(model.tabs) do
        if not other.locked then
            model.active = other.id
            return
        end
    end
end

function router.Back(model, phase)
    if router.Pop(model) then return "pop" end
    if phase == "LOBBY" then return "stay" end
    return "close"
end

function router.Act(model, action, phase)
    if action == "tab_next" or action == "tab_prev" then
        local top = router.Top(model)
        if top ~= nil and top.OwnsTabKeys == true then return nil end
        return router.Cycle(model, action == "tab_next" and 1 or -1) and "tab" or "stay"
    end
    if action == "back" then return router.Back(model, phase) end
    return nil
end

function router.Build(model, ctx)
    -- Each failed attempt drops a screen or locks a tab, so the loop is bounded by their total count.
    local attempts = #model.tabs
    for _, stack in pairs(model.stacks) do attempts = attempts + #stack end
    for _ = 1, attempts do
        local top = router.Top(model)
        if top == nil then return nil end
        local view = PW.Call(top, "Build", ctx)
        if view ~= nil then return view, top end
        if not router.Pop(model) then router.SetLocked(model, model.active, true, "error") end
    end
    return nil
end
