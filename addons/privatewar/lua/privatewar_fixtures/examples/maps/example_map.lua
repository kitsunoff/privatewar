-- Example (T-2.7): map data (03-mapdata.md d.2). One file per map in lua/privatewar/maps/; the file name is the map
-- name lowercased, with every character outside [a-z0-9_] replaced by "_" (cs-office.v2 -> cs_office_v2). Every
-- field is optional: a map without a file still plays with spawns from its entities (d.1, d.3).

-- Spawn points by team index (1..N); 0 holds points for any team (FFA). When this table has a valid point it
-- replaces the spawn entities of the map.
MAP.Spawns = {
    [1] = { { pos = Vector(-1200, 2400, 64), yaw = 90 } },
    [2] = { { pos = Vector(1200, -2400, 64), yaw = 270 } }
}

-- Data per mode id, read by the mode with PW.Map.GetModeData(self.ClassName); the map module never interprets it.
MAP.Modes = {
    dom = { flags = { A = Vector(0, 0, 0), B = Vector(500, 0, 0), C = Vector(1000, 0, 0) } }
}
