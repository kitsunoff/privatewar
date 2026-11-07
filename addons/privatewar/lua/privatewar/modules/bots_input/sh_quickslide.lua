-- Optional Quick Slide support (T-11.6; 07-bots.md d.13 revision 2026-11-07). Quick Slide is a third-party
-- Workshop addon (2416989205). Only its public surface is read, its code is never copied (CLAUDE.md, "Code you must
-- not copy"): a player starts a slide by holding duck and sprint together while standing on the ground and moving
-- faster than half the run speed; the slide lasts while duck is held, at most the ConVar sv_qslide_duration
-- (default 0.75 s). The addon adds Player:GetSliding and the ConVar. Bots therefore slide with keys only, through
-- the input writer (intent.slideAt, docs/api/bots-blackboard.md "Intent").
--
-- Detection runs once (the first Available() call; bots think only after InitPostEntity, when every autorun file
-- has run) and is cached for the session. Without the addon Available() is false and every slide request is
-- ignored, so the feature is a clean no-op.

local lib = (rawget(PW, "BotQuickSlide") or {}) --[[@as PW.BotQuickSlideLib]]
PW.BotQuickSlide = lib

lib.ConVar = "sv_qslide_duration"
lib.DefaultDuration = 0.75

PW._BotQuickSlide = rawget(PW, "_BotQuickSlide") or {}
local store = PW._BotQuickSlide --[[@as PW.BotQuickSlideStore]]

function lib.Detect(probe)
    return probe.getSliding == true and (probe.convar == true or probe.hook == true)
end

function lib.Probe()
    local meta = FindMetaTable("Player") --[[@as table<string, any>?]]
    local setup = (hook.GetTable() --[[@as table<string, table<any, any>>]]).SetupMove
    local convar = ConVarExists(lib.ConVar)
    local cvar = convar and GetConVar(lib.ConVar) or nil
    return {
        getSliding = meta ~= nil and isfunction(meta.GetSliding), convar = convar,
        hook = setup ~= nil and setup.qslide ~= nil, duration = cvar ~= nil and cvar:GetFloat() or nil
    }
end

function lib.Available()
    if store.detected == nil then
        local probe = lib.Probe()
        store.detected = lib.Detect(probe)
        store.duration = probe.duration
        print(string.format("[PW] Quick Slide for bots: %s", store.detected and "addon found" or "addon not found"))
    end
    return store.detected == true
end

function lib.Duration()
    local d = store.duration
    if d == nil or d <= 0 then return lib.DefaultDuration end
    return math.max(d, 0.1)
end

function lib._Reset()
    store.detected, store.duration = nil, nil
end
