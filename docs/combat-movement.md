# Optional combat movement

The `bots_combat_movement` module refines only `fight`'s direct strafe legs. It defaults **on**.
Change `pw_module_bots_combat_movement_enabled` through the existing entity enable UI or server ConVar.
The ordinary enable snapshot applies the change at the **next match**, not immediately during LIVE.
No separate live toggle or second movement controller is installed.

## Ownership and fallback

- The active utility-selected Action still owns movement; ranks, weights, difficulty data and fairness are unchanged.
- `fight` asks the module for a protected proposal through `PW.Call`. Missing, disabled or failed modules use
  the existing fight movement. A runtime error disables the refinement through ordinary core error handling.
- Direct movement remains `intent.drive`; the follower's `intent.move` retains precedence. Acquiring an active
  fight leg may release an exact inherited `hunt` goal, so suspended roaming cannot keep driving the legs.
  Guard/objective/tactical/critical goals are preserved and take precedence. The planner only proposes this
  release; the active Action commits it through the existing goal API after checking identity and priority.
  The planner never creates goals or writes targets, aim, fire or sprint.
- The fight frame owns its proposal. Loss of sight, suspension, end, death and existing round/match teardown
  release only its exact drive and slide request; replacement values belonging to another writer survive.
- Independent direction rolls allow repeated sides, not predictable mandatory alternation. Ordinary strafe legs
  last 0.3–0.6 seconds; the existing difficulty's strafe probability is retained.

## Safety and cost bounds

The server checks the standing hull corridor and ground support at intervals no larger than 32 units.
Missing ground, solid starts, walls and ground normals below 0.7 reject a side. Both rejected sides stop direct
movement. Ordinary checks use the bot's current command-view yaw; an owned slide checks its live velocity corridor.
Neither check reads a hidden enemy position or forces an aim override.
Dead, airborne, swimming, ladder and nav-owned movement do not enter direct strafing.

Ordinary checks cover 48–96 units, with at most **eight traces per active fight update**: one hull and up to
three support rays per side. A prospective dodge additionally checks its complete conservative launch corridor,
`runSpeed * addonDuration * 1.5 + 32`, at most 512 units and **seventeen additional traces**. Larger corridors
fail closed before tracing. There are no world/entity searches, new per-tick hooks or independent scheduled jobs.

## Quick Slide evidence and limits

The installed addon was measured on the Deck on `gm_construct`, through `PW.BotInput.SetScripted` and the sole
normal StartCommand writer. Fixture placement and velocity were reset between trials, before input acceleration.
No aim override, direct movement setter during a measured trial, velocity boost or modified addon physics was used.
The command view remained yaw 0 throughout the measurements.

| Trial | Observed result |
| --- | --- |
| Straight right / left | Both slide along the intended lateral axis; right is negative world Y |
| Forward | Forward slide, without the earlier forced-aim contamination |
| Forward/right and forward/left diagonals | Both slide along the commanded diagonal |
| Right to left during a right slide | Velocity stays right during the slide; left motion appears after it ends |
| Ordinary lateral movement / sprint | Achievable speeds approximately 200 / 320 units/s, without velocity boosts |
| Simultaneous sprint + duck through `slideAt` | Starts from either ordinary lateral movement or sprint |
| Duck alone / sprint alone | No slide in these trials |
| Sprint held during the slide | Does not reverse or change its launch direction |

Representative right/left launch velocities were about 287 units/s, then 239 units/s, with the public
`GetSliding()` true; the public duration ConVar was 0.75 seconds. These numbers describe this installation,
not a promised addon-independent speed or friction model.
Delayed duck/sprint sequencing was not established conclusively: that probe's request timestamp could expire
the writer's startup window before sprint was emitted. Mid-slide view steering was not tested either.
The refinement implements neither a delayed startup sequence nor a view-steering controller.

Two preliminary probes were rejected: one conflicted with normal quota removal; another ran after a test
had left availability reporting false despite the public addon surface being present. Only the clean map-load
matrix, with GLuaTest skipped and availability true, is accepted as control evidence.

The refinement requests only **straight sideways dodges**, using existing `slideAt`, the shared tactics cooldown,
the unchanged slide probability and recent enemy-damage condition. It requires a standing grounded bot already
moving fast enough, velocity aligned with the chosen side and a supported launch corridor along the actual
horizontal velocity (not the ideal lateral axis). It does not prepare
a dodge by forcing sprint or aim,
generate diagonal slide requests, or try to reverse direction during a slide. Existing peek/close behaviour
is not redesigned. Sprint/fire/ADS and slide key timing remain in the existing input writer.

## Verification

- Exact integration base: `e9d3ccf050e2e596823205ad4706bfe90b2c8c51`; baseline full suite: **1869/0/0**.
- Initial movement tests were observed RED: **0/5**. The two new slide-hold/corridor tests were also observed RED
  before their implementation. Intermediate targeted integration: **13/0/0**.
