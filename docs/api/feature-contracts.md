# Approved feature contracts: S&D detection, scheduled playlists and bot chatter

Status: approved design/API revision, 2026-11-11; **not implemented or game-verified**.
Explicit user approval covers these design changes and the playlist JSON mandatory-test replacement only.
This file supersedes conflicting legacy descriptions in `map.md`, `modes.md`, `ui.md` and `core.md` for these
features. Unmentioned APIs, gameplay, validation, privilege and mandatory tests are unchanged.

## S&D map eligibility and activation

Sources: `design/02-modes.md` d.10, `design/03-mapdata.md` d.10. Owner: mapdata stores/queries opaque generated
mode data; S&D detection/validation owns its geometry. No generic objective fallback is introduced.

### Public seam (to implement)

- `PW.Map.ModeFits(mode, mapName) -> boolean, string?, string?` preserves the existing first two returns.
  The third is `"authored"`, `"provisional"`, `"generated"` or nil when rejected/not applicable. It is an eligibility
  query, **not** a playable-start guarantee. Existing two-return callers remain compatible.
- `PW.Map.GetModeReadiness(modeId) -> state, reason?` is server-only for the current map, with state
  `"pending"`, `"ready"` or `"rejected"`. Pending never permits playable spawning. Rejected carries a nonempty
  player-safe reason. Callers do not inspect a detector's private store.
- `PW.Map.GetModeData(modeId)` retains authored Base lookup and returns generated current-map data only when
  there is no authored entry and detection is ready. It never supplies geometry for an unloaded map.
  Present non-table authored values are invalid, not absent. The first existing authored entry blocks fallback
  even if structurally invalid. Do not mutate any returned table.

Installed-map/junk/enable/dependency checks remain at their normal owners. The S&D-specific exception follows
the resolved Base chain to `snd`, not a name substring and not every `round_base` child. For unloaded maps:
structurally valid authored data first; absent authored data plus `de_` gives provisional eligibility; invalid
authored data rejects. On the loaded map pending may remain selectable but start waits; rejection is not a
validated candidate. Replicate the same classification/reason to clients, including late joins.

Every route (Custom, playlist, normal/privileged vote pick, same-map start, pending-map restore, rotation) uses
this policy. After load, before PREMATCH can produce playable bodies, resolve readiness and run S&D activation
checks. A detector/activation error cancels the pending start/rotation, removes owned transient state and returns
to LOBBY on the loaded map with a player-visible reason and a usable picker. No retry, same-mode repeat,
unrelated-mode substitution or automatic nav generation. A later explicit attempt may redetect; no disk failure
cache. Runtime failure evidence is not permanent map eligibility metadata.

### Detection rules

1. Capture entities only after InitPostEntity; after reload rebuild once from current entities/nav readiness.
   During nav generation readiness is pending, never ready. Keep the final activation guard at every start.
   If `func_bomb_target` needs an inert server SENT, register before entity creation only if no foreign class owns
   it; do not detour or overwrite that class. Missing/unsafe source data rejects with a reason.
2. Use `info_player_terrorist` for side 1 and `info_player_counterterrorist` for side 2. Filter nonfinite/out-of-world,
   unsupported ground, standing-hull blocked and unreachable positions; finite yaw is required. At least one safe
   spawn per side, even for human-only play; navmesh is mandatory. Never merge generic/nav spawn fallback into
   these pools. Existing side swaps use these side indices, not persistent cohorts.
3. Targets supply finite, ordered **world** AABBs and targetnames. A nonempty targetname forms one group by exact
   string equality. Never merge different named groups by proximity. Unnamed targets form connected components
   using AABB minimum Euclidean separation <= 128 units (touch/overlap = 0). Compute gaps on x/y/z, then their
   Euclidean norm; this includes vertical separation, not only XY. An unnamed component adjacent to any named
   group is ambiguous and rejects rather than guessing membership. Named groups may contain disjoint brushes:
   targetname, not proximity, determines their membership. Reject a result other than two groups, and reject
   geometry that cannot yield two safe unambiguous plant volumes at activation (including overlapping sites).
   This conservative rejection is a technical ambiguity rule, not a guarantee that all CS ports are supported.
4. Sort the two groups by union-AABB center `(x, y, z)` lexicographically; tie-break by union bounds, then targetname.
   Indistinguishable keys reject. Assign A then B; enumeration order and randomness cannot change labels. Labels may
   differ from CS. No dependency on nav place names, entity index or MapCreationID ordering.
5. Generate the existing S&D shape: exactly two `{ id, pos, radius, above, below, approach }` sites, `bomb` and
   `spawns[1]`, `spawns[2]`. Finite positive radius, nonnegative vertical extents; safe grounded/hull-clear plant
   and approach points inside each cylinder, safe attacker-side initial/recovery bomb point. Approximate cylinders
   need not reproduce brushes. Validate with `PW.SND.Validate` plus current-world ground/hull/LOS and mutual
   **directed** nav reachability among usable spawn/site/bomb points. Never substitute undirected connectivity.
   Bound search work and reject exhaustion; exact geometric sampling/caps are implementation details to document
   and test, not grounds to bypass safety or invent valid points.

