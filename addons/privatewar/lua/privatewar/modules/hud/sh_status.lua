-- Pure rules of the match status element (U-8, T-6.2; 09-hud.md d.2): timer arithmetic and formatting, the
-- victory/defeat decision and the score order. Shared and plain data in, plain data out, so the server-side test
-- runner covers it; the drawing is hud/match_status.lua. Loaded by shared.lua through include.

local lib = PW.HUD --[[@as PW.HudLib]]

function lib._Remaining(endsAt, now)
    if endsAt == nil or endsAt <= 0 then return nil end
    return math.max(0, endsAt - now)
end

function lib._FormatTime(seconds)
    local whole = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

function lib._TimerEnd(phase, phaseEnd, modeEnd)
    if phase == "LIVE" then return modeEnd end
    return phaseEnd
end

function lib._Verdict(draw, winner, teams, ownTeam, ownId)
    if draw then return "draw" end
    if winner <= 0 then return nil end
    if teams > 0 then
        if ownTeam < 1 or ownTeam > teams then return "over" end
        return winner == ownTeam and "victory" or "defeat"
    end
    return winner == ownId and "victory" or "defeat"
end

function lib._Lead(scores, count, own)
    if count < 1 then return nil, nil end
    ---@type integer?
    local first = own
    if first ~= nil and (first < 1 or first > count) then first = nil end
    if first == nil then
        first = 1
        for i = 2, count do
            if scores[i] > scores[first] then first = i end
        end
    end
    ---@type integer?
    local second = nil
    for i = 1, count do
        if i ~= first and (second == nil or scores[i] > scores[second]) then second = i end
    end
    return first, second
end
