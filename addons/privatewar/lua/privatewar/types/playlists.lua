---@meta
-- Types of the playlists kind and module (T-2.6; 02-modes.md d.2-d.5b; docs/api/modes.md "Playlists").
-- Module: lua/privatewar/modules/playlists/ (shared.lua: pure rules and wire; init.lua: server glue and messages;
-- cl_init.lua: client state). Kind: lua/privatewar/kinds/playlists.lua.

---The class table of a playlist file (data only).
---@class PW.Playlist : PW.Entity
---@field Name string display name
---@field Modes table<string, number> mode id -> weight (> 0)
---@field Maps? string[] map pool; nil = every map that fits the modes
---@field Settings? table<string, any> match-scope overrides by full setting id

---A validated playlist (the same shape for Lua files and host-saved JSON).
---@class PW.PlaylistData
---@field Name string
---@field Modes table<string, number>
---@field Maps? string[]
---@field Settings table<string, any> validated, clamped values

---One listed playlist.
---@class PW.PlaylistEntry : PW.PlaylistData
---@field id string
---@field source "lua"|"json"

---What validation needs to know about the game; every field is optional (not given = not checked).
---@class PW.PlaylistFacts
---@field modes? table<string, true> ids of the known modes
---@field settings? PW.SettingIndex full id -> definition of the known settings
---@field validate? fun(def: PW.SettingDef, value: any): boolean, any, string? the settings validator

---Options of PW.Playlist.Sample.
---@class PW.PlaylistSampleOptions
---@field rng fun(): number returns a number in [0, 1)
---@field maps? string[] the pool of a playlist with Maps = nil
---@field fits? fun(modeId: string, map: string): boolean whether the mode is offered on the map (default: always)

---A sampled next match.
---@class PW.PlaylistPick
---@field mode string
---@field map string

---A playlist as the lobby shows it (wire form of pw_playlist_list).
---@class PW.PlaylistSummary
---@field id string
---@field name string
---@field summary string for example "tdm, ffa on 2 maps"
---@field fill integer the playlist's bots.fill, 0 when it sets none

---What the server sends to one client.
---@class PW.PlaylistListState
---@field list PW.PlaylistSummary[]
---@field active string the active playlist id, "" for Custom
---@field canPick boolean

---@class PW.PlaylistWriter
---@field uint fun(value: integer, bits: integer)
---@field string fun(value: string)
---@field bool fun(value: boolean)

---@class PW.PlaylistReader
---@field uint fun(bits: integer): integer
---@field string fun(): string
---@field bool fun(): boolean

---Why a JSON file was not loaded.
---@class PW.PlaylistFileError
---@field file string
---@field message string

---Injectable glue of the server side (tests give fakes).
---@class PW.PlaylistStoreOptions
---@field log? PW.LogFn
---@field dir? string folder under data/ with the host's JSON files
---@field luaEntries? fun(): table[] enabled entries of the playlists registry
---@field facts? fun(): PW.PlaylistFacts
---@field pool? fun(): string[] the maps of a playlist with Maps = nil
---@field fits? fun(modeId: string, map: string): boolean
---@field rng? fun(): number
---@field setSetting? fun(fullId: string, value: any): boolean, string?
---@field start? fun(modeId: string, map: string): boolean
---@field readId? fun(): string
---@field send? fun(ply: Player, state: PW.PlaylistListState)
---@field getActive? fun(): string
---@field setActive? fun(id: string)
---@field fillOf? fun(entry: PW.PlaylistEntry): integer

---@class PW.PlaylistStore
---@field log PW.LogFn
---@field dir string
---@field luaEntries fun(): table[]
---@field facts fun(): PW.PlaylistFacts
---@field pool fun(): string[]
---@field fits fun(modeId: string, map: string): boolean
---@field rng fun(): number
---@field setSetting fun(fullId: string, value: any): boolean, string?
---@field start fun(modeId: string, map: string): boolean
---@field readId fun(): string
---@field send fun(ply: Player, state: PW.PlaylistListState)
---@field getActive fun(): string
---@field setActive fun(id: string)

---@class PW.PlaylistItems
---@field items { id: string, label: string }[]
---@field selected string the selected row id ("@custom" for Custom)
---@field warning? string set when the active playlist wants more players than the server has
---@field activeName? string the name of the active playlist

