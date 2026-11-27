CHALLENGE.Name = "Marksman"
CHALLENGE.Description = "Get {target} kills from 30 m or more"
CHALLENGE.Event = "kill"
CHALLENGE.Filters = { distanceMin = 30 }
CHALLENGE.Target = { easy = 5, medium = 15, hard = 30 }
local card = { kind = "cards", id = "challenge_longshots" }
CHALLENGE.Rewards = {
    easy = { xp = 2500, currency = 50, items = { card } },
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
