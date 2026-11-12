PLAYLIST.Name = "Free-for-All Frenzy"
PLAYLIST.Description = "Every player for themselves. Fast five-minute rounds with quick respawns."
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "ffa_frenzy") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "ffa_frenzy", now) end
