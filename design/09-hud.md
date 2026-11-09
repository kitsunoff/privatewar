# 09 — HUD

Status: decided.

## Goal and scope

In-match HUD: element registry, hitmarkers, killfeed, score popups, scoreboard, compass, markers.

## Decisions

- Immediate-mode HUD in Lua (see `../DESIGN.md`, Decided).

1. **Keep the vanilla HUD; draw only our additions on top. As simple as possible.**

   | Element | Source |
   | --- | --- |
   | Health, ammo | Vanilla GMod HUD or the weapon base's own HUD (ARC9, TFA) |
   | Crosshair | Vanilla or the weapon base's |
   | Killfeed | Vanilla `DeathNotice` of the base gamemode |
   | Scoreboard (Tab) | Vanilla base gamemode scoreboard (superseded by the 2026-11-10 revision below) |

2. **Our overlay elements.**
   - Effects: hitmarker (red on kill); score popups ("+100", "+50 Headshot") from `PW_ScoreEvent` (`06-progression.md` decision 3); medals (icon, name, sound) for events with `Medal = true`.
   - Minimum required by other decisions:
     - match status: team scores (`team.GetScore`) and time left, computed locally from `pw_phase_end` (`00-core.md` decision 10);
     - Domination point status (A, B, C with owner colour), drawn by the mode's own element;
     - radar: a circle in a corner; teammates always, enemies only while a UAV is active, jammed by Counter-UAV (MVP streaks, `05-loadout.md` decision 10);
     - phase messages: "Match starts in 10", "Victory" / "Defeat" in `POSTMATCH`.

- **Revision 2026-11-07 (user decisions after the first playtest; decision 2 stays valid for everything not mentioned here):**

  1. **Killstreak element.** Three squares on the right edge, one per streak in the player's set, ordered by cost.
     - A progress bar along the squares fills with kills or score, depending on the streak earning mode.
     - A square lights up (usable) when the bar reaches its cost.
     - The selected streak is highlighted; ready streaks show the key or the gamepad hint.
  2. **XP bar in the MWR style.**
     - A thin full-width bar at the bottom edge: the current level at the left end, the next level at the right end, an eased fill.
     - On level-up the bar fills to full and restarts.
     - A "LEVEL UP" popup is shown centred in the upper middle. It goes through the same queue as the medal popups, so they never overlap.
     - The old top-left LVL element is removed.
  3. **Scoreboard (match status) moves from the top centre to the top left, under the radar** (the radar stays in the corner).
     - Per team a horizontal bar in the team colour, filled by score / score limit, with the number next to it.
     - A semi-transparent L-shaped outline marks the full bar length, which is the score limit.
     - The own team is on top.
     - FFA shows you and the leader (you and second place if you lead).
     - The match timer sits next to the bars.
     - The Domination flag tiles stay in the top centre.
  4. **No "Match starts in N" message (user request after the playtest, T-11.10).** The lobby stays open in `PREMATCH` and its START button shows the countdown ("STARTING N…", accent text on a dark fill); an announced map change shows "MAP CHANGE N…" on the same button and a map change popup (`00-core.md` d.9, `08-lobby.md`). Pending confirmation of the exact look: the local manual checklist (not published) section 45.

- **Revision 2026-11-08 (user-approved T-11.11; overrides decision 1 for health and ammo only):**
  - Bottom left: the local player's nickname, below it three small armor bars representing 50 armor each (150 in total), below them a simple health bar. Armor fills continuously within each segment; presentation clamps to 0..150. Health uses the player's actual maximum. No numeric health/armor or portrait.
  - Bottom right: only the active weapon's localized name and magazine / reserve primary ammo. A clipless weapon shows `- / reserve`, never a fabricated magazine; a weapon without primary ammo shows its name only. Long names fit without splitting UTF-8.
  - These elements appear only for the living local player during `LIVE`, never an observed player. Hide the corresponding native health/battery or ammo panels only while their custom replacement is enabled, visible and successfully drawing; disabling the HUD or a replacement, or an error/missing module, restores vanilla.
  - Preserve grenade equipment above the weapon and the bottom XP strip. Use the existing palette and font families. No changes to health/armor maxima, damage, loadouts or balance; crosshair, killfeed, Tab, radar, XP, streaks and other elements keep their existing decisions.

- **Revision 2026-11-10 (user-approved custom in-match scoreboard; overrides decision 1 for Tab only):**
  - Hold the standard `+showscores` binding (Tab by default) during `LIVE` to show a custom table in the current match-result style. Reuse its table component, palette, fonts and own-player highlight. Releasing closes it; no movement or mouse capture.
  - Team modes group by the public current teams, own team first, with the published mode-specific team totals; FFA ranks by kills. Show public kills, deaths and score, distinguish bots and separate spectators/JIP holdouts. Never show hidden positions, targets, equipment, bomb possession or inferred living/dead state.
  - Keep the result/vote/lobby and pause flows intact. Close on phase exit, module disable, lost focus or an open pause/native menu; a death class picker may remain underneath. Native controller View also holds the board; arrows/d-pad scroll and Page Up/Down page without borrowing movement keys.
  - Use existing replication only. Optional mode presentation may use already published public or own-player data; Infection shows own round wins, not an invented live leaderboard. No new assets or dependencies. Cache text/layout outside Paint, refresh data at most four times per second only while visible, cull offscreen rows, and retain UI scaling and native fallback on disable/build failure.

3. **One `HUDPaint` iterating the `HUDELEMENT` registry (kind `hud/`).**
   - An element is a `Draw` function plus subscriptions to events; modes and modules bring their own elements (Domination: points; streaks module: radar).
   - Element calls go through `PW.Call` (pcall + profiler, `00-core.md` decision 6; `01-extensibility.md` decision 15).
   - No layers, no animation framework, no themes.

## Interfaces

TBD.

## Performance budget

- No allocations in `HUDPaint`.
- Fonts, materials and colors are cached.
- One `HUDPaint` iterates the HUD element registry.

## Security

TBD.

## Open questions

None.
