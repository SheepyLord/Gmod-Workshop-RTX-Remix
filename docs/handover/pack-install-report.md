# Workshop models installed several at once (report)

Claude, 2026-11-21, on the branch `pack-install-speed` (worktree `out\worktrees\packi`, from `main` at `11e21cf0`).
Package only: the Model Hotloader part's `workshop.lua` and `library.lua` and its natives (rebuilt, build
`9085be02d76d-20261122T035107Z`: the identity names the commit of the checkout the build's work folder lay in, the
main checkout at the time; the source is this branch's, staged from `packages/model-hotloader/source`); no loader
(`winmm.dll`) or runtime change. Decision: [ADR 0255](../decisions/0255-workshop-models-install-several-at-once.md)
(0254 was taken on `main` meanwhile by the queued render calls' second check).

## The task

The user's report of 2026-11-21, with a content pack of twelve characters made with the workshop-content-pack skill
(3.8 GB: the characters' Model Hotloader package, their Remix PBR mod and their textures; rebuilt with ten at 19:59
that day): "When loading a
workshop addon, such as the one provided above after a fresh subscription, the game is laggy for each item. Please
optimize this lag and the speed of installation." The user chose to have it done in this session.

## What was found

A new PoC tool, [`pack_install_session.py`](../../tools/qa/pack_install_session.py.md) with its probe, installs a
content pack as a fresh subscriber would (the pack and the RTX package as local packages, the Model Hotloader's library
moved aside) and times every frame, each model's install and the install's native steps; `--seed-library` gives the
install a library the size of the user's (their 220 characters' manifests and settings and 20 props, copied read only)
and `--spawnmenu` opens the spawn menu on the Model Hotloader's tab. Facts with file and line references:
[RESEARCH](../RESEARCH.md), "Workshop model packages: what an install costs".

- **The loader's deploy and the Remix mod are not the slow part.** The pack's root files (its PBR mod) are deployed by
  the loader at the start after Steam downloads the item; the Model Hotloader installs its models in the game.
- **The install was slow because it waited for one asset check at a time.** It moved one file and one model at a
  time. Of 76 s for fourteen models (the pack's twelve and the RTX package's own two), the models' asset checks took 64
  s: `StartAssetCheck` loads each character as a spawn would, which builds its Source materials (every PNG decoded, an
  uncompressed VTF with mip levels written for each and again into `materials-v5.gma`) and its collision fit, 1-13 s
  per character on one thread. Moving the 196 files (416 MB) took 11 s: streaming 4 s, the natives' commits 7 s.
