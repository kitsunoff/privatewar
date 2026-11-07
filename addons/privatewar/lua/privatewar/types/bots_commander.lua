---@meta
-- Types of the bots_commander module (T-5.11; 07-bots.md d.9, d.14). Code: lua/privatewar/modules/bots_commander/
-- (shared.lua: the pure assignment and the hunt filter; sh_hunt.lua: the pure hunt slots; init.lua: the 1 Hz glue).

---@alias PW.PlayerTeamChangingHook fun(ply: Player, from: integer, to: integer, reason: string)
---@alias PW.PlayerTeamChangedHook fun(ply: Player, from: integer, to: integer, reason: string)
---@alias PW.ObjectiveInvalidatedHook fun(id: string, revision: integer)

---The commander's order (docs/api/bots-blackboard.md "Blackboard" types; writer: bots_commander). One objective of
---MODE:BotObjectives plus the assignment. A hunt assignment is carried by board.hunt, not by the order.
---@class PW.BotOrder
---@field objective PW.BotObjective the objective as returned by MODE:BotObjectives (refreshed every commander pass)
---@field type string the objective's action: "capture", "defend", "collect", "deny", "hold"
---@field id string the objective's id (contract addition: the order's key for anti-dither)
---@field priority number the objective's weight at the last pass, 0..1 (contract addition)
---@field since number CurTime() of the assignment; kept while the bot stays on the same objective and action

---The hunt slot of a bot (board.hunt; writer: bots_commander). Present on every managed bot while the commander runs;
---absent = no commander, the hunt behaviour then goes to every hot spot.
---@class PW.BotHuntSlot
---@field target? Player the human this bot hunts; nil = the bot holds no hunt slot
---@field since number CurTime() the slot was given (or the pass that wrote "no slot")

---@class PW.BotBoard
---@field order? PW.BotOrder the commander's order (nil = none)
---@field hunt? PW.BotHuntSlot the commander's hunt slot

---One bot as the pure assignment sees it.
---@class PW.CommanderBot
---@field id integer stable key (UserID in the glue); ties are broken by the smaller id
---@field pos Vector
---@field team? integer
---@field stationary? boolean the personality is of type "stationary" (prefers defend, 07 d.14)
---@field busy? boolean the bot has an order (hunt slots go to bots without one first)
---@field seen? table<integer, number> CurTime() of the bot's last contact with each human (by human id)

---One human as the hunt slots see it.
---@class PW.CommanderHuman
---@field id integer stable key (UserID in the glue)
---@field pos Vector
---@field team? integer nil in FFA

---Options of PW.BotCommander.Assign. Defaults come from PW.BotCommander.Config.
---@class PW.CommanderAssignOpts
---@field hold? number seconds an order is kept before it may be reassigned (anti-dither hysteresis)
---@field defendShare? number at most this share of the team defends (07 d.14: a third)
---@field teamSize? integer team size the defender cap is taken of; default #bots
---@field sticky? number score factor for the objective a bot already has
---@field stationaryDefend? number score factor of defend objectives for a stationary bot

---One hunter of one human.
---@class PW.CommanderHunter
---@field since number CurTime() the slot was given
---@field progressAt number CurTime() of the last progress (closer by Config.huntProgress, or a contact)
---@field best number the closest distance to the human seen since the last progress

---The hunt state of one human.
---@class PW.CommanderHuntHuman
---@field budget integer how many bots may hunt this human now (1..Config.huntMax, re-rolled)
---@field rerollAt number CurTime() of the next re-roll of the budget
---@field hunters table<integer, PW.CommanderHunter> by bot id
---@field cooldown table<integer, number> bot id -> CurTime() until which a replaced hunter is not picked again

---The persistent state of the hunt slots (one per server, all teams).
---@class PW.CommanderHuntState
---@field humans table<integer, PW.CommanderHuntHuman> by human id

---Options of PW.BotCommander.Hunt. Defaults come from PW.BotCommander.Config.
---@class PW.CommanderHuntOpts
---@field max? integer hunt slots per human, at most
---@field stall? number seconds without progress after which a hunter is replaced
---@field progress? number units closer to the human that count as progress
---@field contact? number seconds: a contact this fresh counts as progress
---@field rerollMin? number seconds, the shortest budget period
---@field rerollMax? number seconds, the longest budget period
---@field random? fun(): number uniform in [0, 1), default math.random

