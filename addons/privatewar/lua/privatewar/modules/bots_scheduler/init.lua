-- Bots scheduler, server glue (T-5.3). The engine Think hook ticks the default scheduler; everything else is in
-- shared.lua. Bots register their tick function there; with nothing registered a tick costs nothing.

local lib = PW.BotScheduler --[[@as PW.BotSchedulerLib]]

PW.HookFor(MODULE, "Think", function()
    lib.Default.Tick()
end)
