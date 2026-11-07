# Core API (frozen after T-1.3)

Status: **frozen** on 2026-11-06. Changes go only through the orchestrator. Type definitions: `lua/privatewar/types/core.lua`.

Extended after T-1.4 to T-1.19 (2026-11-06) and after wave 0, 2026-11-07 (required fields checked after `Base`, `PW.HookFor`, class table `IsValid`, net `owner`,
shared enable snapshot: see "Required fields", "Auto-subscription", "Enable ConVars" and "Client messages"): sections "Built-in kind `modes`", "Built-in kind `weapons`", "Weapon
registration phase", "Auto-subscription", "Enable ConVars", "Settings", "Hot reload", "Hook dispatch", "Entity
calls", "Instances", "Phases and match", "Phase networking", "Client messages", "Map change", "Privileges" and "Base
gamemode overrides" added; `PW.Enable.ConVarName` and `PW.Settings.Format` (T-1.19) and the entity file convention
for methods added; `KIND.Subscribe`, `opts.subscribe`, `opts.methods`,
`GetEnabledList`, `IsValid`, the late-registration rule, the release in `PW.Loader.Boot`, the boot steps and
`PW.Match.Start(mode, map?)` added to the existing sections; hook dispatch, the match hooks, `PW_PhaseChanged` and
`PW_PendingMatchApplied`, `PW_PendingTeams`, `PW_RegisterWeapons` and `PW_WeaponsLoaded` added to "Hooks". The teams
module (T-1.16) is documented in `teams.md`; the widget kit and the lobby screen (T-1.19) in `ui.md`. The contract stays frozen; the additions are non-breaking (`design/01-extensibility.md` d.14), so `PW.API` is unchanged.

Extended on 2026-11-07 after T-2.13: the question hook `PW_NextMatch`, `PW.Match.EndVote` and the `VOTE` to `PREMATCH` hand-over, including a map change from `VOTE` (see "Phases and match", "Map change" and "Hooks").

Source decisions: `design/01-extensibility.md` d.8–d.18;
`design/04-weapons.md` d.3; `design/00-core.md` d.1–d.11.

## Namespace

| Field | Type | Meaning |
| --- | --- | --- |
| `PW.Version` | string | Semantic version of the gamemode |
| `PW.API` | integer | Bumped only on breaking API changes (d.14) |
| `PW.Registry` | `PW.RegistryLib` | Registry constructor |
| `PW.Loader` | `PW.LoaderLib` | Kind loader |
| `PW.Registries` | `table<string, PW.Registry>` | Every registry by kind id (set by `PW.Loader.Boot`) |
| `PW.Kinds` | `PW.Registry` | Built-in kind `kinds` |
| `PW.Modules` | `PW.Registry` | Built-in kind `modules` |
| `PW.ActiveMode` | `table?` | The active mode, `nil` outside a match (see "Hook dispatch") |
| `PW.Ask` | function | Dispatches a question hook (see "Hook dispatch") |
| `PW.Notify` | function | Dispatches a notification hook (see "Hook dispatch") |
| `PW.Call` | function | Calls an entity method safely (see "Entity calls") |
| `PW.Profile` | `PW.ProfileLib` | `PW.Call` timings (see "Entity calls") |
| `PW.Instance` | function | Creates a per-owner instance of a definition (see "Instances") |
| `PW.Phase` | `PW.PhaseLib` | Phase names and transition rules, shared (see "Phases and match") |
| `PW.Match` | `PW.MatchLib?` | Match control, server only; `nil` on the client (see "Phases and match") |
| `PW.Net` | `PW.NetLib` | Client → server messages, server only (see "Client messages") |
| `PW.HookFor` | function | Adds an engine hook to an entity for as long as it is enabled (see "Auto-subscription") |
| `PW.MapChange` | `PW.MapChangeLib?` | Map change, server only (see "Map change") |
| `PW.Reload` | `PW.ReloadLib` | Hot reload, shared (see "Hot reload") |
| `PW.Modes` | `PW.Registry` | Registry of the `modes` kind (see "Built-in kind `modes`") |
| `PW.Weapons` | `PW.Registry` | Registry of the `weapons` kind (see "Built-in kind `weapons`") |
| `PW.WeaponPhase` | `PW.WeaponPhaseLib` | Weapon registration phase, shared; only internal functions (see "Weapon registration phase") |
| `PW.Enable` | `PW.EnableLib` | Enable ConVars and the enable snapshot; shared, `ConVarName` is server only (see "Enable ConVars") |
| `PW.Setting` | function | Reads a setting by full id (see "Settings") |
| `PW.Settings` | `PW.SettingsLib` | Settings schema, changes and form groups, shared (see "Settings") |
| `PW.Privilege` | function | Declares a named privilege (see "Privileges") |
| `PW.Can` | function | Checks a named privilege (see "Privileges") |
| `PW.<Name>` | `PW.Registry` | Accessor per declared kind: `PW.Loader.AccessorName(kindId)` (`weapon_adapters` → `PW.WeaponAdapters`). If the name is taken by the core, only `PW.Registries.<kindId>` exists |

Anything prefixed with `_` is internal (d.14).

## Kinds

A kind is a file `lua/privatewar/kinds/<id>.lua` (d.16):

```lua
KIND.Folder    = "streaks"   -- scanned under lua/privatewar/
KIND.Global    = "STREAK"    -- class table name inside entity files
KIND.Required  = { Name = "string", Cost = "number" }  -- optional; field -> Lua type
KIND.Subscribe = "never"     -- optional; "always" or "never" (see "Auto-subscription")
```

- Required fields of `KIND`: `Folder` (string), `Global` (string).
- `kinds` and `modules` are reserved ids; a kind file with either id is rejected.
- Fields added by later tasks (`Subscribe`, ...) are documented in this file when they land.

## Built-in kind `modes`

`lua/privatewar/kinds/modes.lua` (T-1.5, `design/02-modes.md` d.7): folder `modes/`, class table `MODE`,
`Subscribe = "never"` (the active mode is dispatched through `PW.ActiveMode`, d.18), required fields
`Name` (string) and `Teams` (number). Accessor `PW.Modes`. It is a kind file, not a core-reserved kind. Modes may
declare `Settings` and `SettingDefaults` and get `self:Setting(key)` (see "Settings").

## Built-in kind `weapons`

`lua/privatewar/kinds/weapons.lua` (T-1.17, `design/04-weapons.md` d.3): folder `weapons/`, class table `WEAPON`,
`Subscribe = "never"` (a weapon entry is data), no `Required` fields: a soft registration may carry only some
fields and other sources fill the rest. Id = the SWEP class. Accessor `PW.Weapons`. Enable ConVar
`pw_weapon_<class>_enabled` (token `weapon`, see "Enable ConVars"). Entries come from files in
`lua/privatewar/weapons/` and from `PW_RegisterWeapons` listeners (see "Weapon registration phase"). Types:
`lua/privatewar/types/weapons.lua`.

`PW.Weapon` fields (all optional, besides the fields every entity has):

| Field | Type | Meaning |
| --- | --- | --- |
| `Category` | `string?` | Weapon category, for example `"ar"` or `"smg"` |
| `Name` | `string?` | Display name |
| `Unlock` | `integer?` | Unlock level, read by progression (`design/06-progression.md`); empty means its default |

## Weapon registration phase

Source: `gamemodes/privatewar/gamemode/core/sh_weapon_phase.lua` (shared, T-1.17), `design/04-weapons.md` d.3,
`design/01-extensibility.md` d.16 step 7, d.12. SWEPs load after the gamemode, so weapons are registered in a phase
of their own.

- The phase runs on both realms (server and every client), each on its own: first in `InitPostEntity` of that realm
  (once per map), then again after every `PW.Loader.Boot` once `InitPostEntity` has passed (`pw_reload`, auto
  refresh: the reload builds a new weapons registry holding only the declared files). A `Boot` before
  `InitPostEntity` (gamemode load) does not run it.
