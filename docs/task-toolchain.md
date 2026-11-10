# Task toolchain

Moved from [TASKS.md "Toolchain"](../TASKS.md#toolchain); that heading remains a stable entry point.

Lint, type and test tools come from `flake.nix` (`nix develop`, or direnv `use flake`). Agents run these commands through `nix develop --command <cmd>` because their shells are non-interactive. Run ordinary git commands directly in your own worktree.

**Rule: nothing is built from source.** A tool missing from nixpkgs is packaged from its **release binary** under the nixpkgs naming convention `<name>-bin`.

| Tool | Source | Notes |
| --- | --- | --- |
| `lua-language-server` (LuaLS) | nixpkgs (3.19.2, verified 2026-11-08) | Language server and **type checker** (`--check`) on every platform |
| `markdownlint-cli2` | nixpkgs (0.24.0, verified 2026-11-08) | Docs |
| `luajit` | nixpkgs | Same Lua as GMod for quick scripts |
| `glualint-bin` | Release binary `FPtje/GLuaFixer` 1.30.0 | Assets: `OSX-x86_64` (runs through Rosetta on Apple Silicon), `x86_64-linux`; no native arm64 macOS build |
| `glua-ls-bin` (optional, editor only) | Release binary `Pollux12/gmod-glua-ls` | Only `glua_ls` has macOS builds (`darwin-arm64-experimental`); `glua_check` ships for linux-x64 and win32 only, so it is **not** the gate |
| GMod annotations | Pinned non-flake input `luttje/glua-api-snippets` (data, not built) | Fed to LuaLS via `.luarc.json` |
| GLuaTest | Pinned non-flake input `CFC-Servers/GLuaTest` | Docker runner script; Docker itself (Colima) stays in nix-darwin |
| Git hooks | `cachix/git-hooks.nix` (Apache-2.0) | Installed by the devShell; all four `pre-commit` fast checks; no automatic `pre-push` tests (user decision 2026-11-08). Manual `make check` / `make test` acceptance/merge gates remain mandatory |
| CI (later) | `nix flake check` | Same checks as the hooks |

Outside the flake (system level): Colima/Docker, Garry's Mod itself.
