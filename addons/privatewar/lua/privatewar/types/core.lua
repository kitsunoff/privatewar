---@meta
-- Type definitions of the Private War core API (DESIGN.md global rule 5). Shipped for addon authors.

---@alias PW.LogFn fun(message: string)

---Listener of PW_PreRegister: edit tbl in place, or return false to cancel the registration.
---@alias PW.PreRegisterFn fun(kind: string, id: string, tbl: table): boolean?

---PW_EntityDisabled notification, after invalidation, unsubscription and exact-definition instance cleanup.
---Cleanup-only listeners must return nothing, never error, and never regrant or perform gameplay.
---@alias PW.EntityDisabledFn fun(kind: string, id: string, definition: table, reason: string)

---When the entities of a kind are auto-subscribed to PW_* hooks (01-extensibility.md d.18).
---"always": every PW_* method of every enabled, non-abstract entity; "never": not at all (the default).
---@alias PW.SubscribeMode "always"|"never"

---Fields the core sets on every registered entity.
---@class PW.Entity
---@field ClassName string id of the entity (file or folder name)
---@field Base? string id of the entity this one inherits from
---@field BaseClass? PW.Entity resolved base entity
---@field Abstract? boolean usable as a base only; hidden from GetList
---Set by the core on the resolved entity (own definitions are overwritten): false once the entity is disabled,
---replaced by a re-registration or a later Base resolution, or its registry was released. GMod then drops the
---entity's hook.Add subscriptions by itself (01-extensibility.md d.18).
---The registry also sets IsValid on the class table a file filled (MODULE, MODE, ...) when it is registered: true
---while that table is the registered one for its id and its resolved entity is valid. So a file can hand its
---class table to PW.HookFor or to PW.Net.Receive (opts.owner) and to its own checks (MODULE:IsValid()).
---@field IsValid? fun(self: PW.Entity): boolean
---@field _Registry? PW.Registry internal: the registry that resolved this entity
---Internal: hooks added through PW.HookFor, by hook name. Copied to the resolved entity with the other fields.
---@field _EngineHooks? table<string, function>
---@field [string] any kind-specific fields

---@class PW.RegistryOptions
---@field log? PW.LogFn receives one line per problem (default: print with the [PW] tag)
---@field preRegister? PW.PreRegisterFn default: fires the PW_PreRegister hook
---@field subscribe? PW.SubscribeMode auto-subscription of resolved entities (default "never")
---Functions put on every resolved entity that does not define a field of the same name (modes and modules get
---Setting, T-1.5).
---@field methods? table<string, function>
---Required fields of the kind (KIND.Required), checked on the resolved entity, after Base (01-extensibility.md
---d.15): a field inherited from the Base chain counts. A non-abstract entity that fails is logged once and is
---absent from Get and GetList (it can still be a Base).
---@field required? table<string, type>

---Internal: the private state of one registry (sh_registry.lua).
---@class PW.RegistryState
---@field kind string
---@field log PW.LogFn
---@field preRegister PW.PreRegisterFn
---@field subscribe PW.SubscribeMode
---@field methods table<string, function>
---@field required? table<string, type>
---@field stored table<string, table<any, any>> registered tables by id
---@field resolved table<string, PW.Entity|false> false marks an entry that failed to resolve
---@field invalid table<string, true> resolved entities that failed the required-field check
---@field loaded boolean
---@field released boolean
---@field kept table<string, true> ids that stay valid after release
---@field disabled table<string, string> reason by id
---@field subscriptions table<string, {entity: PW.Entity, names: string[]}> live hooks by id
---@field reported table<table, string> weak-keyed: the last required-field error logged per registered table
---@field registry PW.Registry
---@field isValid fun(self: PW.Entity): boolean

---@class PW.RegisterOptions
---@field soft? boolean fill only missing fields of an existing entry, never overwrite

