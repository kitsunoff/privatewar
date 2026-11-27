CHALLENGE.Name = "Weapon Assignment"
CHALLENGE.Description = "Get {target} kills with the {param.weapon}"
CHALLENGE.Group = "weapon_kills"
CHALLENGE.Event = "kill"
CHALLENGE.Params = { weapon = { source = "weapons" } }
CHALLENGE.Filters = { weapon = "{param.weapon}" }
CHALLENGE.Target = { easy = 10, medium = 25, hard = 50 }
