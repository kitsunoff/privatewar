# Workshop packaging

Local build of the Workshop addons (TASKS.md T-10.2). The build never uploads anything: publishing is a manual step done by the maintainer.

## Build

```bash
nix develop --command make package
```

This runs `scripts/package/build.sh` and stages the addons into the git-ignored `dist/`. Use `--output DIR` to stage elsewhere:

```bash
nix develop --command bash scripts/package/build.sh --output /tmp/pw-dist
```

Each staged tree is checked by `scripts/package/verify.sh`; the build fails if an excluded path, a dotfile or a file of another type is inside, or if `addon.json` or a required gamemode file is missing.

If `gmad` is on `PATH`, every staged tree is also packed into a `.gma` next to it. Neither nixpkgs nor `flake.nix` provides `gmad` today, so the build normally stops at the staged trees. To get `.gma` files, pack a tree with the `gmad` that ships with the Garry's Mod install (`gmad create -folder dist/privatewar -out privatewar.gma`) or let the Workshop publishing tool pack the folder itself.

## What ships

Gamemode addon `dist/privatewar/`:

| Path | Source |
| --- | --- |
| `addon.json` | `addons/privatewar/addon.json` (title, description with the licence notice, type `gamemode`, tags, ignore list) |
| `gamemodes/privatewar/` | `addons/privatewar/gamemodes/privatewar/` (manifest, menu images and gamemode Lua files) |
| `lua/privatewar/` | `addons/privatewar/lua/privatewar/`, including the built-in content and `types/` for addon authors |
| `data_static/privatewar/LICENSE.txt` | `LICENSE` (GPL-3.0) |
| `data_static/privatewar/THIRD_PARTY_NOTICES.txt` | `THIRD_PARTY_NOTICES.md` |

Only `.lua` files, the gamemode manifest `.txt`, the two gamemode menu PNGs and the two licence files are copied.

Integration addons: one addon per weapon base from `addons/<name>/` (every addon folder except `addons/privatewar/` and the dev addon `addons/privatewar-dev/`; each with its own `addon.json`), staged as `dist/<name>/` under the same checks. Today that is `privatewar-arc9` (type `weapon`); the self-test asserts that each one is staged with its `addon.json`, Lua and licence files and without `lua/tests`. Each integration gets the same licence files under `data_static/<name>/`.

## What is excluded

| Excluded | Why |
| --- | --- |
| `lua/tests/` | GLuaTest cases; the test tool is dev-only |
| `lua/privatewar_fixtures/` | test fixtures and examples; the examples may be published separately as author docs |
| `addons/privatewar-dev/` (devbridge, testgate, dummy mode, `pw_dev_start`, dev kit screen) | the whole dev addon |
| `cfg/` | recommended server config, not part of the addon |
| `scripts/`, `docs/`, `tests/`, `design/`, `notes/`, `*.md`, `*.nix` | tooling and documentation |
| Dotfiles (`.deck.env`, `.DS_Store`, `.git`, `.nix`) | local state and the Steam Deck connection |

## Licence files

The gamemode is licensed under GPL-3.0-or-later (D4, decided 2026-11-07). Every staged addon gets `LICENSE` and `THIRD_PARTY_NOTICES.md` as `data_static/<addon>/LICENSE.txt` and `data_static/<addon>/THIRD_PARTY_NOTICES.txt`: the gmad whitelist (`Facepunch/gmad`, `include/AddonWhiteList.h`) rejects files in the addon root and any `.md`, while `data_static/*.txt` is allowed. `verify.sh` fails a staged addon without them.

## Checks

```bash
nix develop --command make package-selftest
```

The self-test builds into a temporary directory, asserts that the exclusions hold, and plants forbidden files to prove that `verify.sh` rejects them. It takes about two seconds and runs as part of `make check`.

## Publishing from the Steam Deck

The Private War gamemode Workshop item is <https://steamcommunity.com/sharedfiles/filedetails/?id=3836206472> (ID `3836206472`). Update this item instead of creating another one. Visibility is managed on the Workshop page.

The separate ARC9 integration Workshop item is <https://steamcommunity.com/sharedfiles/filedetails/?id=3836210106> (ID `3836210106`). Use this ID with `--addon privatewar-arc9` when updating the integration.

Run the following on the development machine, with the Deck configured as in `scripts/deck/common.sh` and Steam signed in on the Deck. The script locks the Deck, stages the current working tree (including uncommitted changes) with the same checks as `make package`, transfers the selected addon to a temporary directory, and uses the Deck's `gmad` and `gmpublish`. It does not deploy into the game's addons directory.

```bash
nix develop --command bash scripts/deck/publish.sh create --addon privatewar --icon /path/to/icon.jpg
nix develop --command bash scripts/deck/publish.sh update --addon privatewar --id 3836206472 --changes 'Fix bot navigation'
```

`--addon` defaults to `privatewar`; use `privatewar-arc9` for the separate integration. Create requires a 512×512 baseline JPEG icon; update accepts an optional `--icon`. The script does not validate the image format. Update requires the existing numeric Workshop ID and a single-line ASCII change note. Save the ID printed by the first upload; do not use create to update an existing item. Review the staged content and change note before running either command: both immediately upload to Workshop. Set the description, screenshots and visibility on the Workshop page.

The script uses the Linux `gmad` and `gmpublish` binaries if present; otherwise it attempts the Windows binaries with GMod's configured Proton and compatibility prefix. Steam must be signed in on the Deck. Failed uploads may leave an empty Workshop item; inspect Workshop before retrying create.

The public source repository is exported separately: see `docs/publishing.md`.
