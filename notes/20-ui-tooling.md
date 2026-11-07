# UI tooling for an AI-assisted GMod CoD-style gamemode

Research date: 2026-11-03. Host: macOS (nix-darwin), Claude Code.
All dates are GitHub `pushed_at` (last push) unless stated otherwise. Star counts are a rough popularity signal only.

Evidence labels:

- **[verified]** — read in the primary source (repo README/source, Facepunch wiki raw text, release list) during this research.
- **[unverified]** — plausible, from memory or a secondary source; check before relying on it.
- **[proposal]** — my design suggestion, not a claim about an existing tool.

## 1. Recommendation (ranked)

### 1.1 Stack

| Rank | Layer | Choice | Why |
| --- | --- | --- | --- |
| 1 | Menus: main menu, lobby, loadout, gunsmith, scoreboard, end-of-match | HTML/CSS/TS in a `DHTML` panel, built with Vite + Preact or Svelte, Tailwind **v3** | The only path that previews 1:1 outside GMod (normal browser + Playwright screenshots). AI models are far more fluent in HTML/CSS than in Derma. |
| 2 | HUD (per-frame: health, ammo, minimap, killfeed, hitmarkers, crosshair) | Lua `surface`/`draw` + Mantle (or a standalone RNDX copy) for rounded/blurred shapes | Per-frame data, no input focus problems, no extra web view cost. |
| 3 | 3D previews inside HTML menus (weapon model in gunsmith, player model in loadout) | `DModelPanel` placed as a Lua child panel over the `DHTML` panel; JS reports the target rectangle | CEF cannot render game models. **[proposal]** |
| 4 | Static analysis for the agent | `glua_check` (from Pollux12/gmod-glua-ls) with JSON output + `glualint` | CLI diagnostics the agent can read without an editor. |
| 5 | API knowledge for the agent | Facepunch wiki raw endpoint (`?format=text`) via curl/WebFetch, optionally the `glua` Claude Code skill | Exact signatures and realms instead of guesses. |
| 6 | In-game verification | `AmyJeanes/GMod-MCP-Server` (file-bridge, no binary module; screenshot, Lua run, console capture, hot-reload of a single file) | Only MCP found that does not need a native module and has a client screenshot tool; host launch tools are Windows-only. |
| 7 | Browser verification | Playwright MCP (already configured in this Claude Code setup: `mcp__playwright__*`) | Screenshot at 1280x720 / 1920x1080 / 2560x1440 with mock data. |

### 1.2 Dev loop

```text
1. Edit       ui/src/**  (TS + CSS)          or  lua/**  (HUD, bridge)
2. Check      npm run build (target chrome86) + glua_check --output-format json + glualint
3. Preview    vite dev server with mock bridge -> Playwright screenshot -> agent reads PNG
4. Ship to GMod
              vite build -> single-file bundle -> written into a Lua file as a string
              (or kept on disk for local asset:// loading during development)
5. Reload     in GMod: lua_refresh_file <path>  /  MCP reload_file_cl  /  a dev concommand
              that re-runs SetHTML on the open panel
6. Verify     MCP screenshot_cl (or `jpeg` console command) -> agent reads the image
              -> compare with the browser screenshot of step 3
```

Key facts that shape this loop:

