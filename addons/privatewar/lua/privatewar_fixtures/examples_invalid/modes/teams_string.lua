-- Invalid example (T-1.18): MODE.Teams must be a number. This mode is skipped with the log line
-- 'modes "teams_string" (...): field Teams must be number, got string'.

MODE.Name = "Teams as text"
-- The deliberate mistake; the cast only keeps the type checker quiet about it.
MODE.Teams = "2" --[[@as any]]
