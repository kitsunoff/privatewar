HUDELEMENT.Order = 32
HUDELEMENT.Phases = { "LIVE", "POSTMATCH" }

local challenges = PW.Challenges --[[@as PW.ChallengesViewLib?]]
local kit, hud = PW.UI, PW.HUD
local fontBody = kit and kit.FontName("body") or "DermaDefault"
local fontHeading = kit and kit.FontName("h2") or "DermaDefault"
local fontSmall = kit and kit.FontName("small") or "DermaDefault"
---@type PW.ChallengeWeekView?
local previous
---@type PW.ChallengeToast[]
local queue = {}
---@type PW.ChallengeToast?
local current
local expires = 0
local title, detail, reward = "", "", ""
local textWidth = 0

---@return boolean
local function activePhase()
    local phase = PW.Phase.GetPhase()
    return phase == "LIVE" or phase == "POSTMATCH"
end

local function update()
    local owner = LocalPlayer()
    if challenges == nil or not IsValid(owner) then return end
    local snapshot = challenges._OwnerChallengeView(PW, owner, os.time())
    if snapshot ~= nil and activePhase() then queue = challenges._UpdateChallengeToasts(queue, previous, snapshot) end
    previous = snapshot
end

local function advance()
    if not activePhase() or not IsValid(PW.Modules.Get("challenges")) then
        if #queue > 0 then queue = {} end
        current = nil
        return
    end
    local now = RealTime()
    if current ~= nil and current == queue[1] and now >= expires then table.remove(queue, 1) end
    local nextToast = queue[1] --[[@as PW.ChallengeToast?]]
    local changed = current ~= nextToast
    current = nextToast
    if nextToast == nil then return end
    if changed then
        expires = now + nextToast.duration
        if nextToast.kind == "complete" then surface.PlaySound("buttons/bell1.wav") end
    end
    if kit == nil or hud == nil or hud.S == nil then return end
    local width = hud.S(380)
    if changed or textWidth ~= width then
        local headline = nextToast.kind == "milestone" and fontBody or fontHeading
        textWidth = width
        title = kit.Draw.Fit(nextToast.title, headline, width)
        detail = kit.Draw.Fit(nextToast.detail, fontSmall, width)
        reward = kit.Draw.Fit(nextToast.reward or "", fontSmall, width)
    end
end

if CLIENT then
    PW.HookFor(HUDELEMENT, "PW_ChallengesChanged", update)
    PW.HookFor(HUDELEMENT, "Think", advance)
end

function HUDELEMENT:Draw()
    local toast = current
    if toast == nil or kit == nil or hud == nil then return end
    local s = hud.S
    if s == nil then return end
    local style, rect = kit.Style, kit.Draw.Rect
    local milestone = toast.kind == "milestone"
    local width, height = s(420), s(milestone and 82 or 118)
    local x, y = ScrW() - s(32) - width, s(120)
    local left = x + s(20)
    rect(x, y, width, height, style.bg_raised)
    rect(x, y, s(4), height, style.accent)
    draw.SimpleText(title, milestone and fontBody or fontHeading, left, y + s(12),
        milestone and style.text or style.accent)
    draw.SimpleText(detail, fontSmall, left, y + s(milestone and 39 or 52), style.text)
    if toast.fraction ~= nil then
        local barWidth = width - s(40)
        rect(left, y + s(65), barWidth, s(5), style.bg_selected)
        rect(left, y + s(65), barWidth * toast.fraction, s(5), style.accent)
    elseif reward ~= "" then
        draw.SimpleText(reward, fontSmall, left, y + s(80), style.text_muted)
    end
end
