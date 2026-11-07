-- Difficulty tier "regular" (T-5.12; 07-bots.md d.15; notes/14 "Difficulty model proposal").
-- Starting values, tuned in game.
-- Fairness (07 d.2): only human-like parameters, never damage, health, ammo or spread.
DIFFICULTY.Name = "Regular"
DIFFICULTY.Description = "The default tier: a casual player."

-- Aim spring and turn (bots_aim)
DIFFICULTY.look_stiffness = 150
DIFFICULTY.look_damping = 30
DIFFICULTY.look_max_accel = 2000
DIFFICULTY.turn_max_speed = 360

-- Aim focus and tracking (bots_aim)
DIFFICULTY.aim_focus_initial = 12
DIFFICULTY.aim_focus_decay = 0.5
DIFFICULTY.aim_focus_floor = 1.5
DIFFICULTY.aim_focus_reset_deg = 10
DIFFICULTY.aim_reroll_interval = 0.6
DIFFICULTY.aim_offset_scale = 0.35

-- Firing (bots_aim)
DIFFICULTY.attack_delay = 0.4
DIFFICULTY.lead_target = 0.5
DIFFICULTY.headshot_allowed = "no"
DIFFICULTY.headshot_chance = 0
DIFFICULTY.recoil_comp_gain = 0.5

-- Perception (bots_perception)
DIFFICULTY.reaction_mean = 0.45
DIFFICULTY.reaction_floor = 0.2
DIFFICULTY.reaction_jitter = 0.3
DIFFICULTY.share_delay = 1.5
DIFFICULTY.share_radius = 1200
DIFFICULTY.fov = 110

-- Decisions (bots_brain)
DIFFICULTY.decision_screen = 0.7
DIFFICULTY.commitment_bonus = 1.15

-- Orders (bots_objectives)
DIFFICULTY.teamwork = 0.75

-- Manoeuvres (bots_tactics)
DIFFICULTY.strafe_chance = 0.5
DIFFICULTY.slide_chance = 0.2 -- 07 d.15; only with the Quick Slide addon
