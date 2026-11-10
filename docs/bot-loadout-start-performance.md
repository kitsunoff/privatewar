# ARC9 bot loadouts: synchronous match-start measurements

This follow-up tests actual native LIVE transitions on the Steam Deck, not `PoolFor` cost multiplied by bot count.
It does not change the pre-first-spawn class-assignment contract, mode timing, bot fairness or validation policy.

## Controlled experiment

`bots_arc9_start_perf.lua` starts real TDM matches on `gm_construct`, with nine real player bots and one host.
Each trial goes through public `PW.Match.Start`, the production LIVE phase notification, nine real `Assign` calls
and the production first-spawn `Give` path. Assertions require exactly nine assignments, exactly nine first bot
loadout applications, and a class already assigned before every first `Give`.

Both arms retain enabled code presets plus exactly two human ARC9 classes. Human uploads are fixture-owned,
unlocks are uniformly open, budgets are 10, the attachment cap is 5, and bans are empty in both arms. The actual
human harvest/repair path runs; it is not replaced with a no-op. All original state is restored afterward.
The same map-generated 18 candidate definitions are used before and after optimization, through a temporary
test-only data file with string ARC9 addresses preserved. This is input data, never cached validation results.
Every provider/static adapter check and current per-bot `PW_ValidateLoadout` question path still runs normally.
No production permission/result cache was introduced.

There are two selection regimes:

- **Fixed:** the real picker receives roll zero and uniform category weights, giving all nine bots the same
  first preset with generation off and on. This isolates pool/selection work from changed weapon issuance.
- **Mixed:** the real picker receives nine evenly spaced rolls and uniform category weights. This holds each
  arm's weapon/build distribution constant across trials and revisions while exercising the expanded source pool.
  It is a controlled pool sweep, not a claim about every random personality distribution in ordinary play.

Each regime has three discovery-cold pairs and six warm pairs, with ON/OFF order alternating by pair:
36 real LIVE transitions per series. Discovery-cold clears only our integration's metadata memo and the public
adapter lookup cache. It is **not** an OS/model-cold start: ARC9 startup model precaching remains enabled.
Warm trials retain metadata caches. Generated definitions never reroll between these trials.

Test-only timing wrappers delegate the original functions unchanged and are removed by GLuaTest cleanup:

- `phase`: wall-clock duration of the real synchronous `_SetPhase("LIVE")`, including assignment and first spawns.
- `frame`: maximum consecutive server Think wall-clock gap in the startup window (PREMATCH through 0.5 s of LIVE).
  This includes engine/render scheduling and GC noise; it is not a client GPU benchmark or whole-session FPS metric.
- `nextTick`: wall time from LIVE transition entry to its next zero-delay timer.
- `pool`, `provider`, `give`, `weaponGive`, `apply`: nested call durations; do not sum overlapping columns.
  `give` covers bot loadout issuance; the lower-level weapon/adapter columns include the host's calls too.

## Bounded local experiments

ARC9's cached slot/option records contain scalar strings and booleans. Previously every discovery read recursively
cloned each record with `table.Copy`; class repair and validation do this repeatedly over large option lists.
The first experiment creates independent shallow copies of these flat records. There is no adapter API change, new
global result cache, timing change, altered catalogue, shared mutable return value or skipped per-bot validation.
The existing metadata memo revision/reload lifecycle is unchanged.

TDD: `arc9_discovery_copy.lua` failed **0/1/0** before the implementation: a warmed read made 37 recursive
`table.Copy` calls where the new regression requires zero. The same case checks independent list/record identity,
caller mutation isolation, unchanged subsequent reads and the scalar-only record invariant.

That change passed a full **1954/0/0** run (195 groups, 219.631 seconds), but the controlled native measurements
did **not** demonstrate an end-to-end startup improvement. It is not evidence that match-start lag is solved.

The second, final local experiment limits save-time offered-option discovery to addresses actually present in a
nonempty build. Previously human class harvest/repair enumerated every weapon slot's option list, even though
`_ValidateBuild` only reads the offered sets for addresses in that build. Empty discovery requests retain their
existing all-slots result, including the inherited gunsmith assertion. Slot existence, selected option membership,
static adapter validation, progression, bans, budgets and owner-specific question hooks are not skipped or cached.

## Fixture failures and corrections

