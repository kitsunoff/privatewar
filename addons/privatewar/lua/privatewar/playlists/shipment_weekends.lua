-- Installed Shipment BSPs only; no map download, fabricated BSP id or objective layout.
PLAYLIST.Name = "Shipment 24/7 Weekends"
PLAYLIST.Description = "Close-quarters action on installed Shipment maps. Team deathmatch, tags and objectives."
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "shipment_weekends") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "shipment_weekends", now) end
