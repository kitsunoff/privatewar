-- Pure rules of the score popups and medals (T-6.4; 09-hud.md d.2): the merge and stack of score popups, the fade,
-- the medal queue (with the LEVEL UP entry and its pop scale), the text of an event. Shared and plain data in, plain
-- data out, so the server-side test runner covers it; receiving and drawing are hud/popups.lua. Loaded by shared.lua
-- through include.

local lib = PW.HUD --[[@as PW.HudLib]]

lib.PopupMergeWindow = 1.5
lib.PopupHold = 1.2
lib.PopupFade = 0.6
lib.PopupMax = 4
lib.MedalDuration = 2.5
lib.MedalFadeIn = 0.2
lib.MedalFadeOut = 0.5
lib.MedalMax = 6
lib.LevelUpPop = 0.3
lib.LevelUpScaleFrom = 1.6

function lib._PopupNew()
    return { list = {}, count = 0 }
end

---@param points number
---@param name string
---@return string
local function popupLabel(points, name)
    return string.format("+%d %s", points, name)
end

function lib._PopupAdd(state, id, name, points, now)
    local list = state.list
    for i = 1, state.count do
        local entry = list[i]
        if entry ~= nil and entry.id == id and now - entry.at <= lib.PopupMergeWindow then
            entry.points = entry.points + points
            entry.label = popupLabel(entry.points, entry.name)
            entry.at = now
            return entry
        end
    end
    local entry = { id = id, name = name, points = points, label = popupLabel(points, name), at = now }
    local count = math.min(state.count + 1, lib.PopupMax)
    for i = count, 2, -1 do list[i] = list[i - 1] end
    list[1] = entry
    state.count = count
    return entry
end

function lib._PopupAlpha(age)
    local hold, fade = lib.PopupHold, lib.PopupFade
    if age <= hold then return 1 end
    if age >= hold + fade then return 0 end
    return 1 - (age - hold) / fade
end

function lib._PopupPrune(state, now)
    local list = state.list
    local life = lib.PopupHold + lib.PopupFade
    local kept = 0
    for i = 1, state.count do
        local entry = list[i]
        if entry ~= nil and now - entry.at < life then
            kept = kept + 1
            list[kept] = entry
        end
    end
    for i = kept + 1, state.count do list[i] = nil end
    state.count = kept
end

function lib._MedalNew()
    return { list = {}, count = 0 }
end

function lib._MedalAdd(state, id, name, points, _)
    if state.count >= lib.MedalMax then return false end
    local count = state.count + 1
    state.list[count] = { id = id, name = name, points = points, label = string.format("+%d", points) }
    state.count = count
    return true
end

function lib._MedalCurrent(state, now)
    local list = state.list
    while state.count > 0 do
        local head = list[1]
        if head == nil then return nil end
        if head.startedAt == nil then
            head.startedAt = now
            return head
        end
        if now - head.startedAt < lib.MedalDuration then return head end
        for i = 1, state.count - 1 do list[i] = list[i + 1] end
        list[state.count] = nil
        state.count = state.count - 1
        -- The next medal starts when its turn comes: now, never in the past.
        local nextHead = list[1]
        if nextHead ~= nil then nextHead.startedAt = nil end
    end
    return nil
end

---@param level integer
---@return string
local function levelLabel(level)
    return string.format("LEVEL %d", level)
end

function lib._LevelUpAdd(state, level)
    local list = state.list
    for i = 1, state.count do
        local entry = list[i]
        if entry ~= nil and entry.kind == "levelup" and entry.startedAt == nil then
            entry.level, entry.label = level, levelLabel(level)
            return entry
        end
    end
    local count = state.count + 1
    local entry = { id = "level_up", kind = "levelup", name = "LEVEL UP", points = 0, level = level,
        label = levelLabel(level) }
    list[count] = entry
    state.count = count
    return entry
end

function lib._LevelUpScale(age)
    local pop = lib.LevelUpPop
    if age >= pop then return 1 end
    local t = 1 - math.max(age, 0) / pop
    -- Ease out: fast at first, settling into 1.
    return 1 + (lib.LevelUpScaleFrom - 1) * t * t * t
end

-- Design units between the LEVEL UP title and the level line, and the least room kept to the screen edges.
lib.LevelUpGap = 6
lib.LevelUpMargin = 16
-- Padding scales with the HUD; the draw helper's one-pixel shadow is measured before the animation matrix.
lib.LevelUpPadding = 12
lib.LevelUpShadow = 1

function lib._LevelUpLayout(facts, out)
    local s, maxScale = facts.scale, lib.LevelUpScaleFrom
    local gap, margin = lib.LevelUpGap * s, lib.LevelUpMargin * s
    local blockW = math.max(facts.titleW, facts.labelW)
    local blockH = facts.titleH + gap + facts.labelH
    local inset = lib.LevelUpPadding * s + lib.LevelUpShadow
    local halfW, halfH = blockW / 2 + inset, blockH / 2 + inset
    local cx = facts.width / 2
    -- The centre keeps the max-scale box on screen; the box can never be taller than the screen in practice.
    local cy = math.max(facts.anchorY, margin + halfH * maxScale)
    cy = math.min(cy, facts.height - margin - halfH * maxScale)
    out.cx, out.cy = cx, cy
    out.titleY = cy - blockH / 2
    out.labelY = out.titleY + facts.titleH + gap
    out.boxX, out.boxY = cx - halfW * maxScale, cy - halfH * maxScale
    out.boxW, out.boxH = halfW * 2 * maxScale, halfH * 2 * maxScale
    return out
end

function lib._MedalAlpha(age)
    local duration = lib.MedalDuration
    if age <= 0 or age >= duration then return 0 end
    if age < lib.MedalFadeIn then return age / lib.MedalFadeIn end
    local left = duration - age
    if left < lib.MedalFadeOut then return left / lib.MedalFadeOut end
    return 1
end

---"first_blood" -> "First Blood".
---@param id string
---@return string
local function humanise(id)
    local text = id:gsub("_", " "):gsub("(%a)(%w*)", function(first, rest) return first:upper() .. rest end)
    return text
end

function lib._PopupText(name, id, phrase)
    if name == nil or name == "" then return humanise(id) end
    if name:sub(1, 1) ~= "#" then return name end
    local text = phrase(name)
    if text == nil or text == "" or text == name or text == name:sub(2) then return humanise(id) end
    return text
end

function lib._PopupKind(isMedal, id, ids)
    if not isMedal then return "score" end
    for i = 1, #ids do
        if ids[i] == id then return "medal" end
    end
    return "score"
end
