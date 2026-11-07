---@meta
-- Optional addon scaffold only: no mode, module, hook, timer or runtime API is registered here.
-- Gameplay implementation waits for the orchestrator's shared-contract freeze and approved rule preset.

---Either a human player or a managed player bot can hold either role.
---@alias PW.InfectionRole "survivor"|"infected"

---Pure addon rules, keyed by stable round identity (not entity indices). No round loop lives here.
---@class PW.InfectionParticipant
---@field id string
---@field bot boolean
---@field life integer

---@class PW.InfectionLife : PW.InfectionParticipant
---@field role PW.InfectionRole
---@field initial boolean
---@field present boolean
---@field converted boolean

---@class PW.InfectionRound
---@field players table<string, PW.InfectionLife>
---@field deadline number
---@field winner? PW.InfectionRole immutable once decided

---@class PW.InfectionRulesLib
---@field PickSeed fun(players: PW.InfectionParticipant[], previous: string?, rng: fun(): number): string?
---@field NewRound fun(players: PW.InfectionParticipant[], seed: string, deadline: number): PW.InfectionRound?, string?
---@field Death fun(round: PW.InfectionRound, id: string, life: integer, now: number): boolean
---@field Disconnect fun(round: PW.InfectionRound, id: string, now: number)
---@field Admit fun(round: PW.InfectionRound, player: PW.InfectionParticipant): boolean
---@field Winner fun(round: PW.InfectionRound, now: number): PW.InfectionRole?
---@field Summary fun(rounds: PW.InfectionRound[]): PW.MatchResult

---@class PW
---@field InfectionRules? PW.InfectionRulesLib optional addon; declaration is not an implementation

---@class PW.InfectionSnapshot
---@field revision integer
---@field round integer
---@field survivors integer
---@field infected integer
---@field deadline number
---@field role PW.InfectionRole
---@field personalWins integer

---@class PW.InfectionPresentationLib
---@field Accept fun(current: PW.InfectionSnapshot?, incoming: table<string, any>): PW.InfectionSnapshot?
---@field Model fun(snapshot: PW.InfectionSnapshot, now: number): table<string, any>

---@class PW
---@field InfectionPresentation? PW.InfectionPresentationLib optional addon presentation reducer