- **The hitch per model was the library's rebuild.** Each installed model rebuilt the whole library 0.25 s later
  (every character's settings read, every manifest's size and time checked, the props' catalog) and, when open, the
  library window's list (220 rows, about 2,000 panels). With the user's library and the spawn menu open, each model
  cost a frame of 100-140 ms; in a fresh library 40-90 ms. Each model also wrote the whole Workshop state file twice.
- **On the main thread the install itself costs little**: its Think hook's own time was 0.33 s over a 68 s install,
  `AppendSharedChunk` 0.19 s for 7,298 chunks; `SharedFileMatches` (a main-thread hash) never took more than 4 ms.

## What changed

- **Several models at once** (`workshop.lua`): a few models in hand (two more than the checks), one file streaming on
  the main thread within the same 4 ms of each frame, up to three commits in the natives, up to `MaxChecks` asset checks
  side by side (one per six logical threads, one to four: four on the user's computer). A shared file moves once and is
  then known to be in place (written and verified this session, unchanged since). A check that failed beside others
  runs once more alone before the model is refused (a load's memory budget counts the others).
- **No rebuild per model**: installed models reach the library through `library.Add` (`library.lua`: the entry a
  rebuild makes, from the new models' manifests and settings alone; one revision for the batch), at most every four
  seconds while models install, the first at once, the rest when the last one is in. Each character's manifest is
  decoded in its own frame as it installs (`library.Prime`), not with the others' at the update. Full rebuilds
  (packages changed) are unchanged.
- **State written once for a burst**: the install record before any file of a model (one write for the models taken
  together), the installed records a second later, at the batch's end and at shutdown.
- **Below normal priority** (`source/install-priority.patch`, `module.cpp`): a file's commit and a model's asset check
  run at `THREAD_PRIORITY_BELOW_NORMAL`; a spawn's load does not. Windows' background mode, the first build, also
  lowers I/O and memory priority to very low: beside other checks a large character's check, which writes about a
  gigabyte of Source materials, then took 93-114 s instead of 8-13 s (see Measured).

## Measured

All in the PoC, gm_construct at 1600x900, with `pack_install_session.py` and the library of the user's size
(`--seed-library`: 222 characters' manifests and settings and 20 props, read only from the field install) and the
spawn menu open on the Model Hotloader's tab (`--spawnmenu`). The pack was rebuilt at 19:59 that day (ten characters
instead of twelve, Collei and Furina moved to a second part), so the final pair of runs uses that pack with both
packages, back to back: the published package `0.0.0-dev.20261122030548+82015679` (before) and this branch's (after).

| | Before (`base4`) | After (`fix4`) |
|---|---|---|
| From the first install to the last (12 models) | 44.1 s | **11.9 s** |
| Asset checks | one at a time, 38.3 s | four at once, 39.2 s in all |
| Library window rebuilds | 13 | 5 |
| Install frames over 50 / 80 / 100 ms (after the map's first 6 s) | 14 / 2 / 1 | 4 / 0 / 0 |
| Longest install frame | 110.4 ms (`vgui.Create` 44.9 ms, the list's `Refresh` 21.5 ms) | 66.5 ms (the RTX Remix guide's timer) |
| Median / p95 install frame | 11.4 / 22.2 ms | 10.4 / 21.0 ms |

What an update of the library costs now is the library window's own rebuild of its 220 rows (52-59 ms, five times
in this install); a fresh library or a closed spawn menu costs far less.

The first build of this branch put the natives' install work in Windows' background mode. With the earlier pack
(twelve characters) and the same library (`big1` before, `fix2` after) the frames were smoother (p95 47.2 to 18.4 ms,
frames over 100 ms 5 to 0), but the large characters' checks took 93-114 s instead of 8-13 s and the pack 119 s
instead of 68 s: background mode also lowers I/O and memory priority to very low, and a large check writes about a
gigabyte. The natives were rebuilt with below-normal CPU priority only, which gave the final numbers above.

Earlier, with a fresh library (`base2`, the earlier pack): 76 s for 14 models, 64 s of it in checks one at a time;
196 files (416 MB) moved in 11 s. Evidence: `<repo>\out\worktrees\packi\out\packi\` (`base2`, `big1`, `fix2`, `base4`,
`fix4`; each `<label>\results\result.json` with its trace and `frames.csv`).

The base4 run's driver ended a game running in the field install at 20:57 (the user's standing rule for test runs;
`base4\field-games.json`).

## Tests

- [`test_hotloader_workshop_install.py`](../../tools/tests/test_hotloader_workshop_install.py.md) (new): the shipped
  `workshop.lua` and `library.lua` under LuaJIT with the natives, disk, timers and frames instrumented (`parallel`,
  `failures`, `replace`, `library_add`), and source checks of the natives' install priority. `parallel` fails on the
  file before the change.
- The gate, `tools\test.ps1 -Config Release` in the worktree, on the final state: repo conventions OK, CTest 35 of 35,
  Python 2,186 of 2,187 (one skipped); the one failure is `test_topbr_publish.test_the_guard_regression_passes`, which
  fails in any checkout whose path holds "pack" (see Open items) and passes unchanged in the main checkout.

## Open items

- Not tried: the field install (the user's game), a multiplayer game (a listen server's host approving installed
  models, a dedicated server's own installs), a computer with few threads.
- The asset check is still the slow part of each model: a character's Source materials are built on one thread. Building
  a character's textures on several threads would speed up single large models (ADR 0255, rejected for now).
- Each library update still rebuilds the library window's whole list when it is open (52-59 ms with 220 rows, five
  times for this pack). Adding the new rows alone would remove that last hitch.
- In this worktree (`packi`) the gate's `test_topbr_publish.test_the_guard_regression_passes` fails: its C++ test
  (`packages/fixes/.../topbr-publish/tests/fallback_guard_test.cpp:119`) looks for the removed folder `pack` in whole
  paths under `<repo>\out\tmp`. It passes unchanged in the main checkout; the test could look in relative paths.
- Nothing is committed to `main`, pushed or published: the main thread decides when this lands (a commit on `main`
  publishes the Workshop item).

## Published

Merged by the main thread with the other pieces of 2026-11-21 on the branch `integrate-1122`: the content packs'
install (ADR 0255), the render guard inside DLib's and ULib's hook libraries (ADR 0256, ADR 0257) and the library
window's rows (ADR 0258). DLib's decision, drafted as 0254, became 0256 there. The gate passed on that branch
(`tools\test.ps1 -Config Release`). Under the standing permission (AGENTS.md rule 5) `main` was fast-forwarded from
`602f401d` to `6dca0e9b` and pushed; the merge's hook built the package here and uploaded item 3829070317 as
**`0.0.0-dev.20261122060047+34cd2c57`** (content digest `cdf287a621f3760c`).

The merge also made `test_hotloader_workshop_install.py`'s `failures` scenario accept either of the two models that
share the failed texture taking the failure: the install queue follows `W.provided`'s `pairs` order, which LuaJIT
2.1 seeds per run, so in some runs (4 of 30) model 2 took the failed commit, as designed, and the test had failed.
Test only; the Model Hotloader is unchanged.
