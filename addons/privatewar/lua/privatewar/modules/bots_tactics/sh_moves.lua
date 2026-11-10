-- Bots tactics: combat movement rules (T-11.6; 07-bots.md d.13 revision 2026-11-07, d.15 manoeuvre chances). Pure
-- over plain data: when to take cover, how long a strafe leg lasts, when to sprint, when to switch to melee and when
-- to slide (the optional Quick Slide addon). Small ctx helpers write the legs-channel intent fields the input writer
-- turns into CUserCmd (intent.sprint, intent.drive, intent.slideAt; docs/api/bots-blackboard.md "Intent").
--
-- Decisions of the lane agent (to confirm):
--   6. take_cover is a survival option when the bot is hurt, low on health or outnumbered (two or more enemies in
--      sight); a combat option otherwise when the enemy is far. A running take_cover keeps its rank without a fresh
--      cover (it holds its own cover point) and weighs at least 1 in the combat bucket, so the commitment bonus keeps
--      it against fight until its hide and peek cycles are done.
--   7. Strafe legs are direct sideways moves (intent.drive), not path goals: 0.35 to 1.45 s, shorter for a mobile
--      personality (jitter). The personality field mobility (0..1) also is the chance to sprint a long leg.
--   8. Melee at Config.meleeRange (110 units, about 2 m) when the bot carries a melee weapon; from Config.meleeRush
--      (350) when the gun is dry (no magazine and no reserve).
--   9. A slide needs the addon, the ground, a standing bot that moves at least half its run speed, the cooldown and
--      the difficulty's slide_chance (07 d.15); then its own condition: peek (the peek point is a step away), dodge
--      (hurt within Config.dodgeWindow) or close (the target 150 to 450 units away before melee).

local lib = PW.BotTactics --[[@as PW.BotTacticsLib]]
local cfg = lib.Config

cfg.meleeRange = 110 -- units: about 2 m, switch to melee
cfg.meleeRush = 350 -- units: a dry gun rushes into melee from this close
cfg.meleeLeave = 220 -- units: melee ends when the target is farther and the gun can shoot
cfg.outnumbered = 2 -- visible enemies that make a fight unfavourable
cfg.sprintMin = 300 -- units: a shorter leg is walked
cfg.coverSprintMin = 150 -- units: a cover farther than this is reached at a sprint
cfg.slideCooldown = 3 -- s between two slides
cfg.slideStart = 0.15 -- s the slide keys (sprint and duck) are pressed together
cfg.dodgeWindow = 0.5 -- s: a hit this fresh may be dodged with a slide
cfg.slidePeekMin = 64 -- units: a peek step at least this long may be a slide
cfg.slideCloseMin = 150 -- units
cfg.slideCloseMax = 450 -- units

local legBase, legMobility, legSpread = 0.35, 0.6, 0.5

function lib.CoverWanted(i)
    if not i.hasCover then return false, 0 end
    local pressure = i.health < cfg.lowHealth or i.hurt or i.visibleCount >= cfg.outnumbered
    if pressure and (i.dist >= cfg.coverMinThreat or i.health < cfg.lowHealth) then
        local extra = i.visibleCount >= cfg.outnumbered and 0.1 or 0
        return "survival", 0.6 + 0.4 * (1 - i.health) + extra
    end
    if (i.engaged or i.running) and i.dist > cfg.combatCoverRange and i.coverChance > 0 then
        local weight = 0.3 + i.coverChance
        if i.running then weight = math.max(weight, 1) end
        return "combat", weight
    end
    return false, 0
end

function lib.LegLength(profile, roll)
    return legBase + legMobility * (1 - math.Clamp(profile.mobility, 0, 1)) + legSpread * roll
end

function lib.SprintWanted(dist, profile, roll)
    return dist >= cfg.sprintMin and roll < profile.mobility
end

function lib.Dry(f)
    return f.capacity > 0 and f.clip <= 0 and f.reserve <= 0
end

function lib.MeleeWanted(dist, f)
    if f.melee == nil then return false end
    return dist <= cfg.meleeRange or (lib.Dry(f) and dist <= cfg.meleeRush)
end

---@type table<string, fun(s: PW.BotSlideFacts): boolean>
local slideKinds = {
    peek = function(s) return (s.dist or 0) >= cfg.slidePeekMin end,
    dodge = function(s) return s.hurtAge ~= nil and s.hurtAge >= 0 and s.hurtAge <= cfg.dodgeWindow end,
    close = function(s)
        local d = s.dist or 0
        return d >= cfg.slideCloseMin and d <= cfg.slideCloseMax
    end
}

function lib.SlideWanted(kind, s)
    local own = slideKinds[kind]
    if own == nil or not s.available or s.cooling or not s.onGround or s.crouching then return false end
    if s.speed <= s.runSpeed * 0.5 or s.roll >= s.chance then return false end
    return own(s)
end

---@return PW.BotQuickSlideLib?
local function quickSlide()
    return rawget(PW, "BotQuickSlide")
end

local slideMark = "tactics.slide"

function lib.SlideReady(ctx, kind, dist)
    local qs = quickSlide()
    local f = lib.FactsOf(ctx)
    ---@type PW.BotSlideFacts
    local s = {
        available = qs ~= nil and qs.Available() == true, cooling = lib.Marked(ctx.board, slideMark, ctx.now),
        onGround = f.onGround ~= false, crouching = f.crouching == true, speed = f.speed or 0,
        runSpeed = f.runSpeed or 0, roll = lib.Random(), chance = f.profile.slide, dist = dist,
        hurtAge = f.hurtAt ~= nil and ctx.now - f.hurtAt or nil
    }
    return lib.SlideWanted(kind, s)
end

function lib.CommitSlide(ctx)
    lib.Mark(ctx.board, slideMark, ctx.now + cfg.slideCooldown)
    ctx:Intent().slideAt = ctx.now
end

function lib.Slide(ctx, kind, dist)
    if not lib.SlideReady(ctx, kind, dist) then return false end
    lib.CommitSlide(ctx)
    return true
end

function lib.Run(ctx, on)
    local intent = ctx:Intent()
    intent.sprint = on or nil
    if on and ctx.target ~= nil then ctx:SetTarget(nil) end
end

function lib.Travel(ctx, point)
    local f = lib.FactsOf(ctx)
    local on = lib.SprintWanted(f.pos:Distance(point), f.profile, lib.Random())
    lib.Run(ctx, on)
    return on
end

function lib.Drive(ctx, forward, side)
    local intent = ctx:Intent()
    if forward == 0 and side == 0 then
        intent.drive = nil
        return
    end
    intent.drive = Vector(forward, side, 0)
end

function lib.Walkable(ctx, point)
    local injected = ctx._api.walkable
    if injected ~= nil then return injected(point) == true end
    if navmesh == nil or not isfunction(navmesh.GetNavArea) then return true end
    return navmesh.GetNavArea(point + Vector(0, 0, 16), 96) ~= nil
end

function lib.Bash(ctx)
    local injected = ctx._api.bash
    if injected ~= nil then return injected(ctx.bot) == true end
    local bot = ctx.bot --[[@as Player]]
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    if adapters == nil or not IsValid(bot) then return false end
    local wep = bot:GetActiveWeapon()
    if not IsValid(wep) then return false end
    return adapters.CallFor(wep, "BotAction", bot, wep, "melee") == true
end
