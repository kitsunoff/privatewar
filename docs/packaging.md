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
| `gamemodes/privatewar/` | `addons/privatewar/gamemodes/privatewar/` (`privatewar.txt` and the `gamemode/` Lua files) |
| `lua/privatewar/` | `addons/privatewar/lua/privatewar/`, including the built-in content and `types/` for addon authors |
| `data_static/privatewar/LICENSE.txt` | `LICENSE` (GPL-3.0) |
| `data_static/privatewar/THIRD_PARTY_NOTICES.txt` | `THIRD_PARTY_NOTICES.md` |

Only `.lua` files, the gamemode manifest `.txt` and the two licence files are copied.

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

## Publishing (manual)

1. Run `make package` and inspect `dist/`.
2. Upload with the Workshop tooling from the Garry's Mod install (`gmpublish` or the in-game publisher). The icon and description are set at upload time.
3. Record the Workshop ID by hand where the project needs it.

The public source repository is exported separately: see `docs/publishing.md`.