- The first full measurement run reported **1952/1/0**. Its new fixture called GLuaTest's injected `stub` from a
  file-scope helper, whose environment does not receive that injection. The fixture now explicitly passes its
  injected stub factory and completion callback to helpers; no production rule was changed.
- The next targeted run reported **0/1/0** before measurements: default GMod JSON decoding converted string ARC9
  addresses such as `"1"` into numeric keys, correctly causing the saved dataset legality assertion to refuse it.
  The test input decoder now uses the public `ignoreConversions` option. It still checks dataset legality.
- The corrected native fixture passed **1/0/0**. A preliminary series used ordinary personality weights; a second
  controlled pre-optimization series fixes weights uniformly so match personality rerolls cannot change issuance.
  The controlled series, not the preliminary series, is the before/after comparator below.

The selected-build regression was also observed RED (**2/1/0**): the old implementation queried the unused muzzle
slot for an optic+camo build. After filtering, the empty-discovery and invalid-option/static-validation assertions
remain unchanged and pass. No inherited assertion was removed or weakened.

## Controlled results

All times are milliseconds, medians over three cold or six warm trials per arm. `Before` uses the original
production runtime; `After` uses both local experiments at `79bea31`. Every matched trial selected the **same nine
class references** before and after, using the same frozen candidate definitions. Columns overlap as described
above; they are not additive. Cold first-trial initialization and large engine/GC outliers are retained, not discarded.

| Series | Picks | Cache | Generated | LIVE | Think gap | PoolFor | Provider | Bot Give | Weapon Give | Apply |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Before | Fixed | Cold | Off | 328.03 | 361.25 | 267.16 | 0.05 | 6.32 | 4.87 | 0.00 |
| Before | Fixed | Cold | On | 341.67 | 378.16 | 319.91 | 36.10 | 5.88 | 4.30 | 0.00 |
| After | Fixed | Cold | Off | 239.39 | 273.48 | 213.56 | 0.05 | 6.99 | 5.71 | 0.00 |
| After | Fixed | Cold | On | 306.78 | 346.93 | 277.30 | 14.86 | 7.08 | 5.01 | 0.00 |
| Before | Fixed | Warm | Off | 242.79 | 278.74 | 219.27 | 0.04 | 6.18 | 4.81 | 0.00 |
| Before | Fixed | Warm | On | 294.62 | 333.77 | 258.92 | 7.23 | 6.10 | 4.42 | 0.00 |
| After | Fixed | Warm | Off | 251.85 | 290.17 | 224.27 | 0.05 | 7.07 | 5.24 | 0.00 |
| After | Fixed | Warm | On | 270.58 | 313.85 | 244.55 | 6.15 | 7.02 | 5.53 | 0.00 |
| Before | Mixed | Cold | Off | 273.18 | 321.61 | 203.48 | 0.04 | 53.13 | 44.99 | 6.64 |
| Before | Mixed | Cold | On | 474.12 | 535.37 | 317.35 | 16.16 | 89.12 | 74.34 | 12.12 |
| After | Mixed | Cold | Off | 434.26 | 483.83 | 214.23 | 0.05 | 56.93 | 46.81 | 7.62 |
| After | Mixed | Cold | On | 553.17 | 656.20 | 392.94 | 19.72 | 118.59 | 95.58 | 17.56 |
| Before | Mixed | Warm | Off | 309.00 | 381.57 | 218.53 | 0.04 | 54.86 | 44.73 | 7.67 |
| Before | Mixed | Warm | On | 358.61 | 421.69 | 249.86 | 5.90 | 89.88 | 75.83 | 12.14 |
| After | Mixed | Warm | Off | 289.40 | 372.57 | 207.06 | 0.05 | 60.33 | 49.37 | 8.73 |
| After | Mixed | Warm | On | 368.84 | 433.46 | 244.05 | 6.11 | 94.29 | 79.17 | 12.74 |

After-change paired LIVE differences (ON minus OFF, not subtraction of separately computed medians):

| Picks | Cache | Pairs | Median | Minimum | Maximum |
| --- | --- | ---: | ---: | ---: | ---: |
| Fixed | Cold | 3 | 67.39 | -725.19 | 179.09 |
| Fixed | Warm | 6 | 18.73 | -91.12 | 195.96 |
| Mixed | Cold | 3 | 118.91 | 107.05 | 339.97 |
| Mixed | Warm | 6 | 85.43 | -120.85 | 241.56 |