---One registry per kind (01-extensibility.md d.8, d.12).
---@class PW.Registry
---@field Kind string kind id
---@field Register fun(tbl: table, id: string, opts?: PW.RegisterOptions): boolean false when vetoed or invalid
---@field Get fun(id: string): PW.Entity? resolved entity with Base applied
---@field GetStored fun(id: string): table<string, any>? the table as registered, without Base
---@field GetList fun(): PW.Entity[] resolved non-abstract entities, sorted by id
---GetList without the disabled entities: disabled by the enable ConVar snapshot of the current match
---(01-extensibility.md d.11) or after an error (d.15). What the lobby, vote, loadout, HUD and bots list.
---@field GetEnabledList fun(): PW.Entity[]
---@field ResolveAll fun() resolve Base for every entry; later registrations resolve immediately
---Internal: disables an entity (IsValid false, subscriptions removed) until _Enable. Survives re-registration
---and Base resolution. Used by enable ConVars (T-1.4) and disable-after-error (T-1.8).
---On an actual enabled-to-disabled transition, removes exact-definition instances then notifies PW_EntityDisabled.
---@field _Disable fun(id: string, reason: string)
---Internal: clears a disable; the entity is subscribed again (its PW_* methods if its kind subscribes, and its
---PW.HookFor hooks).
---@field _Enable fun(id: string)
---@field _DisabledReason fun(id: string): string? internal: the reason given to _Disable, nil when enabled
---Internal: removes every subscription of the registry and invalidates its entities (the registry is replaced).
---Ids in keep stay valid (the active mode of a running match, 01-extensibility.md d.12).
---@field _Release fun(keep?: table<string, true>)
---@field _Released fun(): boolean internal: true after _Release (a reload replaced the registry)

---@class PW.RegistryLib
---@field New fun(kind: string, opts?: PW.RegistryOptions): PW.Registry
---@field _HookMethods fun(tbl: table): string[] internal: names of the PW_* functions of a table, sorted
---Pure: checks required fields (01-extensibility.md d.15), in name order. true, or false and a readable reason
---("missing required field Cost (number)", "field Cost must be number, got string").
---@field ValidateRequired fun(tbl: table<string, any>, required?: table<string, type>): boolean, string?

---@class PW.ListingEntry
---@field id string
---@field form "file"|"folder"

---Declaration of a kind: a file in lua/privatewar/kinds/ (01-extensibility.md d.16).
---@class PW.KindDef : PW.Entity
---@field Folder string folder scanned under lua/privatewar/
---@field Global string name of the class table inside entity files, e.g. "STREAK"
---@field Required? table<string, type> required fields and their Lua types
---When entities of the kind are auto-subscribed to PW_* hooks (d.18); omitted means "never".
---@field Subscribe? PW.SubscribeMode

---Subsystem code: a folder in lua/privatewar/modules/ (01-extensibility.md d.16).
---@class PW.Module : PW.Entity
---@field Settings? table<string, PW.SettingDecl> settings of the module, any scope (01-extensibility.md d.17)
---Value of one of the module's settings: self:Setting("count") reads "<id>.count".
---@field Setting fun(self: PW.Module, key: string): any

---@class PW.LoadOptions
---@field log? PW.LogFn

---@class PW.LoadContext
---@field root string Lua path the tree was loaded from, e.g. "privatewar"
---@field registries table<string, PW.Registry> by kind id
---@field log PW.LogFn

---@class PW.LoaderLib
---@field ParseListing fun(files: string[], dirs: string[]): PW.ListingEntry[], string[]
---@field ValidateRequired fun(tbl: table, required?: table<string, type>): boolean, string?
---@field AccessorName fun(kindId: string): string
---@field LoadRoot fun(root: string, opts?: PW.LoadOptions): PW.LoadContext
---@field Boot fun()

---Default usergroups a privilege can fall back to (00-core.md d.7).
---@alias PW.Usergroup "user"|"admin"|"superadmin"

---Privilege as passed to CAMI.RegisterPrivilege.
---@class PW.CamiPrivilege
---@field Name string
---@field MinAccess PW.Usergroup
---@field Description? string

---The part of the CAMI library the core uses. The global exists only when an admin mod ships it.
---The core calls PlayerHasAccess without a callback (synchronous answer); see sh_privileges.lua.
---@class PW.CamiLib
---@field RegisterPrivilege fun(privilege: PW.CamiPrivilege): PW.CamiPrivilege
---@field PlayerHasAccess fun(actor: Player, privilege: string, callback?: function): boolean?, string?

---Internal (01-extensibility.md d.14): one declared privilege.
---@class PW.PrivilegeDef
---@field Name string
---@field MinAccess PW.Usergroup
---@field cami? PW.CamiLib the CAMI table this privilege is registered in, if any

---Internal (01-extensibility.md d.14): declared privileges and the logger.
---@class PW.PrivilegeStore
---@field defs table<string, PW.PrivilegeDef> by privilege name
---@field log PW.LogFn

---Internal (01-extensibility.md d.14): logger of the hook dispatch (debug warnings).
---@class PW.HookStore
---@field log PW.LogFn

