-- Bot input writer, server glue (T-5.2). Thin wrappers around the pure translation in shared.lua:
--   StartCommand (through PW.HookFor, 07-bots.md d.3; nothing else in the gamemode defines StartCommand): for a bot
--     the writer drives, the command of this tick replaces the CUserCmd: buttons, move values, view angles and
--     SelectWeapon. The only output is CUserCmd (07-bots.md d.2).
--   Which bots: a bot with a scripted intent (pw_bot_intent, tests) or with a blackboard (PW.Bot.Get). A managed bot
--     without an intent stands still. Other bots (engine `bot` command, other test groups) are left alone.
--   Rules: PW.Adapters.CallFor(activeWeapon, "GetInputRules", activeWeapon); the defaults without a weapon.
--   pw_bot_intent <bot name|*> <fields>: scripts an intent for manual checks (CP-5a); privilege pw.bots.debug,
--     default superadmin; the server console (and the Deck bridge) may always use it.

local lib = PW.BotInput --[[@as PW.BotInputLib]]

PW.Privilege(lib.Privilege, "superadmin")

PW._BotInput = PW._BotInput or {
    scripted = setmetatable({}, { __mode = "k" }),
    states = setmetatable({}, { __mode = "k" })
}

function lib.SetScripted(bot, intent)
    PW._BotInput.scripted[bot] = intent
end

function lib.IntentFor(bot)
    local scripted = PW._BotInput.scripted[bot]
    if scripted ~= nil then return scripted, true end
    local botLib = rawget(PW, "Bot") --[[@as PW.BotLib?]]
    local board = botLib ~= nil and botLib.Get(bot) or nil
    if board == nil then return nil, false end
    return board.intent, true
end

function lib._RulesFor(wep)
    if wep == nil or not IsValid(wep) then return lib._Rules(nil) end
    return lib._Rules(PW.Adapters.CallFor(wep, "GetInputRules", wep) --[[@as table?]])
end

function lib._CommandFor(bot, now)
    local intent, driven = lib.IntentFor(bot)
    if not driven then return nil end
    local store = PW._BotInput
    local state = store.states[bot]
    if state == nil then
        state = lib.NewState()
        store.states[bot] = state
    end
    local wep = bot:GetActiveWeapon()
    local active = IsValid(wep) and wep:GetClass() or nil
    local slide = intent ~= nil and intent.slideAt ~= nil and PW.BotQuickSlide.Available()
    local facts = { now = now, eye = bot:EyeAngles(), active = active, dt = engine.TickInterval(), slide = slide,
        slideTime = slide and PW.BotQuickSlide.Duration() or nil }
    local out = lib.Translate(intent, lib._RulesFor(IsValid(wep) and wep or nil), state, facts)
    -- The stepped view becomes the intent's view: when the target goes away (goal done) the bot keeps looking there.
    if intent ~= nil and intent.viewTarget ~= nil then intent.view = out.angles end
    return out
end

---Writes a command into the engine CUserCmd.
---@param bot Player
---@param cmd CUserCmd
---@param out PW.BotCmd
local function apply(bot, cmd, out)
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetButtons(out.buttons)
    cmd:SetForwardMove(out.forward)
    cmd:SetSideMove(out.side)
    cmd:SetUpMove(out.up)
    cmd:SetViewAngles(out.angles)
    -- Verified in game: a bot moves along the CUserCmd view, but its eye angles (what weapons aim along) keep the
    -- spawn angles. Mirror the same view, no other value, so the bot looks and shoots where its CUserCmd says.
    bot:SetEyeAngles(out.angles)
    if out.weapon ~= nil then
        local wep = bot:GetWeapon(out.weapon)
        if IsValid(wep) then cmd:SelectWeapon(wep) end
    end
end

---@param ply Player
---@param cmd CUserCmd
PW.HookFor(MODULE, "StartCommand", function(_, ply, cmd)
    if not ply:IsBot() then return end
    local out = lib._CommandFor(ply, CurTime())
    if out ~= nil then apply(ply, cmd, out) end
end)

---@param line string
local function printLine(line)
    print("[PW] " .. line)
end

---@param pattern string
---@return Player[]
local function findBots(pattern)
    ---@type Player[]
    local found = {}
    for _, bot in ipairs(player.GetBots()) do
        if lib._NameMatches(bot:Nick(), pattern) then found[#found + 1] = bot end
    end
    return found
end

function lib._Command(ply, args, out)
    out = out or printLine
    if ply ~= nil and IsValid(ply) and not PW.Can(ply, lib.Privilege) then
        out(string.format("pw_bot_intent denied for %s", ply:Nick()))
        return 0
    end
    ---@type string[]
    local rest = {}
    for i = 2, #args do rest[#rest + 1] = args[i] end
    local parsed, err = lib.ParseArgs(rest)
    if args[1] == nil or parsed == nil then
        out(err or "usage: pw_bot_intent <bot name|*> <fields>")
        return 0
    end
    local bots = findBots(args[1])
    for _, bot in ipairs(bots) do
        lib.SetScripted(bot, parsed.intent)
        out(string.format("pw_bot_intent: %s %s", bot:Nick(), parsed.clear and "cleared" or "scripted"))
    end
    if #bots == 0 then out(string.format("pw_bot_intent: no bot matches %q", args[1])) end
    return #bots
end

concommand.Add("pw_bot_intent", function(ply, _, args) lib._Command(IsValid(ply) and ply or nil, args) end, nil,
    "Private War: script a bot's input (<bot name|*> clear | stop | forward=N side=N yaw=N pitch=N attack reload"
        .. " jump crouch sprint weapon=<class>); needs pw.bots.debug")
