-- Personality "run_and_gun" (T-5.12; 07-bots.md d.10, MVP set: run-and-gun, CQB, camper).
PERSONALITY.Name = "Run and gun"
PERSONALITY.Description = "Pushes forward and fights on the move."
PERSONALITY.type = "active"

-- Combat numbers (bots_tactics)
PERSONALITY.crouch_chance = 0.1
PERSONALITY.aggression = 0.8
PERSONALITY.engage_range = 1500
PERSONALITY.cover_chance = 0.3
PERSONALITY.flank_radius = 450
PERSONALITY.third_party_delay = 0.5
PERSONALITY.mobility = 0.9 -- T-11.6: strafe jitter and sprint chance

-- Class weights by the category of the primary weapon (bots_loadouts, T-5.13; unlisted categories weigh 1)
PERSONALITY.class_weights = { smg = 3, ar = 1.5, sniper = 0.5 }
