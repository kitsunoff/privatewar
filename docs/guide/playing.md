# Playing Private War

Private War is a casual "modern CoD in Garry's Mod": you alone, or you and a few friends, against bots that move,
take cover and flank. It runs on a player-hosted listen server, so nothing needs a dedicated machine.

Extending the gamemode with your own content is covered in [extending.md](extending.md).

## Start solo with bots

Bots need a listen server with more than one slot. In Singleplayer they cannot be created (the game shows a hint
instead of the lobby).

1. In the GMod main menu choose New Game.
2. Pick the gamemode Private War and a map.
3. Set Max Players to 12 (any value above 1 works; 12 is the recommended value).
4. Start. The lobby opens by itself (F1 toggles it while you are in the lobby).
5. Choose a playlist, or Custom game for a mode and a map. Open Game Setup and check `bots.fill` (the total number
   of players including you) and the bot difficulty.
6. Press START.

Bots fill the free slots up to `bots.fill`, but never above `maxplayers`; one slot always stays free.

## Host for friends

1. Start a game as above: New Game, Private War, Max Players above 1.
2. Make sure Steam P2P is on (`p2p_enabled 1`). The lobby shows a hint when it is off.
3. Friends join through Steam "Join Game". A joining human replaces one bot of the smaller team.
4. The host presses START in the lobby. Only the host can change Game Setup, the Host settings and the enabled
   content; guests see them read only.

Bots exist from the countdown until the vote and are removed when the game returns to the lobby.

## The match flow

1. LOBBY: nobody is spawned. Pick a class and check Game Setup.
2. PREMATCH: a short countdown, then everyone spawns.
3. LIVE: the match runs until the score limit or the time limit of the mode.
4. POSTMATCH: the result (VICTORY, DEFEAT or DRAW), the scoreboard, XP and currency earned.
5. VOTE: a vote for the next map and mode (the host can pick directly), then a new PREMATCH. The host can also
   send everyone back to the lobby from the Match menu.

Built-in modes: Team Deathmatch (TDM), Free-for-all (FFA), Domination (DOM) and Kill Confirmed (KC).

## The menu

The front end has four tabs, switched with Q and E (LB and RB on a gamepad):

| Tab | What it holds |
| --- | --- |
| PLAY | The lobby hub: playlist, party, Game Setup, START |
| LOADOUT | Classes: presets and your own, the class editor, the gunsmith for supported weapon bases |
| PROGRESS | Level, XP, weapon levels, next unlocks, medals |
| STORE | Daily featured bundles, operator models and cards, bought with the match currency |

Settings is a screen opened with F2 (Start on a gamepad), not a tab. It has Personal settings (button hints and the
match menus, saved on your computer), Host settings (host only) and a link to Enabled content.

## Controls

| Action | Keyboard | Steam Deck gamepad |
| --- | --- | --- |
| Move in menus | Arrow keys or WASD | D-pad or left stick |
| Select / back | Enter or Space / Esc or Backspace | A / B |
| Previous / next tab | Q / E | LB / RB |
| Secondary / tertiary action | F / R | X / Y |
| Open settings | F2 | Start |
| Use the selected killstreak | 5 | bind the console command `pw_streak` |
| Select the next killstreak | 6 | bind `pw_streak_next` |
| Lethal equipment | G | bind `pw_lethal` |
| Tactical equipment | 4 | bind `pw_tactical` |

In a match:

- Esc opens the Match menu (resume, change class, settings, return to the lobby for the host, leave game, GMod
  menu). Esc again closes it.
- Shift+Esc opens the normal GMod menu.
- When you die, a compact class picker opens; the new class applies from your next spawn. Respawn is automatic.

The keys 5 and 6 replace weapon slots 5 and 6 only while you hold a streak; with none, they switch weapons as usual.
The key names are the client ConVars `pw_key_streak`, `pw_key_streak_next`, `pw_key_lethal` and `pw_key_tactical`.

## Where your progress is stored

Progression (XP, weapon levels, currency, owned items) is stored on your own computer in
`data/privatewar/progression.json`, and your classes in `data/privatewar/classes.json`. The host stores nothing
between sessions: your client sends its progression to the host when you join. The files are client-local and
forgeable by design: this is a casual game, and a hand-edited file is accepted.

## When something looks wrong

- No bots: check that the game was started with Max Players above 1 and that `bots.fill` is above the number of
  humans.
- A mode is missing on a map: Domination needs map data for that map; the other modes still work.
- A map without a navmesh gets no bots: the lobby offers GENERATE NAVMESH.
