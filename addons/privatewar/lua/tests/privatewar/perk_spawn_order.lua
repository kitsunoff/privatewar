-- Review regression: normal loadout notification occurs before the synchronous post-base spawn signal.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "spawn order test requires its public owner")
    return value
end

---@param bot boolean
---@return Player, table<string, number>
local function participant(bot)
    local d = { hp = 100, max = 100, walk = 200, run = 400 }
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot end, Alive = function() return true end,
        Health = function() return d.hp end, GetMaxHealth = function() return d.max end,
        SetHealth = function(_, n) d.hp = n end, SetMaxHealth = function(_, n) d.max = n end,
        GetWalkSpeed = function() return d.walk end, GetRunSpeed = function() return d.run end,
        SetWalkSpeed = function(_, n) d.walk = n end, SetRunSpeed = function(_, n) d.run = n end,
        SetNW2Bool = function() end
    } --[[@as Player]], d
end

---@param role boolean
---@return PW.PlayerOverrideProfile?
local function profile(role)
    if role then return { maxHealth = 400, spawnHealth = 400, walkSpeedMult = 1.15, runSpeedMult = 1.15 } end
end

---@param ply Player
local function beforeBase(ply)
    local owner = must(PW.Modules.Get("player_overrides"))
    local engineHooks = owner._EngineHooks or {}
    -- Exercise the owner's engine glue if present, without prescribing that particular implementation.
    local begin = engineHooks.PlayerSpawn
    if begin ~= nil then begin(owner, ply) end
end

---@param n number
---@param expected number
---@return boolean
local function close(n, expected) return math.abs(n - expected) < 0.001 end

---@param role boolean
---@param check fun(value: any): any
local function recordingSpawn(role, check)
    for _, bot in ipairs({ false, true }) do
        local ply, d = participant(bot)
        PW.ActiveMode = { PW_PlayerOverrides = function() return profile(role) end }
        beforeBase(ply)
        d.hp, d.max, d.walk, d.run = 100, 100, 200, 400 -- ordinary base initialization
        PW.Notify("PW_LoadoutGiven", ply, { perk1 = "fleet_foot" })
        local during = { d.max, d.hp, d.walk, d.run }
        PW.Notify("PW_PlayerSpawned", ply) -- only after the ordinary base returns
        local mult = role and 1.15 or 1
        local complete = close(d.walk, 200 * mult * 1.1) and close(d.run, 400 * mult * 1.1)
        local hp, max = d.hp, d.max
        d.hp = 75
        must(PW.PlayerOverrides).Refresh(ply)
        local refreshed = { d.hp, d.walk, d.run }
        must(PW.Perks).Revoke(ply)
        local roleOnly = { d.max, d.walk, d.run }
        PW.ActiveMode = nil
        must(PW.PlayerOverrides).Refresh(ply)
        local ordinary = { d.hp, d.max, d.walk, d.run }
        check(complete).to.beTrue()
        check({ hp, max }).to.deepEqual(role and { 400, 400 } or { 100, 100 })
        check(during).to.deepEqual({ 100, 100, 200, 400 })
        check(refreshed[1]).to.equal(75)
        check(close(refreshed[2], 200 * mult * 1.1) and close(refreshed[3], 400 * mult * 1.1)).to.beTrue()
        check(roleOnly[1]).to.equal(role and 400 or 100)
        check(close(roleOnly[2], 200 * mult) and close(roleOnly[3], 400 * mult)).to.beTrue()
        check(ordinary).to.deepEqual({ 75, 100, 200, 400 })
    end
end

