-- Built-in behaviour: camp (T-5.10; 07-bots.md d.13). Roam bucket, stationary personalities only (07 d.10:
-- board.personality.type == "stationary"). Picks a spot (near a flag the team defends, else a quiet point at a
-- medium distance), walks there as a guard goal, crouches and watches its entrances: the way it came in and the
-- opposite side, switching every 3-5 s. Holds 25-45 s, then ends (cooldown 8 s) so the camper does not rot in place.
-- Weight 0.6: above roaming (0.25), below a fresh hot spot for hunt (up to 0.8), so a camper still reacts to noise.
BEHAVIOR.Interval = 1
BEHAVIOR.Cooldown = 8

---@return PW.BotObjectivesLib
local function lib()
    return PW.BotObjectives --[[@as PW.BotObjectivesLib]]
end

---@param _ Player
---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    if PW.BotObjectives == nil or not lib().Facts(ctx).stationary then return false end
    return "roam"
end

---@return number
function BEHAVIOR:Weight()
    return 0.6
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    ctx:ClearGoal()
    local facts = lib().Facts(ctx)
    local st = ctx.state or {}
    st.spot = lib().PickCampSpot(facts.pos, facts.candidates, facts.objectives, facts.mates)
    st.from = facts.pos
    if st.spot ~= nil then ctx:SetGoal(st.spot, 48, "guard") end
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    lib().LookAt(ctx, nil)
    ctx:Intent().stance = "stand"
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnSuspend(_, ctx)
    lib().LookAt(ctx, nil)
    ctx:Intent().stance = "stand"
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnResume(_, ctx)
    local st = (ctx.state or {}) --[[@as table<string, any>]]
    st.holdUntil = nil
    if st.spot ~= nil then ctx:SetGoal(st.spot, 48, "guard") end
end

---The two entrances it watches: back the way it came, and the opposite side.
---@param ctx PW.BotBrainCtx
---@param st table
local function watch(ctx, st)
    if ctx.now < (st.nextLook or 0) then return end
    local spot = st.spot --[[@as Vector]]
    local from = st.from --[[@as Vector]]
    local back = from - spot
    back.z = 0
    if back:IsZero() then back = Vector(1, 0, 0) end
    back:Normalize()
    st.side = not st.side
    local dir = st.side and back or -back
    lib().LookAt(ctx, spot + dir * 600 + Vector(0, 0, 60))
    st.nextLook = ctx.now + 3 + 2 * lib().Random(ctx)
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local st = ctx.state or {}
    if st.spot == nil then return PW.BotBrain.Done("no camp spot") end
    local status = ctx:GoalStatus()
    if status == "failed" or status == "unreachable" then return PW.BotBrain.Done("camp spot " .. status) end
    if status ~= "arrived" then return PW.BotBrain.Continue() end
    if st.holdUntil == nil then st.holdUntil = ctx.now + 25 + 20 * lib().Random(ctx) end
    if ctx.now >= st.holdUntil then return PW.BotBrain.Done("camp over") end
    ctx:Intent().stance = "crouch"
    watch(ctx, st)
    return PW.BotBrain.Continue()
end