The flat-copy-only repeat also did not show an end-to-end improvement: warm Fixed OFF/ON LIVE medians were
249.54/310.48 ms; warm Mixed OFF/ON were 274.35/402.38 ms. Its corresponding pool medians were 226.57/285.27 ms
and 204.07/257.91 ms. This repeat is evidence against treating the first local experiment as a proven startup fix.

Full raw samples, including `nextTick`, assignment counts, every nested timing and picked refs, were retained outside
the public tree for coordinator review. Console marker: `[PW] ARC9 START PERF`. Raw refs can contain the host's
SteamID64; do not publish them without scrubbing. The table above contains no private roster identifiers.

## Verdict and gate evidence

**The no-new-match-start-lag goal is not passed.** Both local changes are safe with respect to validated contents
and first-spawn ordering, but these noisy end-to-end measurements do not establish a reliable removal of the
added startup spike. The fixed-preset regime still shows selection/pool overhead; the mixed regime additionally
shows materially more synchronous weapon issuance. Do not infer absence of lag from the earlier map-generation
slice or provider microbenchmarks. This is a server/startup-window measurement, not human gameplay acceptance.

Final runtime `79bea31`: `nix develop --command make check` PASS; full unfiltered
`PW_MAP=gm_construct PW_TEST_TIMEOUT=600 nix develop --command make test` **1957/0/0**, 196 groups,
213.471 seconds. That run also read back actual ARC9 camouflage on 17 generated builds. Runtime registration,
same-map cache rules, bans, budgets, progression separation and all inherited test assertions remain in place.

Work stops after these two local experiments. No asynchronous spawning, earlier class-selection phase, staggered
LIVE admission, actor-permission cache or altered `PW_MatchStart` contract was introduced. A requirement to remove
the remaining synchronized Give/Apply spike needs an architectural escalation and an explicitly approved seam;
it must not be implemented by silently changing the decided pre-first-spawn lifecycle.

## Authorized metadata-only escalation (2026-11-10)

The subsequent explicit authorization permits at most two additional targeted reworks, without changing lifecycle
or caching actor-specific decisions. The first rework adds optional `IsSelectionCosmetic(class, slot, option)`:
`nil` retains the original discovery fallback; a boolean answers only the cosmetic metadata question. The ARC9
implementation reads current slot/attachment/cosmetic-category fields, calls live `Offerable`, and retains ARC9's
public category discovery for a cosmetic option in a noncosmetic slot. Ordinary selected attachments no longer
require caller-owned copies of complete slot/option lists. It introduces no metadata-result or player-verdict cache.

The per-bot `PW_ValidateLoadout`, `PW_LoadoutCost`, wildcard modifications, owner/role policies, match bans/caps,
static adapter validation, human class harvest/repair, weighted selection and pre-first-spawn sequencing remain
on their existing paths. Neither generation scheduling nor weapon Give/Apply is changed. The API annotation is in
`types/adapter.lua`; the frozen API document remains orchestrator-owned.

TDD evidence retained outside the public tree:

- Tests-first full run: **1959/3/0**, 204.875 seconds. The three new failing cases did not weaken inherited cases.
  The initial dynamic fixture was corrected to dispatch its synthetic class through the actual ARC9 adapter.
- Corrected targeted RED: **2/3/0**. It observes 76 legacy list calls for mounted selected builds, and an immediately
  stale cosmetic answer after a blacklist replacement with unchanged identity/count.
- Targeted GREEN after the implementation and a real `pw_reload`: **5/0/0**. Differential cases cover mounted
  builds, unavailable/legacy adapters, warm blacklist swaps, in-place slot/category/attachment edits, memo reset,
  changing owner-specific permissions/costs, wildcard callbacks, bans/caps and weighted selection order.

The original raw failures, including lint/type-check diagnostics during test authoring, are retained, not erased.

### Controlled before/after evidence

The fresh pre-change baseline is `8c60c4d`; the implementation is `7f5bfc3`. The same frozen 18 definitions, two
human ARC9 classes, nine bots, uniform weights, alternating OFF/ON order and 36-transition fixture described above
are used. **All 36 matched trials select identical class references before and after.** Each cold arm has three
samples; each warm arm has six. Values are medians in milliseconds; overlapping columns must not be added.

