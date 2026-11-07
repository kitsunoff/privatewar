# Private War: Infection

Optional content for the Private War gamemode. Install this addon alongside `privatewar`; it is not
a separate engine gamemode and needs no weapon framework, Workshop model pack or external assets.
Select **Infection** in the normal lobby and configure **Total rounds** (default 3, including 1).
A host plus one bot is enough. Fewer than two participants aborts the match with an explanation.

## Rules

- Each 120-second round chooses one random initial infected, avoiding the previous identity when possible.
- Survivors use their ordinary saved class. Every survivor death converts, including suicide or world death.
- Infected have 400 spawn/max health, ordinary walk/run speeds multiplied by 1.15, native `weapon_fists`
  and a validated stock zombie player model. Jump and native fist damage are unchanged for humans and bots.
  An unavailable or incompatible model falls back to the player's ordinary operator, not an NPC model.
- Infected respawn after 3 seconds. A dead infected awaiting respawn still counts as present.
- All survivors converted means infected victory. At the deadline, any remaining survivors win;
  deadline equality takes precedence over a death. The last infected leaving awards survivors the round.
- New joiners and reconnects wait for the next round. Bot quota replacements occur only between rounds.
- Only surviving survivors or the initial seed on an infected victory earn a personal round win.
  Converted players do not inherit a win. The configured total rounds always runs; a shared top score draws.
- Infection counts are informational. There are no additional XP or money rewards. Infected cannot use
  perks, grenades or streak inventory/effects. Saved classes and operator choices are not overwritten.

## Integration and removal

The addon uses the shared `round_base` lifecycle, public team transitions, item revocation and player
overrides. No built-in module recognizes its mode id. Bots use normal perception, goals, aim and usercmd;
the addon does not teleport bots, inject damage or disclose hidden enemy positions.

Disable `pw_infection_rules` before a new match to refuse Infection safely, or disable the mode through
the usual entity-enable setting. Ordinary modes remain available. Removing the addon is a **between-session**
operation: stop the game, remove the addon and start again. Hot unmount is not supported. Changing enabled
entities follows the base gamemode's match-boundary snapshot policy.

API and test mapping: [Infection integration](../../docs/api/infection.md).
The root GPL-3.0-or-later license applies; no third-party code or assets are bundled.

## Verification status

This implementation is in development. Installed lifecycle and native-fists smoke checks pass. The full
merge gate remains incomplete: a generic MatchEnd reset dependency is RED, and the ordinary POSTMATCH
screen still ranks FFA by kills rather than personal round wins. LIVE HUD captures have been inspected;
human/P2P and HUD visual checkpoints are not passed by automated tests or agent inspection.
