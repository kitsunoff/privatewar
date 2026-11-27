# Lambda-compatible bot voices, names and chat

Status: `done`
Recorded: 2026-11-11

Research: [Lambda Players voice research](../../notes/28-lambda-voice-research.md). This record is tracking only; it does not authorize implementation, design changes, Deck access, redistribution or publication.

## Delivery and verification

Merged into `main` as `1446796` on 2026-11-21. The integration passed `make check` and the full Deck suite:
2131 passed, 0 failed, 0 skipped. This records delivery and automated verification, not manual acceptance
of playback with every installed Lambda content source.

Private War's Player bots can use installed Lambda names, spatial voice and contextual text through the
optional PW-owned chatter service. Voice and text profiles are selected independently and remain stable
across respawns. Third-party content is not bundled.

The user approved optional names from installed Lambda content on 2026-11-11; `design/06-progression.md` d.7 records the extension. Preserve uniqueness, safe name handling and the built-in fallback. The built-in pool retains its original restrictions; the extension does not authorize redistributing third-party material.

## Approved boundary (2026-11-11)

The user explicitly approved `design/12-audio.md` d.1–3 and the
[Lambda contract](../../docs/api/feature-contracts.md#optional-lambda-content-boundary): locally installed content
only, no distribution/download, built-in fallback, no semantic content filtering beyond necessary safety;
idle/enemy-spotted/kill/death events, spatial voice, common chat and bounded rate/concurrency. Names remain unique
and safe, identity stable across respawns. These are decisions, not research recommendations.

## Additional approved decisions (2026-11-11)

- [x] Integration enabled=false by default; voice/chat=true after enabling. Default interval 20 seconds per bot,
  default concurrent voices 2; optional adjustment settings are allowed. These are no longer open choices.
- [x] Use only installed sources enumerated by the current chatter adapter; the API inventory records concrete
  GAME/DATA paths and formats. No all-version compatibility, redistribution or new source families are implied.
- [x] Choose voice and text profiles independently and retain them for the bot's connected lifetime across respawns;
  no required personal-profile binding. Keep safe unique names and ordinary built-in fallback.
- [x] Necessary technical protection is authorized without semantic censorship. Additional ranges, global gap,
  playback lease, volume/fade values, scan budgets and minimal template handling are initial tunable engineering
  details, not separately user-selected product values. See the API contract for the inspected initial values.

## Remaining verification and scope limits

- No product blocker remains for these defaults, supported sources or independent selection. Broader personal
  profile imports, additional sources and a full Lambda template language remain outside the approved minimum.
- Manual checks with mounted assets, audible playback, chat delivery and multiplayer behavior remain separate
  from the automated integration result.
- Do not call third-party entity APIs on Player bots or conflate social profiles with combat personalities.
