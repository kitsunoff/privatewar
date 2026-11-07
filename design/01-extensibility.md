# 01 — Extensibility

Status: decided (in-game confirmation tests pending, see `../notes/09-lua-file-shadowing.md`).

## Goal and scope

The extension model for the whole gamemode: how content and behaviour are added by built-in modules and by Workshop addons written by third parties.

Extensions are written both by the gamemode authors and by players. The model must be stable and documented enough for third-party Workshop authors.

## Decisions

1. **Vanilla GMod approach: registries + hooks.** No custom event bus, no `hook.Call` override, no replacement of the `hook` module.
   - Rationale: it is the model every GMod author already knows (SWEP/SENT registries, `hook.Add`). It keeps the core small (suckless).
2. **Definitions go into registries.** Modes, streaks, perks, HUD elements, weapon adapters and other "things that exist" are registered as tables in a typed registry and validated by the core.
   - Rationale: the core needs to list them (mode vote, loadout), pick by priority (weapon adapters), resolve `base` inheritance and assign stable network ids. Hooks cannot do any of this.
3. **Events go through plain GMod hooks** (`hook.Run("PW_*", ...)`).
4. **Discovery through a shared folder.** Extensions are found with `file.Find` on the `LUA` path, so any Workshop addon that ships files under the agreed folder is picked up without the core knowing about it.
5. **Built-in modules use the same mechanism as third-party extensions.** There is no private API for the core's own content.
6. **Extensions are a public, third-party API.** Their interface is versioned and documented.
7. **No manifest.** Like SWEPs, the core loads whatever it finds; there is no per-pack metadata file.
   - Rationale: simplest possible model; nothing beyond what a GMod author already knows.
   - Consequences (accepted):
     - enabling and disabling works per registered entity (for example `pw_mode_kc_enabled`), not per pack;
     - the core cannot list "packs" in the lobby, only registered entities;
     - API compatibility is the extension's own job: the core exposes `PW.API` (integer), and an extension may guard itself with `if not COD or PW.API ~= 1 then return end`.
8. **SWEP-style registration: one folder per kind, one file (or folder) per entity.**
   - Layout: `lua/privatewar/<kind>/<id>.lua`, for example `lua/privatewar/modes/kc.lua`, `lua/privatewar/streaks/uav.lua`, `lua/privatewar/hud/killfeed.lua`.
   - The id is the file (or folder) name.
   - The core creates a global class table for the kind (`MODE = {}`, `STREAK = {}`, ...), includes the file, then registers the table and clears the global. Same as the engine does for `SWEP`. The list of kinds is not hardcoded: kinds are declared by files (decision 16).
   - Two file forms, exactly like SWEPs and SENTs:
     - single file `<id>.lua`, shared, realm split inside with `if SERVER` / `if CLIENT`;
     - folder `<id>/` with `shared.lua`, `init.lua` (server), `cl_init.lua` (client).
   - Inheritance through a `Base` field, resolved after every file has loaded (deferred, like `weapons.OnLoaded`), so load order does not matter.
   - A pack that adds several kinds simply ships files in several kind folders.
   - The registry functions (`PW.<Kind>.Register(t, id)`, `Get`, `GetStored`, `GetList`) are public, so code can also register entities programmatically, like `weapons.Register`.
   - Rationale: identical to the model every GMod author already uses for weapons and entities.
   - Consequence (accepted): two addons shipping the same `<kind>/<id>.lua` path shadow each other and only one is loaded. Which one wins is decided by the Steam mount order, not by the authors, and GMod warns the player about the conflict in the main menu (`../notes/09-lua-file-shadowing.md` §1, §5).
   - Therefore **a built-in entity is never replaced by shipping the same path.** To replace one: register a new id with `Base = "<old id>"`, and veto the old id in `PW_PreRegister` (decision 10) or disable it with its ConVar (decision 11). Authors must use unique file names.
   - Built-in content ships under `lua/privatewar/...` inside the gamemode's own Workshop addon; `lua/` is allowed in a gamemode-type addon, while extra Lua folders inside `gamemodes/privatewar/` outside `gamemode/` are rejected by gmad (`../notes/09-lua-file-shadowing.md` §3, §4).
   - Clients run only files the server sent with `AddCSLuaFile`; with `sv_allowcslua 0` a client's local addons cannot add or replace files, so clients see the same winning file as the server (`../notes/09-lua-file-shadowing.md` §2).
