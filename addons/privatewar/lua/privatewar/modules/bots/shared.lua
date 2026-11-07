-- Bots module (T-2.6, owned by the bots lane since T-5.1; 02-modes.md d.5a; 07-bots.md d.3, d.10). One module
-- `bots` owns the bot settings; the bots_* modules of 07-bots.md d.3 are its sub-modules (the manager is
-- modules/bots_manager/). This file only declares the match settings the lobby, the playlists and the manager use.
--
-- Settings (scope match, edited in Game Setup, set by a playlist through its Settings table):
--   bots.fill        fill with bots up to N players in total (humans included), capped by maxplayers (02 d.4, d.5a)
--   bots.tickbudget  ms per tick the bot scheduler may spend (T-5.3; scope server; 07-bots.md d.3)
--   bots.difficulty  the difficulty tier of the bots, or "mix": a tier per bot (07-bots.md d.10; the tier list is the
--                    example of 01 d.17; the tiers are files in bot_difficulties/, see sh_profiles.lua)
--   bots.classes     where bots take their classes from: "preset" (the classes/ kind) and "players" (the custom
--                    classes of the humans of this session), default both (05-loadout.md d.14; bots_loadouts)
--   bots.classrepick chance that a bot picks a new class when it respawns (T-5.13, lane decision; bots_loadouts)

MODULE.Name = "Bots"

MODULE.Settings = {
    fill = { scope = "match", type = "int", default = 12, min = 0, max = 128, label = "Fill with bots up to N" },
    difficulty = { scope = "match", type = "enum", default = "regular",
        options = { "recruit", "regular", "hardened", "veteran", "mix" }, label = "Bot difficulty" },
    tickbudget = { scope = "server", type = "float", default = 2, min = 0.5, max = 10,
        label = "Bot tick budget (ms per tick)" },
    classes = { scope = "match", type = "set", options = { "preset", "players" }, default = { "preset", "players" },
        label = "Bot classes from" },
    classrepick = { scope = "match", type = "float", default = 0.25, min = 0, max = 1,
        label = "Bot class change chance per respawn" }
}

if SERVER then AddCSLuaFile("privatewar/modules/bots/sh_profiles.lua") end
include("privatewar/modules/bots/sh_profiles.lua")
