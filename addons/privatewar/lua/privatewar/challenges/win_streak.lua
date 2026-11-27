CHALLENGE.Name = "Winning Streak"
CHALLENGE.Description = "Win {target} matches in a row"
CHALLENGE.Group = "matches"
CHALLENGE.Event = "match_end"
CHALLENGE.Filters = { won = true }
CHALLENGE.ResetOn = { { Event = "match_end", Filters = { won = false } } }
CHALLENGE.Tiers = { "hard" }
CHALLENGE.Target = { hard = 4 }
