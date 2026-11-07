-- Built-in behaviour: third_party (T-5.10; 07-bots.md d.13, bucket combat). Heard a fight nearby (gunfire or an
-- explosion of an enemy within hearing range, through perception): wait the profile's third-party delay, then go to
-- a flank point beside the line to the fight, then close in on it. A fresher sound of the fight moves the target.
-- The bot looks toward the heard fight the whole time (a look-at point: the aim turns the view, never fires), as a
-- player turns toward gunfire; a bot that looked elsewhere could walk past the shooter without ever seeing it.
BEHAVIOR.Interval = 0.5
BEHAVIOR.MinRun = 1
BEHAVIOR.Cooldown = 3

local closeRadius, retarget, giveUp = 200, 400, 15

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---@param c PW.BotContact
---@return boolean
local function fightSound(c)
    local lib = tactics()
    return lib ~= nil and lib.FightSounds[c.source] == true
end

---@param ctx PW.BotBrainCtx
---@return PW.BotContact?
local function heard(ctx)
    local lib = tactics()
    if lib == nil or lib.Visible(ctx) ~= nil then return nil end
    local c = lib.Lost(ctx, lib.Config.fightSoundAge, fightSound)
    if c == nil or lib.FactsOf(ctx).pos:Distance(c.pos) > lib.Config.fightSoundRange then return nil end
    return c
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    return heard(ctx) ~= nil and "combat" or false
end

---@param ctx PW.BotBrainCtx
---@return number
function BEHAVIOR:Weight(_, ctx)
    local lib = tactics()
    if lib == nil then return 0 end
    return 0.5 + 0.3 * lib.FactsOf(ctx).profile.aggression
end

---Looks at the heard fight (a Vector target is a look-at point for the aim, never fired at).
---@param ctx PW.BotBrainCtx
---@param point Vector
local function lookAt(ctx, point)
    ctx:SetTarget(point --[[@as any]])
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param lib PW.BotTacticsLib
local function flank(ctx, st, lib)
    local f = lib.FactsOf(ctx)
    st.phase = "flank"
    ctx:SetGoal(lib.FlankPoint(f.pos, st.target, st.side, f.profile.flankRadius), 96, "tactical")
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function close(ctx, st)
    st.phase = "close"
    ctx:SetGoal(st.target, closeRadius, "tactical")
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    if lib == nil then return PW.BotBrain.Done("no tactics") end
    if lib.Visible(ctx) ~= nil then return PW.BotBrain.Done("enemy in sight") end
    local st = ctx.state --[[@as table<string, any>]]
    local c = heard(ctx)
    if st.target == nil then
        if c == nil then return PW.BotBrain.Done("nothing heard") end
        st.target, st.since, st.phase = c.pos, ctx.now, "wait"
        st.side = lib.Random() < 0.5 and -1 or 1
        lookAt(ctx, st.target)
    end
    if c ~= nil and c.pos:Distance(st.target) > retarget then
        st.target = c.pos
        lookAt(ctx, st.target)
        if st.phase == "close" then close(ctx, st) end
    end
    if ctx.now - st.since > giveUp then return PW.BotBrain.Done("fight not found") end
    if st.phase == "wait" then
        if ctx.now - st.since >= lib.FactsOf(ctx).profile.thirdPartyDelay then flank(ctx, st, lib) end
        return PW.BotBrain.Continue()
    end
    local status = ctx:GoalStatus()
    if status == "moving" or status == nil then return PW.BotBrain.Continue() end
    if st.phase == "flank" then
        close(ctx, st)
        return PW.BotBrain.Continue()
    end
    return PW.BotBrain.Done("reached the fight")
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    if st.phase == "flank" or st.phase == "close" then ctx:ClearGoal() end
    if isvector(ctx.board.target) then ctx:SetTarget(nil) end
end
