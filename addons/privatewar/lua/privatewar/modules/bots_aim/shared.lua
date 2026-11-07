-- Bots aim controller (T-5.8; 07-bots.md d.8, d.10, d.15; notes/14 "Aiming and difficulty"). A sub-module of
-- `bots`. Pure math over plain numbers: a spring-damper over the view angles with an acceleration and a speed clamp,
-- integrated at a fixed step; a focus error that shrinks while the aim is steady and resets on large moves; target
-- lead; the headshot gate; recoil compensation; the fire tolerance and the line-of-fire decision. One aim step and the
-- dev command parser are in sh_step.lua; the engine glue (Tick, traces, the blackboard, pw_bot_aim) is in init.lua.
--
-- Decisions of the lane agent (to confirm):
--   1. Gameplay constants (Config) are in code; the per-tier values are the bot_difficulties files (T-5.12), read from
--      the bot's board.difficulty (the regular tier when a board has none).
--   2. Damping acts on the view speed relative to (1 - aim_offset_scale) times the goal's own angular speed, so a
--      bot tracks a moving target with a lag that shrinks with difficulty (notes/14 row aim_offset_scale: "tracking
--      error while the target moves"). With a still goal it is the CS spring of notes/14.
--   3. The turn speed of 07 d.15 is a per-axis speed clamp of the spring.
--   4. The focus error is an angular offset (constant angular error = proportional to range, 07 d.8) in a random
--      direction of the unit disk re-rolled every aim_reroll_interval and approached smoothly (CS lerp). It shrinks by
--      aim_focus_decay per second while the goal moves slower than Config.steadyRate and the view turns slower than
--      Config.steadySpeed, never below aim_focus_floor; it resets to aim_focus_initial when the goal movement summed
--      over Config.driftWindow exceeds aim_focus_reset_deg, and on every new target.
--   5. Headshots: headshot_allowed "no" / "rifles" (categories ar and sniper) / "yes", then headshot_chance rolled
--      once per acquisition; otherwise the chest.
--   6. Fire only when the view has stayed within the tolerance for Config.settleTime, the attack delay since
--      acquisition has passed, the target is an entity seen now, and one line-of-fire trace is clear. The tolerance is
--      the angular size of the CS fire half size at the target's range (FireHalfSize: two hull half widths, one for a
--      sniper rifle; cs_bot_weapon.cpp) plus Config.focusTolerance times the current focus error, clamped to
--      [minTolerance, maxTolerance]. The view is compared with the goal, which carries the focus error: the error
--      decides where the shots land, the gate only that the view holds to the precision the bot has now. A gate as
--      small as the aimed part kept the spring chasing the wandering error for seconds before the first shot, and at
--      long range almost forever (lua/tests/privatewar/bots_engagement.lua). Once settled, the view stays settled
--      while the error is within Config.holdTolerance tolerances (hysteresis): with the wandering error the spring
--      lags the goal by a few degrees after each re-roll, and a single-threshold gate chattered open and closed,
--      which delayed the first shot by up to 2 s after the view had settled.

MODULE.Name = "Bots aim"

local lib = (rawget(PW, "BotAim") or {}) --[[@as PW.BotAimLib]]
PW.BotAim = lib

lib.Privilege = "pw.bots.debug"

lib.Config = {
    step = 1 / 66, -- seconds, the fixed integration step of the spring (07 d.8)
    pitchLimit = 89, -- degrees
    steadyRate = 20, -- degrees/s: the goal moves slower than this while the aim is steady
    steadySpeed = 30, -- degrees/s: the view turns slower than this while the aim is steady
    driftWindow = 0.5, -- seconds, time constant of the summed goal movement (focus reset)
    wanderRate = 6, -- 1/s, how fast the error direction approaches its new roll (about 0.1 per tick, CS)
    settleTime = 0.05, -- seconds within the tolerance before the first shot
    holdTolerance = 2, -- a settled view stays settled while the error is within this many tolerances
    minTolerance = 0.4, -- degrees
    maxTolerance = 12, -- degrees
    fireHalfSize = 32, -- units, the fire gate half size (CS: 2 * HalfHumanWidth)
    fireHalfSizeSniper = 16, -- units (CS: HalfHumanWidth with a sniper rifle)
    focusTolerance = 0.15, -- share of the current focus error added to the fire tolerance
    chestHeight = 0.7, -- share of the hull height
    traceSlack = 48, -- units past the target the line-of-fire trace reaches
    maxKickShots = 10 -- shots counted for the recoil estimate of an adapter that deflects bot shots
}

---@type table<string, true>
local rifles = { ar = true, sniper = true }

---The difficulty fields the aim reads (declared for the T-5.12 field test; the values live in bot_difficulties/).
local fields = { "look_stiffness", "look_damping", "look_max_accel", "turn_max_speed", "aim_focus_initial",
    "aim_focus_decay", "aim_focus_floor", "aim_focus_reset_deg", "aim_reroll_interval", "aim_offset_scale",
    "attack_delay", "lead_target", "headshot_allowed", "headshot_chance", "recoil_comp_gain" }
PW.BotProfiles.Reads("difficulty", "aim", fields)

---@type table<string, true>
local headshotValues = { no = true, rifles = true, yes = true }

function lib.ParamsFor(difficulty, tier)
    local out = PW.BotProfiles.Pick(fields, difficulty, tier)
    if not headshotValues[out.headshot_allowed] then
        out.headshot_allowed = PW.BotProfiles.Tier(tier).headshot_allowed
    end
    return out --[[@as PW.BotAimParams]]
