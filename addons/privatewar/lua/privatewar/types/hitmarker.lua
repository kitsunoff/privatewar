---@meta
-- Types of the hitmarker (T-6.3, 09-hud.md d.2). Source: lua/privatewar/modules/hitmarker/ (shared.lua: pure rules;
-- init.lua: server glue; cl_init.lua: the receiver) and lua/privatewar/hud/hitmarker.lua (the drawing).

---What a hit was, weakest first. A kill (also by a headshot) outranks a headshot, a headshot outranks a hit.
---@alias PW.HitKind "hit"|"headshot"|"kill"

---Plain facts about one damage event.
---@class PW.HitFacts
---@field attacker any the damage attacker (anything: world, NPC, player)
---@field victim any
---@field dmg number damage after scaling
---@field killed boolean the victim died of this damage
---@field hitgroup integer HITGROUP_* of the victim (HITGROUP_GENERIC for non-players)

---Internal (server): hits of the current tick waiting to be sent.
---@class PW.HitmarkerStore
---@field pending table<any, PW.HitKind> strongest kind per attacker
---@field send fun(ply: any, kind: integer) sends the wire value
---@field defer fun(fn: fun()) runs fn at the end of the tick

---@class PW
---@field Hitmarker? PW.HitmarkerLib the hitmarker module (nil when the module is missing)

---Hitmarker module. Wire: server to client message "pw_hitmarker", one UInt(2): 1 hit, 2 headshot, 3 kill.
---@class PW.HitmarkerLib
---Seconds a marker takes to fade out.
---@field Duration number
---Pure: the kind of a damage event, nil when it neither hurt nor killed. A kill outranks a head hit.
---@field _Classify fun(facts: { dmg: number, killed: boolean, hitgroup: integer }): PW.HitKind?
---Pure: the stronger of two kinds (nil is the weakest).
---@field _Merge fun(a: PW.HitKind?, b: PW.HitKind?): PW.HitKind?
---Pure: kind to wire value 1..3.
---@field _Encode fun(kind: PW.HitKind): integer
---Pure: wire value to kind; nil outside 1..3.
---@field _Decode fun(value: integer): PW.HitKind?
---Pure: fade alpha 0..1 of a marker of the given age: 1 at age 0, falling linearly to 0 at the duration.
---@field _Alpha fun(age: number, duration: number): number
---Pure: true when the attacker is told: a valid human player that is not the victim.
---@field _Eligible fun(attacker: any, victim: any): boolean
---Server: a store over injected engine calls (send, defer); defaults are net.Send and timer.Simple(0).
---@field _NewStore fun(opts?: { send?: fun(ply: any, kind: integer), defer?: fun(fn: fun()) }): PW.HitmarkerStore
---Server: records one damage event; the first hit of an attacker in a tick schedules the flush that sends one
---merged marker. Returns true when the event was recorded.
---@field _Handle fun(store: PW.HitmarkerStore, facts: PW.HitFacts): boolean
---Client: the marker being shown (kind and the CurTime it started); nil kind when none.
---@field Current { kind: PW.HitKind?, at: number }
---Client: starts a marker now (the receiver of the message).
---@field _Show? fun(kind: PW.HitKind, now: number)
