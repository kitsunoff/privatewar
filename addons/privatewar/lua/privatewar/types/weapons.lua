---@meta
-- Types of the weapon registration phase (T-1.17, 04-weapons.md d.3; 01-extensibility.md d.16 step 7, d.12).
-- Code: gamemodes/privatewar/gamemode/core/sh_weapon_phase.lua; the weapons kind: lua/privatewar/kinds/weapons.lua.

---One run of the phase, recorded on the store.
---@class PW.WeaponPhaseRun
---@field reason string "InitPostEntity" or "reload"
---@field sweps integer #weapons.GetList() when the run started (Lua SWEPs registered by then)

---Options of a weapon phase store; every field has a default (tests inject their own).
---@class PW.WeaponPhaseStoreOptions
---@field log? PW.LogFn

---Internal: state of the weapon phase of this realm.
---@class PW.WeaponPhaseStore
---@field log PW.LogFn
---@field ready boolean InitPostEntity of this realm has run (SWEPs exist); a later Boot re-runs the phase
---@field runs integer runs so far (InitPostEntity, then one per reload)
---@field first? PW.WeaponPhaseRun the first run of this map
---@field last? PW.WeaponPhaseRun the latest run

---The weapon registration phase (04-weapons.md d.3). Shared: it runs on the server and on every client.
---@class PW.WeaponPhaseLib
---Internal: runs the phase over registries.weapons: PW.Notify("PW_RegisterWeapons", reg), then
---PW.Notify("PW_WeaponsLoaded"). reg is the weapons registry: reg.Register(tbl, class, { soft = true }) registers a
---weapon (soft fills only missing fields of an existing entry). An error in a PW_RegisterWeapons listener is logged
---and PW_WeaponsLoaded still fires. Without a weapons registry nothing fires: one log line, false.
---@field _Run fun(store: PW.WeaponPhaseStore, registries: table<string, PW.Registry>, reason: string): boolean
---Internal: InitPostEntity of this realm. Marks PW._WeaponPhase ready and runs the phase on PW.Registries.
---@field _OnInitPostEntity fun()
---Internal: called by PW.Loader.Boot after PW_RegistriesLoaded. A reload replaces the weapons registry, so after
---InitPostEntity every Boot runs the phase again on the new registries; before it (gamemode load) nothing runs.
---@field _OnBoot fun()
---Internal: a fresh store (tests swap PW._WeaponPhase).
---@field _NewStore fun(opts?: PW.WeaponPhaseStoreOptions): PW.WeaponPhaseStore

---@class PW
---@field WeaponPhase PW.WeaponPhaseLib
---@field _WeaponPhase PW.WeaponPhaseStore internal
---The weapons kind (lua/privatewar/kinds/weapons.lua): id = SWEP class. Filled by lua/privatewar/weapons/ files
---and by PW_RegisterWeapons listeners.
---@field Weapons PW.Registry

---@class PW.AttachmentCuration
---@field Unlock? integer weapon level that unlocks the option
---@field Cost? number Pick X cost of the option
---@field Hidden? boolean never offered

---@class PW.CamoCuration
---@field Unlock? integer weapon level that unlocks the camo

---An entry of the weapons kind (04-weapons.md d.3): id = SWEP class. No field is required: a soft registration may
---carry only some fields and other sources fill the rest.
---@class PW.Weapon : PW.Entity
---@field Category? string weapon category, for example "ar" or "smg"
---@field Name? string display name
---@field Unlock? integer unlock level, read by 06-progression; empty means its default
---@field Kind? PW.WeaponKind filled softly from the adapter's ListWeapons
---@field Slot? integer 1 primary, 2 secondary, 3 equipment; filled softly from ListWeapons
---@field Attachments? table<string, PW.AttachmentCuration> curation by option id (adapter.md "Weapon catalogue")
---@field Camos? table<string, PW.CamoCuration> cosmetic options by id
---@field Cost? number Pick X cost, default 1
---@field Price? number shop price

---Class table inside a weapons/ file.
---@type PW.Weapon
WEAPON = nil