---Internal (00-core.md d.6; 01-extensibility.md d.15): state of PW.Call for the current map.
---@class PW.CallStore
---@field log PW.LogFn receives one line per runtime error
---Weak-keyed: erroring tables without an own (raw) _Registry, never called again. Instances land here even when
---their definition is a registered entity, so an error disables the instance, not the definition. Only actual
---Remove can admit its single OnUnequip cleanup call despite this failure; ordinary calls remain blocked.
---@field failed table<table, true>
---@field profile table<string, PW.ProfileEntry> accumulated timings by "<kind>:<id>"

---Accumulated PW.Call timings of one entity while pw_profile is 1 (00-core.md d.6).
---@class PW.ProfileEntry
---@field time number seconds spent inside the entity's methods (SysTime)
---@field calls integer number of measured calls

---Read and reset access to the PW.Call timings, for the profiler module.
---@class PW.ProfileLib
---Copy of the timings by "<kind>:<id>" (kind is the registry kind, "?" for an entity without a registry).
---@field Get fun(): table<string, PW.ProfileEntry>
---@field Reset fun() forgets every timing

---Per-owner instance of a definition (00-core.md d.11), made by PW.Instance(def, owner). Inherits every field
---of the definition through __index, so `self` in the definition's methods is the instance and per-owner state
---lives on it. Its callbacks run through PW.Call: an error disables (and ends) this instance only.
---@class PW.Instance
---@field _Owner any internal: the owner given to PW.Instance (passed to OnEquip and OnUnequip)
---@field _Definition table internal: own exact source-table reference, never inferred from ClassName
---False once removal starts, a callback errored, or the source definition's IsValid returns false.
---@field IsValid fun(self: PW.Instance): boolean
---hook.Add(name, self, fn) through PW.Call: fn receives the instance and the hook arguments, and its results
---are returned to the hook. One callback per hook name; dropped when the instance ends.
---@field Hook fun(self: PW.Instance, name: string, fn: fun(self: PW.Instance, ...: any): ...: any)
---Uniquely named timer.Create(delay, reps, ...) through PW.Call; fn receives the instance. Removed when the
---instance ends.
---@field Timer fun(self: PW.Instance, delay: number, reps: integer, fn: fun(self: PW.Instance))
---Ends the instance: blocks gameplay, invokes OnUnequip(owner) once through protected cleanup-only PW.Call even
---after failure/definition disable, then removes hooks, timers and the live entry regardless of cleanup errors.
---Reentrant/repeated calls do nothing. Cleanup is profiled, never disables the definition or resumes gameplay.
---@field Remove fun(self: PW.Instance)
---@field _Hooks table<string, true> internal: hook names the instance listens to
---@field _Timers table<string, true> internal: names of the instance's timers
---@field _Ended? boolean internal: Remove has started
---@field _Dead? boolean internal: the instance is dead; IsValid is false
---@field [string] any fields of the definition and per-owner state

---Internal (00-core.md d.11): live instances, ended by the core on PW_MatchEnd.
---@class PW.InstanceStore
---@field live table<PW.Instance, true> instances not yet removed
---@field count integer counter for unique timer names

---Match phases (00-core.md d.1).
---@alias PW.PhaseName "LOBBY"|"PREMATCH"|"LIVE"|"POSTMATCH"|"VOTE"

---What happens after POSTMATCH (00-core.md d.2): back to the lobby, or rotation with a vote.
---@alias PW.AfterMatch "lobby"|"rotation"

---Durations (seconds) and the after-match setting the machine reads when it enters a phase (00-core.md d.5).
---@class PW.PhaseSettings
---@field prematch number PREMATCH wait for players before the countdown (pw_prematch_timeout)
---@field countdown number countdown at the end of PREMATCH (pw_countdown)
---@field postmatch number POSTMATCH duration (pw_postmatch_time)
---@field vote number VOTE duration (pw_vote_time)
---@field afterMatch PW.AfterMatch pw_aftermatch

---The part of the machine state the pure rules read.
---@class PW.PhaseState
---@field phase PW.PhaseName
---@field endsAt number CurTime() at which the phase ends, -1 if none
---@field countdown boolean PREMATCH only: the countdown is running

---A timer-driven phase change decided by PW.Phase._Next.
---@class PW.PhaseStep
---@field phase PW.PhaseName
---@field duration number seconds until the new phase ends, -1 for none
---@field countdown? boolean the step starts the PREMATCH countdown
---@field begin? boolean the step begins the next match (VOTE -> PREMATCH)