end

---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

---@param roll? fun(): number
---@return number, number a point of the unit disk, uniform by area
local function diskPoint(roll)
    local rnd = roll or math.random
    local angle, radius = 2 * math.pi * rnd(), math.sqrt(rnd())
    return radius * math.sin(angle), radius * math.cos(angle)
end

function lib.NewState(p, y, params, now)
    return {
        p = p, y = y, vp = 0, vy = 0, focus = params.aim_focus_initial, offP = 0, offY = 0, rollP = 0, rollY = 0,
        rerollAt = now, drift = 0, goalP = p, goalY = y, acquiredAt = now, part = "chest", err = 0, tolerance = 0,
        fire = false
    }
end

function lib.AimPart(params, category, roll)
    local allowed = params.headshot_allowed == "yes"
        or (params.headshot_allowed == "rifles" and category ~= nil and rifles[category] == true)
    if allowed and roll < params.headshot_chance then return "head" end
    return "chest"
end

function lib.Acquire(s, params, now, category, roll)
    s.focus, s.drift, s.acquiredAt, s.rerollAt = params.aim_focus_initial, 0, now, now
    s.baseP, s.baseY, s.settledSince, s.blockedSince, s.firingSince, s.sighted = nil, nil, nil, nil, nil, nil
    s.fire = false
    s.part = lib.AimPart(params, category, (roll or math.random)())
end

function lib.SpringAxis(pos, vel, goal, goalVel, params, dt)
    local err = math.NormalizeAngle(goal - pos)
    local follow = (1 - params.aim_offset_scale) * goalVel
    local maxAccel, maxSpeed = params.look_max_accel, params.turn_max_speed
    local acc = clamp(params.look_stiffness * err + params.look_damping * (follow - vel), -maxAccel, maxAccel)
    local newVel = clamp(vel + acc * dt, -maxSpeed, maxSpeed)
    return math.NormalizeAngle(pos + newVel * dt), newVel, (newVel - vel) / dt
end

function lib.Spring(s, goalP, goalY, params, dt, gvp, gvy)
    if dt <= 0 then return end
    local steps = math.max(1, math.ceil(dt / lib.Config.step - 1e-9))
    local h = dt / steps
    for _ = 1, steps do
        s.p, s.vp = lib.SpringAxis(s.p, s.vp, goalP, gvp or 0, params, h)
        s.y, s.vy = lib.SpringAxis(s.y, s.vy, goalY, gvy or 0, params, h)
    end
    local limit = lib.Config.pitchLimit
    if s.p > limit or s.p < -limit then
        s.p, s.vp = clamp(s.p, -limit, limit), 0
    end
end

function lib.Focus(s, moved, params, dt)
    local cfg = lib.Config
    s.drift = s.drift * math.exp(-dt / cfg.driftWindow) + moved
    if s.drift > params.aim_focus_reset_deg then
        s.focus, s.drift = params.aim_focus_initial, 0
        return
    end
    local rate = dt > 0 and moved / dt or 0
    local speed = math.sqrt(s.vp * s.vp + s.vy * s.vy)
    if rate <= cfg.steadyRate and speed <= cfg.steadySpeed then
        s.focus = math.max(params.aim_focus_floor, s.focus * params.aim_focus_decay ^ dt)
    end
end

function lib.Wander(s, params, now, dt, roll)
    if now >= s.rerollAt then
        s.rollP, s.rollY = diskPoint(roll)
        s.rerollAt = now + params.aim_reroll_interval
    end
    local k = math.min(1, dt * lib.Config.wanderRate)
    s.offP = s.offP + (s.rollP - s.offP) * k
    s.offY = s.offY + (s.rollY - s.offY) * k
end

function lib.Lead(facts, params)
    local speed = facts.projectileSpeed
    if speed == nil or speed <= 0 or params.lead_target <= 0 then return facts.pos end
    local flight = (facts.pos - facts.eye):Length() / speed
    return facts.pos + (facts.vel - facts.ownVel) * (flight * params.lead_target)
end

function lib.RecoilOffset(kickP, kickY, params)
    local gain = params.recoil_comp_gain
    return -kickP * gain, -kickY * gain
end

function lib.FireHalfSize(category)
    if category == "sniper" then return lib.Config.fireHalfSizeSniper end
    return lib.Config.fireHalfSize
end

function lib.Tolerance(radius, dist, focus)
    local cfg = lib.Config
    local size = math.deg(math.atan(radius / math.max(dist, 1))) + cfg.focusTolerance * (focus or 0)
    return clamp(size, cfg.minTolerance, cfg.maxTolerance)
end

function lib.FireClear(hit, target, isEnemy)
    if hit.fraction >= 1 then return true end
    local ent = hit.ent
    if ent ~= nil and ent == target then return true end
    if hit.world or ent == nil then return false end
    return isEnemy ~= nil and isEnemy(ent) == true
end

function lib.FireRayEnd(eye, point)
    local to = point - eye
    local dist = to:Length()
    if dist < 1e-6 then return point end
    return eye + to * ((dist + lib.Config.traceSlack) / dist)
end

function lib.AnglesTo(eye, point)
    local ang = (point - eye):Angle()
    local limit = lib.Config.pitchLimit
    return clamp(math.NormalizeAngle(ang.p), -limit, limit), math.NormalizeAngle(ang.y)
end

if SERVER then AddCSLuaFile("privatewar/modules/bots_aim/sh_step.lua") end
include("privatewar/modules/bots_aim/sh_step.lua")
