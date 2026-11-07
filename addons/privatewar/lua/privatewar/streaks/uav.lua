-- UAV (T-4.6; 05-loadout.md d.9, d.10): radar reveal. Every Sweep seconds, for Duration, the living enemies of the
-- owner are revealed to the owner's side (team, or the owner in FFA) through PW.Reveal; an enemy Counter-UAV hides
-- its side. The first sweep happens at activation; each sweep's blips live a little longer than the interval.
STREAK.Name = "UAV"
STREAK.Kills = 3
STREAK.Duration = 30
STREAK.Sweep = 3

---One sweep: reveals the owner's living enemies to the side fixed at activation.
---@param owner Player
function STREAK:RevealEnemies(owner)
    local streaks = PW.Streaks
    if streaks == nil or streaks.Enemies == nil or PW.Reveal == nil or self.Side == nil then return end
    PW.Reveal(self.Side, streaks.Enemies(owner), self.Sweep + 0.5, owner)
end

function STREAK:OnEquip(owner)
    local streaks = PW.Streaks
    if not SERVER or streaks == nil or streaks.Viewer == nil then return end
    self.Side = streaks.Viewer(owner)
    self:RevealEnemies(owner)
    self:Timer(self.Sweep, 0, function() self:RevealEnemies(owner) end)
end

function STREAK:BotShouldUse()
    return true
end