---One connected player as the ready check sees it.
---@class PW.ReadyEntry
---@field key any the player (key of the ready set)
---@field bot boolean bots count as ready

---Pure rules of the phase machine (T-1.12, 00-core.md d.1, d.5). Shared; the machine itself is server only.
---@class PW.PhaseLib
---@field Names PW.PhaseName[] every phase, in cycle order
---Every allowed transition: from -> set of targets. PREMATCH -> PREMATCH is the start of the countdown (it
---restarts the phase timer). Any pair not listed is rejected.
---@field Transitions table<PW.PhaseName, table<PW.PhaseName, true>>
---@field CanTransition fun(from: string, to: string): boolean
---Internal: the timer-driven step for this state at time now, or nil.
---@field _Next fun(state: PW.PhaseState, now: number, allReady: boolean, settings: PW.PhaseSettings): PW.PhaseStep?
---Internal: true when every human in players is in the ready set; bots always count as ready.
---@field _AllReady fun(players: PW.ReadyEntry[], ready: table<any, true>): boolean
---Internal: maps a pw_aftermatch value to "lobby" or "rotation" (anything unknown is "lobby").
---@field _AfterMatch fun(value: string): PW.AfterMatch
---Current phase from the NW2 global pw_phase (00-core.md d.10), both realms. "LOBBY" until the server published it.
---@field GetPhase fun(): PW.PhaseName
---CurTime() at which the current phase ends (NW2 global pw_phase_end), -1 if none. Both realms.
---@field GetEnd fun(): number
---Seconds left in the current phase at now (default CurTime()), never below 0; nil when the phase has no end.
---Computed locally every frame: the server sends no timer traffic (00-core.md d.10).
---@field Remaining fun(now?: number): number?
---Internal: transition counter from the NW2 global pw_phase_seq, 0 until the server published it.
---@field _GetSeq fun(): integer
---Internal: the pure part of Remaining: max(0, endsAt - now), nil when endsAt < 0.
---@field _Remaining fun(endsAt: number, now: number): number?
---Internal: the client ends its live instances when the phase leaves LIVE (from may be nil: nothing seen yet).
---@field _EndsInstances fun(from: string?, to: string): boolean
---Internal: applies a published phase to the client view. Returns changed (seq differs from the last one seen,
---so a repeated full update is ignored) and whether the client must end its instances (leaving LIVE).
---@field _Apply fun(view: PW.PhaseView, phase: PW.PhaseName, seq: integer): boolean, boolean
---Internal: the NW2 global keys, in write order end -> phase -> seq.
---@field _Keys { ends: string, phase: string, seq: string }
---Names of the NW2 globals of a pending (announced) map change, written map -> mode -> at by the server.
---@field _ChangeKeys { map: string, mode: string, at: string }
---Both realms: the announced map change: target map, mode id and the time (CurTime) it runs; at < 0 when none.
---@field GetMapChange fun(): string, string, number

---Internal (client): the last published phase the client handled (00-core.md d.10).
---@class PW.PhaseView
---@field phase? PW.PhaseName
---@field seq? integer

---Writes one NW2 global (key, value); the machine calls it end -> phase -> seq. Injectable in tests.
---@alias PW.PhaseWriter fun(key: string, value: any)

---Options of a machine store; every field has an engine default (tests inject their own).
---@class PW.MatchStoreOptions
---@field log? PW.LogFn
---@field clock? fun(): number default CurTime
---@field players? fun(): PW.ReadyEntry[] default: every connected player
---@field settings? fun(): PW.PhaseSettings default: the ConVars (PW.Match._ReadSettings)
---@field write? PW.PhaseWriter default: SetGlobal2Float / SetGlobal2String / SetGlobal2Int by key

---Internal (00-core.md d.1-d.5): state of the phase machine.
---@class PW.MatchStore : PW.PhaseState
---@field mode? table the mode of the current or next match (resolved entity)
---@field ready table<any, true> PREMATCH ready set (reset to loaded when a match begins, cleared in LOBBY)
---@field loaded table<any, true> weak-keyed: players whose client reported loaded on this map
---@field modeStarted boolean MODE:Start was called and MODE:Cleanup is still due
---@field matchStarted boolean PW_MatchStart fired and PW_MatchEnd is still due
---@field result any result given to PW.Match.Finish, passed to PW_MatchEnd
---@field abortReason? string reason of the last abort, kept for the host until the next PW.Match.Start
---@field busy boolean a phase change is in progress; requests made meanwhile are queued
---@field queue fun(store: PW.MatchStore)[] requests made during a phase change
---@field log PW.LogFn
---@field clock fun(): number
---@field players fun(): PW.ReadyEntry[]
---@field settings fun(): PW.PhaseSettings
---@field seq integer transitions so far (+1 per transition, the PREMATCH countdown included); published as pw_phase_seq
---@field networked boolean server InitPostEntity has run (PW.Match._Publish): transitions write the NW2 globals
---@field write PW.PhaseWriter