Generated tables live only in the current-map owner, not registries/disk; invalidate on cleanup/reload, rebuild
before reuse and never retain stale entity/nav handles. Public site snapshot: match/map generation, serial and
exactly two stable ids/positions; finite coordinates, bounded ids and stale/malformed rejection, reset on cleanup
and new generation. Extend the authoritative S&D snapshot to carry these fields before HUD consumption; no client
geometry submission. Public sites do not authorize disclosure of carrier/drop/enemy information: existing
recipient-specific `pw_snd_state` visibility and restricted spectator rules remain mandatory.

## Lua playlists and availability

Sources: `design/02-modes.md` d.2–3, d.9. Owner: playlists; vote/core/lobby consume its public state.
The old JSON contract and JSON-specific mandatory tests are explicitly superseded, not silently waived.

### Definition and normalization

- Kind `playlists/`, `PLAYLIST`, `Subscribe = "never"`; `Name` remains required string. `Modes` must accept table
  **or function**, so remove the old table-only Required constraint and validate the union in playlists.
- `Modes = table<string, number> | function(self) -> table<string, number>`;
  `Maps = string[] | function(self) -> string[]? | nil`;
  `Settings = table<string, any> | function(self) -> table<string, any>? | nil`.
  Functions run server-side once per definition per startup, with no client arguments, after registries/settings
  and required content are ready. Resolve in Modes, Maps, Settings order, copy and run ordinary Normalize validation.
  Absent Maps still means curated fitting maps; absent Settings becomes `{}`. Exceptions/invalid outputs reject
  only that entry with a readable log. No function serialization, repeated sampling evaluation or uptime dependency.
- `PW.Playlist.Normalize(resolvedData, facts?)` remains pure and applies all existing name/id/weight/map/settings
  constraints. `PW.Playlist.Resolve(definition, facts?) -> data?, reason?` runs startup resolvers and Normalize.
  Keep the source definition associated server-side for its availability method; never lose it by copying only data.
- `PLAYLIST:IsActive(nowUTC: number) -> boolean, number?`: host UTC Unix seconds. Absent method = true, nil.
  Nonboolean first return or exception = inactive, unknown boundary, invalid evaluation; log the failure without
  disabling other entries. Retained expiry entitlement cannot bypass an invalid evaluation. A valid false result
  represents ordinary inactivity; an invalid next-change alone does not invalidate a boolean result.
  Next-change must be finite and strictly greater than now, otherwise unknown, without changing a valid first return.
  Active means next end; inactive means next start. No guessed boundary, required-content or entitlement rule.
  Author checks installed content in this method; normal enabled-mode/map/settings validation is independent.
  For the same definition/version, UTC time and installed content, the result is deterministic and independent
  of selection/uptime. Different host clocks/content versions need not agree; no online service is required.
- Resolved pools/settings remain stable for the session. No new public hot-reload/reevaluation contract is approved;
  dependent explicit-reload behavior must be settled before adding it. Weighted sampling and vote exclusions remain.
- `FromJson`, `ToJson`, `FileId`, `LoadDir`, `Save`, playlist `Version` and `DataDir` are removed, not compatibility
  wrappers. `GetList`/`Get` expose only enabled, validated Lua entries (`source = "lua"`). Never scan, read, write,
  migrate, delete or rewrite user playlist JSON; leave files byte-for-byte untouched. Other JSON storage is unchanged.

### Time and state machine

`PW.Playlist.RefreshAvailability(nowUTC)` evaluates only outside PREMATCH/LIVE/POSTMATCH; those phases are the
running-match interval for this contract, including intermissions. Poll at least every 60 seconds in LOBBY/VOTE
and at startup; a known-boundary timer may supplement but never replace unknown-boundary polling. Reevaluate
only outside the running-match interval even when startup is restoring an accepted pending start. Startup data
resolution may run then, but availability evaluation waits until the next non-match boundary. Reevaluate
immediately after match completion, before the core chooses vote/rotation. No missed-transition replay. On clock
jumps use the next actual UTC sample (forward skips missed intervals, backward recomputes current availability);
neither replay nor match-time predicate calls. The 60-second bound assumes a responsive process/accurate host clock.

Selection/start requests require ordinary permission/phase validation plus current availability or the selected
entry's retained entitlement, never a failed predicate evaluation. A new inactive entry cannot be selected.
A playlist selected while active remains
selected/visible after expiry and has one post-expiry start in the same lobby; selecting Custom or another entry
clears it. Reselecting the same expired entry cannot replenish it. Expiry of a playlist not selected grants nothing.
`Pick(id)` retains its sampling return type; actual selection is `SetActive(id) -> boolean, string?`, enforcing these rules
as well, rather than merely writing a ConVar. Custom is still the empty id. All server/net selection paths use that boundary.

