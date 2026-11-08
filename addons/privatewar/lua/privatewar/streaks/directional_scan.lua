STREAK.Name = "Directional Scan"
STREAK.Description = "One facing 90-degree scan, 1800 units with line of sight. Radar concealment still applies."
STREAK.Kills = 2
STREAK.Score = 200
STREAK.Duration = 1.5
STREAK.Unlock = 1

---@param owner Player
---@return table
function STREAK:Prepare(owner)
    local eye, facing = owner:EyePos(), owner:GetAimVector()
    local bots = PW.Bot
    local board = bots ~= nil and bots.Get ~= nil and bots.Get(owner) or nil
    if board ~= nil then
        local point = board.order ~= nil and board.order.objective.pos or nil
        facing = assert(PW.SupportStreaks).ScanDirection(eye, facing, board.contacts or {}, point)
    end
    return { origin = eye, direction = facing }
end

---@param owner Player
function STREAK:OnEquip(owner)
    if CLIENT then return end
    local plan = self.Activation
    if plan == nil then self:Remove() return end
    ---@type Player[]
    local targets = {}
    local streaks = assert(PW.Streaks)
    for _, target in ipairs(assert(streaks.Enemies)(owner)) do
        if assert(PW.SupportStreaks).ScanEligible(plan.origin, plan.direction, target:WorldSpaceCenter(), true) then
            local tr = util.TraceLine({ start = plan.origin, endpos = target:WorldSpaceCenter(), filter = owner,
                mask = MASK_VISIBLE })
            if tr.Fraction >= 0.99 or tr.Entity == target then targets[#targets + 1] = target end
        end
    end
    assert(PW.Reveal)(assert(streaks.Viewer)(owner), targets, 1.5, owner)
    if PW.Devices ~= nil then PW.Devices.Feedback(owner, "SCAN ACTIVATED") end
end

function STREAK:BotShouldUse() return true end
