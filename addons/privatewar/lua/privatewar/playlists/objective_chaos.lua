-- Only existing Domination/Hardpoint layouts; sampling still filters each individual map/mode pair.
PLAYLIST.Name = "Objective Chaos"
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "objective_chaos") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "objective_chaos", now) end
