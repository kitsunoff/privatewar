---@meta
-- Tests-first contract: docs/api/support-devices.md. Runtime implementation is a separate TDD step.

---@alias PW.SupportDeviceKind "ammo_cache"|"medical_station"|"ground_sensor"

---@class PW.DeploymentFacts
---@field origin Vector
---@field aim Vector
---@field position Vector
---@field normal Vector
---@field hit boolean
---@field world boolean
---@field sky boolean
---@field water boolean
---@field hullClear boolean
---@field exitClear boolean
---@field supported boolean
---@field visible boolean

---@class PW.DevicePlacement
---@field position Vector
---@field angles Angle

---@class PW.SupportDevice
---@field owner Player
---@field kind PW.SupportDeviceKind
---@field entity Entity
---@field position Vector
---@field team integer
---@field ends number
---@field instance PW.StreakInstance
---@field charges? integer
---@field receipts? table<Player, number>
---@field pulse? number
---@field retired? boolean authoritative retirement before engine deletion completes
---@field constructing? boolean reserved ownership, not yet available to effects or perception

---@class PW.SupportDeviceEntity : Entity
---@field GetDeviceKind fun(self: PW.SupportDeviceEntity): PW.SupportDeviceKind
---@field SetDeviceKind fun(self: PW.SupportDeviceEntity, value: PW.SupportDeviceKind)
---@field GetDeviceOwner fun(self: PW.SupportDeviceEntity): Player
---@field SetDeviceOwner fun(self: PW.SupportDeviceEntity, value: Player)
---@field GetDeviceEnds fun(self: PW.SupportDeviceEntity): number
---@field SetDeviceEnds fun(self: PW.SupportDeviceEntity, value: number)

---@class PW.DeviceMarker
---@field x number
---@field y number
---@field text string
---@field visible boolean
---@field width? number
---@field height? number

---@class PW.SupportDeviceConfig
---@field model string
---@field name string
---@field duration number
---@field radius number

---@class PW.SupportEligibility
---@field owner any
---@field recipient any
---@field teams boolean
---@field allied boolean
---@field alive boolean
---@field allowed boolean
---@field distance number
---@field radius number
---@field visible boolean

---@class PW.DeviceLifetimeFacts
---@field now number
---@field ends number
---@field ownerValid boolean
---@field team integer
---@field currentTeam integer
---@field enabled boolean
---@field allowed boolean

---@class PW.SupportStreaksLib
---@field Placement fun(facts: PW.DeploymentFacts): boolean, string?
---@field Capacity fun(records: { owner: any, kind: string }[], owner: any, kind: string): boolean
---@field ScanEligible fun(origin: Vector, direction: Vector, target: Vector, visible: boolean): boolean
---@field SensorEligible fun(origin: Vector, target: Vector, visible: boolean): boolean
---@field SupportEligible fun(facts: PW.SupportEligibility): boolean
---@field ReceiptReady fun(charges: integer, last: number?, now: number): boolean
---@field HealAmount fun(hp: number, max: number, damaged: number, now: number, dt: number, rates: number[]): number
---@field ScanDirection fun(origin: Vector, facing: Vector, contacts: PW.BotContact[], publicPoint?: Vector): Vector
---@field EndReason fun(facts: PW.DeviceLifetimeFacts): string?
---@field DamageAllowed fun(hostilePlayer: boolean, world: boolean): boolean
---@field LayoutMarkers fun(rows: PW.DeviceMarker[], width: number, height: number)

---@class PW.DevicesLib
---@field Config table<string, PW.SupportDeviceConfig>
---@field Prepare fun(owner: Player, kind: PW.SupportDeviceKind): PW.DevicePlacement?, string?
---@field Create fun(inst: PW.StreakInstance, kind: PW.SupportDeviceKind, p: PW.DevicePlacement): PW.SupportDevice?
---@field Remove fun(record: PW.SupportDevice)
---@field List fun(): PW.SupportDevice[]
---@field RemoveOwner fun(owner: Player)
---@field Clear fun()
---@field Enabled fun(kind: PW.SupportDeviceKind): boolean
---@field Feedback fun(owner: Player, text: string)
---@field Validate fun(owner: Player, kind: PW.SupportDeviceKind, position: Vector): boolean, string?
---@field ModelBounds fun(kind: PW.SupportDeviceKind): Vector?, Vector?
---@field EntityRemoved fun(entity: Entity)
---@field Damage fun(entity: Entity, damage: CTakeDamageInfo)
---@field _Records PW.SupportDevice[]
---@field _Damaged table<Player, number>
---@field _Healing table<Player, number> fractional health pending the next integer engine update
---@field ClientTrack? fun(entity: PW.SupportDeviceEntity)
---@field Markers? PW.DeviceMarker[]
---@field Notice? string
---@field MarkerFont? string

---@class PW.BotDeviceContact
---@field device PW.SupportDevice
---@field position Vector
---@field seen number
---@field recognized number
---@field visible boolean

---@class PW.BotDevicesLib
---@field Contact fun(bot: Player): PW.BotDeviceContact?
---@field Perceivable fun(eye: Vector, dir: Vector, pos: Vector, range: number, fov: number, los: boolean): boolean
---@field Recognized fun(firstSeen: number?, now: number, delay: number, visible: boolean): boolean
---@field AttackWanted fun(playerThreat: boolean, deviceVisible: boolean): boolean
---@field Step fun(bot: Player)
---@field CanObserve fun(bot: Player, now: number): boolean
---@field OwnInput fun(bot: Player, intent: PW.BotIntent)
---@field ReleaseInput fun(bot: Player)
---@field Invalidate fun(record: PW.SupportDevice)

---@class PW.BotDeviceState
---@field first table<Entity, number>
---@field index integer
---@field contact? PW.BotDeviceContact

---@class PW.DeviceAimControl
---@field difficulty? table
---@field params PW.BotAimParams
---@field state PW.BotAimState
---@field view Angle
---@field trace Trace
---@field input PW.BotAimInput
---@field device? PW.SupportDevice
---@field weapon? Weapon
---@field recoil? PW.Recoil
---@field fire? PW.FireInfo

---@class PW.Streak
---@field Prepare? fun(self: PW.Streak, owner: Player): table?

---@class PW.StreakInstance
---@field Activation? table server-only prepared data, installed before OnEquip
---@field Device? PW.SupportDevice

---@class PW
---@field SupportStreaks? PW.SupportStreaksLib
---@field Devices? PW.DevicesLib
---@field BotDevices? PW.BotDevicesLib
