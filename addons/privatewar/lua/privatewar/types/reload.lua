---@meta
-- Types of hot reload (T-1.15, 01-extensibility.md d.12): pw_reload, GM:OnReloaded and the loader's rescan.
-- Code: gamemodes/privatewar/gamemode/core/sh_reload.lua, sv_reload.lua, sh_loader.lua.

---The file access of the loader. The default is the engine's LUA path (PW.Loader._EngineFs); tests overlay
---virtual files on it, because the game cannot write .lua files.
---@class PW.LoaderFs
---@field find fun(pattern: string): string[], string[] files and folders matching "<dir>/*" (never nil)
---@field exists fun(path: string): boolean
---@field run fun(path: string): boolean, string? compiles and runs a file; false and the error text on failure
---@field send fun(path: string) server: makes the file downloadable for clients (AddCSLuaFile)

---@class PW.LoadOptions
---@field fs? PW.LoaderFs default: PW.Loader._EngineFs

---@class PW.LoadContext
---@field fs PW.LoaderFs the file access the tree was loaded with

---Options of PW.Loader._Rescan.
---@class PW.RescanOptions : PW.LoadOptions
---@field root? string default "privatewar"
---Entities that stay valid although their registry is replaced: the active mode of a running match (d.12: a
---reload does not touch the running match).
---@field active? table[]

---@class PW.LoaderLib
---@field _EngineFs PW.LoaderFs internal: the engine's LUA path
---Internal, pure: for every active entity whose own registry is one of previous: { [kind] = { [id] = true } }.
---@field _KeepFor fun(previous: table<string, PW.Registry>?, active: table[]): table<string, table<string, true>>
---Internal: loads the root again (every kind folder is scanned anew, so new files are found and a changed file
---replaces its entry), then releases the previous registries: their entities lose their subscriptions and turn
---invalid, except the active ones. Returns the new context; installing it is Boot's job.
---@field _Rescan fun(previous: table<string, PW.Registry>?, opts?: PW.RescanOptions): PW.LoadContext

---@class PW.MatchLib
---Internal, pure: the definition a new match of mode uses. While mode's own registry is live: its current entry
---for the id (a re-registration), else mode itself. When a reload released that registry: the entry with the id
---in the current registry of the kind (the reloaded definition, 01-extensibility.md d.12), nil when there is none.
---A table without a registry is used as is.
---@field _Definition fun(mode: table, registries: table<string, PW.Registry>): table?

---Options of a reload store; every field has an engine default (tests inject their own).
---@class PW.ReloadStoreOptions
---@field log? PW.LogFn
---@field boot? fun() default: PW.Loader.Boot
---@field broadcast? fun() server default: sends pw_reload to every client one tick later (new files reach first)

---@class PW.ReloadStore
---@field log PW.LogFn
---@field boot fun()
---@field broadcast fun()

---Hot reload (01-extensibility.md d.12). Shared; the command is server only.
---@class PW.ReloadLib
---Privilege of the pw_reload command ("pw.reload", default superadmin; 00-core.md d.7). Server only.
---@field Privilege string
---Reloads this realm: PW.Loader.Boot (rescan of every kind folder, Base resolution, PW_RegistriesLoaded) through
---pcall, then one log line with the reason and the summary, or the error. Returns whether the boot succeeded.
---@field Run fun(reason: string): boolean
---Internal, pure: "<kind> <count>, ..." of the listed entities of every registry, sorted by kind id.
---@field _Summary fun(registries: table<string, PW.Registry>): string
---Internal: the pw_reload command. A player needs the privilege (refused: one log line, false); the server
---console always may. Reloads the server, then tells every client to reload (only when the server reload worked).
---@field _Command fun(ply: Player|Entity?): boolean
---Internal: a fresh store (tests swap PW._Reload).
---@field _NewStore fun(opts?: PW.ReloadStoreOptions): PW.ReloadStore

---@class PW
---@field Reload PW.ReloadLib
---@field _Reload PW.ReloadStore internal
