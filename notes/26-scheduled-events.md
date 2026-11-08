# Scheduled events

Status: accepted architectural direction, not implemented. Exact APIs and schemas are not frozen.

## Shared offline scheduling

Use the existing content-kind pattern: a `schedules/` folder and `SCHEDULE` class table, with a shared generic
schedules manager consumed by both playlists and progression. This is not playlist-only scheduling and needs
no permanently running central server. Several events may be active concurrently; this note does not select
a single active event.

A schedule may declare `SCHEDULE.When`, or alternatively provide an optional deterministic
`SCHEDULE:IsActive(nowUTC)` predicate. Names and schema examples here are illustrative, not implemented contracts.
Condition checks use one UTC timestamp. Selection must not depend on randomness, server uptime, players or the
chosen playlist. The same installed schedule/version and clock produce the same locally active events offline.
Bad clocks or different installed versions cannot magically guarantee agreement between machines.

The host evaluates session state and replicates active status to clients. Clients follow that authoritative
session status rather than independently disagreeing about the session's active content.

## Evaluation and lifecycle

Evaluate at server startup and every 300 seconds:

- false → true: create the event instance and call `OnEquip`;
- true → true: retain the instance without repeated activation;
- true → false: remove the instance and call `OnUnequip`;
- disabled content, a disabled manager/module and shutdown: clean up owned instances and registrations.

The existing `PW.Instance` convention is a precedent, not a frozen lifecycle contract for schedules. Event
instances own reversible registrations through the owning modules' public APIs. Removal withdraws only that
instance's playlist availability or multiplier contribution. Never blindly restore shared globals or mutate
foreign stores: other instances may still contribute effects.

Five-minute polling allows up to five minutes of activation/deactivation delay. Startup evaluates the current
interval; it does not replay missed activations. An optional exact-boundary wakeup for a declarative next
transition was discussed only as a possible optimization, not required approved behavior. No cron framework,
timer-event replay or continuously running service is necessary; deterministic predicates are sufficient.

## Examples, not final calendars

- **Shipment 24/7 every second Sunday:** a two-week phase anchored to an explicit UTC date, for example Sunday
  `2026-01-04T00:00:00Z`. Compute elapsed whole UTC days relative to the anchor and select the Sunday interval
  in each 14-day cycle. This is calendar-anchor arithmetic, never time since game launch. The anchor is illustrative.
- **Annual three-day Halloween event:** for example `[October 31 00:00 UTC, November 3 00:00 UTC)` each year.
  October 31 as the starting date is illustrative, not a final approved calendar.
- **Wednesday 2XP:** progression consumes an active Wednesday schedule independently of the selected playlist.
  This does not decide whether the multiplier affects player XP, weapon XP or both.

Half-open windows (`start <= now < end`) are recommended to make adjacent boundaries unambiguous. UTC avoids
local DST shifts; exact leap-year, annual-window and DST/UTC semantics still need definition before implementation.

## Open questions

- Multiple simultaneously available playlists versus a single featured slot, and any priorities.
- Player versus weapon XP scope, and multiplier stacking.
- Exact dates and biweekly anchor.
- What happens to a running match when an event window ends.
- Precise declarative fields, validation, clock-jump handling and persistence across `changelevel`.

## Future tests

No scheduling runtime or tests exist as part of this note; no tests are claimed run. A future implementation
needs pure condition/boundary tests, biweekly anchor tests (including dates before the anchor), annual/year-wrap
and leap-year tests, offline startup without missed-event replay, repeated-evaluation idempotence,
deactivation/disable/shutdown cleanup, overlapping-instance ownership, and authoritative host/client agreement.