1. **Lua auto-refresh does not work on macOS.** The wiki says verbatim: "It doesn't work on OSX". Manual `lua_refresh_file <path>` is the documented alternative. [verified: wiki `Auto_Refresh`]
2. **On macOS, GMod runs only on the `x86-64` branch and needs GModPatchTool**, which upgrades its CEF from 80 to 137. Windows players (all branches) have **CEF 86**. Your Mac preview engine is therefore newer than what most players run: always target Chrome 86. [verified: wiki `HTML_Web_Engine`]
3. **Workshop addons cannot contain `.html`, `.css`, `.js`.** The UI bundle must be shipped as a Lua string (`SetHTML`) or hosted on HTTPS (`OpenURL`). [verified: wiki `Workshop_Addon_Creation`, gmad `AddonWhiteList.h`]
4. **Tailwind v4 needs Chrome 111+** (cascade layers, `@property`, `color-mix`) — it will break on CEF 86. Use Tailwind v3. [unverified: from Tailwind v4 docs' browser-support section, not re-read today]
5. Avoid CSS that Chrome 86 lacks: `aspect-ratio` (88), `inset` shorthand (87), `:has()` (105), container queries (105), native CSS nesting (112), `dvh`/`svh` units (108). Set Vite `build.target: "chrome86"` for JS. [unverified: Can I Use versions from memory; the wiki itself points to Can I Use / MDN for Chrome 86]

### 1.3 Proposed repository layout [proposal]

```text
gamemodes/codlike/
  gamemode/            # shared/server/client Lua
    cl_hud.lua         # surface/draw + RNDX
    cl_webui.lua       # DHTML host, bridge, reload concommand
    cl_webui_bundle.lua  # GENERATED: return [==[ <html>...</html> ]==]
ui/                    # web UI source (not shipped)
  src/bridge.ts        # real bridge (window.gm*) or mock (fake data) — chosen at runtime
  src/mocks/*.json     # lobby, loadout, scoreboard fixtures
  vite.config.ts       # build.target chrome86, vite-plugin-singlefile
  scripts/emit-lua.mjs # wraps dist/index.html into cl_webui_bundle.lua
.gluarc.json           # glua_check config
glualint.json
```

Bridge shape [proposal]:

- JS → Lua: `DHTML:AddFunction("gm", "action", function(json) ... end)`; must be called after the document loaded (wiki note). In the browser, the mock defines `window.gm.action` itself.
- Lua → JS: `panel:QueueJavascript("window.__gmReceive(" .. util.TableToJSON(state) .. ")")`. `QueueJavascript` only runs while the panel is visible. [verified: wiki `DHTML`]
- Detect mock mode: `typeof window.gm === "undefined"` after a short timeout.

## 2. Tool table

| Tool | URL | What it does | Last activity | License | macOS | AI-workflow fit |
| --- | --- | --- | --- | --- | --- | --- |
| gmod-glua-ls (`glua_ls`, `glua_check`) | <https://github.com/Pollux12/gmod-glua-ls> | Rust GLua language server + CLI checker (realm checks, net/hook checks, typed ENT/SWEP) | 2026-11-03; release 1.3.0 (pre-release) 2026-11-01 | MIT | darwin arm64/x64 `glua_ls` binaries marked "experimental"; `glua_check` via `cargo install` | High: `glua_check . --output-format json` gives machine-readable diagnostics |
| vscode-gmod-glua-ls | <https://github.com/Pollux12/vscode-gmod-glua-ls> | VS Code extension wrapping the above, auto-downloads annotations, debugger | 2026-11-02 | MIT | Yes (VS Code) | Medium: editor-side; annotations repo usable standalone |
| annotations-gmod-glua-ls | <https://github.com/Pollux12/annotations-gmod-glua-ls> | Annotation set for gmod-glua-ls | 2026-11-02 | not checked | n/a | Needed when running `glua_check` outside VS Code |
| gmod-luals-addon | <https://github.com/Pollux12/gmod-luals-addon> | LuaLS plugin (predecessor) | 2026-04-13, **archived** | MIT | n/a | Do not use; superseded by gmod-glua-ls |
| glua-api-snippets | <https://github.com/luttje/glua-api-snippets> | Scrapes the wiki into LuaLS annotations; listed in the LuaLS addon manager | 2026-11-01 (automatic releases) | MIT | Yes (LuaLS 3.17.1 is in nixpkgs) | High if you prefer stock LuaLS; `lua-language-server --check` gives CLI diagnostics [unverified flag usage] |
| GLua Enhanced | <https://github.com/WilliamVenner/vscode-glua-enhanced> | VS Code extension: completion, wiki integration, snippets | 2026-06-03 | GPL-3.0 | Yes | Low for agents; incompatible with gmod-glua-ls per its README |
| GLuaFixer / glualint | <https://github.com/FPtje/GLuaFixer> | Linter + pretty printer for GLua (`&&`, `!=`, `continue` aware) | 1.30.0 on 2026-09-12 | LGPL-2.1 | OSX x86_64 binary (Rosetta on Apple Silicon); repo has `flake.nix`; `haskellPackages.glualint` 1.29.0 in nixpkgs is marked **broken** | High: fast CLI, `log_format` option |
| luals_gmod_include | <https://github.com/CFC-Servers/luals_gmod_include> | Makes LuaLS understand GMod `include` | 2025-06-03 | GPL-3.0 | n/a | Medium, only for stock LuaLS |
| gmod_luals_workflow | <https://github.com/CFC-Servers/gmod_luals_workflow> | GitHub Actions workflow running LuaLS checks | 2025-06-12 | GPL-3.0 | CI | Medium: template for CI |
| gmod-wiki-scraper (NullEnt1ty) | <https://github.com/NullEnt1ty/gmod-wiki-scraper> | npm CLI: dumps the wiki to JSON | 2026-09-20 | MIT | Yes (Node) | Medium: offline JSON corpus for grep |
| Facepunch wiki raw endpoints | <https://wiki.facepunch.com/gmod/DHTML:AddFunction?format=text> | Every page as XML-ish markup (`?format=text`) or JSON (`?format=json`); `~pagelist?format=json` lists pages | live | n/a | Yes | High: curl/WebFetch gives exact signatures; no MCP needed [verified by curl] |
| glua Claude Code skill | <https://github.com/Alleexxi/glua-claude-skill> | Skill/plugin with per-member reference files (signatures, realms, panels, hooks, enums) from the wiki | 2026-06-04 | MIT | Yes | High: install via `/plugin marketplace add`; data frozen at June 2026. `chshr247/glua-claude-skill` is an identical non-fork copy (2026-07-24) |
| GMod-MCP-Server (AmyJeanes) | <https://github.com/AmyJeanes/GMod-MCP-Server> | MCP bridge via files in `garrysmod/data/mcp/`: run Lua, console read, `screenshot_cl`, `reload_file_cl/sv`, entity/player tools | 2026-11-03 | MIT | Partial: Lua addon + .NET server are cross-platform; `host_launch`/foreground/close logic is Windows-specific (`gmod.exe`, WMI) [verified in `GameProcessManager.cs`]. Untested on macOS | Highest of the MCPs: screenshot + hot reload + error capture |
| GmodMCP (Celant) | <https://github.com/Celant/GmodMCP> | MCP server inside a binary module (HTTP on `localhost:27513`): console, Lua, files, client screenshot, input incl. VGUI clicks | 2026-07-10 | MIT | Unclear: no prebuilt releases, build yourself; binary modules on macOS client not confirmed | Medium: powerful but needs a native build |
| gmod-mcp (ProjectSocietyStudio) | <https://github.com/ProjectSocietyStudio/gmod-mcp> | Node MCP + file-transport addon for a dedicated server; client relay via net messages; `read_panels`, `inspect_panel` | 2026-08-14 | MIT | Probably (Node + Lua) [unverified] | Medium: server-focused; panel inspection is useful |
| gmod-mcp (mathis1M) | <https://github.com/mathis1M/gmod-mcp> | MCP + native bridge (`127.0.0.1:17905`) + addon; Lua exec, screenshot | 2026-08-16 | MIT | **No**: README lists Windows or Linux only | Low for this user |
| gmod-mcp (DBOYttt) | <https://github.com/DBOYttt/gmod-mcp> | Python MCP driving srcds via PTY and the Linux client via xdotool | 2026-05-27 | none | **No** (Linux/X11) | Low |
| GModPatchTool | <https://github.com/solsticegamestudios/GModPatchTool> | Patches GMod CEF to 137, fixes macOS launch crash | release 2026-07-22, push 2026-10-30 | GPL-3.0 | Required on macOS | Prerequisite for running GMod on the Mac |
| Facepunch/gmod-html | <https://github.com/Facepunch/gmod-html> | Source of GMod's CEF abstraction layer | 2026-09-23 | MIT | n/a | Reference only |
| Stock menu HTML | <https://github.com/Facepunch/garrysmod/tree/master/garrysmod/html> | GMod's own main menu is HTML + AngularJS (`menu.html`, `js/`, `loading.html`) | 2026-10-15 | not stated | n/a | Reference for a production HTML menu in GMod |
| gmod-html-comms | <https://github.com/Rubberbandits/gmod-html-comms> | Helper for bidirectional Lua ↔ JS messaging | 2025-07-20 | Unlicense | n/a | Low/medium: README is one line; read source before use |
| GmodMenuRemake | <https://github.com/VanderCat/GmodMenuRemake> | Vue 2 rewrite of the GMod menu (WIP) | 2022-02-02 | none | n/a | Low: stale, but shows a Vue build copied to `garrysmod/html` |
| Mantle | <https://github.com/darkfated/mantle> | UI + renderer library; modified RNDX with Kawase blur, acrylic; docs site with screenshots | 2026-11-02 | MIT | n/a (Lua) | High for the HUD and any Lua panels |
| RNDX (original) | `github.com/Srlion/RNDX` | Shader-based anti-aliased rounded shapes, blur | **Repo returns 404 today** (deleted or private); copies in Mantle and `acasamit/RNDX` (2025-07-07, MIT) | MIT | n/a | Use Mantle's copy |
| PIXEL UI | <https://github.com/TomDotBat/pixel-ui> | Derma replacement, scaling helpers | 2026-06-29 | GPL-3.0 | n/a | Medium; GPL affects a paid/closed gamemode. `Pulsar-Dev/pulsar-ui` is an archived fork |
| MelonLib | <https://github.com/melonstuff/melonlib> | UI dev library: panel debugger, fonts, image cache, module loader | 2026-09-07 | MIT | n/a | Medium; plus `melonsshadows` (2023) and `melonsroundedboxes` (2024) |
| TDLib | <https://github.com/Threebow/tdlib> | Chainable Derma styling helpers | 2019-10-09 | MIT | n/a | Low: unmaintained |
| XPGUI | <https://github.com/XenPare/gmod-xpgui> | "Modern VGUI framework" | 2024-12-12 | Apache-2.0 | n/a | Low: near-empty README |
| DermaWind | <https://github.com/Zak2801/DermaWind> | Small UI library | 2026-01-06 | MIT | n/a | Low: 2 stars |
| FatedUI | <https://github.com/darkfated/FatedUI> | Older UI lib by Mantle's author | 2023-10-01, archived | GPL-3.0 | n/a | Superseded by Mantle |
| 3D2D imgui | <https://github.com/wyozi-gmod/imgui> | Immediate-mode UI on 3D2D surfaces | 2025-06-02 | MIT | n/a | Only for in-world screens |
| Royal Derma Designer | <https://github.com/glua/Royal-Derma-Designer> | In-game Derma/VGUI designer | 2024-07-29 | none | Runs inside GMod | Low: no export to a reusable format confirmed |
| dermadesigner (Gigabait) | <https://github.com/Gigabait/dermadesigner> | Old in-game designer | 2018-08-04 | none | — | Dead |
| Playwright MCP | already configured locally | Browser automation + screenshots | n/a | Apache-2.0 | Yes | High: preview loop for the HTML UI |

Not found (searched GitHub and the web): a web-based Derma previewer/emulator, a Figma-to-Derma exporter, a dedicated wiki-lookup MCP server, an `html_loader` repository, a maintained React/Svelte-for-GMod framework, published Cursor rules for GLua. "Lyn" and "mgui" did not match any GMod UI library.

## 3. Details by area

### 3.1 AI assistant tooling for GLua

**API lookup.** The simplest reliable lookup is the wiki itself: `https://wiki.facepunch.com/gmod/<Page>?format=text` returns the page source with `<realm>`, `<args>`, `<rets>`, `<note>`, `<warning>` tags; `?format=json` returns metadata and `~pagelist?format=json` lists all pages. [verified by curl] A CLAUDE.md rule such as "before using a GMod function, fetch its wiki page with `?format=text`" gives the agent ground truth without an extra server.

The `glua` skill (Alleexxi) packs the same data offline: 334 globals, 45 classes, 88 libraries, 130 panels, hooks and enums, with realm per member. Its data is a June 2026 snapshot; the wiki endpoint is always current. [verified: README]

**Language server and diagnostics.** Two viable stacks; do not run both in the same editor:

1. **gmod-glua-ls** (Rust, hard fork of EmmyLua Analyzer Rust). `cargo install glua_ls glua_check`. `glua_check` supports `--output-format json|text|sarif`, `--warnings-as-errors`, and `.gluarc.json` / `.luarc.json` config. [verified: `crates/glua_check/src/cmd_args.rs` and crate README] Outside VS Code you must pass the annotations path manually (README). GMod-aware realm and net-message checks are its main advantage for AI-written code, which often mixes client and server functions.
2. **Stock LuaLS + glua-api-snippets.** LuaLS 3.17.1 is in nixpkgs. Example `.luarc.json` in the snippets README sets `runtime.version: LuaJIT`, `nonstandardSymbol` for `!=`, `&&`, `||`, `continue`, and `include` as `dofile`.

**glualint** catches GLua-specific style/syntax issues and pretty-prints. On Apple Silicon, use the OSX x86_64 release under Rosetta or try `nix run github:FPtje/GLuaFixer` (flake exists; darwin build not tested here). The nixpkgs `haskellPackages.glualint` is 1.29.0 and marked broken. [verified: nix eval]

Wiring for the agent [proposal]: a `make check` (or `just check`) target that runs `glua_check . --output-format json` and `glualint lint gamemode/`, plus a Claude Code `PostToolUse` hook on `Edit|Write` for `*.lua` files that runs the same checks on the changed file.

### 3.2 Previewing Derma/VGUI outside GMod

- No Derma emulator, web previewer or Figma exporter was found. Derma depends on the Source engine VGUI and the `surface` library; reproducing it outside the game would be a project in itself.
- In-game designers exist (Royal Derma Designer, older dermadesigner) but they are not useful for an AI loop.
- `derma_controls` console command shows stock controls in-game. [verified: wiki `VGUI_Element_List` via search summary]
- **Headless GMod:** `-textmode` disables rendering, so it cannot produce UI screenshots [unverified]. A Linux dedicated server (srcds) can run in CI, but client rendering needs a real GPU session. On macOS the realistic option is a normal windowed client plus an MCP screenshot tool. MCP host-launch automation found today targets Windows (AmyJeanes) or Linux/X11 (DBOYttt).
- **Screenshots in-game:** Source console commands `jpeg` / `screenshot` write to `garrysmod/screenshots/` [unverified for GMod specifically; standard Source behaviour]. On macOS that folder is probably under `~/Library/Application Support/Steam/steamapps/common/GarrysMod/garrysmod/screenshots` [unverified path]. Programmatic capture: `render.Capture({format = "png", ...})` in `GM:PostRender`, then `file.Write` into `data/`; outside render hooks the result is black and it returns `nil` while the escape menu is open. [verified: wiki `render.Capture`]
- **Hot reload:** auto-refresh does not work on OSX; use `lua_refresh_file <path>` (file must have been included before) or `lua_openscript_cl` (needs `sv_allowcslua 1`). [verified: wiki `Auto_Refresh`, `ConVars_In_Garrysmod` via search summary] The AmyJeanes MCP exposes `reload_file_cl` / `reload_file_sv` for the same purpose.

### 3.3 HTML-based UI in GMod

**Engines (current wiki, `HTML_Web_Engine`)** [verified]:

| Platform | Branch | Engine |
| --- | --- | --- |
| Windows | all branches | CEF 86 ("Stable") |
| Linux | main/dev | Awesomium (≈ Chrome 17) |
| Linux | x86-64 | CEF 80, crashes for some users; GModPatchTool → CEF 137 |
| macOS | x86-64 only | CEF 80, crashes on load for all users; GModPatchTool → CEF 137 required |

Note: the premise "Awesomium on main, Chromium on x86-64" is outdated for Windows; only Linux main/dev still uses Awesomium. The wiki advises not to detect Chrome version or branch; detect Awesomium via `navigator.userAgent` and show a fallback/warning. Known CEF gaps: no mp4 (without patch), YouTube issues, IME problems. GModPatchTool's CEF uses Site Isolation, which clears JS state on navigation — design the UI as a single page that never navigates. [verified: GModPatchTool README via search summary]

**Bridge API** (`DHTML`, wiki) [verified]:

- `SetAllowLua(true)` is required before the page may run Lua; it is off by default. Keep it off and expose only named functions via `AddFunction` — safer.
- `AddFunction(lib, name, cb)` — must be called after the document has loaded.
- `QueueJavascript(js)` / `Call(js)` — no return value; processed only while the panel is visible (hide by overriding `Paint`, not with `SetVisible(false)`, if you need updates while hidden).
- `RunJavascript(js)` exists on the base `HTML` panel [unverified details].
- Relative URLs like `/images/x.jpg` do not work. Use `asset://garrysmod/...`, absolute HTTPS URLs, or `data:` URIs.

**Loading and distribution:**

1. Development on your Mac: put the built UI in a mounted folder and load `asset://garrysmod/...`; fastest iteration. The wiki warns not to point at the `addons` folder path directly — use the mounted game path.
2. Distribution: Workshop GMA cannot contain `.htm/.html/.css/.js` (and `.txt` outside allowed paths). Options: (a) build a single-file HTML (inline JS/CSS/fonts/images as base64) and embed it in a Lua file as a long string, sent by `AddCSLuaFile`, loaded with `SetHTML`; (b) host on HTTPS and `OpenURL` (needs internet; works on CEF); (c) `data_static/*.txt|json` is whitelisted and could carry the bundle, read via `file.Read` [unverified that this path works for this purpose]. Option (a) is the most self-contained; check Lua file size limits for very large bundles [unverified limit].
3. GMod's own main menu and loading screen are HTML (AngularJS) in `garrysmod/html/` — proof that the approach is used in production by Facepunch.

**Performance and input** [unverified, community knowledge]:

- Each `DHTML` panel is an off-screen browser whose frame is uploaded as a texture; several large panels or CSS animations cost frame time. Use one panel per screen, avoid heavy blur/backdrop-filter and continuous animations, and remove the panel when the menu closes.
- Keyboard/mouse input requires `MakePopup()` on the parent frame; while it is open the player cannot move, which is fine for menus and the lobby but wrong for the HUD.

**Recommendation: HTML for menus, lobby, loadout, gunsmith, scoreboard, end-of-round screens. Lua `surface`/`draw` (+ RNDX via Mantle) for the HUD, killfeed, hitmarkers and crosshair.** The HUD updates every frame and must never take input focus; Lua drawing is cheaper and has no browser startup latency. The scoreboard is borderline: HTML works because it is input-driven and data can be pushed every 0.25–0.5 s.

**Mock bridge** [proposal]: a `bridge.ts` module exports `send(action, payload)` and `onState(cb)`. In GMod, `send` calls `window.gm.action(JSON.stringify(...))` registered with `AddFunction`; in a browser it calls a mock that returns fixture data and simulates server responses (timers for lobby countdowns, random scoreboard updates). Playwright then screenshots each screen at three resolutions with the same fixtures that the Lua side uses in a dev concommand (e.g. `cod_ui_debug lobby`).

### 3.4 Lua UI libraries

- **Mantle** (darkfated, MIT, active 2026-11-02): renderer based on modified RNDX (rounded shapes with shader anti-aliasing, Kawase blur, acrylic), panels, docs with screenshots, `mantle_menu` test menu. Best current fit for a HUD and for any Lua panels; MIT is friendly. [verified: README]
- **RNDX**: original `Srlion/RNDX` is gone from GitHub (404; the author's other repos are still listed). Its README (mirrored in `acasamit/RNDX`) describes Shader Model 3.0 rounded shapes, blur flags, works in `3D2D` and `Paint` functions. The Facepunch wiki `custom_shaders` page cites it as an example. Prefer Mantle's maintained copy. [verified: API 404, mirror README, user repo list]
- **PIXEL UI** (GPL-3.0): Derma replacement with scaling helpers; licence matters if the gamemode is sold.
- **MelonLib** (MIT): panel debugger and asset helpers; useful for inspecting AI-generated Lua panels.
- **TDLib, XPGUI, DermaWind, FatedUI**: stale, tiny or archived.
- Scaling: no dedicated library found; use a single `scale(px) = px * ScrH() / 1080` helper and regenerate fonts on `OnScreenSizeChanged`. [proposal]

### 3.5 Visual verification loops

1. **Browser loop (primary):** Vite dev server → Playwright MCP `browser_navigate` + `browser_resize` + `browser_take_screenshot` → agent reads the PNG. Add a CSS-compat lint (for example `stylelint-no-unsupported-browser-features` or `doiuse` with `browserslist: "chrome 86"`) [unverified tool names/behaviour] because Playwright's Chromium is much newer than CEF 86 and will hide incompatibilities.
2. **In-game loop (confirmation):** AmyJeanes MCP `screenshot_cl` returns the real rendered frame including HUD; `console_read_cl` surfaces Lua errors raised outside a tool call. Enable with `mcp_enable 1` in the console; Lua execution needs `mcp_allow_unsafe 1`. Launching GMod must be done by you on macOS (host tools are Windows-specific). [verified: README + source]
3. **Fallback without MCP:** a dev concommand that calls `render.Capture` in `PostRender` and writes `data/ui_snap.png`; the agent reads the file from the GMod `data` folder.

## 4. Open questions to verify before committing

1. Does the AmyJeanes file bridge work on a macOS client (the .NET server's GMod path detection may assume Windows Steam paths)?
2. Exact macOS GMod install path and `screenshots`/`data` folder locations on this machine.
3. Maximum practical size of a Lua string sent via `AddCSLuaFile` for an embedded UI bundle.
4. Whether `glua_ls`/`glua_check` darwin-arm64 builds work with the annotations repo outside VS Code.

## 5. Sources

- Facepunch wiki: `DHTML`, `HTML_Web_Engine`, `Auto_Refresh`, `render.Capture`, `Workshop_Addon_Creation` — <https://wiki.facepunch.com/gmod/>
- gmad whitelist: <https://github.com/Facepunch/gmad/blob/master/include/AddonWhiteList.h>
- Repository READMEs and GitHub API metadata for every repository in the table (fetched 2026-11-03).
