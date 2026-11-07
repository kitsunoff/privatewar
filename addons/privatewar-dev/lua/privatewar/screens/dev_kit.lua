-- Dev-only showcase of the kit v1 components (U-4, checkpoint CP-UI1). It is the root screen of the PLAY tab while
-- no real hub screen exists (Order 900: a real PLAY root wins), opened with pw_ui_root. Fake data only; the form goes
-- through the real PW.UI.BuildForm path and prints the wire value of every change. Never shipped (dev addon).

SCREEN.Tab = "play"
SCREEN.Root = true
SCREEN.Order = 900
SCREEN.Title = "Kit showcase"
SCREEN.Hints = {
    { action = "accept", label = "Select" }, { action = "back", label = "Back" },
    { action = "page_down", label = "Next page" }, { action = "tertiary", label = "Teams preview" }
}

---@type PW.UICard[]
local cards = {
    {
        id = "shipment", title = "Shipment 24/7", new = true,
        text = "Small map, fast respawns. Every mode on one map, all day long.",
        tags = "TDM  ·  DOM  ·  KC", footer = "Fills to 12 with bots"
    },
    { id = "ffa", title = "Free for all", text = "Everyone against everyone.", footer = "Fills to 8 with bots" },
    { id = "hardcore", title = "Hardcore", locked = true, reason = "Unlocks at level 10" },
    { id = "tdm", title = "Team Deathmatch", text = "Two teams, first to the score limit wins." },
    { id = "dom", title = "Domination", new = true, text = "Hold the flags A, B and C." },
    { id = "kc", title = "Kill Confirmed", text = "Collect the tags of the fallen." },
    { id = "gungame", title = "Gun Game", disabled = true },
    { id = "night", title = "Night Ops", text = "Every map at night." },
    { id = "custom", title = "Custom game", badge = "HOST", text = "Pick mode and map yourself." }
}

local fakeMode = {
    ClassName = "dev_kit_mode",
    Settings = {
        hardcore = { type = "bool", default = false, label = "Hardcore" },
        scorelimit = { type = "int", default = 75, min = 10, max = 200, label = "Score limit" },
        timelimit = { type = "float", default = 10, min = 1, max = 30, label = "Time limit (min)" },
        respawn = { type = "enum", default = "wave", options = { "instant", "wave", "none" }, label = "Respawn" },
        streaks = {
            type = "set", default = { "uav" }, options = { "uav", "airstrike", "dogs" }, label = "Killstreaks"
        },
        bots = { type = "int", default = 12, label = "Bots" }
    }
}

---@param friendly boolean
---@return PW.UIPlayerInfo[]
local function fakePlayers(friendly)
    return {
        { name = "Kilo", host = true, team = 1 }, { name = "Friend_01", team = friendly and 1 or 2 },
        { name = "Friend_02", team = 2 }, { name = "Bot01", bot = true, team = 1 },
        { name = "Bot02", bot = true, team = 2 }, { name = "Bot03", bot = true, team = 2 }
    }
end

---@param lib PW.UILib
---@param prematch boolean
---@return PW.UIPlayerSection[]
local function playerSections(lib, prematch)
    if not prematch then
        return lib.PlayerList(fakePlayers(true), { phase = "LOBBY", maxPlayers = 12, botsFill = 12 })
    end
    return lib.PlayerList(fakePlayers(true), {
        phase = "PREMATCH", localTeam = 1, teams = { { id = 1, name = "Rangers" }, { id = 2, name = "Opfor" } }
    })
end

---@param parent Panel
---@param lib PW.UILib
---@return PWButton[]
local function buttons(parent, lib)
    ---@type { [1]: string, [2]: string? }[]
    local specs = {
        { "START MATCH", "primary" }, { "GAME SETUP", "secondary" }, { "LEAVE", "danger" },
        { "DISABLED" }, { "LOCKED" }, { "OPEN DIALOG", "secondary" }
    }
    ---@type PWButton[]
    local out = {}
    for index, spec in ipairs(specs) do
        local button = vgui.Create("PWButton", parent) --[[@as PWButton]]
        button:SetText(spec[1])
        button:SetVariant(spec[2] --[[@as "primary"|"secondary"|"danger"|nil]])
        local focusSpec = lib.Focusable(button, index <= 3 and "dev_buttons_top" or "dev_buttons_bottom")
        focusSpec.axis = "horizontal"
        out[index] = button
    end
    out[4]:SetEnabled(false)
    out[5]:SetLocked(true, "Only the host can start the match")
    out[1].DoClick = function() print("[PW] dev_kit: START MATCH") end
    out[6].DoClick = function()
        lib.OpenDialog({
            title = "Generate navmesh", confirm = "GENERATE",
            text = "Generating a navmesh takes from a minute to over an hour on huge maps. The game stutters and " ..
                "may look frozen: do not close it.",
            onConfirm = function() print("[PW] dev_kit: dialog confirmed") end
        })
    end
    return out
end

---@param parent Panel
---@param lib PW.UILib
---@return PWSettingsForm
local function form(parent, lib)
    local groups = PW.Settings._Groups({
        mode = fakeMode, modules = {}, scope = "match", log = function() end,
        valueOf = function(def) return def.default end
    })
    local settings = vgui.Create("PWSettingsForm", parent) --[[@as PWSettingsForm]]
    settings:SetSections(lib.BuildForm(groups, { dev_kit_mode = "Game setup" }), true)
    settings.OnChange = function(_, control, value)
        print("[PW] dev_kit: " .. control.id .. " = " .. lib.ToWire(control, value))
    end
    return settings
end

