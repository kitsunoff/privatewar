# Shipped playlist rotations

The user delegated these concrete content/calendar choices on 2026-11-11. These are offline host-UTC calendars,
not local time, uptime or online events. Intervals include their start and exclude their end, repeating weekly
unless marked daily. Availability is sampled outside matches under the existing playlist contract.

| Rotation | UTC window | Modes (equal weights) | Bot fill target |
| --- | --- | --- | --- |
| Shipment 24/7 Weekends | Saturday 00:00–Monday 00:00 | TDM, KC; DOM/Hardpoint only with eligible authored data | 12 |
| Ground War TDM 32 | Friday 18:00–Monday 00:00 | TDM | 32 |
| Infected | Daily 18:00–24:00 | `pw_infection` | 12 |
| Small Map Moshpit | Monday 00:00–Saturday 00:00 | TDM, KC, DOM, Hardpoint, each only where eligible | 8 |
| Objective Chaos | Tuesday 00:00–Friday 00:00 | DOM, Hardpoint, each only where eligible | 12 |
| Free-for-All Frenzy | Monday 00:00–Sunday 00:00 | FFA | 8 |

On Wednesday 2026-11-11, Small Map Moshpit, Objective Chaos and Free-for-All Frenzy are active all day with stock
enabled content and `gm_construct` installed. Infected is active after 18:00 only with its dependencies. The
pre-existing always-active Free for all and TDM & FFA playlists remain unchanged. Upcoming cards use the existing
48-hour rule, and Custom remains last. No live server/UI observation is claimed here.

## Maps and dependencies

- Standard pool: installed curated `PW.MapList.GetList()` maps plus installed `gm_construct`, `gm_flatgrass` and
  installed Shipment candidates. This fallback does not modify the host's curated list or whitelist.
- Shipment candidates are actual mounted `maps/*shipment*.bsp` files with an underscore/hyphen-delimited
  `shipment` token, not a guessed BSP id. No map downloads, aliases or authored objective layouts are invented.
  Names outside this discovery convention are not promised compatible. Shipment weekends use only that pool.
- Small Map Moshpit uses only installed `gm_construct` and discovered Shipment maps. Flatgrass is excluded.
  This is a compact activity preset on existing content, not a claim that all of Construct is a competitive arena.
- Every composition filters enabled concrete modes and `PW.Map.ModeFits` pairs. Only maps with at least one
  fitting mode and modes with at least one fitting map survive startup. Sampling continues to filter individual
  pairs, so DOM/Hardpoint cannot be sampled on a Shipment without authored objective data. The repository ships
  their layouts on `gm_construct`; no other objective map availability is assumed.
- Infection requires the separate `privatewar-infection` addon, its enabled `pw_infection` mode,
  `pw_infection_rules`, `teams`, `loadout`, `operators`, `player_overrides`, `match_rules`, `lobby`, native
  `weapon_fists` and at least two server slots. No substitute infection mode or melee weapon is supplied.
- Missing startup dependencies reject only that rotation with a readable console reason. It is not published as
  an empty active/upcoming card. Content loss after resolution suppresses availability and its next boundary.
  Pools remain fixed for the session; newly mounted/enabled content needs a fresh startup, not a promised reload.
- Bot play still requires usable navmesh and enough server slots; normal start/nav generation gates remain.
  Ground War means ordinary TDM with a fill target, not vehicles or new Ground War rules. Existing quota reserves
  one slot and caps bots: at maxplayers 12 with one human, the 32 target produces at most ten bots. No playlist
  changes maxplayers. The existing lobby warning reports insufficient slots for the requested fill.

## Match settings and limitations

Ground War overrides `tdm.scorelimit = 150`, `tdm.timelimit = 900`. FFA Frenzy overrides `ffa.scorelimit = 25`,
`ffa.timelimit = 300`, `ffa.respawndelay = 1`. All rotations set only `bots.fill` otherwise. These are existing
match-schema fields; inherited FFA time/respawn fields use the FFA owner id. Ordinary mode defaults and all
unmentioned host settings remain unchanged; playlists are scoped overrides, not a full settings reset.

Hardcore is **not shipped**: no existing Hardcore mode or health/damage schema implements it. An unknown
`health.hardcore` setting from an old design example would fail real validation. Implementing new gameplay rules
is separate work; labelling normal TDM as Hardcore would be misleading. One in the Chamber also remains absent.

## Verification

`playlists_content.lua` adds composition, missing dependencies, map eligibility, schema, UTC exact-boundary,
repeat/clock-jump, Wednesday availability and reserved-slot quota assertions. Existing mandatory playlist and
entitlement suites are unchanged. Engine RED/GREEN, installed map mounting, actual lobby cards, controller and
multiplayer checkpoints still require an authorized game run; static checks alone do not establish them.
