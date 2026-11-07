-- Built-in behaviour: reload_cover (T-5.10; 07-bots.md d.13, bucket survival). The magazine is low and a threat is
-- known: go to the cover (when one is found and the threat is not at arm's length), reload there crouched, then
-- flank back toward the remembered position of the threat. Without a threat a half-empty magazine is reloaded in
-- place in the roam bucket (a calm reload).
BEHAVIOR.Interval = 0.2
BEHAVIOR.MinRun = 0.5
BEHAVIOR.Cooldown = 1

local moveTimeout, reloadTimeout, flankTimeout, closeRange = 2.5, 4, 6, 400
local flankMark = "reload_cover.flank"

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---Rank and weight from the facts.
---@param ctx PW.BotBrainCtx
---@return PW.BotRank, number
local function assess(ctx)
    local lib = tactics()
    if lib == nil then return false, 0 end
    local f = lib.FactsOf(ctx)
    local threat = lib.Threat(ctx, lib.Config.threatMemory)
    -- T-11.6: an enemy in melee reach is knifed, not reloaded on (melee takes it)
    if threat ~= nil and threat.visible and lib.MeleeWanted(f.pos:Distance(threat.pos), f) then return false, 0 end
    if threat ~= nil and lib.AmmoLow(f, lib.Config.lowAmmo) then
        return "survival", f.clip <= 0 and 0.9 or 0.7
    end
    if lib.Marked(ctx.board, flankMark, ctx.now) and lib.Visible(ctx) == nil then return "survival", 0.5 end
    if threat == nil and lib.AmmoLow(f, lib.Config.calmAmmo) then return "roam", 0.5 end
    return false, 0
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return (assess(ctx))
end

---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local _, weight = assess(ctx)
    return weight
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param point Vector
---@param radius number
local function go(ctx, st, point, radius)
    ctx:SetGoal(point, radius, "tactical")
    st.goalSet = true
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param inCover boolean
local function startReload(lib, ctx, st, inCover)
    st.phase, st.pressAt = "reload", ctx.now
    lib.Run(ctx, false)
    local intent = ctx:Intent()
    intent.stance = inCover and "crouch" or "stand"
    lib.SetButton(intent, IN_RELOAD, true)
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@return PW.BotTransition
local function afterReload(lib, ctx, st)
    local intent = ctx:Intent()
    lib.SetButton(intent, IN_RELOAD, false)
    intent.stance = "stand"
    local threat = lib.Threat(ctx, lib.Config.threatMemory)
    if threat == nil or threat.visible then return PW.BotBrain.Done("reloaded") end
    local f = lib.FactsOf(ctx)
    local side = lib.Random() < 0.5 and -1 or 1
    st.phase, st.flankAt = "flank", ctx.now
    lib.Mark(ctx.board, flankMark, ctx.now + flankTimeout)
    ctx:SetTarget(threat.ent)
    go(ctx, st, lib.FlankPoint(f.pos, threat.pos, side, f.profile.flankRadius), 64)
    return PW.BotBrain.Continue()
end

---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@return PW.BotTransition
local function step(lib, ctx, st)
    local f = lib.FactsOf(ctx)
    if st.phase == "move" then
        local status = ctx:GoalStatus()
        local stop = status == "failed" or status == "unreachable" or ctx.now - st.since > moveTimeout
        if status == "arrived" or stop then startReload(lib, ctx, st, status == "arrived") end
    elseif st.phase == "reload" then
        local full = f.clip >= f.capacity or f.reserve <= 0
        if full or ctx.now - st.pressAt > reloadTimeout then return afterReload(lib, ctx, st) end
        lib.SetButton(ctx:Intent(), IN_RELOAD, true)
    elseif st.phase == "flank" then
        local status = ctx:GoalStatus()
        local over = status == "arrived" or status == "failed" or status == "unreachable"
        if over or lib.Visible(ctx) ~= nil or ctx.now - st.flankAt > flankTimeout then
            return PW.BotBrain.Done("flanked")
        end
    end
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    local st = ctx.state --[[@as table<string, any>]]
    if st.phase == nil then
        st.since = ctx.now
        local f = lib.FactsOf(ctx)
        local threat = lib.Threat(ctx, lib.Config.threatMemory)
        local cover = threat ~= nil and lib.CoverFor(ctx, threat.pos) or nil
        local close = threat ~= nil and f.pos:Distance(threat.pos) < closeRange
        if cover ~= nil and not close then
            st.phase = "move"
            go(ctx, st, cover.pos, 24)
            lib.Run(ctx, f.pos:Distance(cover.pos) > lib.Config.coverSprintMin)
        else
            startReload(lib, ctx, st, false)
        end
    end
    return step(lib, ctx, st)
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    local intent = ctx:Intent()
    intent.stance = "stand"
    if st.goalSet then ctx:ClearGoal() end
    local lib = tactics()
    if lib == nil then return end
    lib.SetButton(intent, IN_RELOAD, false)
    lib.Mark(ctx.board, flankMark, nil)
end
