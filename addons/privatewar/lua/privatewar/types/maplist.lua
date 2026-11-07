---@meta
-- Types of the maplist module (T-2.11; 03-mapdata.md d.9; docs/api/map.md "Map list").
-- Module: lua/privatewar/modules/maplist/ (shared.lua: API and pure rules; init.lua: server glue).

---A set setting value as the settings store gives it: a lookup { [id] = true }; a plain list is accepted too.
---@alias PW.MapListSet table<string|integer, string|true>

---The sources the pure filter merges.
---@class PW.MapListSources
---@field installed string[] map names found on disk (no ".bsp")
---@field data PW.MapListSet map data file ids (PW.Map.Id of a map name) of the enabled maps registry entries
---@field prefixes PW.MapListSet PvP prefixes, for example "de_"
---@field whitelist PW.MapListSet map names the host added by hand

---@class PW.MapListLib
---Default PvP prefixes of the setting maplist.prefixes.
---@field DefaultPrefixes string[]
---Junk name patterns (Lua patterns over the lowercase map name); a match is never listed.
---@field JunkPatterns string[]
---Pure: whether a map name is junk (background, campaign, credits, test maps). Case-insensitive.
---@field IsJunk fun(mapName: string): boolean
---Pure: the curated list: installed maps that have a data file, start with a PvP prefix or are whitelisted, minus
---junk (junk wins over all three sources). Unique, sorted, original spelling of the installed name.
---@field Filter fun(sources: PW.MapListSources): string[]
---Pure: map names from a maps/*.bsp listing (no ".bsp"), unique, sorted.
---@field _NamesFromFiles fun(files: string[]): string[]
---Server: every installed map except junk (the "Show all maps" list of Custom, 03-mapdata.md d.9), sorted.
---@field GetInstalled? fun(): string[]
---Server: the curated list from the engine (file.Find), the enabled maps registry and the settings.
---@field GetList? fun(): string[]
---Server: whether a map is in the curated list.
---@field IsListed? fun(mapName: string): boolean
---Internal (server): the thin wrapper over file.Find: names of the installed maps.
---@field _Installed? fun(): string[]

---@class PW
---@field MapList? PW.MapListLib the maplist module (nil when the module is missing)
