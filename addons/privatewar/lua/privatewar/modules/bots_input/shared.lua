-- Bot input writer (T-5.2; 07-bots.md d.2, d.3; notes/08 section 6; docs/api/adapter.md "Bot input rules";
-- docs/api/bots-blackboard.md "Intent"). A sub-module of `bots`. Every tick it turns the intent of each bot into its
-- CUserCmd: buttons, move values, view angles and weapon select, following the input rules of the adapter of the
-- active weapon. The walking view turns toward intent.viewTarget by at most intent.viewSpeed per second, every tick.
-- Shared: the pure translation (plain data in, a PW.BotCmd out; a per-bot state table carries the
-- memory between ticks) and the parser of the pw_bot_intent dev command. Server glue: init.lua.
--
-- Decisions of the lane agent (to be confirmed):
--   1. Intent fields beyond the frozen contract: `weapon` (class to select). Stance "crouch" holds IN_DUCK.
--   2. Button bits of the move values are added (IN_FORWARD/IN_BACK/IN_MOVELEFT/IN_MOVERIGHT, notes/08 6.1 rule 1).
--   3. releaseBetweenShots: IN_ATTACK is dropped on the tick after a tick that sent it (on, off, on, ...);
--      IN_ATTACK2 (ADS) is held.
--   4. reloadTap: one press per rising edge of the wanted IN_RELOAD, held for half of reloadTapMax, then released
--      until the intent drops IN_RELOAD and wants it again. Without reloadTap IN_RELOAD is held as wanted.
--   5. forbidWithAttack / forbidWithReload strip their bits whenever the intent wants attack, ADS or reload, also on
--      the ticks where the attack itself is released, so IN_USE never flickers.
--   6. noSprintWhileFiring: wanted attack drops IN_SPEED; attack waits sprintToFire seconds after the last sprint
--      tick.
--   7. Weapon select: the class is sent every tick until it is active (reselectEveryTick), else once per request.

MODULE.Name = "Bots input"

local lib = (rawget(PW, "BotInput") or {}) --[[@as PW.BotInputLib]]
PW.BotInput = lib

lib.Privilege = "pw.bots.debug"

local band, bor, bnot = bit.band, bit.bor, bit.bnot
local attackBits = bor(IN_ATTACK, IN_ATTACK2)
local tapFraction = 0.5

---@return PW.InputRules
local function defaultRules()
    return PW.Adapters.Defaults.GetInputRules() --[[@as PW.InputRules]]
end

-- Tables _Rules returned: merging one again gives the same values, so it is returned as it is (T-10.4).
---@type table<table, true>
local merged = setmetatable({}, { __mode = "k" })

function lib._Rules(rules)
    if rules ~= nil and merged[rules] then return rules --[[@as PW.InputRules]] end
    local result = defaultRules()
    merged[result] = true
    if rules == nil then return result end
    for key, value in pairs(result --[[@as table<string, any>]]) do
        local given = (rules --[[@as table<string, any>]])[key]
        if given ~= nil and type(given) == type(value) then (result --[[@as table<string, any>]])[key] = given end
    end
    return result
end

function lib.NewState()
    return { attackSent = false }
end

---Movement button bits that match the move values (MW and ARC9 read them, notes/08 6.1 rule 1).
---@param forward number
---@param side number
---@return integer
local function moveBits(forward, side)
    local bits = 0
    if forward > 0 then bits = bor(bits, IN_FORWARD) elseif forward < 0 then bits = bor(bits, IN_BACK) end
    if side > 0 then bits = bor(bits, IN_MOVERIGHT) elseif side < 0 then bits = bor(bits, IN_MOVELEFT) end
    return bits
end

---No sprint while firing; the attack waits sprintToFire after the last sprint tick.
---@param buttons integer
---@param rules PW.InputRules
---@param state PW.BotInputState
---@param now number
---@return integer
local function applySprint(buttons, rules, state, now)
    if not rules.noSprintWhileFiring or band(buttons, IN_ATTACK) == 0 then return buttons end
    buttons = band(buttons, bnot(IN_SPEED))
    if state.sprintAt ~= nil and now - state.sprintAt < rules.sprintToFire then
        buttons = band(buttons, bnot(IN_ATTACK))
    end
    return buttons
