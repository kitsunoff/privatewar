# Change queue

This is the single entry point to the current queue. A linked change record owns its status; this index does not
copy statuses. Records are grouped by status directory, not priority. Read the record and its dependencies before selecting
work. A record is tracking, not authorization to implement or publish.

## Statuses

- `planned`: identified future work, not currently being implemented.
- `in-progress`: active implementation or verification; record owner and scope.
- `blocked`: cannot proceed; record the blocker and what would unblock it.
- `done`: the recorded scope and required gates are complete; name any separate pending human acceptance explicitly.

The directory and the record's `Status` must agree. On a transition, move the record to the matching directory,
update its `Status`, evidence and date, and repair the index and any inbound links in the same change. Never turn a
historical test result into a current pass. Maintain one record per change and link related work instead of duplicating it.

## Planned

The remaining gameplay/social records below separate the user-approved 2026-11-11 design/API revision from
unresolved choices and unimplemented work. [Approved contracts](../docs/api/feature-contracts.md) are not gate or
human-acceptance evidence; planned status is retained.

- [Fira Sans fonts](planned/fira-sans.md)
- [Automatic Search and Destroy support for `de_` maps](planned/snd-de-autodetect.md)
- [MW Base integration and Deck performance profile (T-3.8)](planned/mwbase-integration.md)
- [TFA Base integration with attachments (T-3.7)](planned/tfa-integration.md)
- [Progression rebalance: pacing, attachment spread and long tail](planned/progression-rebalance.md) (questions for
  the maintainer open)
- [Search and Destroy bot behaviour: site choice, route variety, corner checks, empty grenade](planned/snd-bot-behaviour.md)

## In progress

- [Weekly challenges](in-progress/weekly-challenges.md): core feature and PLAY preview locally integrated;
  guarded dev commands, API documentation, and manual acceptance remain open.
- [Scheduled events (T-11.16)](in-progress/scheduled-events.md): Lua infrastructure/content candidate; game gates pending.

## Blocked

- [Additional weapon-base integrations (T-3.7 and T-3.8)](blocked/weapon-integrations.md)

## Done

- [Lambda-compatible bot voices, names and chat](done/lambda-bot-voice.md): merged and game-tested;
  manual acceptance remains separate.
- [After-match rotation by default for playlists](done/aftermatch-rotation-default.md): local overnight integration;
  human checkpoint pending.
- [Programmatic unlocks and entitlements](done/unlock-entitlements.md): local overnight integration;
  human checkpoint pending.
- [Stim equipment: heal, speed and armor stims](done/stim-equipment.md): local overnight integration;
  optional installed-Arctic case skipped, human checkpoint pending.
- [Calling cards: equip a card, show the victim's card to the killer](done/calling-card-kill-banner.md):
  local integration with Deck smoke; human checkpoint pending.

Historical completion evidence for unmigrated work remains in TASKS.md.

## Remaining queue and history

Migration is intentionally partial: all items not listed above remain tracked in
[TASKS.md Phase 11](../TASKS.md#phase-11--playtest-follow-ups-2026-11-07), including its
[known follow-ups](../TASKS.md#known-follow-ups-not-scheduled-some-need-a-user-decision),
historical implementation evidence and pending human checkpoints. The corresponding text for a migrated item is
historical context; its change record is the only current status. Do not treat historical branches, old phase rows
or a previous automated pass as current completion. Inspect the current code and dependencies before choosing work.

Other unmigrated planning and barriers remain in [design tasks still open](../TASKS.md#design-tasks-still-open),
the [phase plans and checkpoints](../TASKS.md#phase-0--setup), and the
[handover](../TASKS.md#how-to-continue-handover). They are not implicitly assigned one of the new statuses.

[TASKS.md](../TASKS.md) remains authoritative for mandatory test cases, lane ownership, checkpoints and the existing
plan; its toolchain and design-question sections link to their thematic files. When migrating another item, preserve those requirements and history, link the original entry from the new
record, add the record here, and explicitly mark the old status as historical without discarding evidence. Do not
create an overlapping record or silently assign a status to an unverified legacy item.
