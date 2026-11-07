---@meta
-- Types of the bots_perception module (T-5.7; 07-bots.md d.7, docs/api/bots-blackboard.md "Stimuli"). Code:
-- lua/privatewar/modules/bots_perception/ (shared.lua: pure rules; sh_state.lua: the per-bot state and the stimuli;
-- init.lua: engine glue).

---A contact as the blackboard types it (contract). `dir` is added by this module: the unit direction to the attacker
---for a damage contact (07 d.7: damage reveals the attacker's direction).
---@class PW.BotContact
---@field ent Entity the enemy (as decided by PW.IsEnemy)
---@field pos Vector last seen or heard position
---@field vel Vector last known velocity
---@field time number CurTime() of the last sighting or stimulus
---@field visible boolean currently seen through the reaction queue
---@field source string "sight", "sound", "damage", "shared" or a stimulus kind
---@field dir? Vector direction to the attacker, damage contacts only

---Perception writes contacts and memory (docs/api/bots-blackboard.md "Blackboard").
---@class PW.BotBoard
---@field contacts? PW.BotContact[] every known contact: seen first, then the newest
---@field memory? table<Entity, PW.BotContact> the contact memory, 12 s
---@field debug? table counters; perception writes debug.perception

---Perception parameters of one bot (the human-like axes of its difficulty; names as in notes/14).
---@class PW.BotPerceptionParams
---@field reaction_mean number seconds from first visibility to recognition
---@field reaction_floor number hard minimum of the reaction time
---@field reaction_jitter number log-normal style sigma of the reaction time
---@field share_delay number seconds before a teammate's sighting reaches this bot
---@field share_radius number a teammate's sighting is received only within this distance of the sharer, units
---@field fov number total view cone in degrees

---What was seen at one moment: enemy to its position and velocity.
---@alias PW.BotSnapshotSet table<any, { pos: Vector, vel: Vector }>

---One snapshot of the reaction queue.
---@class PW.BotSnapshot
---@field time number
---@field seen PW.BotSnapshotSet

---@class PW.BotReactionQueue
---@field snaps PW.BotSnapshot[]

---A candidate enemy for the sight check: a centre for the cone and body points for the traces (head, chest, feet).
---@class PW.BotCandidate
---@field ent any
---@field center Vector
---@field points Vector[]
---@field vel Vector
---@field dist? number squared distance to the bot, to sort nearest first

---Facts of one sight check.
---@class PW.BotSightCtx
---@field eye Vector
---@field forward Vector unit view direction
---@field fov number total cone, degrees
---@field range number
---@field los fun(point: Vector, cand: PW.BotCandidate): boolean one trace
---@field budget { left: integer } traces left this perception tick, decremented per trace

---A message of team sharing waiting for its delivery.
---@class PW.BotPending
---@field at number
---@field ent any
---@field pos Vector
---@field vel Vector
---@field time number

---Per-bot perception state (plain data).
---@class PW.BotPerceptionState
---@field queue PW.BotReactionQueue
---@field memory table<any, PW.BotContact>
---@field contacts PW.BotContact[]
---@field pending PW.BotPending[]
---@field sharedAt table<any, number> when a sighting of an enemy was last shared
---@field delay? number the reaction delay in force
---@field delayAt number
---@field recognisedTo? number the snapshots up to this time were recognised (perception decision 10)
---@field team? integer set by the glue every tick; team stimuli use it

---A sighting that was recognised and may be shared.
---@class PW.BotSighting
---@field ent any
---@field pos Vector
---@field vel Vector
---@field time number

---Facts of one perception step.
---@class PW.BotThinkCtx
---@field params PW.BotPerceptionParams
---@field seen? PW.BotSnapshotSet enemies found visible this tick (FOV and line of sight done by the glue)
---@field valid? fun(ent: any): boolean an enemy that fails this is dropped
---@field random? fun(): number a number in [0, 1) for the reaction jitter; nil: no jitter

---A stimulus (the data of PW.Bot.AddStimulus). `ent` and `pos` are required.
---@class PW.BotStimulusData
---@field ent any the enemy the stimulus is about
---@field pos Vector
---@field vel? Vector
---@field time? number default CurTime()
---@field dir? Vector

---A listener of a sound: its state and ears.
---@class PW.BotListener
---@field key any the bot, never hears its own sound
---@field state PW.BotPerceptionState
---@field ear Vector

---A teammate that may receive a sharing.
---@class PW.BotMate
---@field state PW.BotPerceptionState
---@field team integer?
---@field pos Vector
---@field params PW.BotPerceptionParams

---The sender of a sharing.
---@class PW.BotSender
---@field state PW.BotPerceptionState
---@field team integer?
---@field pos Vector

---@alias PW.BotRandomFn fun(): number
---@alias PW.BotValidFn fun(ent: any): boolean

---@class PW.BotPerceptionLib
---@field Config table<string, number> gameplay values: fov, sightRange, memorySeconds, maxTraces, queueSeconds
---@field HearingRanges table<string, number> hearing range per sound kind, units
---@field Tiers table<string, PW.BotPerceptionParams> default parameters per difficulty tier
---@field States table<any, PW.BotPerceptionState> weak, by bot
---@field ParamsFor fun(difficulty: table?, tier: string?): PW.BotPerceptionParams
---@field InFOV fun(eye: Vector, forward: Vector, point: Vector, fov: number): boolean
---@field Visible fun(ctx: PW.BotSightCtx, cand: PW.BotCandidate): boolean
---@field HearingRange fun(kind: string): number
---@field CanHear fun(kind: string, ear: Vector, source: Vector): boolean
---@field HeardPosition fun(pos: Vector, ear: Vector, random: (fun(): number)?): Vector
---@field ReactionDelay fun(params: PW.BotPerceptionParams, random: (fun(): number)?): number
---@field NewQueue fun(): PW.BotReactionQueue
---@field QueuePush fun(queue: PW.BotReactionQueue, now: number, seen: PW.BotSnapshotSet)
---@field QueueRecognised fun(queue: PW.BotReactionQueue, now: number, delay: number): PW.BotSnapshotSet
---@field Remember fun(memory: table<any, PW.BotContact>, ent: any, c: table): PW.BotContact
---@field Decay fun(memory: table<any, PW.BotContact>, now: number, seconds: number?, valid: PW.BotValidFn?): integer
---@field SearchPlan fun(contact: PW.BotContact, opts: table?): Vector[]
---@field DamageStimulus fun(victimEye: Vector, attacker: any, attackerPos: Vector): PW.BotStimulusData
---@field NewState fun(): PW.BotPerceptionState
---@field Clear fun(state: PW.BotPerceptionState)
---@field AddStimulus fun(state: PW.BotPerceptionState, kind: string, data: PW.BotStimulusData): boolean
---@field Dispatch fun(botOrTeam: any, kind: any, data: any): integer
---@field HearSound fun(ears: PW.BotListener[], kind: string, pos: Vector, source: any, rnd: PW.BotRandomFn?): integer
---@field Share fun(sender: PW.BotSender, mates: PW.BotMate[], contact: PW.BotSighting, now: number): integer
---@field Think fun(state: PW.BotPerceptionState, ctx: PW.BotThinkCtx, now: number): PW.BotSighting[]

---@class PW.BotLib
---Feeds a stimulus to a bot or to every bot of a team; returns how many bots got it. A table in place of kind is a
---stimulus with its kind in the field `kind`.
---@field AddStimulus fun(botOrTeam: any, kind: any, data: any): integer
---Five search points around the freshest lost contact of the bot (or of ent): last seen, ahead, left, right, far ahead.
---@field GetSearchPlan fun(bot: any, ent: any?): Vector[]?

---@class PW
---@field BotPerception PW.BotPerceptionLib
