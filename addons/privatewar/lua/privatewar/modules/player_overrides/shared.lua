-- Temporary role stats; ordinary player initialization remains owned by the base spawn path.
MODULE.Name = "Player overrides"
PW.PlayerOverrides = (rawget(PW, "PlayerOverrides") or {}) --[[@as PW.PlayerOverridesLib]]
