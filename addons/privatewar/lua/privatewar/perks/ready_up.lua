-- "Ready Up" (T-4.4; 05-loadout.md d.8 sample stat perk). Shorter sprint-to-fire time through PW.SetStatMods; a
-- weapon base honours it only when its adapter supports the key sprint_to_fire (SupportedStatMods).
PERK.Name = "Ready Up"
PERK.Description = "Fire 40% sooner after sprinting."
PERK.Group = 1
PERK.Stats = { sprint_to_fire = 0.6 }
