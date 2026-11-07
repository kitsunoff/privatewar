-- Example (T-2.1): a score event (06-progression.md d.3). One file per event in lua/privatewar/score_events/ fills
-- the EVENT table; the file name is the event id used in PW.Score.Award(ply, "example_bonus", { weapon = wep }).
-- Name and Points are required. XP left out means "same as Points"; Medal = true shows a popup with icon and sound.
-- Listeners and modes can change the points with the question hook PW_ScoreValue.

EVENT.Name = "#pw.score.example_bonus"
EVENT.Points = 25
-- Optional: XP different from the match score.
EVENT.XP = 40
EVENT.Medal = true
