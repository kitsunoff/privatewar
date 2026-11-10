# Lambda Players: personalities, profiles and bot chatter

Status: **research and proposal, not an approved design**. Inspected on 2026-11-11. Follow-up:
[planned Lambda bot voice](../changes/planned/lambda-bot-voice.md).

## Bottom line

Lambda already contains a large pool of short, context-tagged audio clips and text lines. Private War could use
those installed assets to make its own bots talk without spawning Lambda entities or replacing its bot AI. A bot's
combat personality and its social identity should remain separate: a Camper can have any voice, name and chat style.

This is feasible in principle, not demonstrated compatibility. Lambda's player imitation is a `base_nextbot` entity,
while Private War requires real `Player` bots controlled through `CUserCmd` (`design/07-bots.md` d.2). Lambda's
entity-specific playback methods cannot simply be assumed to work on our Players. The practical integration seam is
the **content and its category format**, with a separately implemented Private War event and playback layer.

## Evidence and boundaries

The source reference is
[Lambda Players: Reborn | YerMash Edition](https://steamcommunity.com/workshop/filedetails/?id=3058063563).
This note describes its inspected Lua behavior and content formats, not any user's installed content or settings.
Integration and playback have not been tested, and audio has not been evaluated by listening. Compatibility with
other versions or content packs is unverified.

References such as `lua/...` in sections 2–7 mean paths **inside that third-party archive**, not repository files.
Third-party material remains outside this repository. Format support is not a claim that matching files exist or play
on every client. Workshop distribution alone is not permission to redistribute content.

## 1. The four different things called a profile

| Concept | Meaning | Relevance to Private War |
| --- | --- | --- |
| Personal profile | Named bundle of a Lambda's identity, appearance, voice/text settings and behavior settings | Possible import source for a consistent character, not a ready-made PW bot |
| Voice profile | Named folders of audio clips grouped by event type | Most useful compatibility format for bot voices |
| Text profile | Named folders of text lists grouped by event type | Optional source for chat; independent of the voice |
| Personality | Numerical chances attached to Sandbox actions and dispositions | Not equivalent to PW's combat personality |

The profile editor builds records with `name`, `model`, `profilepicture`, colors, skin and bodygroups, `voicepitch`,
`voice` and `text` chances, `voiceprofile`, `textprofile`, health, armor, weapons and optional `personality` and
`externalvars` (`lua/lambdaplayers/lambda/panels/profilepanel.lua`, `CompileSettings`). The personal profile tool
stores records keyed by name in `data/lambdaplayers/profiles.json`; startup loads them as `LambdaPersonalProfiles`
when that file exists. Lambda's `ApplyLambdaInfo` applies those values to a Lambda entity, including health, weapons
and movement-related fields (`lambda/sh_util.lua`). **Do not apply the whole record to a PW bot:** those fields can
conflict with our match, loadout and fairness rules. An importer could select just approved social/appearance fields.

At initialization, Lambda independently randomizes voice chance, text chance and pitch. If configured, a model-specific
voice profile wins over random profile selection; personal profile data can subsequently override the choices.
Model-to-voice associations are read from `lambdaplayers/modelvoiceprofiles.json` in DATA
(`lua/entities/npc_lambdaplayer.lua`, `lua/lambdaplayers/autorun_includes/shared/filesystem.lua`).

## 2. Personality is not a voice pack

`lambda/sh_personality.lua` builds a list of personality types with 0–100 chances, random unless a profile overrides
them. Registered types in `autorun_includes/shared/lambda_personalityfuncs.lua` include `Build`, `Tool`, `Combat`,
`Friendly` and `Cowardly`; extensions can register additional types. `lambda/sv_chances.lua` checks action chances in
descending order and runs the first successful action, with special handling for multiple 100% values. These are not
normalized weights or a language model; in particular they drive Sandbox actions such as building and using tools.
Voice and text chances are separately stored values, even though the profile editor presents them with personality.

PW already has combat personality data such as Camper, CQB and Run and gun under
`addons/privatewar/lua/privatewar/bot_personalities/`. Reusing Lambda's `Combat` or `Build` numbers as PW behavior
weights would be an unsupported semantic guess. A **proposed** social profile could instead hold a Lambda voice-pack
ID, speech frequency, pitch and optionally a text profile, alongside—not in place of—the existing PW personality.

## 3. Voice-pack discovery and selection

`lua/lambdaplayers/autorun_includes/shared/filesystem.lua`, `GetVoiceProfiles`, scans mounted GAME content:

```text
sound/lambdaplayers/voiceprofiles/<profile>/<event>/<file>
sound/zetaplayer/custom_vo/vp_<profile>/<event>/<file>
```

It creates `LambdaVoiceProfiles[profile][event]` arrays of sound paths. The code also populates
`LambdaVoiceLinesTable[event]` with the common pool from configured per-event directories, plus custom directories
when configured. For each personal pack, missing `fall` may alias `panic`, or vice versa. Registered voice types are
extensible via `LambdaRegisterVoiceType` (`autorun_includes/shared/d_registervoicetypes.lua`); the built-in types are:

| Event | Intended use |
| --- | --- |
| `idle` | Casual/random speech |
| `taunt` | Attack / combat |
| `kill` | Killing an enemy |
| `death` | Dying |
| `laugh` | Laughing |
| `fall` | Dangerous fall |
| `assist` | Someone else killed the current enemy |
| `witness` | Seeing someone die |
| `panic` | Panic / retreat |

`ENT:GetVoiceLine(type)` in `lambda/sh_util.lua` picks a random entry from the bot's profile for that type. If the
profile exists but the type is missing, `lambdaplayers_voice_voiceprofilefallback` governs whether to look in the
general pool. It also has a `randomengine` path for configured types. A subtle edge case: `GetVoiceLine` can return
`false`, but `PlaySoundFile` tests that result for truthiness before its inner `== false` check; inspect and test
the exact missing-type behavior instead of assuming the documented fallback setting always produces silence.

`LambdaVoiceProfiles` and `LambdaVoiceLinesTable` are observable globals, not a verified stable public contract.
An optional adapter could read them when Lambda is loaded; direct discovery by documented folder structure is another
option. Compare refresh, load order, configuration and maintenance behavior before choosing. Never mutate the tables or
assume that a file listed on the server is present on every client.

## 4. When a Lambda talks

The regular think loop in `lua/entities/npc_lambdaplayer.lua` checks roughly every five seconds. If the Lambda is not
disabled, typing, speaking or prevented from communicating, it rolls voice chance. The selected type is `panic` while
retreating, `taunt` in combat, otherwise `idle`. If the voice roll fails, it may instead roll for text when not in
combat or panic. This is a repeated chance per check, **not a fixed five-second interval between successful lines**.

Other events cause their own checks. In `lambda/sh_hooks.lua`, a kill of the current enemy can trigger `kill` after
the voice-chance roll and an additional one-in-three roll, with a speaking-state condition; otherwise text can be
considered. Witness reactions check range, visibility and random conditions, and assist lines can have a short random
delay. Death, falling and other events have their own call sites. These conditions explain the social effect, but are
not a spec to reproduce verbatim: PW has different match phases, target perception and teams.

## 5. How a line gets from the server to ears

The actual flow in `lambda/sh_util.lua` and `autorun_includes/client/netmessages.lua` is:

1. A Lambda event calls `ENT:PlaySoundFile` with a type or file path. It resolves a category to a random file, computes
   an optional delay, calls `LambdaOnPlaySound`, sets speaking state and broadcasts entity, path, creation ID, position
   and delay using `lambdaplayers_playsoundfile`.
2. A client receives the message and opens `sound/<path>` using `sound.PlayFile` with a 3D attempt. If it encounters
   the specific stereo/3D error, it retries without 3D. It handles a configurable limit of concurrent speakers and
   replaces an existing sound channel for that entity.
3. It derives playback rate from the Lambda's pitch, sends duration back to the server, updates location and volume,
   supports global or positional sound, and renders a voice popup and speaking icon. It also updates mouth movement,
   including handling ragdolls.

This is **not actual microphone input**: it is local playback of a file triggered by a server event, with UI to look
like speaking. The Lambda client code expects entity methods including `GetVoicePitch`, `GetLambdaName`, `GetPFPMat`,
`LambdaMoveMouth` and `SetVoiceLevel`. Our Player bots do not automatically implement that interface. Reusing Lambda's
message or calling its entity method on a Player is therefore unproven and likely coupled to its internals; use an
independent, explicitly tested PW playback path rather than monkey-patching Player or Lambda methods.

For PW, a design must choose whether the listener hears nearby positional sound, a global voice-chat-like channel, or
team-only chatter. Those choices have gameplay implications: a positional enemy line can disclose location, while a
global line may be heard through walls. Recipients, spectator policy, source death/respawn, joining late, overlapping
audio and missing client assets must be specified and tested. A UI popup is separate work, not automatic voice-chat
integration.

## 6. Text chatter

`GetTextProfiles` scans `materials/lambdaplayers/textprofiles/<profile>/` and reads JSON or line-based text per file.
`GetTextTable` combines configured default and addon text sources with `data/lambdaplayers/texttypes`; filenames map to
types. `ENT:GetTextLine` uses a profile list when present, otherwise the common type pool. It can filter links, supports
optional Markov generation, checks conditional keywords and performs keyword substitutions; it also exposes a typing
hook (`lambda/sh_util.lua`). Text includes placeholders such as `/keyent/` and is not safe to present unchanged.

An independent PW text integration would need to define supported placeholders and conditional syntax, recipient and
team rules, formatting, delays, rate limits and moderation. It must handle missing targets, unknown syntax and external
links safely. Voice and text are distinct features: importing a text profile does not synthesize voice.

## 7. Packaged content formats

Lambda's packaged static lists live under `materials/lambdaplayers/data/`, as JSON content in files named `.vmt`.
They include names and category-specific text lists, as well as Sandbox content lists. Text requires a moderation
review before use; no full review is claimed here.

The shared voice pool uses `sound/lambdaplayers/vo/`. This is distinct from named personal voice profiles under
`sound/lambdaplayers/voiceprofiles/` and text profiles under `materials/lambdaplayers/textprofiles/`.
An integration must discover available content rather than infer profile availability from support for these formats.

## 8. Names and text chat: requested expansion

The user also proposes using Lambda nicknames and its text chatter, not just voice. The intended result is a coherent
bot identity: the bot has a believable name and can occasionally send context-aware messages such as an idle line or a
reaction after a kill. A named Lambda personal profile could eventually bind name, voice profile and text profile;
where no personal profile exists, these may instead come from separate pools. Whether identities are tied or randomly
combined is still to be chosen.

### Nickname sources and the existing PW rule

`GetNameTable` in Lambda's `autorun_includes/shared/filesystem.lua` merges the packaged
`materials/lambdaplayers/data/names.vmt`, optional `DATA/lambdaplayers/customnames.json` and content found under
`materials/lambdaplayers/data/customnames/`. A personal profile can also have a name. These are possible sources,
not a guarantee that a particular installation provides any optional names.

PW currently selects unique names before `player.CreateNextBot(name)` in
`addons/privatewar/lua/privatewar/modules/bots_manager/init.lua`; its `sh_names.lua` and `sh_name_pool.lua` implement
the existing editable pool and collision handling. On 2026-11-11 the user approved extending
`design/06-progression.md` d.7 to allow optional names from installed Lambda content, including joke names; its original
restrictions remain applicable to the built-in pool. Preserve uniqueness against
human and bot names, length/encoding validation, deterministic overflow behavior and a working built-in fallback.
Treat arbitrary user-supplied names as untrusted display text and handle reload, duplicate and empty-list cases.

### Chat behavior worth carrying over

Lambda's default text pool is already split into idle, kill, death, death-by-player, witness and response lists;
profile-specific text can override a category. Its keyword system can insert context such as `/keyent/`, and it has
conditional checks, optional delayed typing, link filtering and optional Markov generation. PW should independently
implement a deliberately supported subset rather than execute Lambda functions on a Player or copy its code. Proposed
first cases are idle chatter, killer taunt and victim death response, with a valid victim/killer name where relevant;
avoid emitting a broken placeholder when the relevant player is absent. More advanced conversation, generated text,
typing indicators and the full keyword language are optional, not implied by importing text lists.

Message delivery must be designed and tested for real Player bots: sender identity, global versus team/dead chat,
spectators, match phase, duplicate kill events, delays after death, rate limits and safe display of external text.
Restrict or filter offensive text and links according to user-selected settings; respect multiplayer privacy and never
derive hidden enemy positions or identities beyond intended visibility. No chat behavior has been run in game.

## 9. Proposed integration, not implementation authorization

Recommended first experiment: an **optional, separately owned Lambda content adapter** feeding a PW-owned bot chatter
service. No Lambda entity or Lambda AI runs on behalf of a PW bot. A possible flow is:

```text
PW bot event -> eligibility / chance / cooldown -> content provider
             -> profile + category -> validated file identifier
             -> selected recipients -> independent client playback / optional indicator
```

1. On bot creation assign a stable social identity for the match; keep it across respawns. Use an installed personal
   voice pack when explicitly selected and available; otherwise a separately decided common-pool or silent fallback.
   Do not accidentally give every bot a different random voice after each death.
2. Start with `PW_PlayerKilled` for killer `kill` and victim `death`; gate on actual bot, match phase, enemy/suicide
   semantics and lifecycle. The hook is emitted by `addons/privatewar/lua/privatewar/modules/match_rules/init.lua`;
   inspect its exact contract and timing before use. A low-rate `idle` event is a separate scheduler concern.
3. Add `taunt`, `panic`, `assist` and `witness` only after defining what the event means using existing bot knowledge;
   do not add all-map awareness or expensive per-tick scans. PW's FOV, LOS, delay and fairness rules still apply.
4. Server chooses event and recipients. Use per-bot and global cooldowns/concurrency limits, avoid repeated files,
   define whether death may interrupt idle, and bound messages. These are proposed safeguards, not proven settings.
5. Load and cache small indexed metadata outside hot loops; handle Lambda absent, disabled, reloaded, malformed or
   empty data. Decide whether Lambda globals, independent folder scanning or a verified extension API is the supported
   source. Validate paths against discovered assets rather than accepting arbitrary client-provided paths.
6. Play only content actually available to each client; handle missing, stereo, long or invalid clips and entity
   removal. Test actual GMod mounted-content behavior and P2P; do not assume server paths are automatically delivered.
7. Expose host and listener controls for enabling, frequency, volume and content filtering, with an explicit choice for
   potentially offensive material. Check licensing and permissions before shipping any audio or text. Prefer using
   content independently installed by users rather than copying or embedding third-party files.

Open product decisions: positional versus global/team audio, voice popup style, identity mapping, chat delivery and
moderation, whether to fall back to the mixed general pool, and opt-in defaults. External Lambda names are approved in
`design/06-progression.md` d.7; detailed source selection and filtering are not yet specified.
These proposals do not override decided design or authorize implementation. Future verification needs GLuaTest for
selection, fallback, lifecycle, authority and limits; mounted-asset tests; and human multiplayer, sound, performance
and accessibility checks on an explicitly authorized free Deck.
