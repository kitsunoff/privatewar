# After-match rotation by default for playlists

Status: `planned`

Recorded: 2026-11-21

Approval (2026-11-22): the user approved every design change proposed in this record and the recommended
default of every open question, except where an answer below says otherwise. This approves the design
direction for implementation; push, PR, merge to `main` and publication still need separate approval.

This record is tracking only; it does not authorize implementation, design or API changes, Deck access or
publication. The user chose the direction on 2026-11-21 ("variant 3"); the exact wording of the design revision still
needs approval before implementation.

## Problem (verified in code on 2026-11-21)

- The vote screen exists (`modules/vote/`, T-2.13, T-7.7) but a normal player never sees it. `PW.Phase._Next`
  (`gamemodes/privatewar/gamemode/core/sh_phase.lua:59`) enters `VOTE` only when `pw_aftermatch` is `rotation`, and
  the ConVar defaults to `lobby` (`gamemodes/privatewar/gamemode/core/sv_match.lua:21`).
- `pw_aftermatch` is a bare `CreateConVar`, not a `MODULE.Settings` entry, so it is absent from the SETTINGS screen and
  from Game Setup. Only dev tooling sets it (`scripts/deck/cp1.sh:564`, `:618`; `addons/privatewar-dev/lua/autorun/server/
  pw_cp1.lua:10`, `pw_testgate.lua:41`, `pw_devstart.lua:6`). It is not in `cfg/privatewar_recommended.cfg`.
- `design/00-core.md` d.2 and `design/08-lobby.md` d.3 already require the host to choose the after-match behaviour in
  the lobby. This host control was never implemented.
- A playlist cannot request rotation, although a playlist is the public-match style of play for which rotation exists.

## User request

Variant 3: a match started from a playlist continues as a rotation with a vote by default; Custom games return to the
lobby by default; the host can override both through a visible setting.

## Design changes requiring approval

- [ ] `design/00-core.md` d.2: add a third value. Proposed wording: "The host setting has three values: **auto**
  (default): rotation with vote when the match was started from a playlist, back to lobby in Custom; **back to
  lobby**; **rotation with vote**. The setting is a normal host setting (`vote.aftermatch`) shown on the SETTINGS
  screen."
- [ ] `design/08-lobby.md` d.3: keep "after-match behaviour" in the host's lobby controls and state that it is the
  `vote.aftermatch` setting (SETTINGS > Host). The lobby card is an open question below.
- [ ] `docs/api/core.md` ("Phases and match", ConVar table line `pw_aftermatch`) and `docs/api/modes.md` "Vote module":
  replace `pw_aftermatch` with the question hook `PW_AfterMatch` and the setting `vote.aftermatch`. Shared contracts
  change only through the orchestrator (`CLAUDE.md` working rule 6).

## Target behaviour

| `vote.aftermatch` | Active playlist (`pw_playlist_active`) | After `POSTMATCH` |
| --- | --- | --- |
| `auto` (default) | non-empty (a playlist) | `VOTE` for `pw_vote_time`, then the voted match |
| `auto` (default) | empty (Custom) | `LOBBY` |
| `lobby` | any | `LOBBY` |
| `rotation` | any | `VOTE` (in Custom the vote offers the current mode on the curated map pool, as today) |
| vote module disabled | any | `LOBBY` (no module answers `PW_AfterMatch`) |

The host leaves a rotation through the pause menu item "Return to lobby" (`screens/match_pause.lua:56`, `pw_abort`),
which already exists; no new exit is needed.

## Architecture (rails)

The core must not depend on the vote or playlists modules (`design/00-core.md` d.3, `design/01-extensibility.md`).
So the core asks a question hook and the vote module answers.