---Gameplay values of the commander.
---@class PW.CommanderConfig
---@field interval number seconds between two commander passes (07 d.3: 1 Hz)
---@field hold number seconds an order is kept before it may be reassigned (07 d.14: 30-45 s)
---@field defendShare number at most this share of a team's bots defend (07 d.14: a third)
---@field sticky number score factor for the current objective once the hold has passed (hysteresis)
---@field stationaryDefend number score factor of defend objectives for a stationary personality
---@field falloff number units: closeness = 1 / (1 + distance / falloff)
---@field huntMax integer hunt slots per human (07 d.9: 1-2)
---@field huntStall number seconds without progress before a hunter is replaced
---@field huntProgress number units closer that count as progress
---@field huntContact number seconds: a contact this fresh counts as progress
---@field rerollMin number seconds (07 d.9: the budget is re-rolled every 30-60 s)
---@field rerollMax number seconds

---Internal (server): state of the module.
---@class PW.BotCommanderStore
---@field nextRun number CurTime() of the next pass
---@field hunt PW.CommanderHuntState

---The bot commander (T-5.11). Shared: the pure rules; server: the 1 Hz glue.
---@class PW.BotCommanderLib
---@field Config PW.CommanderConfig
---Pure whitelist sanitizer preserving copied eligibility, revision and cylinder.
---@field Sanitize fun(raw: any): PW.BotObjective[]
---Role/roster/carrier eligibility; a present empty set allows nobody.
---@field Eligible fun(objective: PW.BotObjective, botId: integer): boolean
---Server: clear only commander-owned orders/hunt/retained state; goals through the public goal API.
---@field Clear? fun()
---Server: release a specific old visit and its goal; other visits/objectives stay intact.
---@field InvalidateObjective? fun(id: string, revision: integer)
---Pure: closeness of a distance, 1 at 0, 0.5 at Config.falloff.
---@field Closeness fun(dist: number): number
---Pure: the orders of one team. orders = the current orders by bot id; the answer has an entry for every bot that
---gets an order (bots without one are absent). Deterministic: ties go to the smaller objective id, then bot id.
---@field Assign fun(bots: PW.CommanderBot[], objectives: PW.BotObjective[], orders: table<integer, PW.BotOrder>,
---    now: number, opts?: PW.CommanderAssignOpts): table<integer, PW.BotOrder>
---Pure: one pass of the hunt slots over every human; updates state and returns bot id -> human id of every hunter.
---@field Hunt fun(state: PW.CommanderHuntState, humans: PW.CommanderHuman[], bots: PW.CommanderBot[], now: number,
---    opts?: PW.CommanderHuntOpts): table<integer, integer>
---A fresh hunt state.
---@field NewHuntState fun(): PW.CommanderHuntState
---Pure: what the hunt behaviour may chase. A bot with a slot sees every contact and the deaths; a bot without one
---(slot.target nil) does not see the humans' contacts nor the deaths. No slot table (no commander) = no filter.
---@field HuntView fun(board: PW.BotBoard, memory: table<any, PW.BotContact>, deaths: PW.BotDeathInfo[],
---    isHuman?: fun(ent: any): boolean): table<any, PW.BotContact>, PW.BotDeathInfo[]
---Engine predicate: a valid player that is not a bot.
---@field IsHuman fun(ent: any): boolean
---Server: one commander pass at now (the Think hook calls it every Config.interval).
---@field Step? fun(now: number)

---@class PW
---@field BotCommander? PW.BotCommanderLib
---@field _BotCommander PW.BotCommanderStore internal (server)

---@class PW.DomMode
---Objectives of a team for the bot commander (docs/api/modes.md "BotObjectives"); {} without PW.BotObjectives.
---@field BotObjectives fun(self: PW.DomMode, team: integer): PW.BotObjective[]

---@class PW.KCMode
---Objectives of a team for the bot commander (docs/api/modes.md "BotObjectives"); {} without PW.BotObjectives.
---@field BotObjectives fun(self: PW.KCMode, team: integer): PW.BotObjective[]
