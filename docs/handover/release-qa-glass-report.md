# Release QA's glass sessions: stale probes, now measuring the glass system (2026-11-24)

The task of 2026-11-24, after the upstream runtime merge's testing
([upstream-1123-report.md](upstream-1123-report.md), "Open"): find out why release QA's `map-glass` and
`spawned-glass` sessions fail on the PoC and in the field with every package retained since at least 2026-11-14, then
make them measure the glass players see, or fix the glass. Done by Claude in a side session; tools and docs only, no
package change.

## Finding: the glass works, the probes were stale

- **What the probes counted.** [`map_glass_probe.lua`](../../tools/qa/map_glass_probe.lua.md) and
  [`spawned_glass_probe.lua`](../../tools/qa/spawned_glass_probe.lua.md) were written for review R4 on 2026-10-31.
  They counted `procedural_shard` entities, the server entities of Glass-Rewrite-Remix (the RTX fixes' glass add-on),
  and spawned its `procedural_shard_4`.
- **What players have had since 2026-11-01.** G1 ([ADR 0070](../decisions/0070-glass-overhaul.md),
  [glass/README.md](../../glass/README.md)) replaced that add-on the next day: `tools/package_fixes.py` leaves
  `Glass-Rewrite-Remix` out of the package (`RETIRED_ADDONS`, G1-A, merged 2026-11-01). G1 keeps one server entity per
  unbroken pane (`nlglass_pane` and its six presets), watches the map's native `func_breakable` glass without changing
  it, and keeps broken pieces only in each client's debris world (`NLGlassDebris`, on the Jolt module
  `gmcl_nlglass_win64.dll`): no entity for a piece. So `map-glass` saw the window go (`pane_valid false`) and
  `shards 0` every time, and `gm_spawnsent procedural_shard_4` names a class no package has had since.
- **The screenshots show the glass breaking.** The sessions of 2026-11-24 that failed (the main checkout's
  `out/qa-poc/up1123-2/03-map-glass` and `out/qa-field/up1123/map-glass/01-map-glass`, `shot-02-after_first_shot.png`)
  show the shot window's pieces across the floor, at 1280x720 on the PoC and 3840x2160 in the field.
- **The 2026-11-14 reading corrected.** [upstream-runtime-report.md](upstream-runtime-report.md) read the failure as the
  glass module never loading. Its new-runtime run (`out/qa-poc/upstream-1114/03-map-glass`) had the module loaded and
  failed as today; the baseline's `map-glass` (`out/qa-poc/upstream-1114-baseline/01-map-glass`) ended with 0xC0000409
  after its first map and before modern_house and the probe ("game exited before the next window operation", the
  crash that report names), so the module missing from its `modules.json` said nothing about glass.

No glass regression was found, so the glass is unchanged.

## What changed