9. **Two kinds of `PW_*` hooks: questions and notifications.**
   - **Question hooks** (for example `PW_CanRespawn`, `PW_SelectSpawn`, `PW_CanPickup`) are called with `hook.Call(name, PW.ActiveMode, ...)`. Any `hook.Add` listener may return an answer; if every listener returns `nil`, the active mode's method of the same name is the default answer. This is the GMod `GM` contract, and DarkRP's `hook.Call(name, DarkRP.hooks, ...)`, applied to the active mode.
   - **Notification hooks** (for example `PW_PlayerKilled`, `PW_RoundEnd`) are **also** called with `hook.Call(name, PW.ActiveMode, ...)`, so the active mode reacts by simply defining a method with the hook's name (no `hook.Add` / `hook.Remove` in `Start` / `Cleanup`). Listeners must not return a value; the rule is documented for every notification hook, because a returned value stops the remaining listeners **and the mode's method**. Debug mode warns when a notification listener returns a value.
   - Order: addon listeners see an event before the mode. Consumers that need the resulting score listen to a separate notification (for example `PW_ScoreChanged`).
   - The only difference between questions and notifications is the return-value rule; the dispatch is the same.
   - Every hook is documented as either a question or a notification.
   - Rationale: no new mechanism; addons can veto or override decisions without rewriting the mode.
   - Accepted weakness (standard GMod behaviour): for question hooks, the first non-nil answer wins and listener order is undefined.
10. **`PW_PreRegister` hook: patch or veto any entity before it is registered.**
    - Signature: `hook.Run("PW_PreRegister", kind, id, tbl)`. A listener may change fields of `tbl` in place, or return `false` to cancel the registration.
    - It runs for every kind, for built-in and third-party entities alike, before `Base` resolution.
    - Equivalent of GMod's `PreRegisterSWEP` / `PreRegisterSENT` and ARC9's `ARC9_LoadAttachment`.
    - It also covers bulk patches (ARC9 `AddAttachmentPatch` style): a listener can match ids by prefix and change fields. A separate patch API is not needed.
    - Rationale: lets an addon tune or remove someone else's content without editing or shadowing its files.

11. **Enable/disable applies at the start of the next match.**
    - Every registered entity gets a server ConVar `pw_<lowercase KIND.Global>_<id>_enabled` (default 1, archived): the kind's class table name in lowercase, for example `pw_mode_kc_enabled`, `pw_module_<id>_enabled`, `pw_weapon_<class>_enabled`, `pw_streak_uav_enabled`. The built-in kinds use their class tables too (`KIND` → `pw_kind_<id>_enabled`, `MODULE` → `pw_module_<id>_enabled`); a registry whose kind has no declaration falls back to its kind id.
    - Naming decided with the user on 2026-11-06, to match the decision 7 example and the decision 16 module name.
    - All found files are always loaded and registered; the flag only filters the entity out of lists (mode vote, loadout, HUD, bots).
    - The core reads the flags once, on the `LOBBY → PREMATCH` transition, and keeps that snapshot for the whole match. Changes made during a match take effect at the next match; no map change is needed.
    - Who may change the flags: the listen-server host and superadmins, checked on the server (global rule 4).
    - Rationale: the active mode cannot be removed mid-match, and removing streaks or perks mid-match needs cleanup code; the lobby phase is a natural safe point.

12. **Hot reload for development.**
    - Registering an existing id **replaces** the entry (not a silent first-wins, which would break hot reload).
    - `GM:OnReloaded` re-runs `Base` resolution and fires `PW_RegistriesLoaded` again. This covers auto refresh on Windows and Linux.
    - Console command `pw_reload` (host and superadmins only) rescans every kind folder on the server and all clients. It picks up new files and is the workflow on macOS, where auto refresh does not work (wiki: Auto Refresh).
    - Accepted limitation: a reload does not touch the running match; reloaded definitions take effect at the next match (same rule as decision 11).

