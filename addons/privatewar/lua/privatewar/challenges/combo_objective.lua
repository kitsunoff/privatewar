CHALLENGE.Name = "Domination Specialist"
CHALLENGE.Description = "Get {target1} kills and {target2} captures in Domination"
CHALLENGE.Group = "objective"
CHALLENGE.Requires = { modes = { "dom" } }
CHALLENGE.Objectives = {
    { Event = "kill", Filters = { mode = "dom" }, Target = { easy = 20, medium = 40, hard = 80 } },
    { Event = "objective", Filters = { objective = "capture", mode = "dom" },
        Target = { easy = 3, medium = 8, hard = 15 } }
}
