-- Free-for-all (T-2.2; 02-modes.md d.5, d.6). Inherits TDM with no teams: every other player is an enemy, each
-- player's kills count toward the score limit, and the top player wins (a shared top score is a draw). FFA players
-- play in the free team of the match_rules module, so the base gamemode does not spawn them as spectators.

MODE.Base = "tdm"
MODE.Name = "Free-for-all"
MODE.Short = "FFA"
MODE.Teams = 0
MODE.Description = "Everyone for themselves. First to the kill limit wins; at the time limit the top player wins."
MODE.Settings = {
    scorelimit = { default = 30 }
}
