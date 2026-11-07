-- Difficulty tier "veteran" (T-5.12; 07-bots.md d.15; notes/14 "Difficulty model proposal").
-- Starting values, tuned in game.
-- Fairness (07 d.2): only human-like parameters, never damage, health, ammo or spread.
DIFFICULTY.Name = "Veteran"
DIFFICULTY.Description = "Near-human limits: fast, accurate, a good team player."

-- Aim spring and turn (bots_aim)
DIFFICULTY.look_stiffness = 300
DIFFICULTY.look_damping = 30
DIFFICULTY.look_max_accel = 3000
DIFFICULTY.turn_max_speed = 720

-- Aim focus and tracking (bots_aim)
DIFFICULTY.aim_focus_initial = 2
DIFFICULTY.aim_focus_decay = 0.2
DIFFICULTY.aim_focus_floor = 0.4
DIFFICULTY.aim_focus_reset_deg = 20
DIFFICULTY.aim_reroll_interval = 0.2
DIFFICULTY.aim_offset_scale = 0.15

-- Firing (bots_aim)
DIFFICULTY.attack_delay = 0
DIFFICULTY.lead_target = 1
DIFFICULTY.headshot_allowed = "yes"
DIFFICULTY.headshot_chance = 0.8
DIFFICULTY.recoil_comp_gain = 0.9

-- Perception (bots_perception)
DIFFICULTY.reaction_mean = 0.22
DIFFICULTY.reaction_floor = 0.15
DIFFICULTY.reaction_jitter = 0.2
DIFFICULTY.share_delay = 0.5
DIFFICULTY.share_radius = math.huge
DIFFICULTY.fov = 110

-- Decisions (bots_brain)
DIFFICULTY.decision_screen = 0.9
DIFFICULTY.commitment_bonus = 1.25

-- Orders (bots_objectives)
DIFFICULTY.teamwork = 0.95

-- Manoeuvres (bots_tactics)
DIFFICULTY.strafe_chance = 0.9
DIFFICULTY.slide_chance = 0.6 -- 07 d.15; only with the Quick Slide addon
