CHALLENGE.Name = "Air Support"
CHALLENGE.Description = "Get {target} kills with killstreaks"
CHALLENGE.Group = "streaks"
CHALLENGE.Event = "kill"
CHALLENGE.Filters = { streakKill = true }
CHALLENGE.Requires = { kinds = { streaks = { "airstrike" } } }
CHALLENGE.Target = { easy = 3, medium = 10, hard = 20 }
local card = { kind = "cards", id = "challenge_streak_kills" }
CHALLENGE.Rewards = {
    easy = { xp = 2500, currency = 50, items = { card } },
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
