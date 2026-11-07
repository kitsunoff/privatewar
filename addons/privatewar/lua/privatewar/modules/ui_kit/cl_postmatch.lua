-- Postmatch summary, client glue (T-7.7; 08-lobby.md d.4, d.5; 10-frontend.md d.1 POSTMATCH). The rules are pure
-- (sh_postmatch.lua); this file reads the engine and opens or closes the root:
-- - The summary is a PWRoot of its own kind ("postmatch") over the single tab SUMMARY (screens/postmatch.lua). It
--   opens when the phase enters POSTMATCH (replacing a pause menu or class picker) and when the progression summary
--   arrives (PW_ProgressionSummary), and closes on any other phase, so the vote overlay takes over at VOTE.
-- - Escape is Back: the root closes (a root outside LOBBY closes on Back) and stays closed for this POSTMATCH; the next
--   Escape opens the pause menu (T-7.6). pw_ui_postmatch opens it again. Gamepad Start opens the pause menu; closing
--   that menu brings the summary back.
-- - Deaths and currency count from the moment the match went LIVE (client baselines): the engine death counter is not
--   reset between matches, and the wallet has no per-match total.

local lib = PW.UI --[[@as PW.UILib]]
local pm = lib.Postmatch --[[@as PW.UIPostmatchLib]]

local hookName, timerName = "PW_UI_Postmatch", "PW_UI_Postmatch"

---@class PW.UIPostmatchClient
---@field dismissed boolean the player closed the summary in this POSTMATCH
---@field keep boolean the next close is not a dismissal (phase change, pause menu)
---@field deaths table<integer, integer> UserID -> deaths when the match went LIVE
---@field currency? number the wallet when the match went LIVE
---@field summary? PW.ProgressionSummary the summary of this match (nil until it arrives)
---@field lastPhase? string
local state = rawget(pm, "_Client") or { dismissed = false, keep = false, deaths = {} }
rawset(pm, "_Client", state)

---@return boolean
local function kitValid()
    local kit = PW.Modules.Get("ui_kit")
    return kit ~= nil and kit:IsValid()
end

---@param id string
---@return boolean
local function moduleValid(id)
    local entity = PW.Modules.Get(id)
    return entity ~= nil and entity:IsValid()
end

---@return string?
local function openId()
    local root = lib.CurrentRoot() --[[@as PWRoot?]]
    return root ~= nil and root.rootId or nil
end

---@return PW.ProgressionLib?
local function progression()
    if not moduleValid("progression") then return nil end
    return rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
end

---@return number?
local function wallet()
    local prog = progression()
    if prog == nil or not moduleValid("economy") then return nil end
    return prog.GetCurrency(LocalPlayer())
end

-- Data --------------------------------------------------------------------------------------------------------------

---@param ply Player
---@return boolean
local function spectating(ply)
    if ply:Team() == TEAM_SPECTATOR then return true end
    local jip = rawget(PW, "Jip") --[[@as PW.JipLib?]]
    return jip ~= nil and ply:GetNW2Bool(jip.NetBool, false)
end

---@param me Player
---@return PW.UIBoardRow[]
local function boardRows(me)
    local rules = rawget(PW, "MatchRules") --[[@as PW.MatchRulesLib?]]
    local score = rawget(PW, "Score") --[[@as PW.ScoreLib?]]
    ---@type PW.UIBoardRow[]
    local rows = {}
    for _, ply in ipairs(player.GetAll()) do
        local id = ply:UserID()
        rows[#rows + 1] = {
            id = id, name = ply:Nick(), team = ply:Team(), bot = ply:IsBot(), me = ply == me,
            kills = rules ~= nil and rules.GetKills(ply) or ply:Frags(),
            deaths = math.max(0, ply:Deaths() - (state.deaths[id] or 0)),
            score = score ~= nil and score.Get(ply) or 0, spectator = spectating(ply)
        }
    end
    return rows
end

---@return integer teams, table<integer, integer> scores, table<integer, string> names
local function teamFacts()
    local rules = rawget(PW, "MatchRules") --[[@as PW.MatchRulesLib?]]
    local count = rules ~= nil and GetGlobal2Int(rules._ResultTeamsKey, 0) or GetGlobal2Int("pw_teams", 0)
    local prefix = rules ~= nil and GetGlobal2String(rules._ScoreKeyKey, rules._TeamKillsKey) or "pw_kills_team_"
    ---@type table<integer, integer>
    local scores = {}
    ---@type table<integer, string>
    local names = {}
    for index = 1, count do
        scores[index] = GetGlobal2Int(prefix .. index, 0)
        names[index] = team.GetName(index)
    end
    return count, scores, names
end

---"first_blood" -> "First Blood".
---@param id string
---@return string
local function humanise(id)
    local text = string.gsub(string.gsub(id, "_", " "), "(%a)(%w*)", function(first, rest)
        return string.upper(first) .. rest
    end)
    return text
end

---@param name any a display name or a "#phrase"
---@param id string
---@return string
local function phrase(name, id)
    if not isstring(name) or name == "" then return humanise(id) end
    local text = name --[[@as string]]
    if text:sub(1, 1) ~= "#" then return text end
    local translated = language.GetPhrase(text:sub(2))
    if translated == text:sub(2) then return humanise(id) end
    return translated
