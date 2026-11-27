CHALLENGE.Name = "On Duty"
CHALLENGE.Description = "Finish {target} matches in {param.mode}"
CHALLENGE.Group = "matches"
CHALLENGE.Event = "match_end"
CHALLENGE.Params = { mode = { source = "modes" } }
CHALLENGE.Filters = { mode = "{param.mode}" }
CHALLENGE.Tiers = { "easy", "medium" }
CHALLENGE.Target = { easy = 2, medium = 4 }
