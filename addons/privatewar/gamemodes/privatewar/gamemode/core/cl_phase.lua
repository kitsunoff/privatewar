-- Client side of phase networking (T-1.13, 00-core.md d.10). One NW2 proxy on pw_phase_seq fires the client hook
-- PW_PhaseChanged(phase, endsAt, seq). The proxy runs before the new value is stored and again on every full
-- update, so it only schedules a sync one frame later; the sync reads all three globals (by then stored: the server
-- writes them in one tick, end -> phase -> seq) and acts once per seq (PW.Phase._Apply). Leaving LIVE ends the
-- client's live instances, because PW_MatchEnd fires only on the server.
-- Before that, the enable snapshot is read again (cl_enable.lua): a module disabled for the new match is disabled
-- before PW_PhaseChanged, so it never hears of the match it is disabled for.

---@type PW.PhaseView
PW._PhaseView = PW._PhaseView or {}

local function sync()
    PW.Enable._Sync()
    local view = PW._PhaseView
    local changed, endInstances = PW.Phase._Apply(view, PW.Phase.GetPhase(), PW.Phase._GetSeq())
    if not changed then return end
    if endInstances then PW._EndInstances() end
    PW.Notify("PW_PhaseChanged", view.phase, PW.Phase.GetEnd(), view.seq)
end

hook.Add("InitPostEntity", "PW.Phase", function()
    Entity(0):SetNW2VarProxy(PW.Phase._Keys.seq, function() timer.Simple(0, sync) end)
    sync()
end)
