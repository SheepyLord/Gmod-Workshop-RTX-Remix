# VR-V2-F: the add-on's framework

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it: its interfaces 1 to 7 and 10 are what you build, and its
rules are yours. Then V1's [VR-V1-report.md](VR-V1-report.md), [VR-V1-E-report.md](VR-V1-E-report.md) and
[VR-V1-Q-review-report.md](VR-V1-Q-review-report.md) for what V1's add-on and page learned the hard way (engine
console variables Lua may not set, the owned CalcView registry, the render proxies, quitting while paused).

Your branch is `v2f`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2f`. Four tasks (hands,
movement, menus, physical interaction) start from your work when it is merged, each in its own files: what you
build is the ground they all stand on, so make the interfaces exactly as the plan writes them, small and clear.

## What to build

1. **The layout of interface 1**, every file, the four feature modules as stubs that register and do nothing, each
   Lua file with its `.lua.md` (AGENTS.md's documentation duty).
2. **V1's session moved in, unchanged in behaviour**: the camera at the head through the play space, the owned
   CalcView registry, the hidden view model and render proxies, the wrist HUD (as `modules/cl_hud.lua`, on the overlay
   manager, still 769 x 257), the error handling and the complete restoration at Exit. `client.lua` keeps V1's
   contract with the page. The V1 tests (`companion/tests/test_vr.py`, `tools/tests/test_vr_session.py`) and the
   session probe `tools/vr_session.lua` keep working; change the probe only where the move makes it necessary.
3. **The client core** (interface 3): frame, play space (`ToWorld`, `ToTracking`, `Turn` and `Shift` keeping the
   head where it is), poses, rays, the hand resolver chain, the view (head angles into the user command each tick;
   `NLVR.Aim` overriding them for one tick), client movers, events, debug values.
4. **Input** (interface 4) with the plan's default mapping table as data, the dominant hand mirroring everything,
   claims, taps and holds.
5. **Overlays** (interface 5): the manager, the table of reserved odd sizes, painting only when invalidated, `Hit`.
6. **The network** (interface 6): the protocol in `sh_protocol.lua`, the client sync from `CreateMove` (once a server
   tick at most), module message numbers, server-to-client sends.
7. **The server side** (interface 7): the stub in the companion
   (`companion/nativeloader/lua/autorun/server/nativeloader_vr_server.lua` with its `.md`: one network string, one
   receiver, nothing else when VR is off), `server.lua`, `core/sv_core.lua` with the per-player state, the sample
   history, the checks of the sync (finite, within reach, rate), server movers in `SetupMove`/`Move`, start, stop,
   death and spawn events, removal of every hook when the last VR player stops. Only the single-player player and the
   listen-server host's own player are accepted. The client tells the server at Start and Exit.
8. **Settings** (interface 10): create the console variables in the page (one block, archived, with ranges and help
   text; the page's look and texts are task M's), read at Start, change callbacks during VR only.
9. **The harness**: extend `companion/tests/vr_harness.lua` (and the stand-ins beside it) with what the core needs
   (net, user commands, move data, players, traces as stubs) and add LuaJIT tests: the play space (a turn keeps the
   head's world position, round trips), input (mapping, mirroring, claims, taps, holds), overlays (sizes, hits),
   the protocol (pack and unpack, every check that drops a sync), the server movers' order, the lifecycle (after
   Exit no hook, timer or receiver of the add-on is left; with VR off the stub adds no hook).

## Files you may change

`vr/addon/**`, `companion/nativeloader/lua/autorun/client/nativeloader_vr.lua` (the console variables and what the
move needs, nothing of the page's look), the new server stub, `companion/tests/**` (VR tests and stand-ins only),
`tools/vr_session.lua` and its `.md` (only what the move requires), `tools/tests/test_vr_session.py` (same),
decision records **0159** (the add-on's framework: modules, the play space, input claims, overlays) and **0160**
(the server's VR switch and who gets full VR) with their lines in `docs/decisions/README.md`, and your report.

## Proof

- The LuaJIT and Python tests above, in `tools\test.ps1 -Config Release`.
- One session on the Index with the package built from your branch (`python tools\build_package.py --version
  0.0.0-v2f.<n> --require-nlctl --json`, the driver's usual V1 run, 60 to 120 s on gm_construct): V1's acceptance
  still holds (pairs accepted, none refused or unmatched, captures, the wrist HUD, Exit clean, settings restored),
  and the probe shows the server part started with the session and gone after Exit.
- One flat session (`--flat`) showing the stub costs nothing: no hook added, the frame time as before.

## Report

`docs/handover/VR-V2-F-report.md`: what you built, how each interface came out (any difference from the plan, and
why), the tests and their evidence, what the feature tasks must know (a short "how to write a module" with an
example), what is open, your text for the shared documents. `tools\test.ps1 -Config Release` passing in your
worktree.
