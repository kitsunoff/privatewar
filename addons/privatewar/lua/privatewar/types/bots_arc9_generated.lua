---@meta

---@class PW.Arc9BotWeapon
---@field class string
---@field category? string
---@field knife boolean

---@class PW.Arc9BotGenerationApi
---@field weapons fun(): PW.Arc9BotWeapon[]
---@field slots fun(class: string): PW.Slot[]
---@field options fun(class: string, slot: string): PW.Option[]
---@field role fun(option: string): string?
---@field validate fun(class: string, build: PW.Build): PW.Build, table<string, string>
---@field random fun(n: integer): integer

---@class PW.Arc9BotGenerationState
---@field map string
---@field version integer
---@field status "working"|"ready"|"failed"|"stale"
---@field entries PW.BotClassEntry[]
---@field job? thread
---@field error? string
---@field frames integer
---@field resumes integer
---@field totalSeconds number
---@field maxFrameSeconds number cooperative slice time, including indivisible addon calls

---@class PW.Arc9BotLoadoutsLib
---@field Version integer
---@field Archetypes string[]
---@field Perks table<string, string[]>
---@field Available fun(arc9: ARC9Lib?, adapter: PW.Adapter?): boolean
---@field OptionRole fun(att: table<string, any>?): string?
---@field Candidates fun(state: PW.Arc9BotGenerationState?, map: string, enabled: boolean): PW.BotClassEntry[]
---@field Keep fun(state: PW.Arc9BotGenerationState?, map: string): PW.Arc9BotGenerationState?
---@field New fun(map: string, api: PW.Arc9BotGenerationApi): PW.Arc9BotGenerationState
---@field Step fun(state: PW.Arc9BotGenerationState, now: PW.Arc9BotClock, seconds: number, limit: integer): integer
---@field Start fun()
---@field Legal fun(entry: PW.BotClassEntry): boolean

---@alias PW.Arc9BotClock fun(): number

---@class PW
---@field Arc9BotLoadouts? PW.Arc9BotLoadoutsLib
---@field _Arc9BotLoadouts? PW.Arc9BotGenerationState
