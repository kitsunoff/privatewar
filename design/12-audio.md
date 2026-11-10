# 12 — Audio

Status: draft.

## Goal and scope

Announcer priority queue, music states with crossfade, UI sounds.

## Decisions

1. **Optional Lambda-compatible bot chatter (user-approved, 2026-11-11; not yet implemented).**
   Consume only locally installed content; do not bundle, download or distribute Lambda code, profiles or assets.
   A PW-owned service supports real Player bots without depending on Lambda entity methods. Preserve a built-in
   fallback when the addon, a profile or an asset is absent. Imported identity remains stable across respawns;
   names retain uniqueness and safe handling (`06-progression.md` d.7).
2. **Minimal social scope.** Events: idle, enemy spotted, kill and death. Voice is spatial at the bot, text uses
   common chat (not team/dead channels). No semantic/toxicity filtering of installed content; apply only necessary
   safety validation (bounded plain text, safe paths, no executable templates/commands). No new awareness or hidden
   enemy coordinates: spotted events come only from normal perception. Frequency and concurrency are bounded.
3. **Unapproved details remain open.** Supported source versions/paths, profile binding, exact template grammar,
   enable defaults, rate/concurrency values and audibility settings must be settled before their dependent runtime
   work. See `docs/api/feature-contracts.md`; this approval does not decide the unrelated announcer/music system.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

TBD.
