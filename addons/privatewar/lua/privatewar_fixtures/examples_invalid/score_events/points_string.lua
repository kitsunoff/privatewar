-- Invalid example (T-2.1): EVENT.Points must be a number. This event is skipped with the log line
-- 'score_events "points_string" (...): field Points must be number, got string'.

EVENT.Name = "#pw.score.points_string"
-- The deliberate mistake; the cast only keeps the type checker quiet about it.
EVENT.Points = "100" --[[@as any]]
