---@meta

---@class PW.SNDWire
---@field WriteUInt fun(value: integer, bits: integer)
---@field WriteFloat fun(value: number)
---@field WriteBool fun(value: boolean)
---@field WriteString fun(value: string)
---@field WriteVector fun(value: Vector)
---@field ReadUInt fun(bits: integer): integer
---@field ReadFloat fun(): number
---@field ReadBool fun(): boolean
---@field ReadString fun(): string
---@field ReadVector fun(): Vector
---@field BytesLeft fun(): number?, integer? native incoming-message cursor; required for bounded decoding

---@class PW.SNDStatePacket
---@field generation integer
---@field serial integer
---@field view? PW.SNDSnapshot nil resets the legacy state

---@class PW.SNDSitesPacket
---@field generation integer
---@field serial integer
---@field sites? PW.SNDPublicSite[] nil resets optional public sites

---@class PW.SNDLib
---@field _WriteState fun(wire: PW.SNDWire, generation: integer, serial: integer, view: PW.SNDSnapshot?)
---@field _ReadState fun(wire: PW.SNDWire, length: integer): PW.SNDStatePacket?
---@field _WriteSites fun(wire: PW.SNDWire, generation: integer, serial: integer, sites: PW.SNDPublicSite[]?)
---@field _ReadSites fun(wire: PW.SNDWire, length: integer): PW.SNDSitesPacket?
---@field _SitesFor fun(packet: PW.SNDSitesPacket?, generation: integer, serial: integer): PW.SNDPublicSite[]?
