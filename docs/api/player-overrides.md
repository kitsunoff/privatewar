# Player overrides API

Status: implemented after scoped GLuaTest RED; generic API frozen by the orchestrator.
Generic optional module `player_overrides`; types `lua/privatewar/types/player_overrides.lua`.

- Question `PW_PlayerOverrides(ply) -> PW.PlayerOverrideProfile?`: finite positive `maxHealth`,
  `spawnHealth` (at most maxHealth), `walkSpeedMult`, `runSpeedMult`; omitted fields are ordinary.
  Standard first-non-nil dispatch, active mode last. Validate the entire profile before mutation.
- `PW.PlayerOverrides.Refresh(ply) -> boolean, string?`: apply relative to ordinary baseline, never
  multiply already-modified speeds. A living refresh never heals or refills current health.
- `PW.PlayerOverrides.Release(ply) -> boolean`: restore baseline maximum and walk/run; clamp living
  current health down to restored maximum, never increase it. Dead release never revives. Returns
  false when no override was held. Missing provider releases any held override.
- `PW_PlayerSpawned(ply)` is a synchronous notification from `PW.MatchRules.Spawn`, **after** ordinary
  engine spawn initialization/loadout, before that public spawn call returns. Capture ordinary
  maximum/current health and walk/run once per new life before overrides; apply spawnHealth once.
  A new life replaces the old baseline even without a prior Release; never restore old-life current HP.
  No timer or one-tick 100-versus-400 HP window is allowed. External engine-spawn paths require a
  separately agreed owner integration, not a competing PlayerSpawn hook.
- Match end/abort releases all held overrides; next-round preparation commits roles before spawning.
  No saved class/operator setting, jump or damage value is modified.
- Model appearance stays owned by operators: `PW_PlayerModelOverride`, `PW.Operators.Refresh`
  ([operators](operators.md)). No competing PlayerSetModel hook or private-store access.

The Infection provider supplies max/spawn health 400, walk/run multipliers 1.15 for either actor type.
Jump and stock `weapon_fists` damage remain unchanged. These are role rules, never bot-only bonuses.
Tests: `player_overrides.lua`, `infection_presentation.lua`; no runtime/model availability pass is implied.