- Native smoke uses real opponent perception, ordinary utility selection, normal aim and the single input writer;
  it requires both lateral command signs, real displacement and moving fire. It never sets the AI target or input.
- Pre-review full run: **1885/1/0**, 184 groups, 190.393 seconds. All seventeen new cases passed, including the
  planner-owned native smoke (left 5 / right 40 commands, 15 moving-fire commands, 152.2 units displacement).
  The inherited `Device native smoke: legal sight precedes normal usercmd bullets that destroy an enemy sensor`
  failed: sight was recognized, but no shot/attack command followed and the actor remained in `hunt`.
  Its cause has not been isolated with an on/off control; this is **not a green acceptance gate**.
- The preceding ownership-acquisition candidate passed **1885/0/0**, before adding the reentrant-handoff case
  and strengthening same-timestamp cleanup coverage. That historical green does not replace the final red run.
- Post-review RED on `gm_construct`: **1886/3/0**, 184 groups, 184.239 seconds. Exactly the new actual-trajectory,
  reentrant `ClearGoal` and real-commander fixture regressions failed before their corrections. The unchanged device
  smoke passed in this run (40 bullets, 118 attack commands), so the earlier native failure was not reproduced here;
  neither a deterministic movement-layer regression nor a single cause has been established.
- The trajectory regression leaves the ideal lateral corridor clear and places a wall or missing support only on
  an accepted off-axis velocity corridor; the full launch check now follows that actual velocity. The ownership
  regression hands off during `ClearGoal` and requires the newer frame's goal, drive, slide, target and fire inputs
  to survive without an old-frame cooldown write.
- The support fixture now uses real opponent teams and a matching board team. A deterministic real-commander
  control shows a teamless guard is cleared while the fixture's team guard is retained. This isolates the invalid
  fixture assumption, not the cause of every historical no-fire result. All inherited smoke assertions and its
  30-second outer / 23-second observation timeouts are retained; production FFA and commander logic are unchanged.
- The strict LuaLS blocker was reproduced at the existing map-spawn comparator. Its explicit typed comparator and
  `Vector` local preserve ordering logic without disabling checks. Static verification passed after the annotation
  fix. The feature commit was then blocked twice by strict LuaLS `no-unknown` diagnostics in the unchanged
  `hud/sh_vitals.lua` lines 53 and 55. That out-of-scope file was not changed, no rule was disabled, and corrective
  attempts stopped. The feature remains uncommitted; final full gates on a committed revision were not obtained.
- Post-review targeted verification: **22/0/0**, four groups, 7.989 seconds, in one corrective attempt. This includes
  all nineteen movement cases and all three support-native cases. Movement smoke: left 5 / right 40 commands,
  20 moving-fire commands, 128.6 units displacement. Device smoke: 39 bullets, 115 attack commands, exact recognized
  device destroyed, no player contact and owner still dead. A filtered run does not replace the full committed gate.
- Cleanup returned the Deck to the clean integration base with GLuaTest removed; the uncommitted candidate is not
  left deployed as a gameplay build. No merge acceptance is claimed.

### Deck paired cost measurement

One 30-second sampling window per state, following 8 seconds of warm-up, on a clean `gm_construct` load with
GLuaTest skipped. Eight stock-SMG bots fought four legal opponent pairs through normal perception, utility,
aim and input. Fixture invulnerability prevented deaths; it did not change movement or decision parameters.
No profiler detours or forced targets/commands were used. The existing scheduler counters were sampled once
per tick; the existing `pw_profile` accumulator measured protected planner calls.

| Module snapshot | Tick samples | Scheduler mean | Scheduler p99 | Scheduler max | Protected planner calls / mean |
| --- | --- | --- | --- | --- | --- |
| Off | 2001 | 0.865397 ms | 2.209400 ms | 18.430800 ms | 0 / n/a |
| On | 2001 | 0.759065 ms | 2.122000 ms | 2.608600 ms | 815 / 0.138105 ms |

The on-window planner total was 112.555900 ms. The paired scheduler mean difference was approximately
**−0.1063 ms/tick**; p99 differed by **−0.0874 ms**. This single pair is noisy and does not establish a statistically
significant improvement/regression, total server-frame cost, large-map performance or a passed human load test.
It does establish bounded measured work on the target Deck instead of an assumed zero-cost default.
The invulnerable fixture generated no damage, so these averages do not sample the prospective dodge corridor's
extra traces. That path is separately bounded/tested and still needs a representative pressured load test.

Each live window also flipped the archived enable ConVar to its opposite value: the off snapshot remained
invalid with the flag set on, and the next-match on snapshot remained valid with the flag set off. The probe
restored the original ConVars/settings and returned to the lobby.

Human gameplay acceptance remains pending: unpredictability and feel, cover transitions, damage-triggered dodges,
walls/ledges on real maps, controller play and multiplayer. Automated evidence does not pass that checkpoint.
