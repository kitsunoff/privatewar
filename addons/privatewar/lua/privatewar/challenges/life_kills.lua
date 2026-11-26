CHALLENGE.Name = "Untouchable"
CHALLENGE.Description = "Get {target} kills without dying"
CHALLENGE.Group = "skill_kills"
CHALLENGE.Event = "kill"
CHALLENGE.Scope = "life"
CHALLENGE.Tiers = { "medium", "hard" }
CHALLENGE.Target = { medium = 8, hard = 12 }
local card = { kind = "cards", id = "challenge_life_kills" }
CHALLENGE.Rewards = {
    medium = { xp = 5000, currency = 100, items = { card } },
    hard = { xp = 10000, currency = 200, items = { card } }
}
