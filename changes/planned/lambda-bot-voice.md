# Lambda-compatible bot voices, names and chat

Status: `planned`
Recorded: 2026-11-11

Research: [Lambda Players voice research](../../notes/28-lambda-voice-research.md). This record is tracking only; it does not authorize implementation, design changes, Deck access, redistribution or publication.

## Candidate scope

Make Private War's real Player bots able to use installed Lambda voice content for contextual chatter, draw nicknames from Lambda data, and send contextual messages using Lambda text lines. Keep a stable social identity across respawns and support idle and combat-event reactions. Importing personal profiles is a possible way to bind name, voice and text. The approved boundary below uses a PW-owned chatter service with an optional installed-content adapter; specific profile binding remains open. Preserve `design/07-bots.md` d.2 and d.10; do not copy third-party code or bundle assets.

The user approved optional names from installed Lambda content on 2026-11-11; `design/06-progression.md` d.7 records the extension. Preserve uniqueness, safe name handling and the built-in fallback. The built-in pool retains its original restrictions; the extension does not authorize redistributing third-party material.

## Approved boundary (2026-11-11; not implemented)

The user explicitly approved `design/12-audio.md` d.1–3 and the
[Lambda contract](../../docs/api/feature-contracts.md#optional-lambda-content-boundary): locally installed content
only, no distribution/download, built-in fallback, no semantic content filtering beyond necessary safety;
idle/enemy-spotted/kill/death events, spatial voice, common chat and bounded rate/concurrency. Names remain unique
and safe, identity stable across respawns. These are decisions, not research recommendations. Runtime, game
verification and human acceptance remain pending; this record stays planned and grants no device/publication access.

## Blocking questions before dependent implementation

- Which installed Lambda versions, data paths and profile formats are supported? Redistribution is excluded,
  not an open packaging choice; use only content already installed by each participant.
- How should names, voices and text profiles bind to PW identities? What aliases/template grammar are supported?
  Built-in fallback and base events are fixed; do not conflate a social profile with bot combat personality.
- What are server/client opt-in defaults, exact cooldowns/concurrent cap and audibility distance/settings?
  No semantic filtering is required; common chat and spatial voice are fixed, not channel-selection questions.
- Can any Lambda API be relied upon for Player entities? Validate it rather than treating observed globals or entity methods as guaranteed. Does `PW_PlayerKilled` provide the right event and match-state semantics?

## Verification and gates

If implementation is separately approved, use tests first: cover event eligibility and lifecycle, profile discovery and fallbacks, nickname collisions and fallback, placeholder substitution and missing targets, chat recipients, missing content/addon, filtering and permissions, rate limits, cleanup and multiplayer behavior as applicable. Verify actual mounted assets, chat delivery and Player playback in game, including server/client behavior and performance; current research includes no game test. Before merge run `nix develop --command make check` and `nix develop --command make test` with `pipefail`, plus required project and human gates. Steam Deck access requires fresh explicit permission and confirmation it is free; without game testing, report the gate incomplete. Record evidence without exposing private Deck paths or contents.
