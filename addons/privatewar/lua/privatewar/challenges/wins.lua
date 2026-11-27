CHALLENGE.Name = "Champion"
CHALLENGE.Description = "Win {target} matches"
CHALLENGE.Group = "matches"
CHALLENGE.Event = "match_end"
CHALLENGE.Filters = { won = true }
CHALLENGE.Target = { easy = 2, medium = 5, hard = 10 }
local card = { kind = "cards", id = "challenge_wins" }
CHALLENGE.Rewards = {
    easy = { xp = 2500, currency = 50, items = { card } },
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