- One run: `PW.Notify("PW_RegisterWeapons", reg)`, then `PW.Notify("PW_WeaponsLoaded")`. `reg` is the weapons
  registry: `reg.Register(tbl, class)`, or `reg.Register(tbl, class, { soft = true })` to fill only the missing
  fields of an existing entry (see "Registry").
- The `PW_RegisterWeapons` dispatch runs in `pcall`: an error in a listener is logged
  (`weapon phase (<realm>, <reason>): a PW_RegisterWeapons listener failed: <error>`) and `PW_WeaponsLoaded` still
  fires. Because the whole dispatch is in one `pcall`, listeners after the failing one do not run in that phase.
- Without a declared `weapons` kind nothing fires; one log line.
- Listeners must tolerate repeats (one run per map plus one per reload). Consumers (loadout, bots, HUD) wait for
  `PW_WeaponsLoaded` and read the registry again on every `PW_WeaponsLoaded`: a reload replaces it.
- `weapon_fists` is the Lua SWEP the tests use to prove that SWEPs exist at the phase (it ships with every GMod
  install). HL2 weapons (`weapon_crowbar`, `weapon_physgun`) are engine weapons and never appear in
  `weapons.GetStored` or `weapons.GetList`.
- Internal: `PW.WeaponPhase._Run`, `_OnInitPostEntity`, `_OnBoot`, `_NewStore` and the state `PW._WeaponPhase`
  (`ready`, `runs`, `first`, `last`; a run records its `reason`, `"InitPostEntity"` or `"reload"`, and `sweps`, the
  size of `weapons.GetList()` when it started).

## Entity files

- Single file `<kind folder>/<id>.lua` (shared), or folder `<id>/` with `shared.lua`, `init.lua` (server), `cl_init.lua` (client).
- Ids: lowercase letters, digits and `_`. A file and a folder with the same id: the folder wins, one log line.
- The loader sets the kind's global class table to a fresh table, runs the files, restores the previous global value.
- A syntax or runtime error: one log line, the entity is skipped, loading continues. A missing or mistyped required
  field is checked later, by the registry (see "Required fields").
- Methods are defined SWEP-style on the shared class table (`function MODULE:PW_PhaseChanged(...)`), also when an
  entity is split over `shared.lua`, `init.lua` and `cl_init.lua`. Type checking of such files: see `.luarc.json`.

## Fields every entity has

| Field | Type | Meaning |
| --- | --- | --- |
| `ClassName` | string | Id (file or folder name) |
| `Base` | string? | Id of the entity it inherits from (same kind) |
| `BaseClass` | `PW.Entity?` | Resolved base, set by the registry |
| `Abstract` | boolean? | Usable as a base only; absent from `GetList`; never inherited |

## Registry

`PW.Registry.New(kind, opts?) -> PW.Registry`; `opts.log(message)`, `opts.preRegister(kind, id, tbl)` are injectable for tests.
`opts.subscribe` (`PW.SubscribeMode`, `"always"` or `"never"`, default `"never"`) sets auto-subscription; an
unknown value logs one line and falls back to `"never"`. `opts.methods` (`table<string, function>`) is copied onto
every resolved entity that has no field of that name (the loader gives `modes` and `modules` `Setting`).

| Function | Contract |
| --- | --- |
| `Register(tbl, id, opts?) -> boolean` | Fires `PW_PreRegister` first; `false` from it or invalid arguments → returns `false`. Re-registering an id replaces it (d.12). `opts.soft = true` fills only missing fields of an existing entry, nested tables merged per key, never overwrites (`04` d.3). After the main load, a registration (also a soft one) re-resolves at once only the registered id and the entities whose stored `Base` chain includes it; every other resolved table stays the same and valid |
| `Get(id) -> PW.Entity?` | Resolved entity (base fields, then own fields), `nil` if unknown, unresolved or failing the required-field check (see "Required fields") |
| `GetStored(id) -> table?` | The table as registered, without `Base` applied |
| `GetList() -> PW.Entity[]` | Resolved non-abstract entities that passed the required-field check, sorted by id |
| `GetEnabledList() -> PW.Entity[]` | `GetList()` without disabled entities (by an enable ConVar or after an error), sorted by id. Use it for anything shown or picked in a match (mode vote, loadout, HUD, bots) |
| `ResolveAll()` | Resolves `Base` for every entry. Missing base, failed base and cycles: one log line, the entity is unresolved (`Get` returns `nil`) |

## Required fields

Source: `sh_registry.lua`, `sh_loader.lua`, `design/01-extensibility.md` d.15.

- `KIND.Required` (passed to the registry as `PW.RegistryOptions.required`, `table<string, type>`: field name to Lua
  type name) is checked by the registry on the resolved entity, after `Base` resolution: a field inherited from the
  `Base` chain counts. Late registrations are checked too, at the moment they re-resolve.
- `PW.Registry.ValidateRequired(tbl, required?) -> ok, err?`: pure, fields checked in name order. `err` is
  `missing required field <name> (<type>)` or `field <name> must be <type>, got <type>`.
- An entity that fails is absent from `Get`, `GetList`, `GetEnabledList` and the subscriptions, and the registry logs
  one line `<kind> "<id>": missing required field <name> (<type>)` (or the type message), without a file path. The
  line is logged once per registered table and reason. The stored table still exists (`GetStored`) and the entity
  can still serve as a `Base` of other entities.
- Abstract entities (`Abstract = true`) are not checked. `Abstract` is never inherited, so a non-abstract entity whose
  `Base` is abstract is checked with the fields it inherited.

## Loader

| Function | Contract |
| --- | --- |
| `PW.Loader.ParseListing(files, dirs) -> entries, errors` | Pure: form detection from a directory listing |
| `PW.Loader.ValidateRequired(tbl, required?) -> ok, err?` | The same function as `PW.Registry.ValidateRequired` (see "Required fields"); the loader no longer checks the fields itself |
| `PW.Loader.AccessorName(kindId) -> string` | Pure: `snake_case` → `PascalCase` |
| `PW.Loader.LoadRoot(root, opts?) -> PW.LoadContext` | Loads a tree in d.16 order: `kinds/`, `modules/`, every declared kind folder, `Base` resolution |
| `PW.Loader.Boot()` | `LoadRoot("privatewar")`, releases the registries of an earlier `Boot` (their entities become invalid and lose their subscriptions), installs `PW.Registries` and accessors, applies the enable snapshot (server), creates the setting ConVars, fires `PW_RegistriesLoaded`, then re-runs the weapon registration phase if `InitPostEntity` has passed (see "Weapon registration phase") |

## Auto-subscription

Source: `sh_registry.lua`, `sh_loader.lua` (T-1.7), `design/01-extensibility.md` d.18.

- `KIND.Subscribe` is `"always"` or `"never"`. Omitted or unknown means `"never"`; an unknown value logs one line
  (`<kind>: Subscribe must be "always" or "never", got "<value>"; using "never"`) when the registry is created.
- The built-in `modules` kind is `"always"`; the built-in `kinds` kind is `"never"`. A future `modes` kind must
  declare `"never"`: the active mode is dispatched through `PW.ActiveMode`, never subscribed (d.18).
- In an `"always"` registry, every function field whose name starts with `PW_` (sorted) of a resolved, enabled,
  non-abstract entity is subscribed with `hook.Add(name, entity, fn)`; GMod passes the entity as `self`. Other
  names (engine hooks) are never subscribed; modules add those with `hook.Add` themselves.
- Subscriptions are made by `ResolveAll` and redone for every entity a late `Register` re-resolves.
  Engine hooks go through `PW.HookFor` (below).
- `entity:IsValid()` is set by the core on every resolved entity of every registry (an own `IsValid` is
  overwritten). It returns `false` once the entity is disabled, re-resolved (a late registration of its id or of
  an id in its `Base` chain, or another `ResolveAll`, makes a new table) or its registry released. GMod then drops the entity's `hook.Add`
  subscriptions; the registry also removes them at once.
