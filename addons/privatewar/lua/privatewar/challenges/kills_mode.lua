CHALLENGE.Name = "Mode Assignment"
CHALLENGE.Description = "Get {target} kills in {param.mode}"
CHALLENGE.Group = "kills"
CHALLENGE.Event = "kill"
CHALLENGE.Params = { mode = { source = "modes" } }
CHALLENGE.Filters = { mode = "{param.mode}" }
CHALLENGE.Target = { easy = 25, medium = 60, hard = 120 }
