CHALLENGE.Name = "Precision Work"
CHALLENGE.Description = "Get {target} headshots with {param.category} weapons"
CHALLENGE.Group = "headshots"
CHALLENGE.Event = "kill"
CHALLENGE.Params = { category = { source = "categories" } }
CHALLENGE.Filters = { headshot = true, category = "{param.category}" }
CHALLENGE.Target = { easy = 5, medium = 15, hard = 30 }
