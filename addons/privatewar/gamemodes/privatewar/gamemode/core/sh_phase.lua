-- Match phases (T-1.12, 00-core.md d.1, d.2, d.5): pure rules over plain data, shared. The machine that applies
-- them (timers, mode calls, hooks) is server only: sv_match.lua. The client side of phase networking (T-1.13) is
-- cl_phase.lua; its decisions are the pure functions at the end of this file.

PW.Phase = PW.Phase or {}

PW.Phase.Names = { "LOBBY", "PREMATCH", "LIVE", "POSTMATCH", "VOTE" }

-- 00-core.md d.5. PREMATCH -> PREMATCH starts the countdown (it restarts the phase timer); every "-> LOBBY" except
-- POSTMATCH's timer is the host abort. Any pair not listed is rejected.
PW.Phase.Transitions = {
    LOBBY = { PREMATCH = true },
    PREMATCH = { PREMATCH = true, LIVE = true, LOBBY = true },
    LIVE = { POSTMATCH = true, LOBBY = true },
    POSTMATCH = { VOTE = true, LOBBY = true },
    VOTE = { PREMATCH = true, LOBBY = true }
}

---@param from string
---@param to string
---@return boolean
function PW.Phase.CanTransition(from, to)
    local targets = PW.Phase.Transitions[from]
    return targets ~= nil and targets[to] == true
end

---@param value string
---@return PW.AfterMatch
function PW.Phase._AfterMatch(value)
    if value == "rotation" then return "rotation" end
    return "lobby"
end

---@param players PW.ReadyEntry[]
---@param ready table<any, true>
---@return boolean
function PW.Phase._AllReady(players, ready)
    for _, entry in ipairs(players) do
        if not entry.bot and not ready[entry.key] then return false end
    end
    return true
end

---@param state PW.PhaseState
---@param now number
---@param allReady boolean
---@param settings PW.PhaseSettings
---@return PW.PhaseStep?
function PW.Phase._Next(state, now, allReady, settings)
    local phase = state.phase
    local expired = state.endsAt >= 0 and now >= state.endsAt
    if phase == "PREMATCH" then
        if state.countdown then
            if expired then return { phase = "LIVE", duration = -1 } end
        elseif allReady or expired then
            return { phase = "PREMATCH", duration = settings.countdown, countdown = true }
        end
    elseif phase == "POSTMATCH" and expired then
        if settings.afterMatch == "rotation" then return { phase = "VOTE", duration = settings.vote } end
        return { phase = "LOBBY", duration = -1 }
    elseif phase == "VOTE" and expired then
        return { phase = "PREMATCH", duration = settings.prematch, begin = true }
    end
    return nil
end

-- Phase networking (T-1.13, 00-core.md d.10): the server machine writes three NW2 globals, always end -> phase ->
-- seq; both realms read them here. Clients compute the countdown locally; the server sends no timer traffic.

PW.Phase._Keys = { ends = "pw_phase_end", phase = "pw_phase", seq = "pw_phase_seq" }

---@return PW.PhaseName
function PW.Phase.GetPhase()
    return GetGlobal2String(PW.Phase._Keys.phase, "LOBBY") --[[@as PW.PhaseName]]
end

---@return number
function PW.Phase.GetEnd()
    return GetGlobal2Float(PW.Phase._Keys.ends, -1)
end

---@return integer
function PW.Phase._GetSeq()
    return GetGlobal2Int(PW.Phase._Keys.seq, 0)
end

---@param endsAt number
---@param now number
---@return number?
function PW.Phase._Remaining(endsAt, now)
    if endsAt < 0 then return nil end
    return math.max(0, endsAt - now)
end

---@param now? number
---@return number?
function PW.Phase.Remaining(now)
    return PW.Phase._Remaining(PW.Phase.GetEnd(), now or CurTime())
end

---@param from string?
---@param to string
---@return boolean
function PW.Phase._EndsInstances(from, to)
    return from == "LIVE" and to ~= "LIVE"
end

---@param view PW.PhaseView
---@param phase PW.PhaseName
---@param seq integer
---@return boolean changed
---@return boolean endInstances
function PW.Phase._Apply(view, phase, seq)
    if view.seq == seq then return false, false end
    local from = view.phase
    view.phase = phase
    view.seq = seq
    return true, PW.Phase._EndsInstances(from, phase)
end

-- Pending map change networking (00-core.md d.9, delayed change): before a changelevel the server announces the
-- target for pw_mapchange_delay seconds through three NW2 globals, written map -> mode -> at (at < 0: none). The
-- lobby's START button and the map change popup read them (lobby_ui sh_flow.lua).

PW.Phase._ChangeKeys = { map = "pw_mapchange_map", mode = "pw_mapchange_mode", at = "pw_mapchange_at" }

---@return string map, string mode, number at the announced map change; at < 0 when none is pending
function PW.Phase.GetMapChange()
    local keys = PW.Phase._ChangeKeys
    return GetGlobal2String(keys.map, ""), GetGlobal2String(keys.mode, ""), GetGlobal2Float(keys.at, -1)
end
