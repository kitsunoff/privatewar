CHALLENGE.Name = "Playlist Fighter"
CHALLENGE.Description = "Get {target} kills in any playlist"
CHALLENGE.Group = "kills"
CHALLENGE.Event = "kill"
CHALLENGE.Filters = { playlist = true }
CHALLENGE.Requires = { playlists = {
    "tdm_ffa", "objective_chaos", "ground_war", "free_for_all", "small_map_moshpit",
    "ffa_frenzy", "infected", "shipment_weekends"
} }
CHALLENGE.Target = { easy = 25, medium = 60, hard = 120 }
