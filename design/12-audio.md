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
3. **Approved Lambda defaults and identity (additional user approval, 2026-11-11).**
   - `bots_chatter.enabled` defaults false; after enabling, `voice` and `chat` default true. Default minimum
     interval is 20 seconds per bot and default simultaneous voices is 2. Expose optional settings for adjustment.
   - Voice and text profiles are chosen independently, not paired by name/index or a mandatory personal profile.
     Keep each choice stable for the bot's connected lifetime, including death/respawn; a replacement bot is new.
   - Supported installed sources are the finite adapter inventory in `docs/api/feature-contracts.md`, read from
     the current chatter implementation. This is not a promise of compatibility with every Lambda version or API.
   - Necessary technical protection is allowed without semantic censorship. Other bounds, template handling,
     local volume and spatial fade parameters are initial adjustable implementation details, not additional
     specially chosen product values. Announcer/music design and broader integrations remain outside this approval.

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

TBD.
