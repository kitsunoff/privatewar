# Scheduled events (T-11.16)

Status: `in-progress`

Recorded: 2026-11-11

The user-approved direction replaces shared schedules with optional playlist-local availability. The checklist below
retains the original implementation/acceptance inventory, not proof of completion. The user approved the revision and replacement of the
mandatory playlist JSON tests: [contract](../../docs/api/feature-contracts.md#lua-playlists-and-availability),
`02-modes.md` d.2–3, d.9 and TASKS.md T-2.6. The integration branch now contains the infrastructure candidate and
shipped content below; engine verification remains pending. The user explicitly delegated concrete rotations,
calendars, installed maps and schema settings on 2026-11-11. No device/publication permission is implied.

## Current implementation and blockers

Owner/scope: integration content work on the existing Lua-playlist implementation; no Deck or publication access.
The previous infrastructure checklist remains historical/pending verification rather than being checked from
static inspection alone. Concrete policy and dependency details: [shipped playlists](../../docs/playlists.md).

- Added six periodic definitions: Shipment weekends, Ground War TDM 32, Infected, Small Map Moshpit,
  Objective Chaos and FFA Frenzy. Wednesday has three immediately active stock-content rotations.
- Startup resolution filters installed eligible map/mode pairs; missing optional content rejects only its entry.
  Availability rechecks dependencies without publishing known upcoming boundaries for empty content.
- Review correction: both checks delegate mode dependency admission to `PW.Match._CheckDependencies`;
  `playlists_dependencies.lua` covers applied soft toggles, hard failures/repair, Base inheritance and core's
  nonrecursive declaration semantics. All five cases passed a pure Lua smoke using real core registry/checker/
  enable code with mocked engine glue, not GLuaTest. Pending ConVar changes retain core's boot/new-match timing.
- Follow-up review correction: server default sampling also runs the core dependency checker. A tests-first real
  `Pick` regression with RNG=0 fails before the fix and passes after it in the pure Lua harness; all six dependency
  cases pass with actual server store/sampling/core code and mocked engine glue. Partial DOM loss selects
  Hardpoint, restoration selects DOM again, total loss returns no pair and a plain TDM playlist stays unaffected.
  No replacement `fits` predicate is injected; engine GLuaTest remains unobserved.
- Added `playlists_content.lua` tests first, retaining all mandatory infrastructure suites unchanged.
- Hardcore is blocked on absent gameplay/schema, not on calendar choice. No fake mode/map or unsupported
  setting is shipped. Shipment still requires a mounted matching BSP; Infection requires its optional addon.
- `nix develop --command make check` passed (537 source files; all gate selftests). Pure Lua smoke passed for
  six compositions, UTC boundaries and missing content; actual source schema/index/validator smoke accepted all
  11 shipped setting overrides without clamping, including inherited FFA ids. These are not GLuaTest results.
  Engine RED/GREEN and `make test`
  remain unobserved because this content task explicitly forbids Deck access; merge/acceptance gates are incomplete.

## Scope and prerequisites

- [x] Design/API changes explicitly approved: playlist-local Lua predicates/startup resolvers, UTC, outside-match
  evaluation, one expired selected start then lobby; no shared schedules or XP feature. Exact calendars deferred.
- [x] Lua-only playlist storage and replacement mandatory tests approved. Remove all playlist JSON read/write and
  conversion APIs without migration; never delete/rewrite user files. Other mandatory cases and JSON remain.
- [x] Integration candidate replaces playlist JSON conversion/load/save with Lua resolution in
  `addons/privatewar/lua/privatewar/modules/playlists/`. User files remain untouched. This is inspected code,
  not an engine pass; the older note's JSON-retention proposal is superseded by this direction.
- [ ] Keep the scope playlist-local: no shared schedule kind, event lifecycle or separate offer registry. XP events,
  multiplier stacking and progression effects remain separate future questions, not promised by this task. Preserve
  applicable mandatory test requirements and historical evidence in `TASKS.md`.
- [x] User delegated concrete calendars/content/settings and installed-map choices. Shipped weekly/daily UTC
  windows need no annual/leap-day policy. Existing integration ordering is unchanged, not a new UI redesign.

## Playlist API and data

- [ ] Implement the approved optional Lua method `PLAYLIST:IsActive(nowUTC)`: host-supplied UTC timestamp in, boolean
  availability out, optionally followed by the next UTC change (end when active, start when inactive). No method
  means always available; an omitted or invalid next change is unknown, never guessed. Apply the API's finite,
  strictly-future boundary validation and fail-closed nonboolean/error handling.
- [ ] Make results deterministic for the same definition/version, UTC time and installed content, independent of
  uptime or selection; different host clocks or installed versions need not agree. Work offline without a service.
- [ ] Isolate predicate exceptions: log and fail closed for that playlist while continuing to evaluate others.
  Playlist authors own required-content checks in `IsActive`; do not introduce an automatic hidden dependency policy.
  Continue standard playlist, enabled-content and map/mode validation independently of availability.
- [ ] Resolve how methods survive or associate with normalization and registry enablement; update approved contracts,
  public annotations and types. Reconcile selection, sampling, start validation and archived `pw_playlist_active`
  with the new availability and entitlement rules.
- [ ] Support static or function-supplied playlist data for `Maps`, `Modes` and `Settings`. Resolve dynamic values
  on the server at startup against installed content and hold them stable; the callable form is fixed in the API.
  Explicit hot-reload/reevaluation policy remains open; do not add a public reload promise implicitly.

## Timing, selection and votes

- [ ] Evaluate availability at host startup without replaying missed transitions. In the lobby and other non-match
  states, detect changes within one minute, including unknown-next-change predicates; assume an accurate host clock
  and responsive process, not execution while the host is shut down. A known-boundary timer plus polling is only
  a possible implementation, not an approved API.
- [ ] Never evaluate `IsActive` during a running match, including timers and polling. No one-minute guarantee applies
  during a match. After completion, freshly reevaluate before deciding the next flow or vote.
- [ ] Keep a playlist selected before expiry visible and allow one match to start after expiry, without marking it
  generally active. The entitlement lasts in the current lobby until another playlist or Custom Game is selected;
  it does not survive server restart. Preserve the ability to finish that match across a map change while starting.
- [ ] Let a match running at expiry finish normally, then return to the lobby without continuing the expired rotation.
  Follow the API's one-shot pending-attempt failure handling; no expired automatic retry.
- [ ] Keep votes outside running matches. Check availability within one minute during a vote and revalidate before
  launching the next match; if the playlist expires during the vote, return to the lobby without starting another match.

## UI and network

- [ ] Show all concurrently active rotations and Custom Game last, including when no rotations are active. Show an
  upcoming rotation only when its next start is known and within 48 hours; never invent an unknown start. Preserve
  visibility of an entitled expired selection; settle ordering and visual treatment with the user.
- [ ] Show the remaining availability time for active rotations when their end time is known.
- [ ] Design server-authoritative availability and selection snapshots, replication and client refresh timing; clients
  follow host session state. Reconcile existing `pw_playlist_request`, `pw_playlist_list`, `pw_playlist_pick`,
  `pw_playlist_start`, lobby UI and map-change contracts in `docs/api/modes.md` and `docs/api/ui.md`.
- [ ] Validate privileges, phase, rate, payload and current availability/entitlement on the server for pick and start;
  do not trust client state or use `net.WriteTable`. Preserve Custom Game access and normal start validation.

## Proposed content

The original proposed inventory is retained below. The user has now delegated concrete compositions, pools,
settings and calendars within existing content; see the implementation policy above. Checkboxes do not imply
runtime or human acceptance.

- [x] Add Shipment 24/7 weekends with installed-BSP discovery and eligibility filtering.
- [x] Add Ground War TDM 32; player count means bot fill capped by server slots, not a
  Lua change to `maxplayers`.
- [x] Add Infected, subject to its installed mode/content dependency.
- [x] Add Small Map Moshpit.
- [ ] Add Hardcore: blocked on absent real gameplay/schema; do not substitute ordinary TDM.
- [x] Add Objective Chaos.
- [x] Add Free-for-All Frenzy.
- [ ] Consider One in the Chamber only as a future design/content idea: its required game rules are unimplemented.
  Its playlist is blocked until those rules are separately designed, approved and implemented; do not imply it exists.

## Tests and acceptance

- [ ] Write GLuaTest cases first and retain all applicable mandatory `TASKS.md` cases. Cover absent predicate,
  active/end and inactive/start, unknown and invalid next change, predicate errors/logging and isolation, author-owned
  dependencies, ordinary validation, enabled content, and stable static/dynamic startup resolution.
- [ ] Cover UTC boundaries, offline startup without replay, repeat evaluation, forward/backward sampled clock jumps
  and host/client authoritative agreement. Biweekly/annual/leap-day calendar fixtures wait for approved author policy;
  use synthetic availability boundaries for the infrastructure tests, not invented shipped calendars.
- [ ] Cover transition detection within one minute outside matches, including unknown next changes; assert zero
  predicate evaluations during a running match and a fresh evaluation before post-match flow or vote.
- [ ] Cover concurrent active rotations, Custom Game last and the empty-active case, the 48-hour boundary, unknown
  upcoming starts, retained selection, one post-expiry start, normal match completion and return to lobby.
- [ ] Cover entitlement replacement, restart, map change while starting and specified failure recovery; cover voting
  outside matches, one-minute checks, revalidation and expiry during a vote without launching a match.
- [ ] Cover approved normalization, API, network, selection/start validation and JSON removal behavior; do not require
  JSON backward compatibility. Test any explicitly approved reload behavior without inventing an outcome.
- [ ] Run the required `nix develop --command make check` and `nix develop --command make test` gates with pipefail
  before merge; game tests require explicit permission and confirmation that the Steam Deck is free.
- [ ] Stop at a user checkpoint for in-game UI, controller/input, multiplayer synchronization, expiry and vote flow;
  record user acceptance separately. Automated results do not replace human acceptance.

## Evidence and links

See the [draft and future tests](../../notes/26-scheduled-events.md); its JSON-retention statement is superseded as
noted above, and its examples are not approved calendars. The
[T-11.16 deliverable and status](../../TASKS.md#class-visibility-implementation-and-future-scheduling-request) are
historical; their shared-schedule direction is superseded, but mandatory test requirements remain in `TASKS.md`.
The integration branch contains implementation candidates, not a game-test result. Design/contract evidence:
the approved 2026-11-11 revision, delegated concrete content and mandatory clauses; unchecked items retain their
original implementation/verification inventory and are not undecided alternatives to approved contracts.
