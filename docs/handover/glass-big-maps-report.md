# GL · Broken glass on large maps

Branch `glass-big-maps`, based on `55e5dcfc`. The glass add-on and its Jolt client module now read
only the map data needed by debris. On Agency the native world finished with 1,688 static bodies
after reading 1.71 MiB from a 302.98 MiB BSP. When collision cannot be imported, players get one
ordinary console line explaining why the map uses simpler physics.

## Evidence

The remaster, Workshop item 3842723143, names base-map item 1280291772. The base archive supplied
the CRC-checked Agency BSP. Pakfile and lighting data account for 297.21 MiB. The probe returned
774 solid prop instances for the client to resolve and accepted every world brush. It also finished
both import paths on nine other Workshop maps, up to 777.22 MiB. The [measurements](../RESEARCH.md#broken-glass-on-large-maps-2026-11-28)
identify each map, its large lumps and the resulting world. Raw probe output is under
`out/glass-big-maps/imports.log` in this worktree.

The native test uses a virtual BSP with a 300 MiB pakfile before its collision data. A read from
the hole fails the test. Other fixtures cover the two v21 directory layouts, water and displacement
geometry, a large unused game sublump, compressed leaves, compressed static props with either length
convention and a compressed game directory pointing outside itself. Budget tests reject raw and
expanded excess before bulk reads. The LuaJIT harness checks short reads, handle closure, mixed
DLL/add-on versions, and notice counts across cleanup, refresh and map changes.
[Design and limits](../decisions/0277-read-only-bsp-collision-for-glass.md)

## Release gate

`tools\test.ps1 -Config Release` finished with `All checks passed.` at 11:05:00 UTC on
2026-11-28. The native Release build and all 35 CTest groups finished at 11:00:20 UTC. The three
Python suites reported 2,338 tests in total, with 10 skips. The glass LuaJIT harness ran and its
standalone invocation reported 15,273 assertions. The timestamped gate log is
`out/glass-big-maps/release-gate.log`.

## Package for PoC

Commit `43daa914` contains the implementation and tests. Commit `8cff7b4d` records the Release
DLL built from it. `python tools/ci/repo_builds.py refresh nl_glass_client` imported the DLL and
recorded its source hashes. `python tools/inputs.py verify --part glass --deep` passed.

The local combined package is
`out/glass-big-maps/package/gmod-rtx-remix-0.0.0-dev.20261128110242_264866ef.gma`.
Its SHA-256 is `001e78f8a0e95aaa1f2ba7fcf4b52074262edb8d5f35e246f63ad0c010c75a18`.
The default part staging path reached Windows' 260-character limit for an HL2 texture. The same
repository package builder completed with a shorter staging folder under `out`. The worktree's
`nlctl` checked the parts and the combined GMA.

The manifests of this package and the last published package (`0.0.0-dev.20261128044434+589c2535`)
each list 2,279 payloads. Exactly two entries differ. The archived `nlglass/world.lua` matches
the add-on source byte for byte. The archived `gmcl_nlglass_win64.dll` matches the Release DLL,
SHA-256 `63ce9163d57f3bd99e6deb4208e11a8d0d342992792670c70d6e330df9f9ef24`.
The local GMA build ended at 11:03:06 UTC on 2026-11-28.

## PoC checks for Claude

1. Load `gm_csgoagency` with both Workshop items mounted and this branch's glass DLL and Lua.
   After the client sees its first pane, let the import finish. In the client console run
   `lua_run_cl print(NLGlassDebris.Backend())` and look for `jolt`.
2. Break a pane above a floor and beside a solid static prop. Check that shards hit and settle on
   the floor and the prop's collision. Break another pane and check that Jolt stays active and the
   console stays clear. The offline probe can enumerate prop instances. GMod supplies the model
   convexes at this step.
3. Change to a second large map such as `gm_funkis` and repeat. If checking the staged update, run
   the new Lua with the previous DLL on Agency. Expect `vphysics` and a single line explaining the
   restart. Repeated panes should produce no additional notice. Restart with the branch DLL and
   check for `jolt` again.

## In the PoC (Claude, 2026-11-28)

Release QA's spawned-glass probe (`tools/qa/spawned_glass_probe.lua`: spawns G1's annealed 96x64 pane, shoots it with
the 357 and counts the debris) on `gm_csgoagency`. The base map came from Workshop item 1280291772, mounted from
`gm_construct`. RTX was on, 1280x720, in one launch per package:

| Package | Console | Debris backend before and after the shot | Pieces from one round |
|---|---|---|---|
| Published `0.0.0-dev.20261128044434+589c2535` | `[NLGlass] Jolt unavailable; using capped client physics: map missing or larger than 256 MiB` | `vphysics` | 64 |
| This branch, `0.0.0-dev.20261128110242+264866ef` | no `[NLGlass]` line | `jolt` (ready at once) | 290, 279 drawn |

The after-shot picture shows the pane broken on the roof's helipad, its pieces on the floor, the path-traced scene
intact.

Not checked in the game: a second large map, shards settling on a static prop, and the new Lua with the previous DLL.
The harness covers that last case.
