-- Compact pool: authored gm_construct and installed Shipment variants, never flatgrass.
PLAYLIST.Name = "Small Map Moshpit"
PLAYLIST.Description = "A compact-map mix of team deathmatch, Kill Confirmed, Domination and Hardpoint."
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "small_map_moshpit") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "small_map_moshpit", now) end
