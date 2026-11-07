-- Test content for gm_construct: Domination flags only. Spawns stay auto-detected (03-mapdata.md d.3).
-- Each flag sits exactly on an info_player_start; A and C are the two spawns farthest apart, B is the one nearest to
-- their midpoint. Written in the format of `pw_mark dom <letter>`.
MAP.Name = "gm_construct"

MAP.Modes = {
    dom = {
        flags = {
            A = Vector(703, -800.34, -143),
            B = Vector(823.85, -32, -143),
            C = Vector(968.61, 721.69, -143)
        }
    }
}