13. **Registry ids travel over the network as strings** (`net.WriteString`).
    - Rationale: ids do not depend on load order, survive `pw_reload`, and need no client/server sync or hash check. Messages carrying ids are rare (kills, streak activation, loadout, votes), so the few extra bytes do not matter.
    - Frequent data (positions, health, timers) carries no registry ids and still follows the bit-packing rule in `../DESIGN.md`.
    - A client that receives an unknown id logs it once and shows a placeholder; it never errors.

14. **API versioning policy.**
    - Public API is only what is documented: `PW_*` hooks, fields and methods of class tables (`MODE`, `STREAK`, ...), registry functions (`Register`, `Get`, `GetStored`, `GetList`) and `PW.*` functions without a leading underscore. Anything prefixed with `_` is internal and may change without notice.
    - `PW.API` (integer) is bumped only on breaking changes: a hook removed or renamed, arguments changed, the meaning of a field changed. Adding hooks or fields does not bump it.
    - No compatibility layer: a breaking change bumps `PW.API` and is listed in the changelog; old packs disable themselves through their own `PW.API` check.
    - Deprecation periods (old hook kept for one version with a warning) are deferred until a real third-party pack community exists (YAGNI).

15. **Error handling.**
    - **Load time.** Every kind file is included through `pcall`. On error the core logs one line (kind, id, file, error); that entity is not registered and loading continues.
    - **Required fields.** Each kind declares a short list of required fields with types (for example `MODE.Name` string, `MODE.ScoreLimit` number). A missing or mistyped required field skips the entity with a readable error. No full schema validator (DarkRP style) — not worth the code.
    - **Runtime, entity methods called by the core** (`MODE:OnKill`, `STREAK:Activate`, HUD element `Draw`, ...) run through `pcall`. On error the core logs one line and disables that entity until the map changes, so an error does not repeat every frame.
    - **Runtime, active mode.** The active mode cannot be disabled in place: the match ends, everyone returns to the lobby, and the host sees "mode `<id>` failed: `<error>`".
    - **HUD cost.** One `pcall` per HUD element per frame (about 20 elements) is accepted in the client budget.
    - **Third-party `hook.Add` listeners** keep standard GMod behaviour: an error in one listener aborts the remaining ones. Changing this would require replacing `hook`, which decision 1 rejects.

16. **Kinds and subsystems are declared by files; the core hardcodes only two kinds.**
    - Requirement: new kinds and whole subsystems can be added by any addon without touching the core.
    - Built-in kind `kinds/` declares a new kind:

      ```lua
      -- lua/privatewar/kinds/streaks.lua
      KIND.Folder   = "streaks"      -- scans lua/privatewar/streaks/
      KIND.Global   = "STREAK"       -- class table name inside files
      KIND.Required = { Name = "string", Cost = "number" }
      ```

    - Built-in kind `modules/` holds subsystem code. A module uses the SENT folder form (`shared.lua`, `init.lua`, `cl_init.lua`) with a `MODULE` table. A module may declare its own kinds, subscribe to hooks and own core-provided extension points (for example the HUD module owns the single `HUDPaint` and iterates the `HUDELEMENT` registry).
    - Every module gets `pw_module_<id>_enabled` (decision 11 timing; global rule 2: a disabled module breaks nothing).
    - Built-in subsystems (HUD, bots, lobby, killcam, ...) are ordinary modules and can be disabled or replaced like third-party ones (extends decision 5).
    - A third-party addon can declare its own kind (for example `kinds/vehicles.lua`), and other addons can add entities to it.
    - Load order:

      ```text
      1. core          loader, the two built-in kinds (kinds, modules), match phases, net helpers
      2. kinds/        all kind declarations from all addons
      3. modules/      all subsystem code
      4. every declared kind folder, in any order
      5. Base resolution for every registry
      6. hook PW_RegistriesLoaded
      7. InitPostEntity (SWEPs are loaded): hook PW_RegisterWeapons(reg), then hook PW_WeaponsLoaded
         (04-weapons.md decision 3)
      ```

    - Rationale: the core stays minimal (loader, two kinds, match phases, net helpers); nothing about streaks, HUD or bots lives in it.

