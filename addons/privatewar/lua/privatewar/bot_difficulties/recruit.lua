-- Difficulty tier "recruit" (T-5.12; 07-bots.md d.15; notes/14 "Difficulty model proposal").
-- Starting values, tuned in game.
-- Fairness (07 d.2): only human-like parameters, never damage, health, ammo or spread.
DIFFICULTY.Name = "Recruit"
DIFFICULTY.Description = "Slow to react, wide aim error, rarely follows orders."

-- Aim spring and turn (bots_aim)
DIFFICULTY.look_stiffness = 100
DIFFICULTY.look_damping = 25
DIFFICULTY.look_max_accel = 1500
DIFFICULTY.turn_max_speed = 180

-- Aim focus and tracking (bots_aim)
DIFFICULTY.aim_focus_initial = 20
DIFFICULTY.aim_focus_decay = 0.7
DIFFICULTY.aim_focus_floor = 3
DIFFICULTY.aim_focus_reset_deg = 10
DIFFICULTY.aim_reroll_interval = 0.7
DIFFICULTY.aim_offset_scale = 0.6

-- Firing (bots_aim)
DIFFICULTY.attack_delay = 0.7
DIFFICULTY.lead_target = 0
DIFFICULTY.headshot_allowed = "no"
DIFFICULTY.headshot_chance = 0
DIFFICULTY.recoil_comp_gain = 0.3

-- Perception (bots_perception)
DIFFICULTY.reaction_mean = 0.6
DIFFICULTY.reaction_floor = 0.25
DIFFICULTY.reaction_jitter = 0.35
DIFFICULTY.share_delay = 2.0
DIFFICULTY.share_radius = 800
DIFFICULTY.fov = 110

-- Decisions (bots_brain)
DIFFICULTY.decision_screen = 0.5
DIFFICULTY.commitment_bonus = 1.1

-- Orders (bots_objectives)
DIFFICULTY.teamwork = 0.5

-- Manoeuvres (bots_tactics)
DIFFICULTY.strafe_chance = 0
DIFFICULTY.slide_chance = 0 -- 07 d.15; only with the Quick Slide addon