- `Get(id)` still returns a disabled entity; check `IsValid()` before using it.
- The class table a file filled (`MODULE`, `MODE`, ...) gets its own `IsValid` when it is registered. It follows the
  resolved entity of the registered id: `true` while that entity is resolved, passed the required-field check, is
  enabled and its registry is not released, and the stored table is still this class table. A file can therefore pass
  its class table as owner (`PW.HookFor`, `PW.Net.Receive` `opts.owner`) or call `MODULE:IsValid()`. While a file
  runs, its class table has no `IsValid` yet (registration comes after the file).
- `PW.HookFor(entity, name, fn)`: records an engine hook on the class table (`entity._EngineHooks[name] = fn`, a later
  call with the same name replaces it). Pass the class table. The registry adds it with `hook.Add(name, entity, fn)`
  for the resolved entity, while it is enabled, and removes it when the entity is disabled, re-resolved (replaced)
  or its registry released; a re-enable adds it again. It works in every registry whatever its `Subscribe` value:
  `"never"` kinds get only the `PW.HookFor` hooks, `"always"` kinds get them besides their `PW_*` methods (a
  `PW_*` method and a `PW.HookFor` hook of the same name: the hook wins). `fn` receives the entity as `self`.
  `hook.Add` itself is never wrapped. Abstract entities get no hooks.

Internal (d.14), listed so other lanes do not depend on them:

| Name | Meaning |
| --- | --- |
| `registry._Disable(id, reason)` | Disables an entity until `_Enable`: `IsValid` false, subscriptions removed, live instances of that exact resolved definition removed, then `PW_EntityDisabled` notified once for the enabled-to-disabled transition. Survives re-registration and resolution. Used by enable ConVars (T-1.4) and `PW.Call` |
| `registry._Enable(id)` | Clears a disable; the entity is subscribed again if its kind subscribes |
| `registry._DisabledReason(id) -> string?` | The reason given to `_Disable`, `nil` when enabled |
| `registry._Release(keep?)` | Removes every subscription and invalidates every entity of the registry (it is replaced), except the ids in `keep` (`{ [id] = true }`), which stay valid |
| `registry._Released() -> boolean` | Whether `_Release` ran |
| `PW.Registry._HookMethods(tbl) -> string[]` | Names of the `PW_*` functions of a table, sorted |
| `entity._Registry` | The registry that resolved the entity |

### Disable cleanup notification

`PW_EntityDisabled(kind: string, id: string, definition: table, reason: string)` is a synchronous notification
on the realm applying the disable, not a network message. The definition is the exact resolved registry table,
not its stored class table. It fires only for an actual enabled-to-disabled transition of a valid definition;
repeating `_Disable` does not notify again. `_Enable` allows a later disable to notify again.

Before dispatch the definition is disabled, its ordinary subscriptions are removed, and the core has removed
every live instance whose own `_Definition` is that exact table. Identity is not inferred from `ClassName`:
another registry's same id, another definition, and unrelated instances are untouched.

An owner module may use a stable `hook.Add` identifier independent of its auto-subscription for cleanup only:
revoke its owned caches, effects and replication when it or its content is disabled. A disabled module's ordinary
`PW_*` methods cannot perform this cleanup because they have already been unsubscribed. Cleanup listeners must
not perform gameplay, regrant effects, spawn content, return a value or throw an error. Standard GMod dispatch
still applies: a returned value skips later listeners, and an error aborts dispatch. There is no global hook
transaction or rollback; either misuse cannot undo the already completed core invalidation/instance cleanup.
Replacement, re-resolution and registry release are not disable notifications; kept active definitions remain valid.
This is an additive API 1 hook; `PW.API` remains unchanged.

## Enable ConVars

Source: `sv_enable.lua` (server: ConVars, snapshot, publishing), `sh_enable.lua` (shared), `cl_enable.lua` (client),
all in `gamemodes/privatewar/gamemode/core/`; T-1.4 and wave 0; `design/01-extensibility.md` d.11, d.16.

- Every listed entity (resolved, non-abstract) of every registry gets a server ConVar
  `pw_<token>_<id>_enabled`: default `1`, `FCVAR_ARCHIVE`, range 0..1. `token` is the kind's class table name in
  lowercase: `modes` → `pw_mode_kc_enabled`, `modules` → `pw_module_<id>_enabled`, the built-in `kinds` →
  `pw_kind_<id>_enabled`; a registry whose kind has no declaration with a string `Global` uses its kind id.
  Abstract entities get no ConVar.
- ConVars are created at `Boot`, at every new match, and at once for a late registration. A missing ConVar
  counts as enabled.
- The snapshot (which ids are disabled, per kind) is taken at the first `Boot` and on every entry into `PREMATCH`
  from another phase (`LOBBY` or `VOTE`), before the settings snapshot and before `PW_PhaseChange`. Changes
  during a match take effect at the next match.
- The snapshot is applied through `registry._Disable` / `_Enable`: a disabled entity leaves `GetEnabledList`,
  becomes invalid and loses its `PW_*` subscriptions. Entities disabled after an error (`PW.Call`) keep their
  reason and are never re-enabled by their ConVar.
- A reload (`PW.Loader.Boot` again: the core command `pw_reload` or auto refresh, see "Hot reload") re-applies
  the current snapshot to the new registries; it does not read the ConVars again. A late registration gets its ConVar but the snapshot is not
  applied to it until the next match (an id disabled earlier stays disabled, the disable is kept per id).
- `PW.Match.Start` does not check the mode's flag: a mode disabled by the snapshot taken when its match enters
  `PREMATCH` is invalid for that match (`PW.Call` skips it). Pick modes from `PW.Modes.GetEnabledList()`.
- The snapshot reaches clients as one NW2 global bool per disabled entity, `pw_off:<kind id>:<id>` (`true` while the
  entity is disabled by the snapshot; `PW.Enable._Key`). The server writes only the changes, from server
  `InitPostEntity` on (like the phase globals), and a new match writes its snapshot before it publishes `PREMATCH`.
  The values are there before the client's `InitPostEntity`, so a disabled screen does not flash.
- The client reads those values (`PW.Enable._ReadSnapshot`) and applies them with `_Apply` to its own registries:
  `PW.Enable._Sync()` runs on every client `Boot` and before every `PW_PhaseChanged`. A module disabled for the match
  is disabled on the client too: its `PW_*` methods and `PW.HookFor` hooks stop, `IsValid` is `false`, and the client
  `GetEnabledList` matches the server's. Entities disabled after an error keep their own reason on each side
  (errors are not replicated).
- `PW.Enable.ConVarName(kind, id) -> string?` (server, T-1.19): the enable ConVar name of entity `id` in registry
  `kind`, `pw_<token>_<id>_enabled`; `nil` for an unknown kind. The id is not checked: an unknown id in a known kind
  still gets a name (whose ConVar may not exist).
- Internal: every other `PW.Enable._*` name and the state `PW._Enable`. Shared: `_Reason`, `_Key`, `_Writes`,
  `_ReadSnapshot`, `_Apply`. Server: `_KindToken`, `_ConVarName`, `_TakeSnapshot`, `_NewStore`, `_EnsureConVars`,
  `_NewMatch`, `_Publish`, `_OnBoot`, `_OnRegistered`. Client: `_Sync`, `_OnBoot`, `_OnRegistered` (does nothing).

## Settings

Source: `sh_settings.lua` (pure schema), `sh_settings_store.lua` (store, getters, ConVars), `sv_settings.lua`
(snapshot, net), T-1.5, `design/01-extensibility.md` d.17. Types: `lua/privatewar/types/settings.lua`.

### Declaring

Modes and modules declare `Settings = { <key> = <declaration> }`. Keys use lowercase letters, digits and `_`. The
full id is `<owner ClassName>.<key>`, for example `kc.score_limit`.

| Field | Meaning |
| --- | --- |
| `type` | `"int"`, `"float"`, `"bool"`, `"enum"` or `"set"` (required) |
| `scope` | `"match"` (default), `"server"` or `"client"`. A mode's settings must be `"match"` |
| `default` | Required; must be a valid value and inside `min`/`max` |
| `min`, `max` | `int` and `float` only; finite numbers, `min <= max` |
| `options` | Non-empty list of non-empty strings; required for `enum`, optional for `set`. Or a function returning such a list (dynamic options, T-11.9): it is called at declaration, at every validation and at every form build; a failing call keeps the last good list, and a declaration whose first call fails is skipped |
| `label` | Display text; defaults to the key |
| `description` | Optional text: what the setting changes or trades. A non-string description rejects the declaration. The SETTINGS screen lists `<label>: <description>` in its info column (`PW.UI.Settings.Notes`) |

