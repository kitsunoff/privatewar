-- Score event: a Domination flag captured (06-progression.md d.3, "point capture"; T-2.4). Awarded by the dom mode
-- to every player of the capturing team inside the flag when its owner changes. The team points of held flags are
-- the mode's own tally (pw_dom_score_<team>), not a per-player event.
EVENT.Name = "#pw.score.dom_capture"
EVENT.Points = 200
EVENT.Medal = false
