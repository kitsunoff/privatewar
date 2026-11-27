CHALLENGE.Name = "Headhunter"
CHALLENGE.Description = "Get {target} headshot kills"
CHALLENGE.Group = "headshots"
CHALLENGE.Event = "kill"
CHALLENGE.Filters = { headshot = true }
CHALLENGE.Target = { easy = 10, medium = 25, hard = 60 }
local card = { kind = "cards", id = "challenge_headshots" }
CHALLENGE.Rewards = {
    easy = { xp = 2500, currency = 50, items = { card } },
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