- An invalid declaration is skipped with one log line (`setting <owner>.<key> skipped: <reason>`); the other keys
  of the owner still work.
- Inheritance: the `Settings` of every entity in the `Base` chain are merged root first, per field, so a child
  may re-declare an inherited key partially (`score_limit = { default = 65 }`). This holds for modes and modules.
- `SettingDefaults = { [fullId] = value }` on a mode (merged along its `Base` chain) overrides the default of a
  module's `match` setting for matches of that mode. An invalid value is ignored with one log line. It does not
  apply to the mode's own settings.
- A mode setting and a module setting with the same full id: the module's is used, one log line.

### Values and validation

| Type | Accepted value | Rules |
| --- | --- | --- |
| `int` | finite number | Rounded to the nearest integer (`floor(x + 0.5)`), then clamped to `min`/`max` |
| `float` | finite number | Clamped to `min`/`max` |
| `bool` | boolean | Strict; text form `1`, `0`, `true`, `false` (case-insensitive) |
| `enum` | string | Must be one of `options` |
| `set` | list of ids or lookup `{ [id] = true }` | Stored as a lookup; members are non-empty strings without commas; with `options`, every member must be one of them |

- A wrong type, an unknown enum option or a bad set member rejects the whole value. Clamping accepts the value
  with the note `clamped`.
- Text form (ConVars and net messages): numbers as text, `bool` as `1`/`0`, `set` as a comma-separated list of
  ids (sorted when written; spaces and empty parts are dropped when read). Hence the comma restriction.

### Reading

- `PW.Setting(fullId) -> any`: a `match` setting comes from the current match snapshot; outside a match (or for
  an id not in it) from the host's pending value, else the default (with the active mode's `SettingDefaults`). A
  `server` or `client` setting comes from its ConVar, the default if the ConVar is missing or unparsable. Tables
  are returned as copies. An unknown id returns `nil` and logs once.
- `self:Setting(key)` on modes and modules is `PW.Setting(self.ClassName .. "." .. key)` (from
  `PW.Settings.EntityMethods`, put on every resolved entity of these two kinds that has no own `Setting`).

### Changing and listing

| Name | Contract |
| --- | --- |
| `PW.Settings.Set(fullId, value) -> ok, note?` | Validates and stores. On the server: `match` → the host's pending value for the next match (the current snapshot does not change), `server` → its ConVar. On the client: only `client` settings (its ConVar). Otherwise `false` and a reason; on success the note is `"clamped"` or `nil`. No privilege or phase check: callers check |
| `PW.Settings.GetGroups(scope, mode?) -> PW.SettingGroup[]` | Form data for one scope: for `match`, the group of `mode` (if given) first, then one group per enabled module with fields of that scope. Each group is `{ owner, ownerKind, fields }`, fields sorted by key, each `{ def, value }`; `match` values are pending or default for `mode`, others the current values |
| `PW.Settings.Format(defOrFullId, value) -> string?` | The text form of `value` (see "Values and validation") for a definition or a full id. `nil` for an unknown full id. The value is not validated: pass a validated value (T-1.19) |
| `PW.Settings.Privilege` | `"pw.settings.change"`, default `superadmin`, declared by the core |
| `PW.Settings.EntityMethods` | `{ Setting = fn }`, the methods the loader gives modes and modules |

### Match snapshot

- Taken on every entry into `PREMATCH` from another phase, right after the enable snapshot: every `match`
  setting of the match's mode and of the enabled modules, from the host's pending values (validated again), else
  the default for that mode. Fixed for the whole match; reset when the phase enters `LOBBY`.
- The pending values are not cleared when a match starts or ends; they stay the host's choice for later matches
  on this map.
- `pending_match.json` `settings` now carries the would-be snapshot for the target mode. On the new map it
  replaces the pending values (entries that are unknown, not `match`, or invalid are dropped with one log line
  each) before the match starts and takes the snapshot again.

### Net messages and ConVars

| Message | Phases | Privilege | Rate | maxLen |
| --- | --- | --- | --- | --- |
| `pw_settings_match` | `LOBBY` only | `pw.settings.change` | 10 per s | 1024 bytes |
| `pw_settings_server` | any | `pw.settings.change` | 10 per s | 1024 bytes |

- Payload: `net.WriteString(fullId)`, `net.WriteString(value in text form)`. The setting must have the message's
  scope. Each accepted change logs `setting <id> set to <value> by <nick>`; a rejected one logs one line.
- ConVar of a `server` setting: `pw_<owner>_<key>`, created at `Boot`, `FCVAR_ARCHIVE` + `FCVAR_REPLICATED` on the
  server (replicated to clients), with `min`/`max`. A `client` setting: an archived client ConVar
  `pw_<owner>_<key>` on the client only. `match` settings have no ConVar.

### Known limits

- No client replication of the match snapshot or the pending values: on the client, `PW.Setting` returns defaults
  for `match` settings.
- A `server` or `client` setting of an entity registered after `Boot` has no ConVar until the next `Boot`
  (the core command `pw_reload`); until then it reads its default and `Set` fails.
- Collisions are not detected: a mode and a module with the same id share full ids; `pw_<owner>_<key>` can
  collide between owners (`a_b` + `c` and `a` + `b_c`) and with enable ConVar names.
- Internal: every `PW.Settings._*` name, the state `PW._Settings`.

## Hot reload

Source: `sh_reload.lua` (shared), `sv_reload.lua` (server), `sh_loader.lua`, `sv_match.lua`, T-1.15,
`design/01-extensibility.md` d.12. Types: `lua/privatewar/types/reload.lua`.

- Every `PW.Loader.Boot` is a full rescan: every kind folder is scanned again, new files are found, a changed file
  replaces its entry, `Base` is resolved, the enable snapshot is re-applied, setting ConVars are created and
  `PW_RegistriesLoaded` fires.
- `PW.Reload.Run(reason) -> boolean`: runs `PW.Loader.Boot` in `pcall` on this realm and logs one line,
  `reloaded (<server|client>, <reason>): <kind> <count>, ...` (listed entities per kind, sorted by kind id) or
  `reload (<realm>, <reason>) failed: <error>`.
- Console command `pw_reload` (server, core): privilege `pw.reload` (`PW.Reload.Privilege`, default
  `superadmin`); the server console is always allowed; a player without the privilege is refused with one log line
  (`pw_reload denied for <nick>`). It reloads the server (`reason` `pw_reload by <nick | the server console>`) and,
  only if that worked, sends the server → client net message `pw_reload` (no payload) to every client one tick
  later (`timer.Simple(0)`), so new files are downloadable before clients reload. Each client then runs
  `PW.Reload.Run("pw_reload from the server")`.
- `GM:OnReloaded` (auto refresh) runs `PW.Reload.Run("auto refresh")` on each realm on its own and sends nothing
  to clients. Auto refresh of a gamemode file also re-runs `shared.lua`, which boots once more.
- A reload does not touch the running match: `PW.ActiveMode` stays valid (its old registry keeps that id), and the
  enable and settings snapshots are kept. The next match (`Start` or a rotation) uses the reloaded definition of
  the mode; if the mode no longer exists, `Start` logs `match start ignored: mode <id> is no longer registered
  (reloaded)` and returns `false`, and a rotation aborts to `LOBBY` with that reason.
- Every other entity of the old registries turns invalid at once: modules are replaced immediately (old ones lose
  their subscriptions, new ones are subscribed). A reload also clears disables after an error (new registries); the
  enable snapshot is re-applied. Existing instances keep their old definition tables.
- Limitation: clients run only files the server sent with `AddCSLuaFile`. Verified on the listen server host;
  remote clients may get new or changed files only after they reconnect (or through the engine's own auto
  refresh).
