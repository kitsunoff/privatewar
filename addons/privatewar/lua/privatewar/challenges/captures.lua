CHALLENGE.Name = "Flag Runner"
CHALLENGE.Description = "Capture {target} flags in Domination"
CHALLENGE.Group = "objective"
CHALLENGE.Event = "objective"
CHALLENGE.Filters = { objective = "capture", mode = "dom" }
CHALLENGE.Requires = { modes = { "dom" } }
CHALLENGE.Target = { easy = 5, medium = 15, hard = 30 }
local card = { kind = "cards", id = "challenge_captures" }
CHALLENGE.Rewards = {
    easy = { xp = 2500, currency = 50, items = { card } },
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
