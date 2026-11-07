-- Own immediate-mode element; the base HUD, vitals, native fallback and saved classes are untouched.
HUDELEMENT.Order = 15
HUDELEMENT.Phases = { "LIVE", "POSTMATCH" }

local roleColour = Color(100, 220, 145)
local zombieColour = Color(230, 115, 90)
local white = Color(235, 239, 244)
local muted = Color(175, 185, 198)
local panel = Color(17, 22, 29, 225)
local cache = { revision = -1, second = -1, title = "", line = "", timer = "", score = "", result = "",
    postWins = -1, postCount = -1 }

---@return PW.InfectionSnapshot?
local function view()
    local lib = PW.Infection
    return lib ~= nil and lib.View or nil
end

function HUDELEMENT:ShouldDraw()
    local phase = PW.Phase.GetPhase()
    local current = view()
    return (phase == "LIVE" and current ~= nil and current.active ~= false)
        or (phase == "POSTMATCH" and GetGlobal2Bool("pw_infection_results", false))
end

---@param current PW.InfectionSnapshot
local function refresh(current)
    local second = math.max(0, math.ceil(current.deadline - CurTime()))
    if cache.revision == current.revision and cache.second == second then return end
    cache.revision, cache.second = current.revision, second
    local model = assert(PW.InfectionPresentation).Model(current, CurTime())
    cache.title, cache.timer = model.role, model.timer
    cache.line = string.format("ROUND %d  |  %d SURVIVORS  /  %d INFECTED",
        current.round, current.survivors, current.infected)
    cache.score = string.format("ROUND WINS %d  |  INFECTIONS %d", current.personalWins, current.infections or 0)
    if current.intermission then cache.timer = "ROUND OVER" end
end

function HUDELEMENT:Draw()
    local hud, ui = PW.HUD, PW.UI
    if hud == nil or ui == nil then return end
    local scale = assert(hud.S)(1)
    local y = scale * 135
    local x, width = ScrW() / 2, 600 * scale
    local current = view()
    if PW.Phase.GetPhase() == "POSTMATCH" then
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wins, count = ply:GetNW2Int("pw_infection_wins", 0), ply:GetNW2Int("pw_infection_count", 0)
        if cache.postWins ~= wins or cache.postCount ~= count then
            cache.postWins, cache.postCount = wins, count
            cache.result = string.format("PERSONAL ROUND WINS %d  |  INFECTIONS %d", wins, count)
        end
        draw.SimpleText(cache.result, ui.FontName("body"), x, y, white, TEXT_ALIGN_CENTER)
        return
    end
    if current == nil then return end
    refresh(current)
    surface.SetDrawColor(panel)
    surface.DrawRect(x - width / 2, y, width, 132 * scale)
    local tint = current.role == "infected" and zombieColour or roleColour
    draw.SimpleText(cache.title, ui.FontName("h2"), x, y + 8 * scale, tint, TEXT_ALIGN_CENTER)
    draw.SimpleText(cache.line, ui.FontName("body"), x, y + 48 * scale, white, TEXT_ALIGN_CENTER)
    draw.SimpleText(cache.timer, ui.FontName("body"), x, y + 76 * scale, white, TEXT_ALIGN_CENTER)
    draw.SimpleText(cache.score, ui.FontName("small"), x, y + 106 * scale, muted, TEXT_ALIGN_CENTER)
end
