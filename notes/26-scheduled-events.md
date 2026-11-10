# Scheduled playlist availability

Status: user-approved direction, documentation-only draft. Not implemented, not a frozen API or schema, and no
runtime work is authorized. Existing decisions in `design/` and frozen APIs still apply until separately changed.

## Playlist-local availability

A Lua playlist may optionally define `PLAYLIST:IsActive(nowUTC)`, returning a boolean and optionally a UTC timestamp
for its next change: the end if currently active, or the next start if inactive. Without the method the playlist is
always available. An omitted next change is unknown, not an invitation to guess. The host supplies UTC time; the
same definition/version and clock should give deterministic results offline, independent of uptime or selection.
Different clocks or installed versions cannot guarantee agreement.

This is a method on a Lua playlist definition, not a JSON field or executable JSON. Host-saved JSON playlists will not
have schedules; existing JSON playlist support is not being removed. No generic schedule kind, event lifecycle,
`OnEquip`/`OnUnequip`, or separate registry of offers is proposed
for this task. XP events are a separate potential future topic; no XP design or implementation is promised here.

If `IsActive` errors, fail closed for that playlist, log the error and continue evaluating other playlists. An invalid
optional second return is treated as an unknown next change.

Playlist authors own checks for required installed content in `IsActive`; no automatic hidden dependency policy is
proposed. Standard playlist validation still applies, and exceptions must be isolated rather than affecting other
playlists.

All shipped proposed playlists are intended to be periodically available. Illustrative ideas include a Shipment 24/7
weekend, TDM 32, Infection and fun moshpits. Their actual content, calendars and map names are not decided.

As an additional draft, `Maps`, `Modes` and `Settings` could each be static or supplied by a function. The server
would resolve dynamic data at startup based on installed content and hold the resolved data stable. Whether an explicit
reload or reevaluation is supported remains open, as do the method and form of this mechanism. This is not a frozen API.

## Host evaluation and presentation

The host evaluates at startup and tracks changes within one minute of their UTC boundary in the lobby or another
non-match state; five-minute polling is insufficient there. `IsActive` is never evaluated while a match is running,
including by timers or polling. After the match completes, the host freshly reevaluates before deciding the next flow
or vote. A known-next-change timer plus at-most-one-minute reevaluation for unknown boundaries outside matches is one
possible approach, not a frozen implementation. No one-minute expiry guarantee applies during a match. This assumes an
accurate host clock and a responsive process; offline means no central service, not transitions while the host is shut
down. Startup evaluates current availability without replaying missed transitions. Clients follow the host's
authoritative session state.

- The main-menu playlist list shows all concurrently active rotations, with Custom Game at the bottom and available
  even when none are active.
- Show an upcoming rotation only if its next start is known and within 48 hours; never guess an unknown next start.
  Ordering and presentation details remain open.
- A rotation selected before expiry remains visible and permits one match started after expiry. A match already
  running at expiry finishes normally; afterward return to the lobby without the expired rotation rather than
  continuing it. The entitlement lasts within the current lobby until another playlist or Custom Game is chosen;
  it does not persist across a server restart. A map change while starting the match preserves the ability to finish it.
- Availability and a retained selection are distinct: the host must validate a start against the eventual entitlement
  rules without treating the expired playlist as generally active.
- Votes occur outside a running match. The host checks availability within one minute during a vote and revalidates
  before launching the next match. If the playlist expires during the vote, return to the lobby without launching
  another match.

## Sketch and current contract concerns

The method below illustrates the proposed Lua boundary, not a frozen contract or calendar syntax:

```lua
-- Optional on a Lua PLAYLIST; nextChangeUTC may be nil.
function PLAYLIST:IsActive(nowUTC)
    return active, nextChangeUTC
end
```

An authoritative host snapshot could carry active status and known next changes to the menu, alongside whatever
selection state is ultimately needed. Its shape, update timing, replication and entitlement representation are
open, not existing APIs. In particular, the current frozen `docs/api/modes.md` describes playlists as data-only,
normalizes Lua and host JSON to the same clean data fields, and rejects unknown JSON fields. The existing list,
selection and start messages and archived `pw_playlist_active` state have their own validation and map-change
contracts (`docs/api/modes.md` and `docs/api/ui.md`). Before implementation, decide how the Lua method survives or
is associated with normalization, how validation and disabled content interact with it, and how host-authoritative
snapshots and pick/start validation fit those contracts. Any necessary changes to decided design or frozen APIs
require the appropriate separate approval; this note changes neither.

## Examples, not final calendars

- **Illustrative Shipment 24/7 every second Sunday:** a two-week phase anchored to an explicit UTC date, for example Sunday
  `2026-01-04T00:00:00Z`. Compute elapsed whole UTC days relative to the anchor and select the Sunday interval
  in each 14-day cycle. This is calendar-anchor arithmetic, never time since game launch. The anchor is illustrative.
- **Annual three-day Halloween playlist:** for example `[October 31 00:00 UTC, November 3 00:00 UTC)` each year.
  October 31 as the starting date is illustrative, not a final approved calendar.

Half-open windows (`start <= now < end`) are recommended to make adjacent boundaries unambiguous. UTC avoids
local DST shifts; exact leap-year, annual-window and DST/UTC semantics still need definition before implementation.

## Open questions

- Exact dates, biweekly anchor, calendar rules and clock-jump handling; remaining validation details for the method
  and its optional timestamp.
- Recovery or failure handling during a map change, consistent with the match-completion guarantee.
- Ordering and presentation of simultaneous active, upcoming and retained rotations.
- Dynamic data field method and form, and whether explicit reload or reevaluation is supported.
- Reconciliation with existing playlist normalization, enablement, start/pick validation, network messages and
  archived selection; snapshot format, replication and client update timing.

## Future tests

No scheduling runtime or tests are added by this note; no game tests are claimed run. A future implementation needs
pure condition/boundary tests, including absent method (always available), active/end and inactive/start results,
unknown next change, biweekly anchors including dates before the anchor, annual/year-wrap and leap-year cases,
offline startup without missed-event replay, repeated evaluation and authoritative host/client agreement. Cover
transition accuracy within one minute in non-match states, including unknown-next-change predicates; no `IsActive`
evaluation during a running match and fresh evaluation after completion before the next flow or vote; concurrent active rotations,
Custom Game last and the empty-active case; upcoming at the 48-hour boundary and exclusion when next start is
unknown; selection before expiry, visibility and one post-expiry start; and a running match finishing and returning
to the lobby without the expired rotation. Cover entitlement replacement, server restart and map change while starting;
predicate errors must fail closed and be logged without affecting other playlists, and invalid optional timestamps must
be unknown. Cover author-owned content dependency checks, standard validation, exception isolation and stable startup
resolution of static or dynamic data if adopted. Verify existing JSON playlist support remains intact without schedules.
Cover votes outside matches, availability checks within one minute during a vote, revalidation before the next match,
and expiry during a vote returning to the lobby without launching another match. Exercise eventual decisions on explicit reload, validation, networking, clock jumps and map-change
failure recovery once specified; do not invent outcomes now.
UI/input acceptance remains a future human checkpoint.
