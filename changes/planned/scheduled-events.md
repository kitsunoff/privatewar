# Scheduled events (T-11.16)

Status: `planned`

Recorded: 2026-11-11

The user-approved direction replaces shared schedules with optional playlist-local availability. This record is a
checklist for future work, not a frozen API or authorization to implement runtime changes. Exact rotations, calendars,
map names and content remain unapproved. Existing design and API decisions remain in force until separately changed.

## Scope and prerequisites

- [ ] Obtain explicit implementation authorization and separate approval for the necessary changes to decided design
  and frozen APIs before implementation. Reconcile `design/02-modes.md` d.2–3 and `docs/api/modes.md`, which currently
  define data-only playlists and host-saved JSON, with the proposed Lua methods and any removal of JSON support.
- [ ] Record the approved direction: no JSON playlists and no need for JSON backward compatibility. Existing support
  is real: `addons/privatewar/lua/privatewar/modules/playlists/shared.lua` implements JSON conversion and
  `init.lua` loads and saves host JSON playlists. Removal or migration is future work subject to design/API approval;
  do not claim it is already absent. The older note's JSON-retention proposal is superseded by this direction.
- [ ] Keep the scope playlist-local: no shared schedule kind, event lifecycle or separate offer registry. XP events,
  multiplier stacking and progression effects remain separate future questions, not promised by this task. Preserve
  applicable mandatory test requirements and historical evidence in `TASKS.md`.
- [ ] Decide calendar rules, exact dates and biweekly anchor, UTC boundary and leap-year semantics, clock jumps,
  validation details, map-change failure recovery, and presentation/order of simultaneous and retained rotations
  with the user; do not treat examples as approved calendars.

## Playlist API and data

- [ ] Define the proposed optional Lua method `PLAYLIST:IsActive(nowUTC)`: host-supplied UTC timestamp in, boolean
  availability out, optionally followed by the next UTC change (end when active, start when inactive). No method
  means always available; an omitted or invalid next change is unknown, never guessed. Final return validation is open.
- [ ] Make results deterministic for the same definition/version, UTC time and installed content, independent of
  uptime or selection; different host clocks or installed versions need not agree. Work offline without a service.
- [ ] Isolate predicate exceptions: log and fail closed for that playlist while continuing to evaluate others.
  Playlist authors own required-content checks in `IsActive`; do not introduce an automatic hidden dependency policy.
  Continue standard playlist, enabled-content and map/mode validation independently of availability.
- [ ] Resolve how methods survive or associate with normalization and registry enablement; update approved contracts,
  public annotations and types. Reconcile selection, sampling, start validation and archived `pw_playlist_active`
  with the new availability and entitlement rules.
- [ ] Support static or function-supplied playlist data for `Maps`, `Modes` and `Settings`. Resolve dynamic values
  on the server at startup against installed content and hold them stable; the callable form and explicit reload or
  reevaluation remain open.

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
  Specify map-change failure/recovery separately; do not invent the outcome.
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

All shipped proposed rotations are intended to be periodically available; no exact playlist composition, map pool,
mode settings or schedule is approved. Confirm installed dependencies and feasibility before defining content.

- [ ] Design and, after approval, add Shipment 24/7 weekends.
- [ ] Design and, after approval, add Ground War TDM 32; player count means bot fill capped by server slots, not a
  Lua change to `maxplayers`.
- [ ] Design and, after approval, add Infected, subject to its installed mode/content dependency.
- [ ] Design and, after approval, add Small Map Moshpit.
- [ ] Design and, after approval, add Hardcore.
- [ ] Design and, after approval, add Objective Chaos.
- [ ] Design and, after approval, add Free-for-All Frenzy.
- [ ] Consider One in the Chamber only as a future design/content idea: its required game rules are unimplemented.
  Its playlist is blocked until those rules are separately designed, approved and implemented; do not imply it exists.

## Tests and acceptance

- [ ] Write GLuaTest cases first and retain all applicable mandatory `TASKS.md` cases. Cover absent predicate,
  active/end and inactive/start, unknown and invalid next change, predicate errors/logging and isolation, author-owned
  dependencies, ordinary validation, enabled content, and stable static/dynamic startup resolution.
- [ ] Cover UTC boundaries, biweekly dates including before an anchor, annual/year-wrap and leap years, offline startup
  without replay, repeat evaluation, clock-jump decisions once specified, and host/client authoritative agreement.
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
No runtime implementation or game-test result is claimed by this record.
