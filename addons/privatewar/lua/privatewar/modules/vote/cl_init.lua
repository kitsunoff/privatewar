-- Vote module, client: the vote screen (T-2.13, restyled in U-7; 08-lobby.md d.5; 10-frontend.md VOTE;
-- notes/16-frontend-d1-proposal.md §4d). A full-screen overlay opened when the phase enters VOTE and closed when it
-- leaves (PW_PhaseChanged). It asks the server for the state on open (pw_vote_request) and redraws on every
-- pw_vote_state. One PWVoteCard per option (ui_kit/cl_vote.lua), the turnout and the timer in the header, the hint
-- bar at the bottom, "Pick myself" for players with the pick privilege (opens the map picker in pick mode; the
-- choice goes out as pw_vote_pick). Left and Right move the focus, Enter votes. What is drawn comes from
-- PW.Vote._Screen (sh_cards.lua); the server checks every vote and pick again. Layout only, with the kit's widgets.
-- The file checks its module with IsValid(module) only (MODULE has no IsValid while the file runs).

local module = MODULE

local lib = PW.Vote --[[@as PW.VoteLib]]

---@class PW.VoteClientView
---@field frame? Panel
---@field state? PW.VoteState
---@field model? PW.VoteScreen
---@field cards PWVoteCard[]
---@field pickButton? PWButton
---@field hintBar? PWHintBar
---@field focus integer index of the focused card
---@field shown? integer the last whole second shown
---@field picking? boolean the map picker (PWRoot) was opened from here

---@type PW.VoteClientView
local view = rawget(lib, "_View") or { cards = {}, focus = 1 }
rawset(lib, "_View", view)

function lib.SendVote(index)
    net.Start("pw_vote_cast")
    net.WriteUInt(index, 8)
    net.SendToServer()
end

function lib.SendPick(option)
    net.Start("pw_vote_pick")
    net.WriteString(option.mode)
    net.WriteString(option.map)
    net.SendToServer()
end

function lib.Request()
    net.Start("pw_vote_request")
    net.SendToServer()
end

---@return boolean
local function shouldShow()
    local kit = PW.Modules.Get("ui_kit")
    return PW.Phase.GetPhase() == "VOTE" and IsValid(module) and rawget(PW, "UI") ~= nil and kit ~= nil
        and kit:IsValid()
end

---@return PW.UILib
local function ui()
    return PW.UI --[[@as PW.UILib]]
end

---The map picker needs the lobby's mode and map lists (the lobby state of this session); without them there is
---nothing to pick from.
---@return boolean
local function pickerReady()
    local lobby = rawget(PW, "Lobby") --[[@as PW.LobbyLib?]]
    if lobby == nil or lobby.OpenPicker == nil then return false end
    local lobbyView = rawget(lobby, "_View") --[[@as PW.LobbyClientView?]]
    return lobbyView ~= nil and lobbyView.state ~= nil
end

---@param modeId string
---@return string?
local function shortOf(modeId)
    local modes = (rawget(PW, "Registries") or {}).modes --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(modeId) or nil
    local short = mode ~= nil and mode.Short or nil
    return isstring(short) and short --[[@as string]] or nil
end

local emptyState = { options = {}, mine = 0, canPick = false } --[[@as PW.VoteState]]

---Recomputes the screen model (state, phase time left, humans).
local function update()
    view.model = lib._Screen(view.state or emptyState, {
        remaining = PW.Phase.Remaining(), humans = #player.GetHumans(), shortOf = shortOf, pickReady = pickerReady()
    })
    local bar = view.hintBar
    if bar ~= nil and IsValid(bar) then (bar --[[@as PWHintBar]]):SetEntries(view.model.hints) end
end

---Opens the map picker in pick mode over the vote; Back returns to the vote, Enter sends the pick.
local function openPicker()
    if not pickerReady() or view.model == nil or not view.model.pick.visible then return end
    local kit, lobby = ui(), PW.Lobby --[[@as PW.LobbyLib]]
    kit.OpenRoot()
    ---@type PW.LobbyPickerOpts
    local opts = {
        pick = function(mode, map)
            lib.SendPick({ mode = mode, map = map, name = "", votes = 0 })
            kit.CloseRoot()
        end
    }
    ;(lobby.OpenPicker --[[@as fun(opts: PW.LobbyPickerOpts)]])(opts)
    local root = kit.CurrentRoot() --[[@as PWRoot?]]
    if root ~= nil then
        -- The picker is the only screen: Back leaves the root (router: not LOBBY) instead of showing the hub.
        local stack = root.model.stacks[root.model.active]
        if #stack > 1 then table.remove(stack, 1) end
    end
    view.picking = true
end

---@param index integer
local function setFocus(index)
    if #view.cards == 0 then return end
    view.focus = (index - 1) % #view.cards + 1
    for position, card in ipairs(view.cards) do card._pwFocused = position == view.focus end
end

---@param action string
local function act(action)
    if action == "left" then return setFocus(view.focus - 1) end
    if action == "right" then return setFocus(view.focus + 1) end
    if action == "secondary" then return openPicker() end
    local card = view.cards[view.focus]
    if action == "accept" and card ~= nil then lib.SendVote(card.card.index) end
end

