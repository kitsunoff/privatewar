-- TDM with a 32-participant fill target, not vehicles or a change to engine maxplayers.
PLAYLIST.Name = "Ground War TDM 32"
PLAYLIST.Description = "Large-team deathmatch with a 32-player fill target. First team to 150 kills wins."
function PLAYLIST:Modes() return assert(PW.Playlist)._ResolveRotation(self, "ground_war") end
function PLAYLIST:Maps() return assert(self._RotationData).Maps end
function PLAYLIST:Settings() return assert(self._RotationData).Settings end
function PLAYLIST:IsActive(now) return assert(PW.Playlist)._ShippedActive(self, "ground_war", now) end
