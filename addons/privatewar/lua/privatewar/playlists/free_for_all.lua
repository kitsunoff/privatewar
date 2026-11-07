-- "Free for all": a short FFA preset on the maps installed with the game (T-2.6; 02-modes.md d.2: a preset is a
-- playlist with one mode).
PLAYLIST.Name = "Free for all"
PLAYLIST.Modes = { ffa = 1 }
PLAYLIST.Maps = { "gm_construct", "gm_flatgrass" }
PLAYLIST.Settings = {
    ["bots.fill"] = 8,
    ["ffa.scorelimit"] = 25
}
