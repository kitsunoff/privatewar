---@meta

---@alias PW.DependencySnapshot table<string, table<string, PW.Entity>>

---@class PW.Mode
---@field Dependencies? table<string, string[]> required entity ids by kind, checked regardless of bot count

---@class PW.MatchLib
---@field Dependency fun(kind: string, id: string): PW.Entity? current match's exact dependency, else registry entry
---@field _CheckDependencies fun(mode: table, registries: table<string, PW.Registry>): PW.DependencySnapshot?, string?
---@field _BindDependencies fun(store: PW.MatchStore): boolean bind or queue a server-log-only abort
---@field _DependencyEntities fun(): PW.Entity[] definitions the loader must preserve until match end
