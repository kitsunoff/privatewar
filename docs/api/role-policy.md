# Temporary role policy

Generic, optional policies. No built-in owner tests a mode id. Missing providers preserve ordinary play.
Questions follow first-non-nil dispatch, active mode last; notifications must return nothing.
Types: `lua/privatewar/types/role_policy.lua`. Regression tests: `role_policy.lua`.

## Items and effects

- `PW_CanUseLoadoutKind(ply, kind) -> boolean?`: exactly false rejects equipment equip/use/grant,
  perk refresh, wildcard equip and streak grant/earning/activation. Kinds are `equipment`, `perks`,
  `wildcards`, `streaks`. Saved classes are never modified.
- Server `PW.Perks.Revoke(ply)`: remove only that owner's instances and cached modifiers.
- Server `PW.Equipment.Revoke(ply)`: end instances, cancel cooking without a throw, remove held grenade
  weapons/ammo and previous-weapon state. Delayed grants and switch callbacks cannot cross generations.
- Server `PW.Streaks.EndEffects(ply)`: end only the owner's active instances/effects; keep unused inventory.
- Server `PW.Streaks.Revoke(ply)`: end effects and clear only this owner's progress, inventory and set.
- `PW.Reveal(viewer, targets, duration, owner?)` retains at most 128 unexpired pulses for effect cleanup.
  Built-in UAV supplies its owner. Revocation clears the derived client radar and replays only surviving
  sources for their remaining lifetime. Relationship reset clears all old-side radar/jam caches; remaining
  active sources acquire new information normally. Server-to-client `pw_reveal_reset` has no payload and
  no client request handler. No new enemy coordinates are disclosed by a reset.
- `PW_RoundPreparing`: equipment revokes current life items, streaks end active effects but retain unused
  earned inventory. This never globally clears unused streaks between ordinary rounds.

## Admission and quota

- `PW_CanJoinInProgress(ply) -> boolean?`: exactly false holds a LIVE join, human or bot, as a spectator.
  The ordinary `lobby.joininprogress` setting remains the fallback. Reconnect identity/life policy belongs
  to the mode's own roster, not to the lobby module.
- Server `PW.Jip.Admit(ply) -> boolean`: explicitly release a held spectator and cancel its deferred
  parking. Does not spawn or assign a playable team; false if not held.
- Server `PW.Teams.PlaceLate(ply) -> integer?`: validated LIVE late placement through the teams owner.
  Managed modes use `PW_SelectLateTeam`, without balanced fallback for nil/false/invalid answers.
  An admitted next-round roster must exist before requesting placement; use `Transition` for an already
  admitted member's role change. No addon calls SetTeam or another owner's private stores.
- `MODE.BotQuotaPolicy = "rounds"`: freeze quota creation/kicks during LIVE except at
  `PW_RoundPreparing`, before child preparation. Waiting humans count at that boundary. `continuous`
  preserves ordinary quota. Absent policy defaults to rounds for managed team modes, continuous otherwise.
  New bots still go through the same admission question, so they cannot spawn playable before roles exist.

See [teams](teams.md), [player overrides](player-overrides.md) and [operators](operators.md) for synchronous
relationship resets, post-base new-life stats and temporary appearance.

`PW_ObjectiveInvalidated(id, revision)` also synchronously ends matching running or suspended brain
`objective` frames. The objective owner records the visit in `ctx.state.id` / `ctx.state.revision`; normal
`OnEnd` releases the action's owned input bits. Old revisions and duplicate invalidations are no-ops.
Commander remains the sole owner of orders and hunt slots; no foreign state is cleared by the brain.