---@class PWDevKitView : Panel
---@field cardList PWCardList
---@field operator PWOperator
---@field summary PWSummary
---@field buttons PWButton[]
---@field settings PWSettingsForm
---@field chip PWWarningChip
---@field timer PWTimer
---@field match PWInfoCard
---@field players PWPlayerList
---@field prematch boolean
---@field OnAction fun(self: PWDevKitView, action: string)

---@param view PWDevKitView
---@param lib PW.UILib
local function fill(view, lib)
    view.operator = vgui.Create("PWOperator", view) --[[@as PWOperator]]
    view.cardList = vgui.Create("PWCardList", view) --[[@as PWCardList]]
    view.cardList:SetCards(cards, "shipment")
    view.summary = vgui.Create("PWSummary", view) --[[@as PWSummary]]
    view.summary:SetSelection({ Name = "Team Deathmatch", Short = "TDM" }, "gm_construct")
    view.cardList.OnSelect = function(_, id)
        for _, card in ipairs(cards) do
            if card.id == id then view.summary:SetSelection({ Name = card.title }, "gm_construct") end
        end
    end
    view.buttons = buttons(view, lib)
    view.settings = form(view, lib)
    view.chip = vgui.Create("PWWarningChip", view) --[[@as PWWarningChip]]
    view.chip:SetText("Server has 8 slots: bots fill to 8")
    view.timer = vgui.Create("PWTimer", view) --[[@as PWTimer]]
    view.timer:SetEndTime(CurTime() + 15)
    view.match = vgui.Create("PWInfoCard", view) --[[@as PWInfoCard]]
    view.match:SetTitle("Match")
    view.match:SetRows({ { "Mode", "Team Deathmatch" }, { "Score limit", "75" }, { "Time limit", "10:00" },
        { "Bots fill", "12" } })
    view.match:SetWarning("Server has 8 slots")
    view.players = vgui.Create("PWPlayerList", view) --[[@as PWPlayerList]]
    view.players:SetNote("Teams are assigned when the match starts.")
    view.players:SetSections(playerSections(lib, false))
    view.prematch = false
end

---@param view PWDevKitView
---@param rect PW.UIRect
---@param px fun(n: number): integer
local function layoutCentre(view, rect, px)
    local gap = px(12)
    local operatorH = math.floor(rect.h * 0.4)
    view.operator:SetPos(rect.x, rect.y)
    view.operator:SetSize(rect.w, operatorH)
    rect = { x = rect.x, y = rect.y + operatorH + gap, w = rect.w, h = rect.h - operatorH - gap }
    local bw = math.floor((rect.w - 2 * gap) / 3)
    for index, button in ipairs(view.buttons) do
        local row, col = math.floor((index - 1) / 3), (index - 1) % 3
        button:SetPos(rect.x + col * (bw + gap), rect.y + row * (px(52) + gap))
        button:SetSize(bw, px(52))
    end
    local top = rect.y + 2 * px(52) + gap + px(24)
    local bottom = rect.y + rect.h - px(56)
    view.settings:SetPos(rect.x, top)
    view.settings:SetSize(rect.w, bottom - top - px(16))
    view.chip:SetPos(rect.x, bottom + px(6))
    view.timer:SetPos(rect.x + rect.w - px(120), bottom)
    view.timer:SetSize(px(120), px(56))
end

---@param view PWDevKitView
---@param w number
---@param h number
local function layout(view, w, h)
    local lib = PW.UI --[[@as PW.UILib]]
    local px = lib.Draw.Px
    local columns = lib.Layout.Columns(w, h, { margin = 96, left = 480, right = 520, gap = 48, bottom = 16 }, px)
    local left, centre, right = columns.left --[[@as PW.UIRect]], columns.centre, columns.right --[[@as PW.UIRect]]
    local summaryH = view.summary:GetTall()
    view.cardList:SetPos(left.x, left.y)
    view.cardList:SetSize(left.w, left.h - summaryH - px(24))
    view.summary:SetPos(left.x, left.y + left.h - summaryH)
    view.summary:SetWide(left.w)
    layoutCentre(view, centre, px)
    view.match:SetPos(right.x, right.y)
    view.match:SetSize(right.w, view.match:WantedHeight(right.w))
    view.players:SetPos(right.x, right.y + view.match:GetTall() + px(24))
    view.players:SetSize(right.w, view.players:WantedHeight(right.w))
end

function SCREEN:Build(ctx)
    local lib = PW.UI --[[@as PW.UILib]]
    local view = vgui.Create("Panel", ctx.parent) --[[@as PWDevKitView]]
    view:Dock(FILL)
    fill(view, lib)
    local hooks = view --[[@as PANEL]]
    hooks.PerformLayout = function(_, w, h) layout(view, w, h) end
    hooks.Think = function()
        if view.timer._seconds == 0 then view.timer:SetEndTime(CurTime() + 15) end
    end
    view.OnAction = function(_, action)
        if action ~= "tertiary" then return end
        view.prematch = not view.prematch
        view.players:SetNote(not view.prematch and "Teams are assigned when the match starts." or nil)
        view.players:SetSections(playerSections(lib, view.prematch))
        view:InvalidateLayout(true)
    end
    return view
end

-- Drives the open root from the console (screenshots through the dev bridge: "client pw_dev_kit_act down").
if CLIENT then
    concommand.Add("pw_dev_kit_act", function(_, _, args)
        local root = PW.UI ~= nil and PW.UI.CurrentRoot() or nil
        if root == nil or args[1] == nil then return end
        local typed = root --[[@as PWRoot]]
        local before = tostring(typed.focusPanel)
        typed:Act(args[1])
        print(string.format("[PW] dev_kit: %s %s -> %s", args[1], before, tostring(typed.focusPanel)))
    end, nil, "Private War (dev): give an input action to the open UI root")
end
