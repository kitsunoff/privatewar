# Lambda-compatible bot voices, names and chat

Status: `planned`
Recorded: 2026-11-11

Research: [Lambda Players voice research](../../notes/28-lambda-voice-research.md). This record is tracking only; it does not authorize implementation, design changes, Deck access, redistribution or publication.

## Candidate scope

Make Private War's real Player bots able to use installed Lambda voice content for contextual chatter, draw nicknames from Lambda data, and send contextual messages using Lambda text lines. Keep a stable social identity across respawns and support idle and combat-event reactions. Importing personal profiles is a possible way to bind name, voice and text. A PW-owned chatter service with an optional Lambda content adapter is the research recommendation, not an approved design. Preserve `design/07-bots.md` d.2 and d.10; do not copy third-party code or bundle assets without established rights and approval.

The user approved optional names from installed Lambda content on 2026-11-11; `design/06-progression.md` d.7 records the extension. Preserve uniqueness, safe name handling and the built-in fallback. The built-in pool retains its original restrictions; the extension does not authorize redistributing third-party material.

## Questions before implementation

- Which Lambda versions and installed content sources are supported? What licenses, permissions and redistribution model are acceptable?
- Which events and voice profiles should apply, and how should defaults, aliases, missing assets and unavailable addons behave? How should user profiles map to PW bots without conflating personalities?
- What filtering and opt-in controls are required for potentially toxic voice and text? Who controls server and client permissions?
- How should personal names, voice and text profiles be paired? Define placeholder substitution, typing delays, chat recipients, dead/team chat, link handling and the treatment of unrecognized template syntax.
- How should server and clients mount content, and how should multiplayer spatial playback, visibility and UI work? What are acceptable frequency, concurrency and performance budgets?
- Can any Lambda API be relied upon for Player entities? Validate it rather than treating observed globals or entity methods as guaranteed. Does `PW_PlayerKilled` provide the right event and match-state semantics?

## Verification and gates

If implementation is separately approved, use tests first: cover event eligibility and lifecycle, profile discovery and fallbacks, nickname collisions and fallback, placeholder substitution and missing targets, chat recipients, missing content/addon, filtering and permissions, rate limits, cleanup and multiplayer behavior as applicable. Verify actual mounted assets, chat delivery and Player playback in game, including server/client behavior and performance; current research includes no game test. Before merge run `nix develop --command make check` and `nix develop --command make test` with `pipefail`, plus required project and human gates. Steam Deck access requires fresh explicit permission and confirmation it is free; without game testing, report the gate incomplete. Record evidence without exposing private Deck paths or contents.
