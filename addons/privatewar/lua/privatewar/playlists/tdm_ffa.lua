-- "TDM & FFA": the two shipped modes in turn, on the maps installed with the game (T-2.6; 02-modes.md d.2). Equal
-- weights; the bot count is the fill setting of the bots module.
PLAYLIST.Name = "TDM & FFA"
PLAYLIST.Modes = { tdm = 1, ffa = 1 }
PLAYLIST.Maps = { "gm_construct", "gm_flatgrass" }
PLAYLIST.Settings = {
    ["bots.fill"] = 12
}