end

---@param buttons integer
---@param rules PW.InputRules
---@param state PW.BotInputState
---@return integer
local function applyRelease(buttons, rules, state)
    if rules.releaseBetweenShots and state.attackSent then return band(buttons, bnot(IN_ATTACK)) end
    return buttons
end

---@param buttons integer
---@param rules PW.InputRules
---@param state PW.BotInputState
---@param now number
---@return integer
local function applyReloadTap(buttons, rules, state, now)
    if band(buttons, IN_RELOAD) == 0 then
        state.reloadSince = nil
        return buttons
    end
    if state.reloadSince == nil then state.reloadSince = now end
    if rules.reloadTap and now - state.reloadSince >= rules.reloadTapMax * tapFraction then
        return band(buttons, bnot(IN_RELOAD))
    end
    return buttons
end

---Strips forbidWithAttack while attack or ADS is wanted, forbidWithReload while reload is wanted.
---@param buttons integer
---@param wanted integer
---@param rules PW.InputRules
---@return integer
local function applyForbid(buttons, wanted, rules)
    if band(wanted, attackBits) ~= 0 then buttons = band(buttons, bnot(rules.forbidWithAttack)) end
    if band(wanted, IN_RELOAD) ~= 0 then buttons = band(buttons, bnot(rules.forbidWithReload)) end
    return buttons
end

---@param class string?
---@param rules PW.InputRules
---@param state PW.BotInputState
---@param active string?
---@return string?
local function selectWeapon(class, rules, state, active)
    if class == nil or class == active then
        state.selected = nil
        return nil
    end
    if rules.reselectEveryTick then return class end
    if state.selected == class then return nil end
    state.selected = class
    return class
end

---@param state PW.BotInputState
---@param eye Angle
---@return PW.BotCmd
local function standStill(state, eye)
    state.attackSent = false
    state.reloadSince = nil
    state.selected = nil
    return { buttons = 0, forward = 0, side = 0, up = 0, angles = eye }
end

---@param value number
---@param limit number
---@return number
local function clampStep(value, limit)
    return math.max(-limit, math.min(limit, value))
end

function lib.StepView(eye, target, speed, dt)
    local step = math.max(speed, 0) * math.max(dt, 0)
    local pitch = eye.p + clampStep(math.AngleDifference(target.p, eye.p), step)
    local yaw = eye.y + clampStep(math.AngleDifference(target.y, eye.y), step)
    return Angle(math.NormalizeAngle(pitch), math.NormalizeAngle(yaw), 0)
end

---The view of this tick: the walking view target approached by at most viewSpeed * dt (the path follower writes it
---at 10 Hz, this runs every tick), else intent.view, else the current eye angles.
---@param intent PW.BotIntent
---@param facts PW.BotInputFacts
---@return Angle
local function viewFor(intent, facts)
    local target, speed = intent.viewTarget, intent.viewSpeed
    if target ~= nil and speed ~= nil and facts.dt ~= nil then
        return lib.StepView(facts.eye, target, speed, facts.dt)
    end
    return intent.view or facts.eye
end

---The move values: the path follower's move, else the behaviour's direct drive (T-11.6), else none.
---@param intent PW.BotIntent
---@return number forward, number side, number up
local function moveOf(intent)
    local move = intent.move
    if move ~= nil then return move.x, move.y, move.z end
    local drive = intent.drive
    if drive ~= nil then return drive.x, drive.y, 0 end
    return 0, 0, 0
end

-- Sprint and Quick Slide keys (T-11.6). A sprint (moving forward) holds IN_SPEED and drops the attack and ADS: a
-- running bot does not shoot. A slide, only with the addon, holds IN_DUCK for its duration and IN_SPEED during its
-- first SlideStart seconds (the addon starts a slide on duck plus sprint), without the attack in that window.
lib.SlideStart = 0.15

