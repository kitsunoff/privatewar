-- Actions are called by the objective facade, never auto-subscribed. Mutable data belongs to a bot's visit.
KIND.Folder = "objective_actions"
KIND.Global = "OBJECTIVEACTION"
KIND.Subscribe = "never"
KIND.Required = { Update = "function" }
