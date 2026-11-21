---@meta
-- Unlock authority types (06-progression.md d.8).

---@alias PW.UnlockField integer|false|{ level?: integer|false, hint?: string, reward?: string }

---@class PW.UnlockSpec
---@field level integer|false 0 = open; false = no level path
---@field hint? string plain text or a language phrase
---@field reward? string grant source for reward discovery, not a condition
---@field declared boolean whether the raw field was not nil

---@alias PW.UnlockReason
---| "unknown"
---| "hidden"
---| "override"
---| "unlockall"
---| "grant"
---| "purchase"
---| "grant_only"
---| "price"
---| "level"
---| "weapon_level"
---| "default"

---@class PW.UnlockRequirement
---@field unlocked boolean
---@field reason PW.UnlockReason
---@field level? integer required player level
---@field weaponLevel? integer required weapon level
---@field price? integer present if purchasable
---@field hint? string policy hint, then the definition's hint
---@field lockText? string short badge
---@field text? string requirement sentence

---@class PW.UnlockItem
---@field kind string registry kind, "attachments" or "camos" ("camo" is an alias)
---@field id string entity or option id
---@field weapon? string required for options only

---@class PW.UnlockItemView
---@field key string
---@field kind string
---@field id string
---@field weapon? string
---@field name string
---@field valid boolean resolves on this host

---@class PW.UnlockGrantOptions
---@field source string
---@field grant? string idempotency key

---@class PW.UnlockGrantMeta
---@field source string
---@field at integer Unix time; 0 when unknown
---@field grant? string

---@class PW.UnlocksFile
---@field v integer
---@field grants table<string, PW.UnlockGrantMeta>
---@field claims table<string, integer> grant id to Unix time
---@field batch PW.ProgressionBatch

---@class PW.UnlockUpload
---@field grants table<string, boolean> granted keys, without metadata
---@field claims table<string, boolean> claimed ids, without timestamps

---@class PW.UnlockDeltaPart
---@field granted? table<string, PW.UnlockGrantMeta>
---@field revoked? table<string, string> key to the revoking source
---@field claims? table<string, integer>

---@class PW.UnlocksLib
---@field MaxHintLength integer
---@field MaxSourceLength integer
---@field _CheckHint fun(value: any): string?
---@field _CheckSource fun(value: any): string?
---@field _Price fun(entity: table<string, any>): integer?
---@field _Spec fun(unlock: any): PW.UnlockSpec
---@field _StaticRequirement fun(entity: table<string, any>?, isOption: boolean): PW.UnlockRequirement
---@field LockText fun(req: PW.UnlockRequirement): string?, string?
---@field KeyOf fun(item: PW.UnlockItem|string): string?
---@field ParseKey fun(key: string): string?, string?, string?, string?
---@field _Decide fun(view: PW.ProgressionView, kind: string, id: string): boolean, PW.UnlockReason
---@field _Requirement fun(view: PW.ProgressionView, kind: string, id: string): PW.UnlockRequirement
---@field FilePath string
---@field FileVersion integer
---@field UploadMaxBytes integer
---@field MaxGrants integer
---@field MaxClaims integer
---@field MaxGrantIdLength integer
---@field MaxGrantPerCall integer
---@field MaxDeltaGrants integer
---@field MaxDeltaRevokes integer
---@field MaxDeltaClaims integer
---@field _CheckGrantId fun(value: any): string?
---@field _EntitlementKey fun(value: any): string?
---@field _CheckTime fun(value: any): integer?
---@field _CheckGrants fun(raw: any, limit?: integer): table<string, PW.UnlockGrantMeta>
---@field _CheckClaims fun(raw: any, limit?: integer): table<string, integer>
---@field _FileFromJson fun(decoded: any): PW.UnlocksFile
---@field _FileToJson fun(stored: PW.UnlocksFile): PW.UnlocksFile
---@field _ListEntitled fun(owned: table<string, boolean>?, granted: table<string, PW.UnlockGrantMeta>?):
---table<string, PW.UnlockGrantMeta>
---@field _ApplyDelta fun(current: PW.UnlocksFile, delta: PW.ProgressionDelta):
---PW.UnlocksFile, boolean, PW.UnlockDeltaPart?
---@field _EncodeUpload fun(stored: PW.UnlocksFile, writer: PW.ProgressionWriter)
---@field _DecodeUpload fun(reader: PW.ProgressionReader): PW.UnlockUpload?
---@field _EncodeDeltaPart fun(part: PW.UnlockDeltaPart, writer: PW.ProgressionWriter)
---@field _DecodeDeltaPart fun(reader: PW.ProgressionReader): PW.UnlockDeltaPart

---@class PW
---@field Unlocks? PW.UnlocksLib the progression unlock authority