- Internal: `PW.Loader._Rescan(previous, opts?)`, `PW.Loader._KeepFor(previous, active)`, `PW.Loader._EngineFs`,
  the loader option `fs` (`PW.LoaderFs`: `find`, `exists`, `run`, `send`; also on `PW.LoadContext`),
  `registry._Release(keep)`, `registry._Released()`, `PW.Match._Definition(mode, registries)`,
  `PW.Reload._Summary`, `_Command`, `_NewStore` and the state `PW._Reload`.

## Hook dispatch

Source: `gamemodes/privatewar/gamemode/core/sh_hooks.lua` (shared), `design/01-extensibility.md` d.9, d.18. Every
`PW_*` hook is a question or a notification; both use the same dispatch, `hook.Call(name, PW.ActiveMode, ...)`:
`hook.Add` listeners first (order undefined), then the active mode's method with the hook's name, as the default.

| Name | Contract |
| --- | --- |
| `PW.ActiveMode` | The active mode table or `nil`. Assigning it switches the mode: the next dispatch calls the new table's methods, the old mode is no longer called. The mode is never subscribed with `hook.Add` (d.18). Assigning does nothing else (no start or cleanup call) |
| `PW.Ask(name, ...) -> ...` | Question hook. Same as `hook.Call(name, PW.ActiveMode, ...)` and returns its values: the first non-nil listener answer, otherwise the mode method's answer, otherwise nothing |
| `PW.Notify(name, ...)` | Notification hook. Same dispatch, returns nothing. Listeners must not return a value: it skips the remaining listeners and the mode's method. With `pw_debug 1`, a non-nil first return value produces one log line naming the hook. This includes a value returned by the mode's own method; the two cannot be told apart without replacing `hook.Call` |

- ConVar `pw_debug`: default `0`, range 0..1, flags `FCVAR_ARCHIVE` and `FCVAR_REPLICATED`. Read on every
  `PW.Notify`.
- Log lines go through `print("[PW] " .. message)`.
- `PW._Hooks` (the logger, injectable in tests) is internal (d.14).

## Entity calls

Source: `gamemodes/privatewar/gamemode/core/sh_call.lua` (shared, T-1.8), `design/00-core.md` d.6,
`design/01-extensibility.md` d.15. The core and modules call entity methods only through `PW.Call`.

`PW.Call(entity, method, ...) -> ...`:

1. Returns nothing without calling when `entity[method]` is not a function, when the entity failed earlier without
   a registry, or when `entity.IsValid` is a function and returns `false`.
2. Otherwise runs `pcall(entity[method], entity, ...)` and returns the method's results.
3. On error it returns nothing and:
   - for an entity that is not `PW.ActiveMode`: logs one line
     `<kind> "<id>": <method> failed, disabled until map change: <error>` and calls
     `registry._Disable(id, "error in <method>: <error>")` on `entity._Registry`. An entity without a registry
     (`kind` and `id` are then `?` when unknown) is remembered as failed and never called again;
   - for `PW.ActiveMode` (checked first, even if the mode has a registry): the mode is not disabled. It logs one
     line `mode <id> failed: <error>` and, if `PW.Match.Abort` exists, calls `PW.Match.Abort` with that same text.
     An error inside `Abort` is not caught.
4. "Until map change": the disable lives in the registry, which the next boot creates anew (a map change, or a
   reload: see "Hot reload").

On the server `PW.Match.Abort` is the phase machine's abort (see "Phases and match"). On the client `PW.Match`
is absent, so only the log line remains. The registry used here is the entity's own (raw) `_Registry` field: an
instance (see "Instances") inherits `_Registry` from its definition but is never disabled through it; its kind and
id in the log line and the profile key are still the definition's.

Profiling:

- ConVar `pw_profile`: default `0`, range 0..1, flag `FCVAR_REPLICATED`. Read on every call that reaches the
  method.
- With `pw_profile 1`, every call that reaches the method (including one that errors) adds its `SysTime()`
  duration to the entry `"<kind>:<id>"` (`kind` from `entity._Registry.Kind`, `?` without a registry; `id` from
  `ClassName`, `?` without one).
- `PW.Profile.Get() -> table<string, PW.ProfileEntry>`: a copy of the timings; `PW.ProfileEntry` is
  `{ time: number (seconds), calls: integer }`.
- `PW.Profile.Reset()`: forgets every timing.

`PW._Call` (logger, failed set, timings; injectable in tests) is internal (d.14).

## Instances

Source: `gamemodes/privatewar/gamemode/core/sh_instance.lua` (shared, T-1.9), `design/00-core.md` d.11. Per-owner
state of a definition (perk, streak, equipment) with hooks and timers that end with the instance.

| Function | Contract |
| --- | --- |
| `PW.Instance(def, owner) -> PW.Instance` | A new table whose missing fields are read from `def` (`__index`), with `IsValid`, `Hook`, `Timer`, `Remove` set on it (they shadow fields of `def`). Calls `PW.Call(instance, "OnEquip", owner)` and returns the instance |
| `instance:IsValid() -> boolean` | `false` once removal starts, one of its calls through `PW.Call` errored, or its source definition has an `IsValid` function returning false. Plain non-registry definitions without `IsValid` still work |
| `instance:Hook(name, fn)` | `hook.Add(name, instance, ...)`: on the hook, `fn(instance, ...)` runs through `PW.Call` and its results are returned (it may answer a question hook). One callback per hook name; a second `Hook` with the same name replaces it. Ignored on an invalid instance |
| `instance:Timer(delay, reps, fn)` | `timer.Create` with a unique name (`PW.Instance.<n>`); `fn(instance)` runs through `PW.Call`. `reps` as in `timer.Create` (0 = forever). Ignored on an invalid instance |
| `instance:Remove()` | Runs once: blocks gameplay, runs `OnUnequip(owner)` through a protected cleanup-only call even if the instance failed or its definition is disabled, then removes all owned hooks, timers and the live entry. Reentrant calls do nothing |

- Errors: an error in `OnEquip`, a hook callback or a timer callback makes the instance invalid (`PW.Call` keeps
  it in its failed set; the definition is not disabled). After a failed hook or timer callback the instance is
  removed at once. Removal still calls `OnUnequip` exactly once; this cleanup-only exception does not resume
  ordinary `PW.Call` gameplay. An `OnUnequip` error is logged with the definition id and method, never rethrown,
  never disables the definition, and cannot skip core hook/timer/live-entry cleanup.
- An error in `OnEquip` does not remove the instance at once: it stays invalid (no hooks or timers can be added)
  until `Remove()` or the end of the match.
- Cleanup on the server: the core removes every live instance on `PW_MatchEnd` (listener `"PW.Instance"`).
- Cleanup on the client (`PW_MatchEnd` is server only): the core removes every live client instance when the
  networked phase leaves `LIVE`, before `PW_PhaseChanged` fires (see "Phase networking").
- Disabling the definition (`registry._Disable`) synchronously removes existing instances of that exact resolved
  table before `PW_EntityDisabled`. Re-enabling does not revive removed instances. An existing instance keeps
  reading its original table across replacement/re-resolution/release, but gameplay checks that source's validity;
  a kept active definition remains valid. This does not introduce eager instance cleanup on replacement/release.
- `PW._Instances` (live set, timer counter), `instance._Definition` (own source-table reference),
  `PW._EndInstances()` (removes every live instance), and `PW._EndDefinitionInstances(definition)` (removes only
  live instances with that exact source reference) are internal (d.14). The registry calls the latter only when
  the instance core has loaded.

## Phases and match

Source: `gamemodes/privatewar/gamemode/core/sh_phase.lua` (shared rules), `sv_match.lua` (server machine, T-1.12),
`design/00-core.md` d.1–d.5.

### `PW.Phase` (shared)

- `PW.Phase.Names`: `{ "LOBBY", "PREMATCH", "LIVE", "POSTMATCH", "VOTE" }` (`PW.PhaseName`).
- `PW.Phase.Transitions[from][to] = true` for every allowed pair:

  | From | To |
  | --- | --- |
  | `LOBBY` | `PREMATCH` |
  | `PREMATCH` | `PREMATCH` (starts the countdown), `LIVE`, `LOBBY` |
  | `LIVE` | `POSTMATCH`, `LOBBY` |
  | `POSTMATCH` | `VOTE`, `LOBBY` |
  | `VOTE` | `PREMATCH`, `LOBBY` |