17. **Settings are declared as data by modes and modules; three scopes.**

    ```lua
    -- modes/tdm.lua (scope is always "match" for modes and may be omitted)
    MODE.Settings = {
        scorelimit   = { type = "int",   default = 75,  min = 10, max = 1000, label = "#pw.set.scorelimit" },
        timelimit    = { type = "int",   default = 600, min = 0,  max = 3600, label = "#pw.set.timelimit" },  -- 0 = none
        respawndelay = { type = "float", default = 3,   min = 0,  max = 30,   label = "#pw.set.respawndelay" },
    }
    -- in mode code: self:Setting("scorelimit")

    -- modules/bots/shared.lua
    MODULE.Settings = {
        count      = { scope = "match",  type = "int",  default = 6, min = 0, max = 16, label = "#pw.set.bots.count" },
        difficulty = { scope = "match",  type = "enum", default = "regular",
                       options = { "recruit", "regular", "hardened", "veteran" }, label = "#pw.set.bots.difficulty" },
        tickbudget = { scope = "server", type = "float", default = 2, min = 0.5, max = 10, label = "#pw.set.bots.budget" },
    }
    ```

    - Types: `int`, `float`, `bool`, `enum`, `set` (a set of string ids, for example banned weapon classes or allowed weapon bases).
    - Scopes:

      | Scope | Affects | Shown in | In playlists | Stored as |
      | --- | --- | --- | --- | --- |
      | `match` | Gameplay of the current match, same for everyone | Game Setup in the lobby | Yes | Snapshot taken at match start (decision 11 timing) |
      | `server` | How the server runs between matches | Host settings menu | No | Server ConVar (archived) |
      | `client` | One player only | Personal settings menu | No | Client ConVar (archived) |

    - Full setting id: `<owner id>.<key>`, for example `tdm.scorelimit`, `bots.count`. Used by playlists and on the wire (decision 13).
    - Inheritance: a mode with `Base` inherits the base's settings, may add its own and may change inherited defaults (for example `kc` sets `scorelimit` default to 65).
    - A mode may override defaults of module `match` settings: `MODE.SettingDefaults = { ["health.friendlyfire"] = true }`.
    - Settings screens are generated from the schema. Game Setup shows a "Mode" group first, then one group per enabled module that has `match` settings. Custom UI only through an optional `BuildSettings(panel)`.
    - The server validates every incoming value against the schema (type, `min`/`max`, enum options) and clamps it; handlers do no manual checks.
    - Changing `match` and `server` settings requires a privilege (`00-core.md` decision 7).

18. **Auto-subscription of entities to `PW_*` hooks.**
    - Vanilla mechanism: `hook.Add(name, tbl, fn)` accepts a table with an `IsValid` method as identifier, passes it as `self`, and drops the subscription once `IsValid()` returns false (`garrysmod/lua/includes/modules/hook.lua:33`, `:110-120`, verified in the local clone). NutScript plugins use the same trick.
    - The core subscribes every method of an entity whose name starts with `PW_` through `hook.Add(name, entity, entity[name])`.
    - **Only the `PW_` prefix.** Engine hooks (`PlayerSpawn`, `StartCommand`, ...) are subscribed explicitly with `hook.Add` in module code. Rationale: subscribing every module function by name would make a helper named like an engine hook run every frame.
    - **Each kind declares when its entities are subscribed:** `KIND.Subscribe = "always"` (for example modules, while enabled) or `"never"` (for example streaks and perks, which are dispatched per owner by their module; designed in `05-loadout.md`).
    - Activity is expressed through `IsValid`: a disabled entity, or one disabled after an error (decision 15), returns false, and GMod removes its subscriptions by itself.
    - **Two roles:**

      | Role | Who | How it is called |
      | --- | --- | --- |
      | Default implementation | The active mode | `hook.Call(name, PW.ActiveMode, ...)`, last, like `GM` |
      | Listener | Modules and other entities of kinds with `Subscribe = "always"` | Auto-subscription `hook.Add(name, entity, fn)` |

    - The active mode is **not** auto-subscribed: as a listener its order would be undefined (`pairs`) and it could answer before an addon's veto.