---@param role boolean
---@param check fun(value: any): any
local function nativeSpawn(role, check)
    local bot = player.GetBots()[1]
    local created = false
    local count = 0
    local base = { walk = 0, run = 0, max = 0 }
    local selected, roleEnabled = false, false
    PW.ActiveMode = { ClassName = "pwt_native_spawn", Teams = 0,
        PW_PlayerOverrides = function(_, ply) if ply == bot then return profile(roleEnabled) end end }
    local match = must(PW.Match)
    local phase = match.GetPhase
    rawset(match, "GetPhase", function() return "LIVE" end)
    if not IsValid(bot) then bot = player.CreateNextBot("PW spawn order") created = true end
    assert(IsValid(bot), "native spawn order test needs a player slot")
    hook.Add("PW_PlayerLoadout", "PW_Test_PerkSpawn", function(ply)
        if ply ~= bot then return end
        return selected and { perk1 = "fleet_foot" } or {}
    end)
    hook.Add("PW_LoadoutGiven", "PW_Test_PerkSpawn", function(ply)
        if ply == bot then count = count + 1 end
    end)
    local ok, err = pcall(function()
        -- A separate ordinary control life supplies native baseline values, not repeated Resolve queries.
        must(PW.MatchRules).Spawn(bot)
        base.walk, base.run, base.max = bot:GetWalkSpeed(), bot:GetRunSpeed(), bot:GetMaxHealth()
        local controlGives = count
        count, selected, roleEnabled = 0, true, role
        must(PW.MatchRules).Spawn(bot) -- actual native base PlayerSpawn -> PlayerLoadout -> post-base signal
        local mult = role and 1.15 or 1
        local walk, run, max, hp = bot:GetWalkSpeed(), bot:GetRunSpeed(), bot:GetMaxHealth(), bot:Health()
        bot:SetHealth(75)
        must(PW.PlayerOverrides).Refresh(bot)
        local refreshedHP = bot:Health()
        must(PW.Perks).Revoke(bot)
        PW.ActiveMode = nil
        must(PW.PlayerOverrides).Refresh(bot)
        print(string.format("[PW] native perk spawn role=%s loadouts=%d base=%.2f/%.2f/%d final=%.2f/%.2f/%d",
            tostring(role), count, base.walk, base.run, base.max, walk, run, max))
        check(controlGives).to.equal(1)
        check(count).to.equal(1)
        check(close(walk, base.walk * mult * 1.1) and close(run, base.run * mult * 1.1)).to.beTrue()
        check(max).to.equal(role and 400 or base.max)
        check(hp).to.equal(role and 400 or base.max)
        check(refreshedHP).to.equal(75)
        check(bot:GetMaxHealth()).to.equal(base.max)
        check(close(bot:GetWalkSpeed(), base.walk) and close(bot:GetRunSpeed(), base.run)).to.beTrue()
    end)
    hook.Remove("PW_PlayerLoadout", "PW_Test_PerkSpawn")
    hook.Remove("PW_LoadoutGiven", "PW_Test_PerkSpawn")
    must(PW.Perks).Revoke(bot)
    must(PW.PlayerOverrides).Release(bot)
    must(PW.Equipment).Revoke(bot)
    rawset(match, "GetPhase", phase)
    if created and IsValid(bot) then bot:Kick("spawn order test done") end
    if not ok then error(err, 0) end
end

return {
    groupName = "PW perk spawn pipeline review",
    beforeEach = function(state)
        state.perks, state.mode = PW._Perks, PW.ActiveMode
        PW._Perks = must(must(PW.Perks)._NewStore)({ send = function() end })
    end,
    afterEach = function(state)
        hook.Remove("PW_PlayerLoadout", "PW_Test_PerkSpawn")
        hook.Remove("PW_LoadoutGiven", "PW_Test_PerkSpawn")
        for ply in pairs(must(PW._Perks).players) do
            must(PW.Perks).Revoke(ply)
            must(PW.PlayerOverrides).Release(ply)
        end
        PW._Perks, PW.ActiveMode = state.perks, state.mode
    end,
    cases = {
        { name = "Spawn order: human and bot loadout Fleet Foot is applied once after ordinary base initialization",
            func = function() recordingSpawn(false, expect) end },
        { name = "Spawn order: 400 HP role and 1.15 compose once with in-base loadout and restore ordinary baseline",
            func = function() recordingSpawn(true, expect) end },
        { name = "Native spawn order: selected Fleet Foot reaches PlayerLoadout before post-base signal"
                .. " without double give",
            func = function() nativeSpawn(false, expect) end },
        { name = "Native spawn order: in-base role profile and Fleet Foot never capture a modified 400 HP baseline",
            func = function() nativeSpawn(true, expect) end }
    }
}
