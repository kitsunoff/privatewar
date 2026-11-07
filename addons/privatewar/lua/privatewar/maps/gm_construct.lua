-- Authored objective content. Ordinary spawns stay auto-detected (03-mapdata.md d.3).
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
    },
    -- Ordered, original zones observed on the loaded map; not converted from DOM flags.
    -- Standing hull, floor normal and directed nav connectivity checked on gm_construct.
    -- Human travel fairness and vertical-contest checks remain pending.
    hardpoint = {
        zones = {
            { id = "Courtyard", pos = Vector(-400, -1400, -143.96875), radius = 192, above = 96, below = 16 },
            { id = "Lawn", pos = Vector(-1325, -575, -147.608963), radius = 192, above = 96, below = 16 },
            { id = "West", pos = Vector(-1975, -1550, -143.96875), radius = 192, above = 96, below = 16 }
        }
    },
    snd = {
        sites = {
            { id = "A", pos = Vector(-400, -1400, -143.96875), radius = 160, above = 96, below = 16,
                approach = Vector(-400, -1400, -143.96875) },
            { id = "B", pos = Vector(-1325, -575, -147.608963), radius = 160, above = 96, below = 16,
                approach = Vector(-1325, -575, -147.608963) }
        },
        bomb = Vector(-1975, -1550, -143.96875),
        spawns = {
            [1] = { { pos = Vector(-1975, -1550, -141.96875), yaw = 0 } },
            [2] = { { pos = Vector(1375, -1712.5, -141.96875), yaw = 180 } }
        }
    }
}
