# Operators API

Module `operators` (T-11.9, `design/06-progression.md` d.7, `design/10-frontend.md` d.6). One global operator (player
model) per player, used in every match and in the lobby operator panel; random operators for bots. Bot names are part
of the bots manager (`bots-blackboard.md`, "Bot names").

Files: `lua/privatewar/modules/operators/` (`shared.lua`, `sh_rules.lua` pure, `init.lua` server, `cl_init.lua`
client), screen `lua/privatewar/screens/loadout_operator.lua`, types `lua/privatewar/types/operators.lua`.

## The choice

Client setting `operators.model` (ConVar `pw_operators_model`, shown under Personal settings), an `enum` whose options
are dynamic (`core.md`, "Declaring": `options` may be a function):

| Value | Meaning |
| --- | --- |
| `auto` (default) | The player's own GMod model (`cl_playermodel`) |
| `<name>` | A stock player model by its `player_manager` name (`player_manager.AllValidModels()`, Workshop playermodels included) |
| `models:<id>` | An economy `models` entry (`economy.md`) |

## The list (`PW.Operators.List`, pure)

1. The enabled economy `models` entries, sorted by name: open when `PW.Progression.IsUnlocked(ply, "models", id)` holds
   (bought, level reached, or free: no `Price`), else locked with their price or level.
2. Every stock model, sorted by name. A stock model whose path (lowercase, forward slashes) belongs to an enabled economy
   entry is dropped: the economy entry governs that model (the samples reuse stock paths, for example `swat.mdl`).

## Resolution (`PW.Operators.Resolve`, pure)

The chosen entry when it exists and is not locked; else the `cl_playermodel` entry when it is an open stock entry; else
the first open stock entry in the existing list order (sorted by display name, then id). An open economy entry earlier
in the list never takes priority over stock for a default. With no usable choice and no open stock entry, `Resolve`
returns `nil` and the server and client use the last-resort path `models/player/kleiner.mdl`, even for an empty list.
A rejected choice reports `unknown` or `locked`. The server and the client use the same function, so the lobby shows
what the match will show.

## Net message

| Message | Direction | Fields | `PW.Net.Receive` |
| --- | --- | --- | --- |
| `pw_operator_model` | client to server | `choice` string | `who = "any"`, rate 2 per second, `maxLen` = `MaxChoiceBytes + 1` (65), owner the module |

The client sends it at `InitPostEntity` and on every change of `pw_operators_model` (picker, settings form, console).
The server drops a bot sender and a malformed choice (`CheckChoice`: a string of 1 to 64 bytes, no control characters).
Before storing a well-formed choice, `_OnRequest` checks that its entry exists and is unlocked for the sender; `auto`
is always a valid sentinel. An unknown or locked choice is rejected and logged, leaving both the previous accepted
choice and the current model unchanged. `CheckChoice` is only the syntax check, not the ownership validator.

The list and ownership are checked anew on every request and spawn. A model bought later can be selected by sending a
new request; an accepted model that later becomes locked or unavailable resolves to the safe default at spawn.
A player with no accepted choice uses `auto`. Outside `LIVE` an alive player gets an accepted new choice at once;
during `LIVE` from the next spawn.

## Server: `PlayerSetModel`

- Humans: the resolved choice. Bots: a random entry of the full list (economy models included, locks ignored), picked
  at the first spawn and kept for the session.
- Player colour (`SetPlayerColor`): in team modes (`#PW.Teams.GetActive() > 0`, team in `1..N`) the engine team colour
  (`team.GetColor`), for humans and bots. Otherwise humans use `cl_playercolor`, bots a colour picked once.

## API

| Function | Contract |
| --- | --- |
| `PW.Operators.List(input) -> PW.OperatorEntry[]` | Shared, pure. `input = { stock, economy, unlocked }` |
| `PW.Operators.Resolve(entries, choice, auto) -> entry?, reason?` | Shared, pure |
| `PW.Operators.CheckChoice(choice) -> boolean` | Shared, pure syntax check; the server also validates existence and unlocks before storing |
| `PW.Operators.BotPick(entries, roll) -> entry?` | Shared, pure |
| `PW.Operators.Colour(facts) -> { r, g, b }` | Shared, pure, in 0..1 |
| `PW.Operators.Cards(entries, choice, auto) -> cards, selected` | Shared, pure: the picker cards (`Auto` first; locked cards with `lockText` `"<price> CR"` or `"LV <n>"`) |
| `PW.Operators.LiveInput(unlocked?)` | Shared: the stock models and the enabled economy entries |
| `PW.Operators.LocalList()`, `LocalChoice()`, `LocalModel()` | Client: the local list, the setting, the resolved model path |
| `PW.Operators.Choose(choice) -> boolean` | Client: writes the setting (false for a locked or unknown choice) |
| `PW.Operators.OpenPicker()` | Client: switches the open menu to LOADOUT and pushes `loadout_operator`; console command `pw_operator` |

Internal: `_NewStore`, `_ListFor`, `_OnRequest`, `_OnSetModel` and the state `PW._Operators`.

## UI

- Picker: screen `loadout_operator` (`Tab = "loadout"`), opened by the OPERATOR button of `loadout_classes`. Left: the
  cards; centre: `PWOperator` with the focused or hovered card (locked ones too); right: a `PWInfoCard` (source, model,
  lock reason). Selecting an open card writes the setting.
- `PWOperator` shows `PW.Operators.LocalModel()` by default (the player is a spectator in the lobby, so its own model is
  not set there); `ShowLocal()` re-reads it, the lobby hub calls it on every refresh.
