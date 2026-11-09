-- Standard +showscores hooks (Tab/remapped/Steam Input), plus native View. Never replaces a router root.
local lib = PW.UI --[[@as PW.UILib]]
local sb = lib.Scoreboard --[[@as PW.UIScoreboardLib]]
local hookName = "PW_UI_Scoreboard"
local panel = rawget(sb, "_Panel") --[[@as PWLiveScoreboard?]]
local nativeHeld, failed, nextRefresh = false, false, 0
---@type integer?
local heldCode = nil
---@type integer?
local pendingCode = nil
local lastCode, lastFrame, lastHandled = -1, -1, false
---@type PW.UIScoreboardFacts
local facts = { phase = "LOBBY", enabled = false, playerValid = false, gameUI = false, focused = false }

function sb.IsOpen() return IsValid(panel) end

function sb.Hide()
    if IsValid(panel) then (panel --[[@as PWLiveScoreboard]]):Remove() end
    panel, nativeHeld, heldCode, pendingCode = nil, false, nil, nil
    rawset(sb, "_Panel", nil)
end

sb.Hide() -- hot reload must not leave an old renderer or held-button state behind

---@return boolean
local function allowed()
    local module = PW.Modules.Get("ui_kit")
    local setting = GetConVar("pw_ui_kit_scoreboard")
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    facts.phase, facts.playerValid = PW.Phase.GetPhase(), IsValid(LocalPlayer())
    facts.enabled = not failed and module ~= nil and module:IsValid() and (setting == nil or setting:GetBool())
    facts.rootId = root ~= nil and root.rootId or nil
    facts.gameUI, facts.focused = gui.IsGameUIVisible() or gui.IsConsoleVisible(), system.HasFocus()
    return sb.Allowed(facts)
end

function sb.Gather()
    local me = LocalPlayer()
    local rules = rawget(PW, "MatchRules") --[[@as PW.MatchRulesLib?]]
    local count = GetGlobal2Int("pw_teams", 0)
    local prefix = GetGlobal2String(rules ~= nil and rules._ScoreKeyKey or "pw_hud_score", "pw_kills_team_")
    ---@type table<integer, integer>, table<integer, string>
    local scores, names = {}, {}
    for index = 1, count do
        scores[index], names[index] = GetGlobal2Int(prefix .. index, 0), team.GetName(index)
    end
    local rowsOf = assert(lib.Postmatch).Rows
    local rows = rowsOf ~= nil and rowsOf() or {}
    local ends = GetGlobal2Float(rules ~= nil and rules._EndsKey or "pw_mode_ends", -1)
    local remaining = math.max(0, math.ceil(ends - CurTime()))
    ---@type PW.UIScoreboardData
    local data = { sections = sb.Sections(rows, { teams = count, ownTeam = me:Team(), teamScores = scores,
        teamNames = names }), map = game.GetMap(),
        timer = ends > 0 and string.format("%d:%02d", math.floor(remaining / 60), remaining % 60) or "",
        gamepad = nativeHeld }
    PW.Notify("PW_ScoreboardGathered", data, me:UserID())
    return data
end

---@return boolean
local function refresh()
    local ok, err = pcall(function()
        if not IsValid(panel) then
            panel = (sb.Create --[[@as fun(): PWLiveScoreboard]])()
            rawset(sb, "_Panel", panel)
        end
        (panel --[[@as PWLiveScoreboard]]):Update((sb.Gather --[[@as fun(): PW.UIScoreboardData]])())
    end)
    if not ok then
        failed = true
        sb.Hide()
        ErrorNoHalt("[PW] scoreboard disabled: " .. tostring(err) .. "\n")
        return false
    end
    nextRefresh = RealTime() + 0.25
    return true
end

function sb.Show()
    if not allowed() then return false end
    if sb.IsOpen() then return true end
    return refresh()
end

---@param code integer
---@return boolean
local function handleKey(code)
    local binding = input.LookupBinding("+showscores")
    local bound = binding ~= nil and input.GetKeyCode(binding) or nil
    if code == KEY_XBUTTON_BACK or code == bound then
        nativeHeld = code == KEY_XBUTTON_BACK
        if not sb.Show() then nativeHeld = false return false end
        heldCode = code
        return true
    end
    if not sb.IsOpen() then return false end
    local shown = panel --[[@as PWLiveScoreboard]]
    local scale = lib.S ~= nil and lib.S(1) or lib.ScaleFor(ScrW(), ScrH())
    local delta = sb.Scroll(code, shown:GetViewportHeight(), scale)
    if delta == nil then return false end
    shown:Scroll(delta)
    return true
end

function sb.HandleKey(code)
    local frame = FrameNumber()
    if code == lastCode and frame == lastFrame then return lastHandled end
    lastCode, lastFrame, lastHandled = code, frame, handleKey(code)
    return lastHandled
end

hook.Add("ScoreboardShow", hookName, function()
    if not sb.Show() then pendingCode = nil return end -- keep the base path on disable/failure/outside LIVE
    local binding = input.LookupBinding("+showscores")
    local fallback = binding ~= nil and input.GetKeyCode(binding) or nil
    heldCode = pendingCode or heldCode or (fallback ~= nil and input.IsButtonDown(fallback) and fallback or nil)
    pendingCode = nil
    return true
end)

hook.Add("PlayerBindPress", hookName, function(_, bind, pressed, code)
    if bind == "+showscores" and pressed then pendingCode = code end
    if code == KEY_XBUTTON_BACK and allowed() then return true end
    if not sb.IsOpen() or code == nil then return end
    -- D-pad defaults are sandbox tools; do not activate those while it scrolls our board.
    if sb.Scroll(code, 1, 1) ~= nil then return true end
end)

hook.Add("ScoreboardHide", hookName, function() sb.Hide() end)
hook.Add("ShutDown", hookName, function() sb.Hide() end)
hook.Add("PW_PhaseChanged", hookName, function(phase)
    if phase ~= "LIVE" then sb.Hide() end
end)

hook.Add("Think", hookName, function()
    if not sb.IsOpen() then return end
    local released = nativeHeld and not input.IsButtonDown(KEY_XBUTTON_BACK)
        or (heldCode ~= nil and not nativeHeld and not input.IsButtonDown(heldCode))
    if not allowed() or released then
        sb.Hide()
        return
    end
    if RealTime() >= nextRefresh then refresh() end
end)

hook.Add("PlayerButtonDown", hookName, function(ply, code)
    if ply ~= LocalPlayer() or not IsFirstTimePredicted() then return end
    sb.HandleKey(code)
end)

hook.Add("PlayerButtonUp", hookName, function(ply, code)
    if ply == LocalPlayer() and code == KEY_XBUTTON_BACK then sb.Hide() end
end)
