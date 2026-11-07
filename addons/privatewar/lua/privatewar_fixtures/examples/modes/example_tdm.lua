-- Example (T-1.18): a game mode (02-modes.md d.7). One file (or folder) per mode in lua/privatewar/modes/ fills the
-- MODE table; the file name is the mode id. Name and Teams are required. The core calls MODE:Start on entering
-- LIVE, MODE:Think every tick during LIVE (server) and MODE:Cleanup on leaving LIVE; the mode itself ends the
-- match with PW.Match.Finish(result).

MODE.Name = "Example TDM"
-- Team count; 0 = free for all (02-modes.md d.6).
MODE.Teams = 2

-- Match settings, edited by the host in the lobby (01-extensibility.md d.17); read with self:Setting("timelimit").
MODE.Settings = {
    timelimit = { type = "int", default = 600, min = 60, max = 3600, label = "Time limit (s)" }
}

function MODE:Start()
    self.EndsAt = CurTime() + self:Setting("timelimit")
end

function MODE:Think()
    if self.EndsAt ~= nil and CurTime() >= self.EndsAt then
        self.EndsAt = nil
        -- PW.Match exists on the server, where Think runs.
        assert(PW.Match).Finish({ reason = "timelimit" })
    end
end

function MODE:Cleanup()
    self.EndsAt = nil
end
