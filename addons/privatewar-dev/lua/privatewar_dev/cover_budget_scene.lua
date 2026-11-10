-- Explicit controlled fixture, not an untouched match. World deaths and placement precede measurement.
-- Measured infected have no forced contacts, target, goal, behavior, aim, difficulty or input.
-- Human controls are untouched too. No function wrappers; all capture hooks are removed by Stop.
---@class PWDev.CoverBudgetScene
---@field Run fun(tag: string, count: integer)
---@field Stop fun()
local scene = {}
local probe = include("privatewar_dev/cover_budget.lua") --[[@as PWDev.CoverBudgetProbe]]
local key = "PW.Dev.CoverBudgetScene"
local active, staged, arranged, measured = false, false, false, false
local readyAt, deadline, wanted = 0, 0, 0
local label = ""
---@type Player?
local host
---@type table<Player, boolean>
local frozen = {}

---@param point Vector
---@return Vector
local function ground(point)
    local area = navmesh.GetNearestNavArea(point + Vector(0, 0, 64), false, 512, false, false)
    return assert(area, "fixture needs navmesh"):GetClosestPointOnArea(point) + Vector(0, 0, 2)
end

function scene.Stop()
    if not active then return end
    active = false
    probe.Stop()
    hook.Remove("Think", key)
    for ply, value in pairs(frozen) do if IsValid(ply) then ply:Freeze(value) end end
    assert(PW.Match).Abort("bounded cover-budget observation complete")
    print("[PW] coverbudget scene done " .. label)
end

local function prepare()
    assert(PW.Infection.Role(assert(host)) == "survivor", "human selected seed; retry fixture")
    assert(#player.GetBots() == wanted, "quota mismatch")
    for _, ply in ipairs(player.GetAll()) do
        frozen[ply] = ply:IsFrozen()
        ply:Freeze(true)
    end
    for _, bot in ipairs(player.GetBots()) do
        if PW.Infection.Role(bot) == "survivor" then bot:Kill() end
    end
    staged, readyAt = true, CurTime() + 4
end

local function arrange()
    local human = assert(host)
    human:SetPos(ground(Vector(700, -1500, -144)))
    human:SetEyeAngles(Angle(0, 180, 0))
    for n, bot in ipairs(player.GetBots()) do
        assert(bot:Alive() and PW.Infection.Role(bot) == "infected", "conversion must finish before placement")
        bot:SetPos(ground(Vector(-1975 + math.floor((n - 1) / 5) * 96,
            -1700 + ((n - 1) % 5) * 96, -144)))
        bot:SetEyeAngles(Angle(0, 0, 0))
    end
    readyAt, arranged = CurTime() + 1, true
end

local function step()
    if CurTime() >= deadline then scene.Stop() return end
    local phase = assert(PW.Match).GetPhase()
    if measured and (phase ~= "LIVE" or PW.Infection.State == nil or not PW.Infection.State.playing) then
        scene.Stop()
        return
    end
    if phase == "PREMATCH" then assert(PW.Match).SetReady(assert(host), true) return end
    if phase ~= "LIVE" then return end
    if measured then return end
    if not staged then prepare() return end
    if CurTime() < readyAt then return end
    if not arranged then arrange() return end
    measured = true
    for ply, value in pairs(frozen) do if IsValid(ply) then ply:Freeze(value) end end
    deadline = CurTime() + 20.2
    probe.Start(label, 20)
end

function scene.Run(tag, count)
    assert(not active and game.GetMap() == "gm_construct" and assert(PW.Match).GetPhase() == "LOBBY")
    assert(#player.GetHumans() == 1)
    assert(PW.Settings.Set("bots.fill", count + 1))
    host, wanted, label = player.GetHumans()[1], count, tag
    active, staged, arranged, measured, frozen = true, false, false, false, {}
    deadline = CurTime() + 90
    hook.Add("Think", key, function()
        local ok, why = pcall(step)
        if not ok then print("[PW] coverbudget scene failed " .. tostring(why)) scene.Stop() end
    end)
    assert(assert(PW.Match).Start(assert(PW.Modes.Get("pw_infection"))))
    print("[PW] coverbudget scene start " .. tag)
end

return scene