---@class PW.PlaylistLib
---Format version written into host-saved JSON ("Version"); a file without it is read as version 1.
---@field Version integer
---Folder under data/ with the host-saved JSON files: "privatewar/playlists".
---@field DataDir string
---Privilege to pick and start a playlist: "pw.match.start" (the lobby's privilege).
---@field Privilege string
---Row id of Custom in the lobby's playlist list: "@custom".
---@field CustomRow string
---Pure: the same validation for Lua playlists and JSON: Name, Modes (known ids, weights > 0), Maps (nil or a
---non-empty list of map names), Settings (known match settings, valid values). Returns a clean copy or nil and
---a message.
---@field Normalize fun(raw: any, facts?: PW.PlaylistFacts): PW.PlaylistData?, string?
---Pure over util.JSONToTable: JSON text -> a validated playlist, or nil and a readable message.
---@field FromJson fun(text: any, facts?: PW.PlaylistFacts): PW.PlaylistData?, string?
---Pure: a validated playlist -> JSON text (with Version).
---@field ToJson fun(data: PW.PlaylistData): string
---Pure: file name -> playlist id ("night.json" -> "night"); nil unless the name is [a-z0-9_]+ plus ".json".
---@field FileId fun(fileName: any): string?
---Pure: one id by weight; ids are visited in sorted order; rng() in [0, 1). nil without a positive weight.
---@field PickWeighted fun(weights: table<string, number>, rng: fun(): number): string?
---Pure: the next mode and map of a playlist by weight, or nil and a reason.
---@field Sample fun(data: PW.PlaylistData, opts: PW.PlaylistSampleOptions): PW.PlaylistPick?, string?
---Pure: the pw_playlist_list encoding.
---@field _Encode fun(state: PW.PlaylistListState, writer: PW.PlaylistWriter)
---@field _Decode fun(reader: PW.PlaylistReader): PW.PlaylistListState
---Pure: the lobby summary of a listed playlist.
---@field _Summary fun(entry: PW.PlaylistEntry, fill: integer): PW.PlaylistSummary
---Server: the listed playlists: enabled Lua playlists, then the host's JSON ones; sorted by name. Invalid ones are
---skipped with one log line each.
---@field GetList? fun(): PW.PlaylistEntry[]
---@field Get? fun(id: string): PW.PlaylistEntry?
---Server: reads and validates every *.json of the folder; returns the playlists and the files that failed.
---@field LoadDir? fun(dir?: string): PW.PlaylistEntry[], PW.PlaylistFileError[]
---Server: validates and writes a playlist as <id>.json in the folder.
---@field Save? fun(id: string, data: table, dir?: string): boolean, string?
---Server: samples the next mode and map of a listed playlist.
---@field Pick? fun(id: string): PW.PlaylistPick?, string?
---Server: applies the settings of a playlist, remembers it as the active one and starts the match.
---@field Start? fun(id: string): boolean, string?
---Server: the active playlist id, "" for Custom (a ConVar, so it survives a map change).
---@field GetActive? fun(): string
---@field SetActive? fun(id: string)
---Client: the last list the server sent, nil before the first answer.
---@field GetState? fun(): PW.PlaylistListState?
---Client: asks the server for the list.
---@field Request? fun()
---Client: asks the server to make a playlist the active one ("" = Custom).
---@field SendPick? fun(id: string)
---Client: asks the server to start a playlist.
---@field SendStart? fun(id: string)
---Pure: the rows of the lobby's playlist list ("@custom" first) and the warning for the active playlist.
---@field _Items fun(state: PW.PlaylistListState, maxPlayers: integer): PW.PlaylistItems
---Client: called after a list arrives (the lobby screen sets it).
---@field OnChange? fun()
---@field _NewStore? fun(opts?: PW.PlaylistStoreOptions): PW.PlaylistStore
---@field _RegisterNet? fun(owner?: table)
---@field _OnRequest? fun(ply: Player): boolean
---@field _OnPick? fun(ply: Player): boolean
---@field _OnStart? fun(ply: Player): boolean

---@class PW
---@field Playlist? PW.PlaylistLib the playlists module (nil when the module is missing)
---@field Playlists? PW.Registry the playlists kind registry (lua/privatewar/playlists/)
---@field _Playlist PW.PlaylistStore internal

---Class table inside a playlists/ file.
---@type PW.Playlist
PLAYLIST = nil
