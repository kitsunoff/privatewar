-- Dev-only dummy mode for checkpoint CP-1 item 2 (TASKS.md): a match that does nothing and finishes itself after a
-- short time limit, so the phase machine can be watched through every phase. It lives in the dev addon, whose
-- lua/privatewar/modes/ merges into the LUA path, so the real loader finds it; never shipped (T-10.2). Started with
-- pw_dev_start (autorun/server/pw_devstart.lua, which also lists the checkpoint steps).

-- Match state: self._EndsAt is the CurTime() at which the match finishes, self._Finished is true once
-- PW.Match.Finish was called for this match.

MODE.Name = "Dummy (dev)"
MODE.Teams = 2
MODE.Settings = {
    timelimit = { type = "int", default = 30, min = 5, max = 600, label = "Time limit (s)" }
}

function MODE:Start()
    local limit = tonumber(self:Setting("timelimit")) or 30
    self._EndsAt = CurTime() + limit
    self._Finished = false
    print(string.format("[PW] pw_dummy: LIVE, finishing in %d s", limit))
end

function MODE:Think()
    if self._Finished or self._EndsAt == nil or CurTime() < self._EndsAt then return end
    self._Finished = true
    print("[PW] pw_dummy: time limit reached, PW.Match.Finish")
    assert(PW.Match).Finish({ reason = "timelimit" })
end

function MODE:Cleanup()
    self._EndsAt = nil
    self._Finished = false
end
