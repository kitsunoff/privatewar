# Automatic Search and Destroy support for `de_` maps

Status: `planned`

Recorded: 2026-11-11

## Goal and scope

Offer installed `de_` maps as provisional Search and Destroy (S&D) candidates without reading unloaded BSP contents.
After loading the map, derive team spawns and two approximate bomb sites from its entities. A site may use a radius
rather than reproduce the original brush shape. Authored `MAP.Modes.snd` remains the preferred source. Other Counter-Strike
map types and automatic objective layouts for other modes are out of scope.

The user explicitly approved the design/API revision on 2026-11-11; runtime remains unimplemented and this record
does not grant device/publication permissions. [Approved contract](../../docs/api/feature-contracts.md#snd-map-eligibility-and-activation).
The research in
[notes/27](../../notes/27-snd-de-map-autodetect.md) contains proposals and inferences, not game-test results.

## Decisions and prerequisites

- [x] Design/API revision approved: `03-mapdata.md` d.10 and `02-modes.md` d.10; authored-first, invalid authored
  blocks fallback; mandatory navmesh for humans too; at least one safe spawn per T/CT side. No unrelated modes change.
- [x] Provisional installed de_ maps participate in Custom, playlists and votes, including derived S&D. Validate
  after load; failure returns to usable lobby with a visible reason. No persistent failure cache/retry/substitution.
- [x] Nonempty targetname first; unnamed adjacent AABB grouping at 128 units; reject ambiguity, exactly two sites.
  Deterministic A/B may differ from CS; the API contract fixes technical ordering and bounded safe activation.
- [ ] Obtain explicit permission and confirmation that the Steam Deck is free before any game access or tests. Verify
  the assumptions in notes/27 section 9, especially brush SENT registration timing, entity visibility, world bounds,
  nonblocking behavior, site naming and representative maps. Do not treat inferred engine behavior as established.

## Candidate selection and lifecycle

- [ ] Keep installed-map, junk and enabled-mode checks intact. Use a shared, S&D-specific provisional `de_` rule for
  unloaded maps, including inherited S&D modes, while keeping Domination, Hardpoint and other modes unchanged.
  Evaluate authored mode data first; apply the approved invalid-data policy consistently.
- [ ] Reconcile the client picker, server lobby start, playlists, vote, pending map change and current-map checks.
  Distinguish a provisional candidate from a validated layout; revalidate on the loaded map before playable rounds.
- [ ] Run detection after map entities and required nav data are ready, including map changes and reloads. Retain the
  final S&D start guard. Expose readiness through an approved public seam rather than reading another module's store.
- [ ] On detection or validation failure, return to a usable lobby with a clear player-visible reason; cover both
  pending starts and direct starts. Do not rely solely on server logs or unhandled assertions. Define recovery for
  playlist and vote flows without silently starting an unrelated mode.
- [ ] Keep failures transient: no persistent cache. Rediscover/validate loaded geometry on a later explicit attempt.

## Entity detection and generated data

- [ ] Verify whether a `func_bomb_target` brush SENT must be registered before map entities spawn. If required,
  register an inert server-side class only when no foreign class owns that name; do not override other addons. Check
  effects on every mode and map cleanup/reload, preserve relevant keyvalues and handle disabled targets explicitly.
- [ ] Collect T and CT spawn entities as attacker and defender pools respectively. Validate finite positions and yaw,
  floor, hull and reachability; filter bad candidates and apply the approved per-side threshold. Preserve round side
  swapping and prevent unintended generic/navmesh spawns from crossing sides.
- [ ] Collect target world bounds, account for brush origin and possible multiple or disjoint volumes, and group
  targets into exactly two sites by an explicitly tested, bounded rule. Reject ambiguous, missing or extra sites with
  a useful reason instead of inventing a layout. Do not assume all ports preserve the same entity classes.
- [ ] Implement deterministic A/B identifiers using the contract's group geometry order, independent of enumeration,
  `MapCreationID` and nav place names. Document that labels can differ from Counter-Strike. Consider that
  existing bots attack the first site.
- [ ] Derive grounded, hull-clear, mutually reachable site and approach points, radius and vertical limits with a
  bounded search. Select a safe attacker-side bomb recovery point. Keep all values finite and make the result pass
  `PW.SND.Validate`; approximate circles may extend outside the original brush.
- [ ] Integrate generated data as a lower-priority current-map source through approved contracts. Preserve authored
  map data and base-mode lookup; never mutate registered authored data. Define cache and reload cleanup ownership.
- [ ] Assess activation cost and the current capped per-point graph search on representative maps. If needed, design
  bounded forward/reverse reachability with correct directed edges. Consider navgen seeds for bomb sites separately;
  do not claim improved reachability or performance without measurement.

## Client and verification

- [ ] Replicate public site identifiers and positions authoritatively for HUD markers and late joins; define bounds,
  lifecycle, malformed-data handling and cleanup. Do not expose carrier or dropped-bomb information beyond the existing
  visibility rules. Update the HUD to use actual identifiers rather than assuming hard-coded labels.
- [ ] Write GLuaTest cases first and preserve mandatory T-11.12 and other applicable `TASKS.md` cases. Cover candidate
  filtering, inheritance and unrelated modes; authored priority and invalid authored policy; site grouping, naming,
  ambiguous layouts, blocked points, geometry limits, finite input, spawn filtering, bomb point and output validation.
- [ ] Cover foreign SENT ownership, readiness and reload, directed/one-way reachability, client/server eligibility,
  public snapshot validation and cleanup, lobby/vote/playlist/map-change flow, and player-visible failure recovery.
  Test absence of persistent failure storage and fresh detection on subsequent explicit attempts.
- [ ] Run `nix develop --command make check` and `nix develop --command make test` with pipefail before merge. Game
  tests require explicit permission and a confirmed-free Deck. Record actual commands, results and skipped checks.
- [ ] At a human checkpoint, inspect representative CS:S `de_` maps including stacked sites, a Workshop port and a map
  without navmesh. Check A/B labels, spawn fairness, approximate plant boundaries, bot navigation and objectives,
  HUD, multiplayer/late join, failure messages and activation performance. Record human acceptance separately.

## Evidence

Research: [notes/27-snd-de-map-autodetect.md](../../notes/27-snd-de-map-autodetect.md). It reports code and external
source inspection only: no Deck, in-game, GLuaTest or performance runs. No implementation or acceptance is claimed.
