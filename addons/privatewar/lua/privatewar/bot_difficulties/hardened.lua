-- Difficulty tier "hardened" (T-5.12; 07-bots.md d.15; notes/14 "Difficulty model proposal").
-- Starting values, tuned in game.
-- Fairness (07 d.2): only human-like parameters, never damage, health, ammo or spread.
DIFFICULTY.Name = "Hardened"
DIFFICULTY.Description = "Quick reactions, rifles aim for the head."

-- Aim spring and turn (bots_aim)
DIFFICULTY.look_stiffness = 200
DIFFICULTY.look_damping = 30
DIFFICULTY.look_max_accel = 3000
DIFFICULTY.turn_max_speed = 540

-- Aim focus and tracking (bots_aim)
DIFFICULTY.aim_focus_initial = 6
DIFFICULTY.aim_focus_decay = 0.35
DIFFICULTY.aim_focus_floor = 0.8
DIFFICULTY.aim_focus_reset_deg = 15
DIFFICULTY.aim_reroll_interval = 0.4
DIFFICULTY.aim_offset_scale = 0.2

-- Firing (bots_aim)
DIFFICULTY.attack_delay = 0.1
DIFFICULTY.lead_target = 1
DIFFICULTY.headshot_allowed = "rifles"
DIFFICULTY.headshot_chance = 0.6
DIFFICULTY.recoil_comp_gain = 0.75

-- Perception (bots_perception)
DIFFICULTY.reaction_mean = 0.32
DIFFICULTY.reaction_floor = 0.18
DIFFICULTY.reaction_jitter = 0.25
DIFFICULTY.share_delay = 1.0
DIFFICULTY.share_radius = 1575
DIFFICULTY.fov = 110

-- Decisions (bots_brain)
DIFFICULTY.decision_screen = 0.8
DIFFICULTY.commitment_bonus = 1.2

-- Orders (bots_objectives)
DIFFICULTY.teamwork = 0.85

-- Manoeuvres (bots_tactics)
DIFFICULTY.strafe_chance = 0.7
DIFFICULTY.slide_chance = 0.4 -- 07 d.15; only with the Quick Slide addon
