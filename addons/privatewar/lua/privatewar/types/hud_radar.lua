---@meta
-- Types of the radar (T-6.6, 09-hud.md d.2). Source: lua/privatewar/modules/hud/sh_radar.lua (pure rules),
-- lua/privatewar/hud/radar.lua (the element).

---The radar state: "normal" (teammates only), "uav" (revealed enemy blips are live, the sweep runs), "jammed"
---(a hostile Counter-UAV: noise, no enemy blips).
---@alias PW.RadarState "normal"|"uav"|"jammed"

---The local view of one radar frame: the player's position and yaw, the world range at the edge, the radius in
---pixels, the blip life in seconds (fade length) and whether the radar is jammed.
---@class PW.RadarFrame
---@field x number
---@field y number
---@field yaw number degrees
---@field range number world units shown from the centre to the edge
---@field radius number pixels
---@field life number seconds over which a blip fades out
---@field jammed boolean

---A player the client already knows (a networked, non-dormant, living player other than the local one).
---@class PW.RadarPerson
---@field x number
---@field y number
---@field enemy boolean PW.IsEnemy(local player, this player)

---A revealed position (PW.RevealBlip on the client; only x, y and ends are read).
---@class PW.RadarBlip
---@field pos { x: number, y: number }
---@field ends? number CurTime() at which the blip expires

---One dot to draw, in pixels from the radar centre.
---@class PW.RadarDot
---@field x number
---@field y number
---@field kind "friend"|"enemy"
---@field alpha number 0..1
---@field clamped boolean outside the range, drawn on the edge

---@class PW.HudLib
---Pure: a world offset (dx, dy from the player) to radar pixels from the centre, rotated so the view direction (yaw,
---degrees) points up; the screen y grows downwards. A point beyond `range` is put on the edge (third result true).
---@field _RadarProject fun(dx: number, dy: number, yaw: number, range: number, radius: number): number, number, boolean
---Pure: the alpha (0..1) of a blip that ends at `ends`: linear from 1 (`life` seconds left) to 0 (ended).
---@field _RadarFade fun(ends: number, now: number, life: number): number
---Pure: the radar state from the jam flag and the number of live blips. Jammed wins.
---@field _RadarState fun(jammed: boolean, blips: integer): PW.RadarState
---Pure: the sweep angle in radians (0 at the top, clockwise) at time `now` for one turn per `period` seconds.
---@field _RadarSweep fun(now: number, period: number): number
---Pure: fills `out` with the dots to draw (teammates first, then the revealed blips unless jammed), reusing its
---tables, and returns their count. Enemies among `people` are never drawn: only blips show enemies.
---@field _RadarDots fun(f: PW.RadarFrame, p: PW.RadarPerson[], b: PW.RadarBlip[], t: number, o: PW.RadarDot[]): integer
---Radar constants (design units and world units); see sh_radar.lua.
---@field Radar PW.RadarConfig

---@class PW.RadarConfig
---@field range number world units from the centre to the edge
---@field radius number design units
---@field left number design units, the left edge of the circle
---@field top number design units, the top edge of the circle
---@field life number seconds, the blip fade length (the UAV blip life)
---@field period number seconds per sweep turn (the UAV refresh interval)
---@field dot number design units, the size of a dot
---@field noise integer specks of noise per frame while jammed