| Runtime | Picks | Cache | Generated | LIVE | Think gap | PoolFor | Provider | Bot Give | Weapon Give | Apply |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Before | Fixed | Cold | Off | 230.75 | 265.66 | 209.43 | 0.06 | 6.07 | 5.10 | 0.00 |
| Before | Fixed | Cold | On | 286.70 | 325.36 | 261.91 | 11.12 | 6.19 | 4.94 | 0.00 |
| After | Fixed | Cold | Off | 245.17 | 281.74 | 220.58 | 0.05 | 7.11 | 5.39 | 0.00 |
| After | Fixed | Cold | On | 254.49 | 286.38 | 229.85 | 12.27 | 6.75 | 5.13 | 0.00 |
| Before | Fixed | Warm | Off | 238.18 | 275.50 | 213.41 | 0.06 | 6.29 | 4.63 | 0.00 |
| Before | Fixed | Warm | On | 284.48 | 321.23 | 260.43 | 7.18 | 6.33 | 4.82 | 0.00 |
| After | Fixed | Warm | Off | 231.76 | 263.84 | 208.45 | 0.04 | 6.48 | 4.83 | 0.00 |
| After | Fixed | Warm | On | 253.77 | 288.62 | 230.40 | 5.93 | 6.94 | 4.88 | 0.00 |
| Before | Mixed | Cold | Off | 341.63 | 388.44 | 200.06 | 0.05 | 126.49 | 117.67 | 6.75 |
| Before | Mixed | Cold | On | 381.88 | 453.89 | 251.31 | 11.56 | 112.32 | 96.28 | 12.34 |
| After | Mixed | Cold | Off | 317.18 | 361.34 | 203.09 | 0.04 | 50.70 | 41.89 | 7.03 |
| After | Mixed | Cold | On | 400.27 | 457.23 | 219.63 | 10.89 | 77.90 | 66.98 | 8.99 |
| Before | Mixed | Warm | Off | 277.09 | 334.02 | 211.42 | 0.04 | 48.36 | 40.52 | 6.05 |
| Before | Mixed | Warm | On | 340.45 | 396.95 | 236.71 | 5.83 | 82.39 | 69.26 | 10.37 |
| After | Mixed | Warm | Off | 271.39 | 311.52 | 203.99 | 0.04 | 49.55 | 42.39 | 5.94 |
| After | Mixed | Warm | On | 399.86 | 492.43 | 279.31 | 8.06 | 81.79 | 69.76 | 9.78 |

Paired LIVE differences after the change (ON minus OFF within each pair):

| Picks | Cache | Pairs | Median | Minimum | Maximum |
| --- | --- | ---: | ---: | ---: | ---: |
| Fixed | Cold | 3 | 9.31 | -799.58 | 144.54 |
| Fixed | Warm | 6 | 21.50 | -96.70 | 65.74 |
| Mixed | Cold | 3 | 92.90 | -76.26 | 141.75 |
| Mixed | Warm | 6 | 124.45 | 24.05 | 201.30 |

An unchanged-runtime repeat during the tests-first full RED run selected the same 36 sets of references too. Its
warm Fixed OFF/ON LIVE medians were 239.14/253.87 ms, and warm Mixed were 277.87/346.19 ms. Thus even the apparent
Fixed improvement against the first baseline is not established against runtime variability. No outlier is removed.
The new-map generation summaries were 191 frames/92.94 ms total/2.01 ms max slice before and
261 frames/145.64 ms total/2.01 ms max slice after. Those newly generated pools are not the frozen startup dataset;
they are descriptive samples, not an identical-input generation comparison or a generation optimization claim.

Full pre-change gate: **1957/0/0**. Full post-change, unfiltered `gm_construct` gate:
`PW_MAP=gm_construct PW_TEST_TIMEOUT=600 nix develop --command make test` **1962/0/0**, 197 groups,
227.040 seconds. All raw timing samples and failures remain outside the public tree; roster references are private.
`nix develop --command make check` also passes. Its final first invocation exhausted the local command's 120-second
timeout during packaging selftests; the complete retry with a 300-second command budget passed without bypasses.

**The no-added-match-start-hitch requirement is still NOT PASSED.** Eliminating redundant metadata-list calls is
verified, but material end-to-end improvement is not. Warm Mixed ON remains slower in every after-change pair,
and synchronous Give/Apply still costs more with the expanded mixed selection. Stop after this first authorized
metadata-only rework rather than spend the second allowance on an unsupported cache or change lifecycle. The
committed implementation and regression tests are retained for coordinator review, not presented as performance
acceptance. No push, PR, merge, design edit, permission cache or spawn-timing change is part of this escalation.
