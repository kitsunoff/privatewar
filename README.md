# Private War

Private War is a Garry's Mod gamemode for casual, Call of Duty style matches: you alone, or you and a few friends,
against bots that move, take cover, flank and play the objective. Matches run on a player-hosted listen server, so no
dedicated machine is needed.

The gamemode is designed to be playable on the Steam Deck. **Optimisation first:** every costly option defaults to
performance, and visual or simulation quality is opt-in through a host setting.

## Features

- **Bots that are real players.** Bots are created with `player.CreateNextBot` and play through the same input as
  humans, so they use the same weapons, movement, teams and scoreboard. Difficulty tiers change reaction, aim and
  decisions, never health or damage.
- **Modes:** Team Deathmatch, Free-for-all, Domination and Kill Confirmed, grouped into playlists.
- **An in-game lobby:** party list, playlist or custom game, Game Setup, bot fill and difficulty, START, then a vote
  for the next map and mode after each match.
- **Loadouts:** classes with a Pick-X style budget, perks, wildcards, equipment (frag and flash grenades) and
  killstreaks.
- **Progression and store:** player and weapon levels, unlocks, medals, a match currency and a daily store rotation.
  Progression is stored on each player's computer and sent to the host on join.
- **Gamepad-friendly front end:** PLAY, LOADOUT, PROGRESS and STORE tabs, usable with a keyboard or the Steam Deck
  controls.
- **Extensible:** modes, perks, killstreaks, HUD elements, bot behaviours and weapon base adapters are files in
  SWEP-style folders under `lua/privatewar/`; your own addon can add or replace them. Everything public is typed with
  LuaLS annotations.

## Install

The repository holds the addons under `addons/`:

| Folder | What it is | Needed |
| --- | --- | --- |
| `addons/privatewar/` | The gamemode | Yes |
| `addons/privatewar-arc9/` | ARC9 integration: catalogue, attachments and the performance profile for ARC9 weapons | Only with ARC9 |
| `addons/privatewar-dev/` | Development bridge for the test loop | No, never install it on a server you play on |

1. Copy `addons/privatewar/` into `garrysmod/addons/` of your Garry's Mod install.
2. Optional: if you use the ARC9 weapon base, also copy `addons/privatewar-arc9/`.
3. Restart Garry's Mod (addon folders are mounted at startup).
4. New Game → gamemode Private War → Max Players above 1 (12 is recommended) → Start. Bots cannot be created in
   Singleplayer.

The game also works without any weapon base: plain SWEPs are supported by a built-in fallback adapter.
Playing, hosting for friends and the controls are described in [docs/guide/playing.md](docs/guide/playing.md).

## Documentation

- [docs/guide/playing.md](docs/guide/playing.md): solo with bots, hosting for friends, the match flow, controls.
- [docs/guide/extending.md](docs/guide/extending.md): write a mode, a perk, a killstreak, a wildcard, an equipment
  item or a bot behaviour.
- [docs/api/](docs/api/README.md): the API contracts (hooks, class tables, settings).
- [DESIGN.md](DESIGN.md) and [design/](design/): the design decisions per subsystem.
- [docs/packaging.md](docs/packaging.md): building the Workshop addons.
- [TASKS.md](TASKS.md): the implementation plan.

## Development

Tools come from the Nix flake; nothing else needs to be installed by hand.

```bash
nix develop                               # toolchain and git hooks
nix develop --command make check          # glualint, lua-language-server --check, markdownlint, rule gate, self-tests
nix develop --command make package        # stage the Workshop addons into dist/ (never uploads)
```

Tests use [GLuaTest](https://github.com/CFC-Servers/GLuaTest) and run inside a real Garry's Mod server.
`make test` runs the suite on a Steam Deck over SSH (see `TASKS.md`, "Dev loop on the Steam Deck"); the connection
comes from the environment (`DECK_HOST`, `DECK_USER`) or a git-ignored `.deck.env`.

Repository layout:

| Path | Content |
| --- | --- |
| `addons/` | The addons (gamemode, integrations, dev bridge) |
| `design/`, `DESIGN.md` | Design decisions |
| `docs/` | Guides, API contracts, packaging, manual test list |
| `notes/` | Research notes behind the design |
| `scripts/` | Quality gates, Steam Deck dev loop, packaging |
| `tests/gates/` | Fixtures that prove the gates reject bad input |
| `cfg/` | Recommended server config |

## License

Copyright (C) 2026 Maxim Belyy (kitsunoff)

Private War is free software, licensed under the GNU General Public License, version 3 or (at your option) any later
version (GPL-3.0-or-later). The full text is in [`LICENSE`](LICENSE).

You may use, change, share and sell the gamemode. If you distribute a modified version or a work based on it, that work
must also be released as open source under the GPL, with its source code available. Third-party code included in the
repository and its licences are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