- `PW.Phase.CanTransition(from, to) -> boolean`: whether the pair is listed. Every `-> LOBBY` except POSTMATCH's
  timer is the host abort.
- The countdown is a `PREMATCH -> PREMATCH` transition with a new end time (`pw_countdown`). It starts when every
  non-bot player is ready or the PREMATCH timeout expires; when it expires, the phase becomes `LIVE` (no end time).
- `PW.Phase.GetPhase()`, `GetEnd()`, `Remaining(now?)`: the networked phase, both realms (see "Phase
  networking").
- Internal: every `PW.Phase._*` name (`_Next`, `_AllReady`, `_AfterMatch`, `_Keys`, `_GetSeq`, `_Remaining`,
  `_EndsInstances`, `_Apply`).

### `PW.Match` (server only)

| Function | Contract |
| --- | --- |
| `Start(mode, map?) -> boolean` | Only in `LOBBY` and outside a phase change, with a table that has a string `ClassName` and a `map` that is `nil` or a string; otherwise one log line and `false`. Clears the abort reason. If the mode has a `_Registry`, its current table is taken from `registry.Get(ClassName)`. While a map change is running: one log line and `false`. With no map or the current map: enters `PREMATCH` for `pw_prematch_timeout` seconds. With another map: writes the pending file, then runs `changelevel` and returns `true`; the phase stays `LOBBY` (see "Map change"); `false` with one log line if the file could not be written |
| `Finish(result?) -> boolean` | Called by the mode when the match is over: `LIVE -> POSTMATCH` for `pw_postmatch_time` seconds; `result` is passed to `PW_MatchEnd`. Outside `LIVE` the transition is rejected (one log line, `false`). During a phase change (for example from `MODE:Start`) it is queued, runs right after it, and returns `true` |
| `EndVote() -> boolean` | Ends `VOTE` now, with the same step as the `VOTE` timer: asks `PW_NextMatch` (see "Hooks") and starts the answer in `PREMATCH` for `pw_prematch_timeout` seconds, or changes the map ("Map change"). Used by the vote module for an early end (every human voted) and for the host's pick. Returns `false` outside `VOTE`, without a mode, and while `VOTE` has no timer (the map change below is already running). During a phase change it is queued like `Finish` and returns `true`. Without a valid answer the same mode repeats |
| `Abort(reason) -> boolean` | Stores `tostring(reason)` as the abort reason and logs `match aborted: <reason>` (always, also in `LOBBY`), then goes to `LOBBY`. In `LOBBY` returns `false`. Queued like `Finish` during a phase change |
| `SetReady(ply, ready?)` | Marks a player ready (`ready ~= false`) or not ready. The ready set is cleared on entering `LOBBY`. On entering a new `PREMATCH` it is refilled with every player already loaded on this map (`pw_client_ready` received, see "Map change"); a player who loads later becomes ready at once. A disconnecting player leaves both sets |
| `GetPhase() -> PW.PhaseName` | Current phase of the machine (server state, not the NW2 global) |
| `GetPhaseEnd() -> number` | `CurTime()` at which the phase ends, `-1` if it has no end (`LOBBY`, `LIVE`) |
| `GetAbortReason() -> string?` | Reason of the last abort, kept until the next `Start` |

- Timer phases advance on the `Think` hook (listener `"PW.Match"`). During `LIVE` the core also calls
  `MODE:Think()` every tick through `PW.Call`.
- `PW.ActiveMode` is set on entering a new `PREMATCH` (from `LOBBY` or `VOTE`), after `PW_PhaseChange`; it stays
  set through `LIVE`, `POSTMATCH` and `VOTE`, and is cleared on entering `LOBBY`, after `PW_PhaseChange`.
- `MODE:Start()` runs on entering `LIVE`, `MODE:Cleanup()` on leaving it, both through `PW.Call`. A mode error
  aborts the match (see "Entity calls").
- After `POSTMATCH`: `pw_aftermatch lobby` goes to `LOBBY`; `rotation` goes to `VOTE` for `pw_vote_time` seconds,
  then a new `PREMATCH` (or earlier, through `PW.Match.EndVote`). The next match is the answer of the question hook
  `PW_NextMatch(mode)`, asked once at that step (`mode` is `PW.ActiveMode`): a table `{ mode = <mode entity>,
  map = <string?> }` (`PW.NextMatch`) with a `ClassName` string on `mode` and a string or `nil` map. The step then
  runs the same path as `PW.Match.Start` (the mode's current registry table, a map change when `map` is another map).
  Without an answer (no vote module, no session, an unregistered mode) the same mode repeats on this map; an answer of
  another shape is ignored with one log line (`PW_NextMatch answer ignored`) and the same mode repeats. The vote module
  (`modes.md` "Vote module") is the only answerer today.
- A rotation to another map (`VOTE` to `PREMATCH` with `map` other than the current one): the map change of "Map
  change" starts from `VOTE`. The phase stays `VOTE`, but its end time is set to `-1` (`GetPhaseEnd()`) so that the
  next tick does not start the next match again; `EndVote` is refused meanwhile. If the pending file could not be
  written the machine goes to `LOBBY` with `PW.Match.Abort("map change to <map> failed: the pending file could not
  be written")`. A mode that a reload removed is not started: one log line and the machine goes to `LOBBY`. While a
  map change is in progress the step refuses with one log line (`match start ignored: a map change is in progress`).
- Late registration during a match: other entities keep their tables (see "Registry"). Re-registering the active
  mode itself, or an entity in its `Base` chain, makes the old table invalid until the next match takes the new one
  (`Start`, or the next rotation). Meanwhile `PW.Call` skips the old table (`MODE:Think` and `MODE:Cleanup` do not
  run), while `PW.Ask` and `PW.Notify` still dispatch to it through `PW.ActiveMode`.
- Internal: `PW.Match._SetPhase` (the only function that changes the phase and writes the phase NW2 globals),
  `_Definition`, `_Publish`, `_SetLoaded`, `_Tick`, `_ReadSettings`, `_NewStore`, `_AbortCommand`, and the state `PW._Match`.

ConVars (server, `FCVAR_ARCHIVE`, read when the phase that needs them starts):

| ConVar | Default | Meaning |
| --- | --- | --- |
| `pw_prematch_timeout` | `60` | Seconds PREMATCH waits for players before the countdown (min 0) |
| `pw_countdown` | `10` | Countdown in seconds (min 0) |
| `pw_postmatch_time` | `15` | POSTMATCH duration in seconds (min 0) |
| `pw_vote_time` | `15` | VOTE duration in seconds (min 0) |
| `pw_aftermatch` | `lobby` | `lobby` or `rotation`; any other value means `lobby` |

Abort command: privilege `pw.match.abort` (default `superadmin`, declared by the core). Console command
`pw_abort [reason]`: from the server console always allowed; a player without the privilege is refused with one
log line (`pw_abort denied for <nick>`). The reason is the arguments joined by spaces, or
`aborted by <nick>` / `aborted by the server console` when empty.

## Map change

Source: `gamemodes/privatewar/gamemode/core/sv_mapchange.lua` (server), `cl_ready.lua` (client), T-1.14,
`design/00-core.md` d.9. Types: `lua/privatewar/types/mapchange.lua`.

- `PW.MapChange.IsChanging() -> boolean`: `true` from the announcement (below) or the `changelevel` command until the
  new map (the Lua state resets) or the 10 s fallback. While it is `true`, `PW.Match.Start` refuses.
- Delayed change (T-11.10): `PW.Match.Start(mode, otherMap)` calls `PW.MapChange.Schedule(mode, map)`. With
  `pw_mapchange_delay` (archived, default 5, 0-60 s) above 0 it announces the change and begins it that many seconds
  later from the `Think` tick; with 0 it begins at once. The announcement is three NW2 globals, written map, mode, end
  time: `pw_mapchange_map` (string), `pw_mapchange_mode` (mode id), `pw_mapchange_at` (`CurTime()` of the change, `-1`
  for none); both realms read them with `PW.Phase.GetMapChange() -> map, mode, at` (keys in `PW.Phase._ChangeKeys`).
  Clients show the map change popup and the START button countdown (`ui.md`, "Match flow in the lobby"). Any phase
  change cancels a change that has not begun (`PW.MapChange._Cancel(reason)`, one log line, the globals cleared), for
  example `pw_abort` during a rotation in `VOTE`. A change whose pending file cannot be written when it begins clears
  the globals and, outside `LOBBY`, aborts to the lobby.
- Order when the change begins (`_Begin`): write `data/privatewar/pending_match.json` (`file.CreateDir`, then
  `file.Write`), check that it exists, set the guard, log `changing map to <map> for mode <id>`, then
  `RunConsoleCommand("changelevel", map)`. From `LOBBY`, `PW.ActiveMode` stays `nil`. From `VOTE` (rotation, see
  "Phases and match") the phase stays `VOTE` without a timer and `PW.ActiveMode` stays the old mode until the map
  reloads.

`pending_match.json` (JSON, `PW.PendingMatch`):

| Field | Type | Value today |
| --- | --- | --- |
| `v` | integer | `1` (format version) |
| `map` | string | Target map |
| `mode` | string | Mode id (`ClassName`) in the `modes` registry |
| `settings` | object | The would-be match settings snapshot for the target mode (see "Settings") |
| `bots` | integer | Bot target of the next match: `PW.BotsManager.PendingTarget(settings)` (the quota of the file's `bots.fill` for the humans connected now, one slot kept free, `bots-blackboard.md` item 10); the current `#player.GetBots()` when the bots manager is not loaded |
| `teams` | object | Team by SteamID64 string: the answer to the question hook `PW_PendingTeams(mode)` if it is a table, else `{}` |
| `createdAt` | integer | `os.time()` when written |
| `mapChangeCount` | integer | `game.GetMapChangeCount()` on the map that wrote the file |

On the new map, one tick after server `InitPostEntity` (`timer.Simple(0)`: `game.GetMapChangeCount()` grows only
from the first tick), the core reads the file and deletes it, then accepts it only if, checked in this order:

1. it decodes to a JSON object with a numeric `v` (else `corrupt`);
2. `v` is `1` (else `version`);
3. every field above has its type (else `corrupt`);
4. `map == game.GetMap()` (else `map`);
5. `game.GetMapChangeCount() == mapChangeCount + 1` (else `count`);
6. the age `os.time() - createdAt` is `>= 0` and `< 120` s (else `age`);
7. `PW.Registries.modes.Get(mode)` returns a mode (else `mode`).

A valid file starts the match on this map (`PW.Match.Start(mode)`, `PREMATCH`) and then fires
`PW_PendingMatchApplied`. A rejected file leaves the server in `LOBBY` with one log line (reason, file content and
this map's facts); a missing file logs nothing. `settings` is restored as the pending values before the match
starts; `teams` is handed to modules through `PW_PendingMatchApplied` (the teams module restores it); `bots` is read
by the bots manager from the same hook: it pins the bot target for `PREMATCH` (capped by the free slots) and brings
the bots to it.

Failed `changelevel`: if the server is still on the old map 10 s (`CurTime()`) after the command, the core clears
the guard, deletes the file, clears the announcement and calls `PW.Match.Abort("map change to <map> failed: still on <current> after 10 s")`.
From `LOBBY` the phase is already `LOBBY`, so this only stores the abort reason for the host and logs it; from a
rotation (`VOTE` without a timer) the abort also takes the machine to `LOBBY`.

Client ready handshake:

- Client: from client `InitPostEntity`, sends `pw_client_ready` (empty) at once and every 2 s until it receives
  `pw_client_ready_ack`. The Lua state resets on `changelevel`, so it runs again on every map.
- Server: `pw_client_ready` goes through `PW.Net.Receive` with `who = "any"`, every phase, `rate = 1`,
  `maxLen = 8`. The handler marks the player loaded and ready (`PW.Match._SetLoaded`) and answers
  `pw_client_ready_ack` to human players, for every message received.
- Bots never send it; `PREMATCH` ignores bots when it checks readiness.

Internal: every `PW.MapChange._*` name (`_Version`, `_MaxAge`, `_FailAfter`, `_Decide`, `_Validate`, `_Encode`,
`_Decode`, `_Begin`, `_Tick`, `_Apply`, `_OnClientReady`, `_NewStore`), the state `PW._MapChange` and
`PW.Match._SetLoaded`.

## Phase networking

Source: `sv_match.lua` (writer), `sh_phase.lua` (readers), `cl_phase.lua` (client hook), T-1.13,
`design/00-core.md` d.10. Clients compute timers locally; the server sends no countdown traffic.

- NW2 globals on the world entity:

  | Key | Type | Value |
  | --- | --- | --- |
  | `pw_phase_end` | float | `CurTime()` at which the phase ends, `-1` if none |
  | `pw_phase` | string | Phase name |
  | `pw_phase_seq` | int | Transition counter |

- Writer: only `PW.Match._SetPhase` (00 d.10 calls it `PW.SetPhase`; in the code it is `PW.Match._SetPhase`).
  Always in the order end → phase → seq, after the exit actions of the old phase and before the server
  `PW_PhaseChange`.
- Nothing is written before server `InitPostEntity`: there `PW.Match._Publish()` writes the current state once
  (the initial `LOBBY` with seq `0`, or a phase set while the map loaded) and enables the writes of later
  transitions.
- `seq` starts at `0` and grows by one per transition, including the `PREMATCH -> PREMATCH` countdown; a
  transition before `InitPostEntity` is counted too.
- Readers (shared): `PW.Phase.GetPhase() -> PW.PhaseName` (default `"LOBBY"`), `PW.Phase.GetEnd() -> number`
  (default `-1`), `PW.Phase.Remaining(now?) -> number?` (`nil` when the phase has no end, else
  `max(0, end - now)`, `now` defaults to `CurTime()`). They read the NW2 globals, also on the server, where they
  lag the machine until `_Publish`; server code reads `PW.Match.GetPhase()`.
- Client hook `PW_PhaseChanged(phase, endsAt, seq)`, see "Hooks".
- Internal: `PW._PhaseView` (the last phase and seq the client acted on), `PW._EndInstances`, `PW.Phase._*`,
  `PW.Match._Publish`.

## Client messages

Source: `gamemodes/privatewar/gamemode/core/sv_net.lua` (server only, T-1.11), `design/00-core.md` d.8. Every
client → server message goes through `PW.Net.Receive` (DESIGN.md global rule 4).

`PW.Net.Receive(name, opts, handler) -> boolean` registers `name` with `util.AddNetworkString` and `net.Receive`;
`handler(ply, len)` runs only after every check passes (`len` in bits, as `net.Receive` gives it). It returns `false`
with one log line (`PW.Net.Receive "<name>" rejected: <error>`) for invalid arguments. Re-registering a name replaces
its options and handler. Names are matched case-insensitively.

`PW.NetOptions` (every field required except `phases`):

| Field | Type | Meaning |
| --- | --- | --- |
| `who` | string | `"any"` or a privilege name (checked with `PW.Can`). Must be non-empty; whether the privilege is declared is not checked at registration |
| `phases` | `PW.PhaseName[]?` | Phases in which the message is accepted; omitted = every phase. An unknown phase name, or a non-table value, is a registration error |
| `rate` | number | Messages per second per player, above 0 |
| `maxLen` | number | Maximum payload in bytes, 0 or more (compared as `len > maxLen * 8` bits) |
| `owner` | table? | Any table, usually the file's class table (`MODULE`). While `owner:IsValid()` is false (the entity is disabled for the match, replaced or released) the message is dropped. A table without `IsValid` counts as not valid. A non-table value is a registration error |

Checks, in this order, all before the handler:

0. Owner: when `opts.owner` is set and `IsValid(owner)` is false, the message is dropped as `disabled`, before
   every other check; it takes no token. The handler never runs for a disabled module.
1. Privilege: `who == "any"` or `PW.Can(ply, who)`.
2. Phase: the server phase (`PW.Match.GetPhase()`) is in `phases`.
3. Rate: a token bucket per player per message, capacity `max(rate, 1)`, starting full, refilled at `rate`
   tokens per second (`SysTime()`); a message takes one token.
4. Length. An over-length message has already taken its token.

A message rejected as `disabled`, for privilege or for phase takes no token. A rejected message is dropped and logged as
`net <name> from <nick> dropped: <reason> (further drops from this player are not logged for 5s)`; `<reason>` is
`disabled`, `privilege`, `phase`, `rate` or `length`. Logging is throttled to one line per 5 seconds per player, across all
messages of that player. The handler runs without `pcall` or `PW.Call`; an error in it is a plain Lua error.

Bypass check: at server `InitPostEntity` the core looks once for entries of `net.Receivers` whose name starts with
`pw_` and that were not registered through `PW.Net.Receive`; with `pw_debug 1` at that moment it logs one line per
such name. Receivers added later, and names without the `pw_` prefix, are not checked. `net.Receive` itself is
never wrapped.

Internal: every `PW.Net._*` function (`_NewStore`, `_TakeToken`, `_Decide`, `_ShouldLog`, `_MakeDef`, `_Dispatch`,
`_FindBypass`, `_CheckBypass`) and the state `PW._Net`.

## Privileges

Source: `gamemodes/privatewar/gamemode/core/sh_privileges.lua` (shared), `design/00-core.md` d.7. Modules declare
privileges; the core declares none (`01` d.16). Usergroups (`PW.Usergroup`): `"user"`, `"admin"`, `"superadmin"`.

| Function | Contract |
| --- | --- |
| `PW.Privilege(name, defaultGroup) -> boolean` | Declares `name` with a default usergroup. An unknown group → `false` and one log line, nothing is stored. Re-declaring a name replaces the previous declaration (and registers it in CAMI again). If the `CAMI` global exists, calls `CAMI.RegisterPrivilege{ Name = name, MinAccess = defaultGroup }`. Returns `true` otherwise |
| `PW.Can(ply, name) -> boolean` | An undeclared privilege → `false` and one log line per call. Without CAMI: `"user"` → everyone, `"admin"` → `ply:IsAdmin()`, `"superadmin"` → `ply:IsSuperAdmin()`. With CAMI: registers the privilege in this CAMI table if not yet done, then calls `CAMI.PlayerHasAccess(ply, name)` synchronously, without a callback; only a returned `true` grants access, an error raised inside CAMI → `false` and one log line |

- The `CAMI` global is read on every call (`PW.Privilege` and `PW.Can`), so an admin mod loaded later is picked
  up: privileges declared before CAMI appeared are registered lazily on their first `PW.Can`.
- A declaration is registered in a given CAMI table once; a different CAMI table (another admin mod, a test stub)
  gets its own registration.
- Log lines go through `print("[PW] " .. message)`.
- `PW._Privileges` (declared privileges and the logger, injectable in tests) is internal (d.14).

## Base gamemode overrides

Source: `gamemodes/privatewar/gamemode/shared.lua`.

- `GM.TeamBased` stays `true` (teams belong to the teams module, `teams.md`).
- The base team chooser is suppressed: `GM:ShowTeam` is a no-op on both realms, so neither joining nor F2
  (`gm_showteam`) opens the base "Pick Team" menu. The lobby is the gamemode's own screen (`ui.md`).

## Hooks

Every hook is dispatched through `PW.Ask` (question) or `PW.Notify` (notification), so the active mode may define a
method with the hook's name as the default implementation, called after the listeners.

| Hook | Type | Arguments | Contract |
| --- | --- | --- | --- |
| `PW_PreRegister` | question, via `PW.Ask` | `kind: string, id: string, tbl: table` | Runs before every registration (file or programmatic, early or late), before `Base` resolution. Edit `tbl` in place to patch; return `false` to veto. Any other return value is ignored (d.10) |
| `PW_EntityDisabled` | notification, via `PW.Notify` | `kind: string, id: string, definition: table, reason: string` | Both realms, locally. Once per actual enabled-to-disabled transition, after invalidation, unsubscription and exact-definition live-instance cleanup. Cleanup-only stable listeners must not return, error, regrant or perform gameplay; see "Disable cleanup notification" |
| `PW_PhaseChange` | notification, via `PW.Notify` | `phase: PW.PhaseName, oldPhase: PW.PhaseName, endsAt: number` | Server. Fired on every transition (also the `PREMATCH -> PREMATCH` countdown), after the phase and its end time (`CurTime()` based, `-1` = none) are stored. Order: exit actions of the old phase (`MODE:Cleanup`, `PW_MatchEnd`), then `PW_PhaseChange`, then entry actions (`PW.ActiveMode` set or cleared, `MODE:Start`, `PW_MatchStart`) |
| `PW_MatchStart` | notification, via `PW.Notify` | — | Server. Entering `LIVE`: after `PW_PhaseChange` and after `MODE:Start` |
| `PW_MatchEnd` | notification, via `PW.Notify` | `result: any` | Server. Leaving `LIVE` (to `POSTMATCH`, or to `LOBBY` by abort): after `MODE:Cleanup`, before `PW_PhaseChange`. `result` is the value given to `Finish`, `nil` on abort. `MODE:Cleanup` and `PW_MatchEnd` run only if the match started (`LIVE` was entered); an abort from `PREMATCH` fires neither. The core removes every live instance here |
| `PW_PhaseChanged` | notification, via `PW.Notify` | `phase: PW.PhaseName, endsAt: number, seq: integer` | Client. Fired once per new `seq` the client sees: one frame after the `pw_phase_seq` NW2 proxy (`timer.Simple(0)`), reading the three globals then. Also fired once at client `InitPostEntity` with the current values (first sync, no delay). Transitions made in one server tick arrive as one call with the last values. Leaving `LIVE` ends the client instances first. On the client `PW.ActiveMode` is `nil`, so only listeners run |
| `PW_NextMatch` | question, via `PW.Ask` | `mode: table` (`PW.ActiveMode`, the mode that just ended) | Server. Asked once at the `VOTE` to `PREMATCH` step (timer end, or `PW.Match.EndVote`). The answer is `{ mode = <mode entity>, map = <string?> }` (`PW.NextMatch`); the core starts it through its usual path, a map change included. `nil` or an invalid answer: the same mode repeats on this map (an invalid non-nil answer logs one line). The first non-nil answer wins, the active mode's method of the same name is the default. Answered by the vote module (`modes.md`) |
| `PW_PendingTeams` | question, via `PW.Ask` | `mode: table` (the target mode) | Server. Asked when `PW.Match.Start` writes `pending_match.json` for another map. The answer (`table<string, integer>?`, team by SteamID64 string) is written to `teams`; a non-table answer or none writes `{}`. The core does not check the content (the file check only needs a table). Answered by the teams module (`teams.md`) |
| `PW_PendingMatchApplied` | notification, via `PW.Notify` | `pending: PW.PendingMatch` | Server. Fired on the new map after a valid pending file started the match: after `PW.Match.Start` entered `PREMATCH` (so after that `PW_PhaseChange`). Not fired for a rejected or missing file |
| `PW_RegistriesLoaded` | notification, via `PW.Notify` | — | Fired after `PW.Loader.Boot` resolved every registry. Listeners must not return a value |
| `PW_RegisterWeapons` | notification, via `PW.Notify` | `reg: PW.Registry` (the weapons registry) | Both realms. Fired by the weapon registration phase: at `InitPostEntity` (once per map) and after every later `Boot`. Register with `reg.Register(tbl, class, opts?)`, `{ soft = true }` for a soft registration. Must tolerate repeats. An error is logged by `pcall` (see "Weapon registration phase") |
| `PW_WeaponsLoaded` | notification, via `PW.Notify` | — | Both realms. Fired right after `PW_RegisterWeapons`, also when a listener of it failed. Consumers re-read `PW.Weapons` on every call |