- **The probes count what the player sees of G1** (client Lua, as before; `sv_cheats 1`, real `+attack` with the 357).
  `map_glass_probe.lua` takes its window from the windows G1 tracks (`NLGlass.Client.records`, the nearest upright one),
  waits until the debris world has imported the map (`NLGlassDebris.Backend()` is `jolt`), shoots it once, and for
  2.5 s samples every frame in `PostRender`: the debris draw calls (`NLGlassDebris.Stats()`), and where the pieces lie
  (`NLGlassDebris.Diagnostics(256)`, the manager's read-only QA accessor). It reports whether the window opened, the
  pieces created since the shot (`NLGlassDebris.Count()`), the frames that drew them and how many lie within 512 units
  of the window; then the follow-up rounds through the hole and at a piece on the floor, with their ray hits and splits.
  `spawned_glass_probe.lua` spawns G1's own preset as the spawn menu does (`gm_spawnsent nlglass_annealed_96x64`),
  checks G1 tracks it, built its mesh and drew it (through `NLGlass.Client`'s observation slot, `Observe`, handed back
  after), shoots it once and reports the glass left in it, the pieces and their draws. Both print `NL_QA_GLASS` JSON
  lines and end with an `error` line rather than a Lua error if something inside them fails.
- **Release QA's pass rules** ([`release_qa.py`](../../tools/qa/release_qa.py.md)) judge those lines: G1 running, a
  tracked window or a spawned, tracked, drawn pane, the debris world on Jolt before and after the shot, an opening,
  pieces, pieces drawn, and for the map window pieces within 512 units of it. The follow-up rounds are reported, not
  judged (a round lands on a piece only when one lies under it). The summary keeps each glass session's measures under
  `glass`.
- Unit tests ([`test_release_qa.py`](../../tools/tests/test_release_qa.py.md)): each rule fails on its own, and the old
  probes' output fails with "no setup line".

## Measured (the published package `0.0.0-dev.20261124104734+42e4e1f8`)

**PoC** (1280x720, `mat_queue_mode 2`, no Workshop mount but the map's item):

| Run (main checkout's `out/qa-poc/`) | `map-glass` | `spawned-glass` |
|---|---|---|
| `glass-g1-1` | PASS: 29 glass windows, 44 tracked by G1; one round opened the window (entity gone), 518 pieces, drawn in all 160 frames sampled (at most 458 draw calls in a frame while they fell), 140 of 256 read within 512 units (nearest 77); through the hole 0 ray hits; at a piece on the floor 1 ray hit, 6 splits | PASS: the pane spawned on the ground ahead, tracked, mesh built, 285 draws before the shot; one round left 65% of its glass and 117 pieces, drawn in all 398 frames |
| `glass-g1-2` | PASS: the same window; 482 pieces, drawn in all 165 frames (at most 425 calls), 123 of 256 within 512 units (nearest 81); through the hole 0 ray hits; on the floor 2 ray hits, 9 splits | PASS: another spawn point; 270 draws before the shot; 65% of its glass left, 114 pieces drawn in all 382 frames |
| `glass-g1-negative` (negative control) | FAIL, as it must: the console ran `NLGlassDebris.Shutdown()` before the probe (the manager stops, nothing archived). The window still broke (entity gone), but the debris world stayed `none` for the 60 s wait, no piece was created and none drawn in 198 frames; the screenshot shows the open frame and an empty floor. The old probe printed `pane_valid false shards 0` for this and for the working glass alike | - |

Settled pieces merge into batches, so the follow-up steps draw a few batch calls (2 in both runs) instead of one call
a piece. Every positive session loaded its map, quit normally, logged no Lua error and ran RTX, and both summaries
passed with no watched file, registry value or setting changed; the PoC's `config.json` went back from the install
step's copy and `out/r10/poc.lock` was held for each run.

**Field** (`release_qa.py --field --only map-glass,spawned-glass` with the user's launch options `-insecure -tickrate
120`, the user's Workshop add-ons mounted, 3840x2160; the main checkout's `out/qa-field/glass-g1`, under the PoC lock,
no game was running): both PASS. `map-glass`: 50 glass windows, 44 tracked, the same window; 560 pieces drawn in all
110 frames (at most 445 calls), 176 of 256 within 512 units (nearest 79); through the hole 0 ray hits; on the floor 2
ray hits, 5 splits. `spawned-glass`: 95 draws before the shot; 65% of its glass left, 114 pieces drawn in all 141
frames. The summary passed with no watched file, registry value or setting changed.

**Gate:** `tools\test.ps1 -Config Release` on `main` `645ec5ed` with this change, in a short worktree under `out\worktrees`
(`NL_FIXES_CLONE` set): repository conventions, 35 of 35 CTests, 2236 Python tests (one skipped), all passed.

## Not covered

- Tempered glass, map windows replaced by G1 panes (`func_breakable_surf`; modern_house has none) and other maps.
  G1's own QA add-on ([`nlglass_qa`](../../tools/qa/nlglass_qa/lua/autorun/nlglass_qa.lua.md)) covers those causes.