function lib.MoveKeys(wanted, intent, facts, forward)
    if intent.sprint and forward > 0 then wanted = band(bor(wanted, IN_SPEED), bnot(attackBits)) end
    local at = intent.slideAt
    if not facts.slide or at == nil then return wanted end
    local t = facts.now - at
    if t < 0 or t > (facts.slideTime or 0.75) then return wanted end
    wanted = bor(wanted, IN_DUCK)
    if t <= lib.SlideStart then wanted = band(bor(wanted, IN_SPEED), bnot(attackBits)) end
    return wanted
end

function lib.Translate(intent, rules, state, facts)
    if intent == nil then return standStill(state, facts.eye) end
    local full = lib._Rules(rules)
    local forward, side, up = moveOf(intent)
    local wanted = bor(intent.buttons or 0, moveBits(forward, side))
    if intent.stance == "crouch" then wanted = bor(wanted, IN_DUCK) end
    wanted = lib.MoveKeys(wanted, intent, facts, forward)
    local buttons = applySprint(wanted, full, state, facts.now)
    buttons = applyRelease(buttons, full, state)
    buttons = applyReloadTap(buttons, full, state, facts.now)
    buttons = applyForbid(buttons, wanted, full)
    state.attackSent = band(buttons, IN_ATTACK) ~= 0
    if band(buttons, IN_SPEED) ~= 0 then state.sprintAt = facts.now end
    return {
        buttons = buttons, forward = forward, side = side, up = up, angles = viewFor(intent, facts),
        weapon = selectWeapon(intent.weapon, full, state, facts.active)
    }
end

local usage = "usage: pw_bot_intent <bot name|*> clear | stop | [forward=N] [side=N] [up=N] [pitch=N] [yaw=N]"
    .. " [weapon=<class>] [attack] [attack2] [reload] [jump] [crouch] [sprint] [walk] [use]"

---@type table<string, integer>
local flagButtons = {
    attack = IN_ATTACK, attack2 = IN_ATTACK2, reload = IN_RELOAD, jump = IN_JUMP, sprint = IN_SPEED,
    walk = IN_WALK, use = IN_USE
}

---@type table<string, true>
local numberFields = { forward = true, side = true, up = true, pitch = true, yaw = true }

---Reads one field into the accumulator; false when it is not valid.
---@param field string
---@param acc table<string, any>
---@return boolean
local function readField(field, acc)
    if flagButtons[field] ~= nil then
        acc.buttons = bor(acc.buttons, flagButtons[field])
        return true
    end
    if field == "crouch" then
        acc.stance = "crouch"
        return true
    end
    local key, value = string.match(field, "^(%a+)=(.+)$")
    if key == "weapon" then
        acc.weapon = value
        return true
    end
    local number = tonumber(value)
    if key == nil or not numberFields[key] or number == nil then return false end
    acc[key] = number
    return true
end

function lib.ParseArgs(args)
    if #args == 0 then return nil, usage end
    if #args == 1 and args[1] == "clear" then return { clear = true } end
    ---@type table<string, any>
    local acc = { buttons = 0 }
    for _, field in ipairs(args) do
        if field ~= "stop" and not readField(string.lower(field), acc) then
            return nil, string.format("bad field %q; %s", field, usage)
        end
    end
    ---@type PW.BotIntent
    local intent = { buttons = acc.buttons, stance = acc.stance, weapon = acc.weapon }
    if acc.forward or acc.side or acc.up then intent.move = Vector(acc.forward or 0, acc.side or 0, acc.up or 0) end
    if acc.pitch or acc.yaw then intent.view = Angle(acc.pitch or 0, acc.yaw or 0, 0) end
    return { intent = intent }
end

function lib._NameMatches(nick, pattern)
    if pattern == "*" then return true end
    return string.find(string.lower(nick), string.lower(pattern), 1, true) ~= nil
end

local quickSlideFile = "privatewar/modules/bots_input/sh_quickslide.lua"
if SERVER then AddCSLuaFile(quickSlideFile) end
include(quickSlideFile)