end

---@param id string
---@return string
local function medalName(id)
    local registry = PW.Registries["score_events"]
    local event = registry ~= nil and registry.Get(id) or nil
    return phrase(event ~= nil and event.Name or nil, id)
end

---@param class string
---@return string
local function weaponName(class)
    local stored = weapons.GetStored(class)
    if stored ~= nil and isstring(stored.PrintName) then return phrase(stored.PrintName, class) end
    local text = language.GetPhrase(class)
    return text ~= class and text or class
end

---@param prog PW.ProgressionLib
---@param summary PW.ProgressionSummary
---@return PW.UILevelStep[]
local function levelSteps(prog, summary)
    local into, need = prog.GetProgress(LocalPlayer())
    local params = prog._Params(PW.Setting)
    return pm.LevelSteps({
        levelBefore = summary.levelBefore, levelAfter = summary.levelAfter, xp = summary.xp, into = into, need = need
    }, function(level) return prog._XpToNext(level, params.xpBase, params.xpExp) end)
end

function pm.Gather()
    local me = LocalPlayer()
    local rows = boardRows(me)
    local teams, scores, names = teamFacts()
    local rules = rawget(PW, "MatchRules") --[[@as PW.MatchRulesLib?]]
    local result = pm.Result({
        draw = rules ~= nil and GetGlobal2Bool(rules._ResultDrawKey, false) or false,
        winner = rules ~= nil and GetGlobal2Int(rules._ResultWinnerKey, 0) or 0,
        teams = teams, ownTeam = me:Team(), ownId = me:UserID(), rows = rows, teamScores = scores
    })
    local prog = progression()
    local summary = prog ~= nil and state.summary or nil
    local medals = rawget(PW, "Medals") --[[@as PW.MedalsLib?]]
    ---@type PW.UIPostmatchData
    local data = {
        result = result, sections = pm.Board(rows, { teams = teams, ownTeam = me:Team(), teamScores = scores,
            teamNames = names }),
        summary = summary, progression = prog ~= nil, steps = {}, medals = {}, weapons = {}, map = game.GetMap()
    }
    local now = wallet()
    if now ~= nil then data.earned = pm.Earned(state.currency, now) end
    if prog == nil or summary == nil then return data end
    data.steps = levelSteps(prog, summary)
    data.medals = pm.Medals(summary.medals, medals ~= nil and medals.Ids or nil, medalName)
    data.weapons = pm.Weapons(summary.weapons, weaponName)
    return data
end

function pm.EarnedNow()
    local now = wallet()
    if now == nil then return nil end
    return pm.Earned(state.currency, now)
end

-- Opening and closing -----------------------------------------------------------------------------------------------

function lib.OpenPostmatch()
    if not kitValid() then return false end
    local root = lib.OpenRoot({
        id = pm.RootId, tabs = { pm.Tab },
        onClose = function()
            if not state.keep then state.dismissed = true end
            state.keep = false
        end
    }) --[[@as PWRoot]]
    if root.view ~= nil then return true end
    root:Remove() -- a dismissal: the watcher does not try again every tick
    return false
end

---Closes our root only (never the lobby or another kind), without counting it as a dismissal.
local function closeOwn()
    if openId() ~= pm.RootId then return end
    state.keep = true
    lib.CloseRoot()
end

function pm.Pause()
    if openId() == pm.RootId then state.keep = true end
    local open = lib.OpenPause --[[@as fun(): boolean]]
    open()
end

---@param event PW.UIPostmatchEvent
local function apply(event)
    local id = openId()
    local action = pm.Decide(event, {
        phase = PW.Phase.GetPhase(), enabled = kitValid(), open = id == pm.RootId,
        otherRoot = id ~= nil and id ~= pm.RootId, dismissed = state.dismissed
    })
    if action == "open" then
        lib.OpenPostmatch()
    elseif action == "close" then
        closeOwn()
    elseif action == "refresh" then
        (lib.CurrentRoot() --[[@as PWRoot]]):Rebuild()
    end
end

---Baselines of a new match: deaths per player and the wallet; the last summary belongs to the previous match.
local function startMatch()
    state.deaths, state.summary = {}, nil
    for _, ply in ipairs(player.GetAll()) do state.deaths[ply:UserID()] = ply:Deaths() end
    state.currency = wallet()
end

hook.Add("PW_PhaseChanged", hookName, function(phase)
    if phase == state.lastPhase then return apply("tick") end
    state.lastPhase = phase
    if phase == "LIVE" then startMatch() end
    state.dismissed = false
    apply("phase")
end)

hook.Add("PW_ProgressionSummary", hookName, function(summary)
    state.summary = summary
    apply("summary")
end)

-- A missed event, a reload and the return from the pause menu are caught here.
timer.Create(timerName, 0.25, 0, function() apply("tick") end)

concommand.Add("pw_ui_postmatch", function()
    if openId() == pm.RootId then return closeOwn() end
    if PW.Phase.GetPhase() ~= "POSTMATCH" then return end
    state.dismissed = false
    lib.OpenPostmatch()
end, nil, "Private War: open or close the postmatch summary (it opens by itself in POSTMATCH)")