1. **Core** (`gamemodes/privatewar/gamemode/core/sv_match.lua`, `sh_phase.lua`):
   - Remove the bare ConVar `pw_aftermatch` and `afterMatchVar`.
   - In `match._ReadSettings()` replace `afterMatch = PW.Phase._AfterMatch(afterMatchVar:GetString())` with
     `afterMatch = PW.Phase._AfterMatch(PW.Ask("PW_AfterMatch", store.mode))`. `PW.Phase._AfterMatch` already maps
     anything unknown (including `nil`) to `"lobby"`; keep that and add a test for `nil`.
   - `_ReadSettings` is called on every machine step; the answer must therefore be cheap (two ConVar reads). Do not
     cache it across a match: the host may change the setting during the match and the value at the end of
     `POSTMATCH` wins.
2. **Vote module** (`lua/privatewar/modules/vote/`):
   - `shared.lua`: add to `MODULE.Settings`:

     ```lua
     aftermatch = {
         scope = "server", type = "enum", default = "auto",
         options = { "auto", "lobby", "rotation" },
         label = "After the match",
         description = "Auto: playlists continue with a vote for the next match, Custom games return to the lobby."
     }
     ```

     Verify the enum option format and `description` support against `gamemodes/privatewar/gamemode/core/
     sh_settings.lua` (enum check at lines 119-192; `description` was added in T-11.8). The ConVar becomes
     `pw_vote_aftermatch` automatically (`sh_settings_store.lua` naming `pw_<owner>_<key>`).
   - `shared.lua`: add the pure function

     ```lua
     ---@param setting string value of vote.aftermatch
     ---@param activePlaylist string pw_playlist_active ("" = Custom)
     ---@return PW.AfterMatch "lobby"|"rotation"
     function lib.ResolveAfterMatch(setting, activePlaylist) end
     ```

     Rules: `"rotation"` → `"rotation"`; `"lobby"` → `"lobby"`; `"auto"` → `"rotation"` when `activePlaylist ~= ""`,
     else `"lobby"`; any other value behaves like `"auto"`.
   - `init.lua`: add `function module:PW_AfterMatch() return lib.ResolveAfterMatch(store().afterMatch(),
     store().activePlaylist()) end`, with two new store fields defaulting to `PW.Setting("vote.aftermatch")` and the
     playlists library's `GetActive()` (nil-safe: `""` when the playlists module is missing), so tests use fakes like
     the other store fields. The default `activePlaylist` also returns `""` when `PW.Playlist._RotationAllowed(false)`
     is false (a scheduled playlist that expired, added by PR #12 in `modules/playlists/init.lua:361`), so `auto` goes
     to the lobby instead of opening a vote that the existing guards (`modules/vote/init.lua`,
     `core/sv_match.lua:238`) would abort.
   - Types: add the store fields and `ResolveAfterMatch` to `lua/privatewar/types/vote.lua`; document the hook
     `PW_AfterMatch` next to `PW_NextMatch` (types and `docs/api/core.md`).
3. **Dev tooling and tests that set `pw_aftermatch`**: switch them to `pw_vote_aftermatch` with the same values:
   `scripts/deck/cp1.sh` (lines 229, 564, 618), `addons/privatewar-dev/lua/autorun/server/pw_cp1.lua:10`,
   `pw_testgate.lua:41` (the guarded ConVar list), `pw_devstart.lua:6` (comment), and every test listed by
   `grep -rln aftermatch addons/privatewar/lua/tests` (at least `core_phases.lua`, `vote.lua`, `match_flow_ui.lua`,
   `core_abort_race.lua`, `core_settings*.lua`, `core_enable.lua`, `loadout.lua`, `streaks.lua`, `equipment.lua`).
   Core tests that drive the machine without the vote module must stub the question hook (or rely on `nil` →
   `lobby`) instead of setting a ConVar. Update `TASKS.md` line 918 wording (testgate backs up
   `pw_vote_aftermatch`) as historical-safe text.
4. **Old archived value**: the old `pw_aftermatch` ConVar is no longer created, so an archived old value is ignored.
   No migration is needed; mention it in the change notes.
5. **UI**: the setting appears in SETTINGS > Host automatically from the schema (`screens/settings.lua`). Verify the
   enum is drawn as a selector there and that its `description` is shown. Optional lobby card: see open questions.

## Implementation steps (TDD; one commit each)

- [ ] Get approval for the design revision wording above; apply it to `design/00-core.md` d.2 and
  `design/08-lobby.md` d.3 (commit `docs(design): ...`).
- [ ] Tests first for `PW.Vote.ResolveAfterMatch` (pure) and the `PW_AfterMatch` answer with a fake store; run them
  red (commit with the implementation of the next step is acceptable if the project keeps red tests out of commits).
- [ ] Add the `vote.aftermatch` setting, `ResolveAfterMatch`, the hook answer and the types.
- [ ] Core: remove `pw_aftermatch`, ask `PW_AfterMatch` in `_ReadSettings`; adapt core tests (`nil` → `lobby`,
  stubbed `rotation`).
- [ ] Switch dev tooling and the remaining tests to `pw_vote_aftermatch`.
- [ ] Update `docs/api/core.md`, `docs/api/modes.md`, `docs/agent-test-map.md` if it lists these cases.
- [ ] Gates, then the human checkpoint.

## Mandatory test cases

Keep every existing T-2.13 and core phase case passing (`TASKS.md` "Mandatory test cases", T-2.13 and the phase
machine cases). New cases (proposed file and names):

- `lua/tests/privatewar/vote.lua`:
  - `ResolveAfterMatch: auto with a playlist is rotation`
  - `ResolveAfterMatch: auto in Custom is lobby`
  - `ResolveAfterMatch: lobby and rotation override the playlist state` (both playlist and Custom)
  - `ResolveAfterMatch: an unknown value behaves like auto`
  - `PW_AfterMatch answers from the store` (fake `afterMatch`, fake `activePlaylist`)
  - `PW_AfterMatch without the playlists module treats the game as Custom`
  - `auto with an expired scheduled playlist goes to the lobby` (fake `_RotationAllowed` returning false)
  - `vote.aftermatch schema: enum, default auto, three options, has a description`
- `lua/tests/privatewar/core_phases.lua`:
  - `POSTMATCH goes to LOBBY when no module answers PW_AfterMatch`
  - `POSTMATCH goes to VOTE when PW_AfterMatch answers rotation`
  - `PW_AfterMatch is asked at the end of POSTMATCH, not cached from the match start` (change the answer during
    `LIVE`, expect the new value to decide)
  - `pw_aftermatch is no longer created`

## Human checkpoint (Steam Deck; requires fresh permission and a free Deck)

- [ ] Fresh settings (no `pw_vote_aftermatch` archived): start a playlist from the lobby, finish the match; the vote
  screen appears after the summary, cards are selectable with the controller, the voted match starts.
- [ ] Start a Custom game; after the match the server returns to the lobby.
- [ ] SETTINGS > Host shows "After the match" with Auto / Lobby / Rotation and its description; changing it during a
  match changes what happens at the end of that match.
- [ ] Pause menu "Return to lobby" leaves a rotation.

## Open questions (recommended defaults)

1. Should the lobby also show the value, as `design/08-lobby.md` d.3 lists it among host lobby controls? Recommended:
   yes, a read-only line on the playlist/Custom screen "After match: Rotation (auto)" that opens SETTINGS > Host; if
   the user prefers, defer to a follow-up.
2. Should a playlist be able to force the value (for example a "one match" event playlist)? Recommended: no for now;
   revisit with `changes/in-progress/scheduled-events.md`, which owns playlist-local behaviour.
3. Should the first match of a playlist also be voted instead of sampled at random by `PW.Playlist.Start`?
   Recommended: no (CoD starts the first match directly); separate task if wanted.

## Gates

- [ ] `nix develop --command make check` and `nix develop --command make test` with `set -o pipefail` before merge.
- [ ] Game tests and the checkpoint require explicit permission and confirmation that the Deck is free; record user
  acceptance separately from automated results.
