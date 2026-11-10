# Task design questions

Moved from [TASKS.md "Design tasks still open"](../TASKS.md#design-tasks-still-open); that heading remains a stable entry point.
These are not implementation tasks. Each one blocks the phase named.

| Id | Topic | Blocks | Where |
| --- | --- | --- | --- |
| ~~D1~~ | Frontend: widget kit, fonts (open licence), operator scene, input (mouse/keyboard/gamepad). Decided 2026-11-07, see `design/10-frontend.md`; font files pending D4 | — | `design/10-frontend.md` d.3–d.13 |
| D2 | Camera and killcam: single `CalcView` owner, camera stack, killcam recording on the server | P9 | `design/11-camera.md` |
| D3 | Audio: announcer, music states, UI sounds, asset licensing | P9 | `design/12-audio.md` |
| ~~D4~~ | Licence of the gamemode: **GPL-3.0-or-later**. Decided 2026-11-07. Vendoring is allowed only for code under a GPL-compatible licence, with its notice in `THIRD_PARTY_NOTICES.md` | — | `LICENSE`, `THIRD_PARTY_NOTICES.md` |
| ~~D5~~ | Gamemode name: **Private War**, folder `privatewar`, Lua prefix `PW` (hooks `PW_*`, ConVars `pw_*`). Decided 2026-11-06 | — | — |