### Override mechanisms (summary)

| Mechanism | Use it to | Status |
| --- | --- | --- |
| `Base` inheritance | Make a new entity based on an existing one | Decision 8 |
| Same-path file | — | Not a supported override: winner depends on Steam mount order (decision 8) |
| Question hooks with mode default | Override a single decision at runtime | Decision 9 |
| `PW_PreRegister` | Tune or remove someone else's entity | Decision 10 |
| ConVar per entity | Disable an entity | Decision 7 |
| Numeric filter chain (ARC9 `XMult`/`XAdd`/`XOverride`) | Stack modifiers from several sources on one number | Not decided; belongs to perks and loadout |
| Detours (wrapping functions) | — | Forbidden (global rule 1) |

## Interfaces

TBD.

## Performance budget

TBD.

## Security

TBD.

## Open questions

1. ~~Folder layout~~ Closed: decision 8. The final `privatewar` folder name depends on the gamemode name.
2. ~~Is a manifest file required?~~ Closed: no manifest (decision 7).
3. ~~Registration style~~ Closed: decision 8 (global class table, SWEP-style).
4. ~~Hook semantics~~ Closed: decisions 9 and 10.
5. ~~Load order between extensions~~ Closed: decision 8. No dependencies; `Base` is resolved after all files load, so order does not matter. Anything that needs another registry's content runs after the `PW_RegistriesLoaded` hook.
6. ~~Enabling and disabling~~ Closed: decision 11.
7. ~~Hot reload~~ Closed: decision 12.
8. ~~Network ids~~ Closed: decision 13.
9. ~~API versioning policy~~ Closed: decision 14.
10. ~~Error handling~~ Closed: decision 15.
11. ~~Same-path shadowing and built-in content location~~ Closed by research (`../notes/09-lua-file-shadowing.md`), decision 8 amended. In-game confirmation tests are listed in that note, §"To verify in game".
12. ~~The final list of kinds~~ Closed for this subsystem: each kind is finalised in its own subsystem (required fields, methods, hooks). Draft list:

    | Folder | Class table | What | Subsystem |
    | --- | --- | --- | --- |
    | `modes/` | `MODE` | Game mode | 02-modes |
    | `maps/` | data only | Map config: spawns, objectives | 03-mapdata |
    | `weapon_adapters/` | `ADAPTER` | Weapon base adapter | 04-weapons |
    | `perks/` | `PERK` | Perk | 05-loadout |
    | `equipment/` | `EQUIPMENT` | Lethal and tactical equipment | 05-loadout |
    | `streaks/` | `STREAK` | Scorestreak | 05-loadout or own subsystem |
    | `score_events/` | `EVENT` | Score event (medals are events with `Medal = true`) | 06-progression |
    | `bot_behaviors/` | `BEHAVIOR` | Bot behaviour | 07-bots |
    | `hud/` | `HUDELEMENT` | HUD element | 09-hud |
    | `screens/` | `SCREEN` | Menu or lobby screen | 10-frontend |
    | `announcers/` | data only | Announcer voice pack | 12-audio |
    | `classes/` | `CLASS` | Ready-made class (also a bot class source) | 05-loadout |
    | `wildcards/` | `WILDCARD` | Pick X wildcard | 05-loadout |
    | `playlists/` | `PLAYLIST` | Curated playlist | 02-modes |
    | `weapons/` | `WEAPON` | Weapon catalogue entry with attachment/camo curation | 04-weapons |
    | `bundles/` | `BUNDLE` | Shop bundle | 06-progression |
    | `models/` | `MODEL` | Player model ("operator") | 06-progression |
    | `cards/` | `CARD` | Calling card | 06-progression |

    Rule already fixed: a kind = a folder + a class table + a list of required fields, declared in `kinds/` (decision 16).
13. ~~Kinds and subsystems addable without touching the core~~ Closed: decision 16.

## Research

- `../notes/09-lua-file-shadowing.md` (same-path shadowing, built-in content location)
