# Lambda-compatible bot voices, names and chat

Status: `planned`
Recorded: 2026-11-11

Research: [Lambda Players voice research](../../notes/28-lambda-voice-research.md). This record is tracking only; it does not authorize implementation, design changes, Deck access, redistribution or publication.

## Candidate scope

Make Private War's real Player bots able to use installed Lambda voice content for contextual chatter, draw nicknames from Lambda data, and send contextual messages using Lambda text lines. Keep a stable social identity across respawns and support idle and combat-event reactions. The approved boundary below uses a PW-owned chatter service with an optional installed-content adapter and independently selected stable voice/text profiles; it does not require a personal-profile bundle. Preserve `design/07-bots.md` d.2 and d.10; do not copy third-party code or bundle assets.

The user approved optional names from installed Lambda content on 2026-11-11; `design/06-progression.md` d.7 records the extension. Preserve uniqueness, safe name handling and the built-in fallback. The built-in pool retains its original restrictions; the extension does not authorize redistributing third-party material.

## Approved boundary (2026-11-11; not implemented)

The user explicitly approved `design/12-audio.md` d.1–3 and the
[Lambda contract](../../docs/api/feature-contracts.md#optional-lambda-content-boundary): locally installed content
only, no distribution/download, built-in fallback, no semantic content filtering beyond necessary safety;
idle/enemy-spotted/kill/death events, spatial voice, common chat and bounded rate/concurrency. Names remain unique
and safe, identity stable across respawns. These are decisions, not research recommendations. Runtime, game
verification and human acceptance remain pending; this record stays planned and grants no device/publication access.

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
- Read-only inspection of the chatter feature's shared/server/content/client files establishes the inventory and
  initial technical values only; it does not establish native compatibility, independent randomness, safe event
  ordering, respawn stability, performance or human acceptance. Verify these through tests before acceptance.
- Do not call third-party entity APIs on Player bots or conflate social profiles with combat personalities.

## Verification and gates

If implementation is separately approved, use tests first: cover event eligibility and lifecycle, profile discovery and fallbacks, nickname collisions and fallback, placeholder substitution and missing targets, chat recipients, missing content/addon, filtering and permissions, rate limits, cleanup and multiplayer behavior as applicable. Verify actual mounted assets, chat delivery and Player playback in game, including server/client behavior and performance; current research includes no game test. Before merge run `nix develop --command make check` and `nix develop --command make test` with `pipefail`, plus required project and human gates. Steam Deck access requires fresh explicit permission and confirmation it is free; without game testing, report the gate incomplete. Record evidence without exposing private Deck paths or contents.
