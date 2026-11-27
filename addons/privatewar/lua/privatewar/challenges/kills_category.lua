CHALLENGE.Name = "Weapon Specialist"
CHALLENGE.Description = "Get {target} kills with {param.category} weapons"
CHALLENGE.Group = "weapon_kills"
CHALLENGE.Event = "kill"
CHALLENGE.Params = { category = { source = "categories" } }
CHALLENGE.Filters = { category = "{param.category}" }
CHALLENGE.Target = { easy = 15, medium = 40, hard = 80 }