---Match control (T-1.12, 00-core.md d.1-d.5; 02-modes.md d.7). Server only.
---@class PW.MatchLib
---Begins a match of mode (a resolved mode entity). With no map or the current one: LOBBY -> PREMATCH, sets
---PW.ActiveMode. With another map (00-core.md d.9): writes the pending file, runs changelevel and stays in LOBBY
---until the new map applies the file (PW.MapChange). Clears the last abort reason. False (one log line) outside
---LOBBY, for a non-entity, a map that is not a string, or while a map change is in progress (the guard).
---@field Start fun(mode: table, map?: string): boolean
---The mode calls it when the match is over: LIVE -> POSTMATCH. result is passed to PW_MatchEnd. False (one log
---line) outside LIVE. Called during a phase change (for example from MODE:Start) it runs right after it.
---@field Finish fun(result?: any): boolean
---Host abort: ends the match, returns to LOBBY and keeps reason for the host (00-core.md d.5; 01 d.15). Logs the
---reason. Does nothing else in LOBBY.
---@field Abort fun(reason: string): boolean
---Ends VOTE now (vote module: every human voted, or the host picked): the same step as the VOTE timer, so the next
---match is the answer of PW_NextMatch. False outside VOTE. During a phase change it is queued like Finish.
---@field EndVote fun(): boolean
---Marks a player ready (or not) for the PREMATCH wait. Bots always count as ready. When a match begins the ready
---set is reset to the players whose client reported loaded on this map (_SetLoaded); entering LOBBY clears it.
---@field SetReady fun(ply: any, ready?: boolean)
---Internal: the client of ply reported loaded on this map (pw_client_ready): ready now and in every later PREMATCH
---on this map. Idempotent. A disconnecting player is forgotten.
---@field _SetLoaded fun(ply: any)
---@field GetPhase fun(): PW.PhaseName
---@field GetPhaseEnd fun(): number CurTime() at which the phase ends, -1 if none
---@field GetAbortReason fun(): string? reason of the last abort until the next Start
---Internal: the only function that changes the phase. Checks the transition table (a rejected transition logs one
---line and returns false), runs the exit actions (leaving LIVE: MODE:Cleanup, PW_MatchEnd), stores phase and end
---time, fires PW_PhaseChange, runs the entry actions (LIVE: MODE:Start, PW_MatchStart; LOBBY: no active mode).
---@field _SetPhase fun(phase: string, duration?: number, countdown?: boolean): boolean
---Internal: one machine step (the core's Think hook): timer transitions, then MODE:Think during LIVE.
---@field _Tick fun()
---Internal: the durations and the after-match setting from the ConVars.
---@field _ReadSettings fun(): PW.PhaseSettings
---Internal: a fresh LOBBY store (tests swap PW._Match).
---@field _NewStore fun(opts?: PW.MatchStoreOptions): PW.MatchStore
---Internal: run in server InitPostEntity. Marks the store networked and writes its current phase, end time and seq
---(end -> phase -> seq); from then on every transition writes them (00-core.md d.10).
---@field _Publish fun()
---Internal: the pw_abort console command (privilege pw.match.abort; ply nil or NULL is the server console).
---@field _AbortCommand fun(ply: any, args: string[]): boolean

---@class PW
---@field Version string semantic version of the gamemode
---@field API integer bumped only on breaking API changes (01-extensibility.md d.14)
---@field Registry PW.RegistryLib
---@field Loader PW.LoaderLib
---@field Registries table<string, PW.Registry> every registry by kind id
---@field Kinds PW.Registry
---@field Modules PW.Registry
---@field Modes PW.Registry the modes kind (lua/privatewar/kinds/modes.lua)
---Settings (T-1.5, 01-extensibility.md d.17).
---@field Settings PW.SettingsLib
---Value of a setting by full id ("tdm.scorelimit"): match settings from the snapshot of the current match (else the
---pending value or the default), server and client settings from their ConVar. Unknown id: nil, logged once.
---@field Setting fun(fullId: string): any
---@field _Settings PW.SettingStore internal
---Declares a privilege with a default usergroup ("user", "admin" or "superadmin"); re-declaring replaces it.
---Registers it in CAMI when the CAMI global exists. Returns false (and logs) for an unknown usergroup.
---@field Privilege fun(name: string, defaultGroup: string): boolean
---Checks a declared privilege: through CAMI (synchronous) when present, else the default usergroup.
---Unknown privilege or a failing CAMI check: false plus one log line.
---@field Can fun(ply: Player, name: string): boolean
---@field _Privileges PW.PrivilegeStore internal
---The active mode (01-extensibility.md d.9, d.18): the default implementation of every PW_* hook, called
---after all listeners. nil outside a match. Assigning it switches modes; the old mode is no longer called.
---@field ActiveMode? table
---Dispatches a question hook: hook.Call(name, PW.ActiveMode, ...). The first non-nil listener answer wins;
---if every listener returns nil, the active mode's method of the same name answers. Returns the answer.
---@field Ask fun(name: string, ...: any): ...: any
---Dispatches a notification hook the same way; listeners must not return a value (it skips the remaining
---listeners and the mode's method). With pw_debug 1 a returned value logs one warning naming the hook.
---@field Notify fun(name: string, ...: any)
---Adds fn to hook name for an entity, through hook.Add(name, entity, fn) (fn gets the entity as self), and only
---while the entity is enabled (01-extensibility.md d.16, d.18). Call it in the entity's file on its class table
---(PW.HookFor(MODULE, "PlayerSpawn", fn)): the registry adds the hook when the entity is resolved and enabled,
---removes it when the entity is disabled, replaced or released, and adds it again when the entity is re-enabled.
---For engine hooks (PlayerSpawn, HUDPaint, ...) of any kind, whatever its Subscribe; one fn per name per entity.
---@field HookFor fun(entity: table, name: string, fn: fun(self: table, ...: any): ...: any)
---@field _Hooks PW.HookStore internal
---Calls entity[method](entity, ...) through pcall and returns its results (00-core.md d.6; 01 d.15).
---A missing method or an entity that is no longer valid (IsValid false, or an earlier error) returns nothing.
---The real instance Remove can admit OnUnequip once despite invalidity/failure. This private cleanup admission
---is consumed before entry, remains profiled, and cleanup errors never disable a definition or resume gameplay.
---On error: one log line (kind, id, method, error) and the entity is disabled until map change through its
---registry (_Disable, so its hook subscriptions drop). The active mode is not disabled: the core calls
---PW.Match.Abort("mode <id> failed: <error>") when it exists, and logs that line in any case.
---With pw_profile 1 the call time is accumulated per "<kind>:<id>" (see PW.Profile).
---@field Call fun(entity: table, method: string, ...: any): ...: any
---@field Profile PW.ProfileLib
---@field Match? PW.MatchLib
---@field Enable? PW.EnableLib enable snapshot: shared (the ConVars and their snapshot are server only)
---@field _Enable PW.EnableStore internal (server)
---@field _Match PW.MatchStore internal (server)
---@field Phase PW.PhaseLib
---@field _PhaseView PW.PhaseView internal (client)
---@field Net? PW.NetLib server only
---@field _Net PW.NetStore internal (server)
---@field _Call PW.CallStore internal
---Creates a per-owner instance of def (00-core.md d.11) and calls its OnEquip(owner) through PW.Call. The
---constructor immediately removes an invalid/failed instance; the core ends every other live instance on
---PW_MatchEnd, and the owning module may end it earlier with instance:Remove().
---@field Instance fun(def: table, owner: any): PW.Instance
---@field _Instances PW.InstanceStore internal
---Internal: removes every live instance (server: on PW_MatchEnd; client: when the phase leaves LIVE).
---@field _EndInstances fun()
---Internal: synchronously removes live instances whose own _Definition is exactly definition; no id matching.
---@field _EndDefinitionInstances fun(definition: table)
---Internal: consumes an existing private Remove-only admission for OnUnequip; never creates admission.
---@field _TakeInstanceCleanup fun(entity: table, method: string): boolean
PW = {}

---Class table inside a kinds/ file.
---@type PW.KindDef
KIND = nil

---Class table inside a modules/ folder.
---@type PW.Module
MODULE = nil
