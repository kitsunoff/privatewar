---@meta

---@class PW.CardChoiceFacts
---@field previous? string previously resolved card
---@field registered fun(id: string): boolean
---@field enabled fun(id: string): boolean
---@field unlocked fun(id: string): boolean

---Snapshot, not an entity reference; an empty card id has no artwork.
---@class PW.KillCardState
---@field name string victim nickname, at most 32 bytes on the wire
---@field card string card id, at most 32 bytes on the wire
---@field bot boolean whether the victim is a bot

---@class PW.CardWriter
---@field WriteString fun(value: string)
---@field WriteBool fun(value: boolean)

---@class PW.CardReader
---@field ReadUInt fun(bits: integer): integer
---@field ReadBool fun(): boolean

---@class PW.CardServerEdges
---@field find fun(id: string): PW.CallingCard?
---@field enabledIds fun(): string[] sorted, wire-safe card ids
---@field unlocked fun(ply: Player, id: string): boolean
---@field phase fun(): string
---@field isPlayer fun(entity: Entity): boolean
---@field isEnemy fun(attacker: Player, victim: Player): boolean
---@field rng fun(): number
---@field send fun(channel: string, killer: Player, state: PW.KillCardState)

---@class PW.CallingCardsStore
---@field io PW.CardServerEdges
---@field requested table<Player, string> the last well-formed requested choice, weak keys
---@field bots table<Player, string> the bot's session choice, weak keys

---Calling cards (06-progression.md d.6, 09-hud.md d.2). Underscored fields are internal.
---@class PW.CallingCardsLib
---@field Default string default card id
---@field ChoiceNet string choice channel (client to server)
---@field KillNet string kill banner channel (server to killer)
---@field ChoiceMaxLen integer wrapper byte limit for the selection channel
---@field _Active fun(): boolean
---@field _ValidChoice fun(id: any): boolean
---@field _CardDefinition fun(id: string): PW.CallingCard? includes disabled definitions
---@field _Resolve fun(id: any, facts: PW.CardChoiceFacts): string
---@field _BotCard fun(sortedIds: string[], rng: fun(): number): string?
---@field _VictimName fun(name: string): string
---@field _ReadChoice fun(reader: PW.CardReader, bits: integer): string?
---@field _Encode fun(state: PW.KillCardState, writer: PW.CardWriter)
---@field _Decode fun(reader: PW.CardReader, bits: integer): PW.KillCardState?
---@field _NewStore? fun(io?: PW.CardServerEdges): PW.CallingCardsStore
---@field _Store? PW.CallingCardsStore
---@field _OnChoice? fun(store: PW.CallingCardsStore, ply: Player, choice: any): boolean
---@field _OnSpawn? fun(store: PW.CallingCardsStore, ply: Player)
---@field _OnKill? fun(store: PW.CallingCardsStore, victim: Player, attacker: Entity)

---@class PW
---@field CallingCards? PW.CallingCardsLib
