-- Personality "cqb" (T-5.12; 07-bots.md d.10, MVP set: run-and-gun, CQB, camper).
PERSONALITY.Name = "CQB"
PERSONALITY.Description = "Prefers close quarters and corners."
PERSONALITY.type = "active"

-- Combat numbers (bots_tactics)
PERSONALITY.crouch_chance = 0.25
PERSONALITY.aggression = 0.65
PERSONALITY.engage_range = 900
PERSONALITY.cover_chance = 0.5
PERSONALITY.flank_radius = 300
PERSONALITY.third_party_delay = 1
PERSONALITY.mobility = 0.7 -- T-11.6: strafe jitter and sprint chance

-- Class weights by the category of the primary weapon (bots_loadouts, T-5.13; unlisted categories weigh 1)
PERSONALITY.class_weights = { shotgun = 3, smg = 2, sniper = 0.25 }
