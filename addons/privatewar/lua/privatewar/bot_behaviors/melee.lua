-- Built-in behaviour: melee (T-11.6; 07-bots.md d.13 revision 2026-11-07: "at close range a bot switches to
-- melee"). Bucket combat, above fight. A visible enemy within Config.meleeRange (about 2 m), or within
-- Config.meleeRush while the gun is dry, and a melee weapon in the loadout (the catalogue's Kind "melee", the
-- loadout's melee slot): select it, run straight at the target (a direct forward move, a Quick Slide to close a gap
-- when the addon is there) and let the aim swing (the aim presses attack when its view has settled, as for a gun).
-- Ends when the target is lost or, with a gun that can shoot, farther than Config.meleeLeave; then the previous
-- weapon is selected again. Without a melee weapon fight uses the base's melee action (adapter BotAction "melee").
BEHAVIOR.Interval = 0.2
BEHAVIOR.MinRun = 0.4
BEHAVIOR.Cooldown = 0.5

local closeEnough, weight = 48, 1.6

---@return PW.BotTacticsLib?
local function tactics()
    return rawget(PW, "BotTactics")
end

---The visible enemy within melee reach, or the running target while it stays close enough to keep at it.
---@param lib PW.BotTacticsLib
---@param ctx PW.BotBrainCtx
---@return PW.BotContact?
local function victim(lib, ctx)
    local c = lib.Visible(ctx)
    if c == nil then return nil end
    local f = lib.FactsOf(ctx)
    local dist = f.pos:Distance(c.pos)
    if lib.MeleeWanted(dist, f) then return c end
    local keep = ctx.running == "melee" and f.melee ~= nil and (dist <= lib.Config.meleeLeave or lib.Dry(f))
    return keep and c or nil
end

---@param ctx PW.BotBrainCtx
---@return PW.BotRank
function BEHAVIOR:Rank(_, ctx)
    local lib = tactics()
    return lib ~= nil and victim(lib, ctx) ~= nil and "combat" or false
end

---@return number
function BEHAVIOR:Weight()
    return weight
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnStart(_, ctx)
    local lib = tactics()
    local st = ctx.state --[[@as table<string, any>]]
    local f = lib ~= nil and lib.FactsOf(ctx) or nil
    st.previous = f ~= nil and f.active ~= f.melee and f.active or nil
    ctx:ClearGoal()
    local intent = ctx:Intent()
    intent.stance = "stand"
    intent.weapon = f ~= nil and f.melee or nil
end

---@param ctx PW.BotBrainCtx
---@return PW.BotTransition
function BEHAVIOR:Update(_, ctx)
    local lib = tactics()
    local c = lib ~= nil and victim(lib, ctx) or nil
    if lib == nil or c == nil then return PW.BotBrain.Done("melee over") end
    if ctx.target ~= c.ent then ctx:SetTarget(c.ent) end
    local f = lib.FactsOf(ctx)
    if f.melee == nil then return PW.BotBrain.Done("no melee weapon") end
    ctx:Intent().weapon = f.melee
    local dist = f.pos:Distance(c.pos)
    lib.Drive(ctx, dist > closeEnough and (f.runSpeed or 400) or 0, 0)
    lib.Run(ctx, false)
    if dist > lib.Config.meleeRange then lib.Slide(ctx, "close", dist) end
    return PW.BotBrain.Continue()
end

---@param ctx PW.BotBrainCtx
function BEHAVIOR:OnEnd(_, ctx)
    local st = ctx.state --[[@as table<string, any>]]
    local intent = ctx:Intent()
    intent.weapon = st.previous
    ctx:SetTarget(nil)
end