---@param frame Panel
---@param w number
---@param h number
local function paintFrame(frame, w, h)
    local s, paint = ui().Style --[[@as PW.UIStyle]], ui().Draw
    paint.Backdrop(frame, w, h)
    local model = view.model
    if model == nil then return end
    local margin = paint.Px(96)
    draw.SimpleText(model.title, ui().FontName("h1"), margin, paint.Px(56), s.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(model.turnout.text, ui().FontName("body"), margin, paint.Px(104), s.text_muted,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(model.timer.text, ui().FontName("title"), w - margin, paint.Px(72),
        model.timer.warning and s.warning or s.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

---Cards in one centred row, the pick button under them, the hint bar at the bottom.
---@param w number
---@param h number
local function layout(w, h)
    local paint = ui().Draw
    local count = #view.cards
    local hintH, top, gap = paint.Px(80), paint.Px(150), paint.Px(32)
    if view.hintBar ~= nil then
        view.hintBar:SetPos(0, h - hintH)
        view.hintBar:SetSize(w, hintH)
    end
    if count == 0 then return end
    local cardW = math.min(paint.Px(460), math.floor((w - 2 * paint.Px(96) - gap * (count - 1)) / count))
    local cardH = math.floor(cardW * 9 / 16) + paint.Px(210)
    local x = math.floor((w - (cardW * count + gap * (count - 1))) / 2)
    local y = top + math.max(0, math.floor((h - hintH - top - cardH - paint.Px(80)) / 2))
    for _, card in ipairs(view.cards) do
        card:SetPos(x, y)
        card:SetSize(cardW, cardH)
        x = x + cardW + gap
    end
    local button = view.pickButton
    if button ~= nil and IsValid(button) then
        (button --[[@as PWButton]]):SetSize(paint.Px(320), paint.Px(56))
        button:SetPos(math.floor((w - button:GetWide()) / 2), y + cardH + paint.Px(24))
    end
end

---Builds the cards and the pick button from the current model.
local function rebuild()
    local frame = view.frame
    if frame == nil or not IsValid(frame) or view.model == nil then return end
    for _, card in ipairs(view.cards) do card:Remove() end
    view.cards = {}
    if view.pickButton ~= nil and IsValid(view.pickButton) then (view.pickButton --[[@as PWButton]]):Remove() end
    view.pickButton = nil
    for index, card in ipairs(view.model.cards) do
        local panel = vgui.Create("PWVoteCard", frame) --[[@as PWVoteCard]]
        panel:SetCard(card)
        panel.DoClick = function()
            setFocus(index)
            lib.SendVote(card.index)
        end
        view.cards[index] = panel
    end
    if view.model.pick.visible then
        local button = vgui.Create("PWButton", frame) --[[@as PWButton]]
        button:SetText(view.model.pick.label)
        button:SetVariant("secondary")
        button.DoClick = openPicker
        view.pickButton = button
    end
    if view.focus > #view.cards then view.focus = 1 end
    setFocus(view.focus)
    frame:InvalidateLayout(true)
end

local function refresh()
    update()
    rebuild()
end

function lib.Close()
    if view.picking then ui().CloseRoot() end
    view.picking = false
    if IsValid(view.frame) then (view.frame --[[@as Panel]]):Remove() end
    view.frame, view.cards, view.pickButton, view.hintBar = nil, {}, nil, nil
end

---A closed picker root gives the keyboard back to the vote.
---@param frame Panel
local function regainInput(frame)
    if not view.picking or ui().RootOpen() then return end
    view.picking = false
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(true)
end

---@param frame Panel
local function think(frame)
    if not shouldShow() then return lib.Close() end
    regainInput(frame)
    local left = math.ceil(PW.Phase.Remaining() or 0)
    if left ~= view.shown then
        view.shown = left
        update()
    end
end

function lib.Open()
    if IsValid(view.frame) or not shouldShow() then return end
    local frame = vgui.Create("EditablePanel") --[[@as Panel]]
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(true)
    -- PANEL: the hook callbacks of a panel (GMod calls them while the panel exists).
    local hooks = frame --[[@as PANEL]]
    hooks.Paint = function(_, w, h) paintFrame(frame, w, h) end
    hooks.PerformLayout = function(_, w, h) layout(w, h) end
    hooks.Think = function() think(frame) end
    hooks.OnKeyCodePressed = function(_, code)
        local action = ui().Input.Press(view.hintBar ~= nil and view.hintBar.input or ui().Input.New(), code)
        if action ~= nil then act(action) end
    end
    view.frame, view.state, view.cards, view.focus = frame, nil, {}, 1
    view.hintBar = vgui.Create("PWHintBar", frame) --[[@as PWHintBar]]
    refresh()
    lib.Request()
end

net.Receive("pw_vote_state", function()
    if not IsValid(module) then return end
    view.state = lib._Decode({ uint = net.ReadUInt, string = net.ReadString, bool = net.ReadBool })
    if not IsValid(view.frame) then lib.Open() end
    refresh()
end)

---@param phase PW.PhaseName
function module:PW_PhaseChanged(phase)
    if phase == "VOTE" then lib.Open() else lib.Close() end
end

-- A reload (pw_reload) re-runs this file: rebuild an open screen with the new code, one tick later (see lobby_ui).
if IsValid(view.frame) then
    lib.Close()
    timer.Simple(0, function() lib.Open() end)
end
