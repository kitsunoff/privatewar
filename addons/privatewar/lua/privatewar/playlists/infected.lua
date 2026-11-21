-- Requires the separate privatewar-infection addon and an eligible installed map.
PLAYLIST.Name = "Infected"
PLAYLIST.Description = "Survive the infected until time runs out. One touch turns a survivor into a hunter."
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "infected") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "infected", now) end
