-- Pure rules of the bottom XP bar (09-hud.md d.2, 06-progression.md d.1): the eased fill with the wrap on a level-up,
-- and the level-up detection over the levels messages the client received. Shared and plain data in, plain data out,
-- so the server-side test runner covers it; reading NW2, the levels message and drawing are hud/progression.lua.
-- Loaded by shared.lua through include.

local lib = PW.HUD --[[@as PW.HudLib]]

lib.XpBarRate = 5
lib.XpBarMinSpeed = 0.25
lib.XpBarSettle = 1

function lib._XpBarNew()
    return { level = nil, fill = 0 }
end

---Moves `from` toward `to` by one eased step: exponential approach, at least XpBarMinSpeed per second, no overshoot.
---@param from number
---@param to number
---@param dt number
---@return number
local function ease(from, to, dt)
    local gap = to - from
    if gap <= 0 then return to end
    local step = math.max(gap * (1 - math.exp(-lib.XpBarRate * dt)), lib.XpBarMinSpeed * dt)
    if step >= gap then return to end
    return from + step
end

function lib._XpBarStep(bar, level, fraction, dt, animate)
    local shown = bar.level
    if shown == nil or not animate or level < shown or (level == shown and fraction < bar.fill) then
        bar.level, bar.fill = level, fraction
        return
    end
    if level == shown then
        bar.fill = ease(bar.fill, fraction, dt)
        return
    end
    -- A level-up: the shown level fills to full first and shows full for one frame; the next frame wraps straight to
    -- the target level at 0.
    if bar.fill >= 1 then
        bar.level, bar.fill = level, 0
        return
    end
    bar.fill = ease(bar.fill, 1, dt)
end

function lib._XpBarAnimate(watch, now)
    local armedAt = watch.armedAt
    return armedAt ~= nil and now - armedAt >= lib.XpBarSettle
end

function lib._LevelWatchNew()
    return { source = nil, level = nil, armedAt = nil }
end

function lib._LevelWatch(watch, source, level, now)
    if source == nil or source == watch.source then return nil end
    watch.source = source
    local baseline = watch.level
    watch.level = level
    if baseline == nil then
        watch.armedAt = now
        return nil
    end
    if level > baseline then return level end
    return nil
end
