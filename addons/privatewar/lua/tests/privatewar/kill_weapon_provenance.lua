-- Regression: autonomous streak kills retain player score/XP but never the unrelated gun in hand.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "kill attribution public owner is missing")
    return value
end

---@return Player, Player, Weapon
local function participants()
    local held
    local owner = {
        IsValid = function() return true end, IsPlayer = function() return true end,
        Alive = function() return true end,
        Team = function() return 1 end, SetNW2Int = function() end,
        GetActiveWeapon = function() return held end
    } --[[@as Player]]
    held = {
        IsValid = function() return true end, IsWeapon = function() return true end,
        GetOwner = function() return owner end, GetClass = function() return "weapon_pistol" end
    } --[[@as Weapon]]
    local victim = {
        IsValid = function() return true end, IsPlayer = function() return true end,
        LastHitGroup = function() return HITGROUP_GENERIC end
    } --[[@as Player]]
    return owner, victim, held
end

---@param inflictor Entity
---@param kind integer
---@return CTakeDamageInfo
local function damage(inflictor, kind)
    return {
        GetInflictor = function() return inflictor end,
        IsBulletDamage = function() return kind == DMG_BULLET end,
        IsDamageType = function(_, mask) return bit.band(kind, mask) ~= 0 end
    } --[[@as CTakeDamageInfo]]
end

return {
    groupName = "PW kill weapon provenance",
    beforeEach = function(state)
        state.mode, state.rules = PW.ActiveMode, PW._MatchRules
        state.award, state.enemy = must(PW.Score).Award, PW.IsEnemy
        state.events = {}
        PW.ActiveMode = nil
        PW._MatchRules = { kills = {}, teamKills = {}, respawnAt = {}, points = {} }
        rawset(PW, "IsEnemy", function(a, b) return a ~= b end)
        rawset(must(PW.Score), "Award", function(ply, id, opts)
            ---@type table<string, any>[]
            local events = state.events
            events[#events + 1] = { ply = ply, id = id, weapon = opts.weapon }
        end)
    end,
    afterEach = function(state)
        rawset(must(PW.Score), "Award", state.award)
        rawset(PW, "IsEnemy", state.enemy)
        PW.ActiveMode, PW._MatchRules = state.mode, state.rules
    end,
    cases = {
        {
            name = "ScoreKill regression: world airstrike blast keeps kill reward with no held weapon attribution",
            func = function(state)
                local owner, victim = participants()
                must(PW.MatchRules).ScoreKill(victim, owner, damage(game.GetWorld(), DMG_BLAST))
                expect(state.events).to.deepEqual({ { ply = owner, id = "kill" } })
                expect(must(PW._MatchRules).kills[owner]).to.equal(1)
            end
        },
        {
            name = "ScoreKill: explicit weapon inflictor remains credited including grenade weapon"
                .. " without direct refill",
            func = function(state)
                local owner, victim, weapon = participants()
                must(PW.MatchRules).ScoreKill(victim, owner, damage(weapon, DMG_BULLET))
                expect(state.events).to.deepEqual({ { ply = owner, id = "kill", weapon = weapon } })
                state.events = {}
                rawset(weapon, "PWGrenade", true)
                must(PW.MatchRules).ScoreKill(victim, owner, damage(weapon, DMG_BLAST))
                expect(state.events).to.deepEqual({ { ply = owner, id = "kill", weapon = weapon } })
            end
        },
        {
            name = "ScoreKill: direct engine player bullet fallback retains weapon XP without general"
                .. " held gun fallback",
            func = function(state)
                local owner, victim, weapon = participants()
                must(PW.MatchRules).ScoreKill(victim, owner, damage(owner, DMG_BULLET))
                expect(state.events).to.deepEqual({ { ply = owner, id = "kill", weapon = weapon } })
            end
        }
    }
}