Reserve/consume the one-shot entitlement only when the normal start request is accepted. Carry that accepted
attempt through pending map state, bound to the existing pending map/count/age/version validity checks and target
playlist/mode/map; it is not a reusable archived flag. Rejected preflight consumes nothing. An accepted attempt
that fails activation returns to lobby and does not refund an expired entitlement. Restart never restores an idle
lobby entitlement; pending-start continuation is the narrow existing one-shot map-change path, not generic recovery.
An expired selected playlist may stay visible without entitlement but Start must reject it. `pw_playlist_active`
alone is never proof of entitlement; an archived inactive id cannot resurrect permission.

A match starting while active or using the one-shot grant finishes normally. Fresh post-match availability false
returns to LOBBY, never automatic rotation. During VOTE refresh within 60 seconds and immediately before accepting
the result/privileged launch. Expiry cancels to LOBBY without starting another match; a vote does not use the lobby
one-shot grant. This overrides legacy empty-vote/same-mode-repeat paths when availability or S&D validation fails.

### Public state and UI integration

`PW.Playlist.GetAvailability(id) -> { active: boolean, valid: boolean, nextChange?: number }?` and
`PW.Playlist.GetSelection() -> { id: string, retained: boolean, canStart: boolean }` are server-owned cached queries;
they do not evaluate predicates. Selection canStart is availability/entitlement only, not a promise of map validity.
Clients consume authoritative list snapshots, not local clocks/predicates. Extend `pw_playlist_list` with a
versioned bounded explicit-field payload: serial, sampled UTC time, selected id, selection retained/canStart,
per-entry id/name/summary/fill/active/valid/optional nextChange and receiver canPick. No Lua/functions/profiles on wire.
Broadcast changed availability/selection to all humans, support initial request and late join, discard stale or
malformed snapshots. Request phases include VOTE; pick/start retain LOBBY-only privileges/rate/length checks.
Start refusals and activation failures must reach the UI, not just logs; no new unvalidated client commands.

Model all concurrent active entries, retained selection even when expired, upcoming entries only with known start
`0 < nextChange - now <= 48 * 3600`, and Custom last. Active known end shows countdown; unknown is not zero.
Do not invent exact calendars, shipped compositions, biweekly anchors or annual/leap-day author policies.
Ordering/visual treatment among playlist cards and concrete wire encoding/version constants remain integration
details to freeze with their implementation; this file fixes required state and validation, not an invented codec.

## Optional Lambda content boundary

Sources: `design/06-progression.md` d.7, `design/12-audio.md` d.1–3. PW owns chatter decisions/lifecycle and the
adapter consumes installed data only. No addon-specific entity method is a Player API; no code/assets are copied.

- Core events are idle, enemy spotted, kill, death. Use normal perceived contact transitions (not every perception
  tick) and authoritative confirmed kill/death events, once per current-life event. No event creates new bot knowledge.
  Idle/spotted/kill require a living admitted bot during LIVE; death may use the just-ended admitted life once.
- Identity/profile selection stays stable across respawns, with unique safe names and built-in fallback for absent
  addon/content/profile. Missing client sound falls back locally or stays silent; never auto-download/distribute.
- Spatial voice follows the bot at event time, not a UI/global nonspatial sound; common chat is visible to all
  ordinary chat recipients, with no hidden enemy coordinates and no team/dead-chat channel introduced.
- Text is bounded plain UTF-8; reject control/command injection and unsafe paths. No RunString, executable
  placeholders, shell, URLs fetched as assets or path traversal. Do not add semantic/toxicity/identity filtering
  for installed lists; built-in-name restrictions remain confined to built-in content.
- Apply finite per-bot and global cooldowns and concurrent-voice caps, bounded queues and no catch-up burst.
  Stop/release owned playback/queued events on disconnect, match end, disable and reload; death gets only its
  permitted one-shot reaction, not stale idle/combat messages. Do not read foreign private stores or scan content
  in hot loops. Clients cannot select arbitrary paths/text or forge bot events.

**Blocking unapproved choices:** supported installed versions/data paths and profile formats; identity/voice/text
binding and template grammar; exact server/client opt-in defaults; cooldown values, concurrent cap and audibility
distance/settings. These are not license approval to redistribute, new content-filter requirements, or permission
to infer defaults from Lambda. Freeze these before dependent APIs/code. Announcer/music remains separate draft work.

## Verification boundary

TASKS.md defines mandatory additions and the narrow T-2.6 replacement. Existing T-11.12, other objective-mode,
spawn, navgen, pending-map JSON, privilege/network, bot fairness/name and UI cases are retained unchanged.
This document supplies contracts only: no new test bodies, RED/GREEN, native assumptions, performance evidence or
human checkpoint passes. Engine entity capture, nav geometry, spatial playback/content mounting, UI/controller,
P2P and performance require authorized game verification; no Deck access is authorized by this revision.
