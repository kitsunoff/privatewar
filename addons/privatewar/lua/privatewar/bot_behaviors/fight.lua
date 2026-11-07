-- Built-in behaviour: fight (T-5.10, T-11.6; 07-bots.md d.13 and its 2026-11-07 revision, bucket combat). Shoot the
-- visible target: the aim (bots_aim) turns and fires once it has settled; the legs strafe (a direct sideways move,
-- intent.drive) or stop and maybe crouch, in legs whose length falls with the personality's mobility (jitter). A
-- fresh hit may be dodged with a Quick Slide. Far from a cover-loving bot's target, a leg may hand over to
-- take_cover by the personality's cover chance. A target farther than the engagement range is approached, at a
-- sprint by the mobility chance. Seen but blocked for 0.4 s (07 d.8): reposition sideways (a half flank). A sight
-- gap shorter than Config.fightGrace keeps the fight and its target. Without a melee weapon a target at arm's length
-- gets the base's melee action (adapter BotAction "melee").
BEHAVIOR.Interval = 0.25
BEHAVIOR.MinRun = 0.5

local strafeMin, strafeSpread, repositionPause, bashEvery, coverAfter = 120, 100, 1.5, 0.8, 1.5
local coolMark = "take_cover.cooling"

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---The enemy to fight: the nearest visible one, else, while fight runs, its target seen within the grace (a short
---sight gap does not end the fight and reset the aim; tactics decision 5).
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@return PW.BotContact?
local function engaged(lib, ctx)
    local seen = lib.Visible(ctx)
    if seen ~= nil or ctx.running ~= "fight" or ctx.target == nil then return seen end
    local held = ctx:Contact(ctx.target) --[[@as PW.BotContact?]]
    if held ~= nil and lib.Age(ctx, held) <= lib.Config.fightGrace then return held end
    return nil
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    local lib = tactics()
    return lib ~= nil and engaged(lib, ctx) ~= nil and "combat" or false
end

---@return number
function BEHAVIOR:Weight()
    return 1
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    st.leg, st.side, st.since = 0, 1, ctx.now
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param point Vector
---@param radius number
local function go(ctx, st, point, radius)
    ctx:SetGoal(point, radius, "tactical")
    st.moving = true
end

---@param ctx PW.BotBrainCtx
---@param st table<string, any>
local function stopMoving(ctx, st)
    if st.moving then
        ctx:ClearGoal()
        st.moving = false
    end
end

---Seconds the aim has been settled on the target with the line of fire blocked; 0 when it is not.
---@param ctx PW.BotBrainCtx
---@return number
local function blockedFor(ctx)
    local debugInfo = ctx.board.debug --[[@as table<string, any>?]]
    local aim = debugInfo ~= nil and debugInfo.aim or nil
    local since = aim ~= nil and aim.blockedSince or nil
    return isnumber(since) and ctx.now - since or 0
end

---A strafe leg: a direct sideways move, the side flipped each leg; the other side when the navmesh ends there.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param f PW.BotCombatFacts
---@param c PW.BotContact
---@return boolean strafing
local function strafe(lib, ctx, st, f, c)
    local dist = strafeMin + lib.Random() * strafeSpread
    for _ = 1, 2 do
        st.side = -st.side
        if lib.Walkable(ctx, lib.StrafePoint(f.pos, c.pos, st.side, dist)) then
            lib.Drive(ctx, 0, st.side * (f.runSpeed or 400))
            return true
        end
    end
    return false
end

---A new leg: hand over to take_cover, strafe, or stop and maybe crouch.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param f PW.BotCombatFacts
---@param c PW.BotContact
---@return PW.BotTransition?
local function newLeg(lib, ctx, st, f, c)
    local intent = ctx:Intent()
    st.leg = ctx.now + lib.LegLength(f.profile, lib.Random())
    stopMoving(ctx, st)
    lib.Run(ctx, false)
    local far = f.pos:Distance(c.pos) > lib.Config.combatCoverRange and ctx.now - st.since >= coverAfter
    local cover = far and not lib.Marked(ctx.board, coolMark, ctx.now) and lib.CoverFor(ctx, c.pos) or nil
    if cover ~= nil and cover.peek ~= nil and lib.Random() < f.profile.coverChance then
        return PW.BotBrain.ChangeTo("take_cover", "fight from cover")
    end
    intent.stance = "stand"
    if lib.Random() < f.profile.strafe and strafe(lib, ctx, st, f, c) then return nil end
    lib.Drive(ctx, 0, 0)
    intent.stance = lib.Random() < f.profile.crouch and "crouch" or "stand"
    return nil
end

---Approach a far target; a sprint (the aim let go for the leg) by the mobility chance.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param f PW.BotCombatFacts
---@param c PW.BotContact
local function approach(lib, ctx, st, f, c)
    st.leg = ctx.now + lib.LegLength(f.profile, lib.Random())
    ctx:Intent().stance = "stand"
    lib.Drive(ctx, 0, 0)
    go(ctx, st, c.pos, f.profile.engageRange * 0.5)
    st.sprinting = lib.SprintWanted(f.pos:Distance(c.pos) - f.profile.engageRange * 0.5, f.profile, lib.Random())
    lib.Run(ctx, st.sprinting)
end

---Close-range actions without a melee weapon (the base's bash) and the dodge slide of a fresh hit.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@param st table<string, any>
---@param f PW.BotCombatFacts
---@param c PW.BotContact
local function reflexes(lib, ctx, st, f, c)
    if f.melee == nil and f.pos:Distance(c.pos) <= lib.Config.meleeRange and ctx.now >= (st.bashAt or 0) then
        st.bashAt = ctx.now + bashEvery
        lib.Bash(ctx)
    end
    if ctx:Intent().drive ~= nil then lib.Slide(ctx, "dodge") end
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    local c = lib ~= nil and engaged(lib, ctx) or nil
    if lib == nil or c == nil then return PW.BotBrain.Done("lost sight") end
    local st = ctx.state --[[@as table<string, any>]]
    if ctx.now >= st.leg then st.sprinting = false end
    if not st.sprinting and ctx.target ~= c.ent then ctx:SetTarget(c.ent) end
    local f = lib.FactsOf(ctx)
    if blockedFor(ctx) >= lib.Config.blockedFlank and ctx.now >= (st.repositionAt or 0) then
        st.side = -st.side
        st.repositionAt, st.leg = ctx.now + repositionPause, ctx.now + repositionPause
        ctx:Intent().stance = "stand"
        lib.Drive(ctx, 0, 0)
        go(ctx, st, lib.FlankPoint(f.pos, c.pos, st.side, f.profile.flankRadius * 0.5), 48)
    elseif f.pos:Distance(c.pos) > f.profile.engageRange and ctx.now >= st.leg then
        approach(lib, ctx, st, f, c)
    elseif ctx.now >= st.leg then
        local handOver = newLeg(lib, ctx, st, f, c)
        if handOver ~= nil then return handOver end
    end
    reflexes(lib, ctx, st, f, c)
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(_, ctx)
    ctx:Intent().stance = "stand"
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnResume(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    st.leg, st.moving, st.sprinting = 0, false, false
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    if st.moving then ctx:ClearGoal() end
    ctx:Intent().stance = "stand"
    ctx:SetTarget(nil)
end
