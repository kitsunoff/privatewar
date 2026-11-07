-- Precision airstrike (T-4.6; 05-loadout.md d.9, d.10): area damage. At activation the owner's aim point (a world
-- trace) and aim direction fix a line; after Delay seconds Count bombs explode along it, Spacing units apart and
-- Interval seconds after each other, each a util.BlastDamage attributed to the owner inside PW.Streaks.StreakDamage
-- (so its kills do not chain). Stock explosion effect and HL2 sound only; nothing vendored, no entities.
STREAK.Name = "Airstrike"
STREAK.Kills = 5
STREAK.Delay = 2
STREAK.Count = 5
STREAK.Spacing = 200
STREAK.Interval = 0.3
STREAK.Damage = 220
STREAK.Radius = 300
STREAK.Duration = STREAK.Delay + STREAK.Count * STREAK.Interval + 0.5
STREAK.BotMinDistance = 500

-- Length of the aim trace. A local: the STREAK global is restored after the file loads.
local range = 16384

---The world point the player aims at and the aim direction.
---@param ply Player
---@return Vector, Vector
local function aimOf(ply)
    local eye, aim = ply:EyePos(), ply:GetAimVector()
    local tr = util.TraceLine({ start = eye, endpos = eye + aim * range, filter = ply,
        mask = MASK_SOLID_BRUSHONLY })
    return tr.HitPos, aim
end

---The ground (or roof) under a bomb point.
---@param point Vector
---@return Vector
local function groundOf(point)
    local tr = util.TraceLine({ start = point + Vector(0, 0, 256), endpos = point - Vector(0, 0, 1024),
        mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or point
end

---@param owner Player
---@param pos Vector
---@param damage number
---@param radius number
local function bomb(owner, pos, damage, radius)
    local attacker = IsValid(owner) and owner or game.GetWorld()
    local streaks = PW.Streaks
    if streaks ~= nil and streaks.StreakDamage ~= nil then
        streaks.StreakDamage(util.BlastDamage, game.GetWorld(), attacker, pos, radius, damage)
    end
    local data = EffectData()
    data:SetOrigin(pos)
    util.Effect("Explosion", data, true, true)
    util.ScreenShake(pos, 8, 40, 1, radius * 2)
end

function STREAK:OnEquip(owner)
    local streaks = PW.Streaks
    if not SERVER or streaks == nil or not IsValid(owner) then return end
    local center, aim = aimOf(owner)
    local points = streaks._AirstrikePoints(center, aim, self.Count, self.Spacing)
    owner:EmitSound("buttons/blip1.wav")
    local next = 1
    self:Timer(self.Delay, 1, function()
        self:Timer(self.Interval, self.Count, function()
            local point = points[next]
            next = next + 1
            if point ~= nil then bomb(owner, groundOf(point), self.Damage, self.Radius) end
        end)
    end)
end

function STREAK:BotShouldUse(bot)
    local streaks = PW.Streaks
    if streaks == nil or streaks.Enemies == nil then return false end
    local center = aimOf(bot)
    if center:Distance(bot:GetPos()) < self.BotMinDistance then return false end
    for _, enemy in ipairs(streaks.Enemies(bot)) do
        if enemy:GetPos():Distance(center) < self.Radius * 1.5 then return true end
    end
    return false
end
