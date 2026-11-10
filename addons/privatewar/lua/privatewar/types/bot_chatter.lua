---@meta

---@class PW.ChatterContent
---@field names string[]
---@field voices table<string, PW.ChatterLines>
---@field texts table<string, PW.ChatterLines>
---@field voice PW.ChatterLines
---@field text PW.ChatterLines
---@field voiceIds string[]
---@field textIds string[]

---@class PW.ChatterState
---@field next number
---@field speaking number
---@field voice string?
---@field text string?
---@field seen boolean?
---@field death boolean?

---@class PW.BotChatterLib
---@field _Discover fun(): PW.ChatterContent
---@field PickName fun(taken: table<string, boolean>, roll: fun(): number): string?
---@field _SoundPath fun(path: any): boolean
---@field _Name fun(value: any): string?
---@field _NameFrom fun(names: string[], taken: table<string, boolean>, roll: number): string?
---@field _Text fun(value: any, target: string?): string?
---@field _CanSpeak fun(s: PW.ChatterState, now: number, globalAt: number, active: integer, limit: integer): boolean
---@field _Line fun(profile: PW.ChatterLines?, common: PW.ChatterLines, event: string, roll: number): string?
---@field _Visible fun(contacts: table[]): boolean
---@field _Identity fun(s: table, bot: any, v: string[], t: string[], rng: PW.ChatterRNG, now: number): PW.ChatterState

---@alias PW.ChatterLines table<string, string[]>
---@alias PW.ChatterRNG fun(): number

---@class PW
---@field BotChatter PW.BotChatterLib?
