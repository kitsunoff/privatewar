# Calling cards

Design: `06-progression.md` d.6 and `09-hud.md` d.2. The `calling_cards` module consumes the economy `cards` kind and
the [unlock authority](progression.md). Use the existing `CARD` schema; the module does not add an ownership store.

## Selection

- `calling_cards.selected` is a client enum. The default `default` is Recruit; the options come from the card
  registry. Disabling a card does not silently overwrite the stored preference.
- LOADOUT > CALLING CARD opens the `loadout_card` picker. The focused card updates the preview; only accepting an
  unlocked card writes the setting. Locked cards show their `PW.Unlocks.Requirement`. Back returns to Classes.
- `PW.CallingCards.LocalChoice() -> string` reads the local choice; it does not report the server's effective choice.
  The player's `pw_card` NW2 string is the effective choice. The server writes it only on change and validates
  against the registered, enabled, unlocked card on selection and spawn.
- An unavailable choice falls back to Recruit without clearing the saved choice. Bots ignore locks and choose from
  sorted enabled IDs once per session. Empty content or a missing card can render a plain plate.

## Messages

| Message | Direction | Payload and authority |
| --- | --- | --- |
| `pw_card_choice` | Client to server | NUL-terminated card ID, at most 32 bytes. Empty is a wire-only reset to Recruit. Sent after join and on preference change; `PW.Net.Receive` limits it to rate `2` and `maxLen = 34`. The sender changes only their own choice. |
| `pw_kill_card` | Server to human killer | Snapshot of the victim's name (up to 32 valid UTF-8 bytes), card ID (up to 32 bytes) and bot flag. Two NUL-terminated strings followed by one boolean. The receiver rejects malformed, truncated or trailing data. |

`PW_PlayerKilled` triggers the banner for an enemy player victim during `LIVE` only. Team kills, suicides, world
deaths and bot attackers do not send a banner. The victim does not receive the killer's card.

## HUD

`kill_card` has order 20 and draws only in `LIVE`. It is centred above the XP bar, with a 400×100 design-unit plate.
The fade-in, hold and fade-out last 0.15, 2.5 and 0.3 seconds. A new kill replaces the banner and restarts that timer.
`calling_cards.banner` is a client boolean defaulting to true.

Art comes from each card's `Material`; small icons are centred and missing materials use a named rarity plate.
A gradient under the victim's name keeps the text readable independently of the art. The module does not
download external material to clients. A peer playtest should install the same addon version on both clients.

## Content

Recruit and the level 20, 40 and 55 cards are joined by six reward-only calling cards. Weekly challenges can grant
their matching card on any existing tier; that requires the separate weekly system. The three existing shop cards
remain available under their economy rules. The ten new card PNGs ship directly under
`materials/privatewar/cards/`.
