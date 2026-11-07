-- Personality "camper" (T-5.12; 07-bots.md d.10, MVP set: run-and-gun, CQB, camper).
PERSONALITY.Name = "Camper"
PERSONALITY.Description = "Holds a spot and covers a flag or a lane."
PERSONALITY.type = "stationary"

-- Combat numbers (bots_tactics)
PERSONALITY.crouch_chance = 0.6
PERSONALITY.aggression = 0.2
PERSONALITY.engage_range = 2500
PERSONALITY.cover_chance = 0.8
PERSONALITY.flank_radius = 600
PERSONALITY.third_party_delay = 3
PERSONALITY.mobility = 0.3 -- T-11.6: strafe jitter and sprint chance

-- Class weights by the category of the primary weapon (bots_loadouts, T-5.13; unlisted categories weigh 1)
PERSONALITY.class_weights = { sniper = 3, lmg = 2, ar = 1.5, shotgun = 0.5 }
