-- Counter-UAV (T-4.6; 05-loadout.md d.9, d.10): radar jamming. For Duration, the owner's side is hidden from every
-- hostile reveal (an enemy UAV shows nothing of it) and the hostile players get a jam notice for their radar (T-6.6).
STREAK.Name = "Counter-UAV"
STREAK.Kills = 4
STREAK.Duration = 25

function STREAK:OnEquip(owner)
    local streaks = PW.Streaks
    if not SERVER or streaks == nil or streaks.Jam == nil then return end
    streaks.Jam(owner, self.Duration)
end

function STREAK:BotShouldUse()
    return true
end
