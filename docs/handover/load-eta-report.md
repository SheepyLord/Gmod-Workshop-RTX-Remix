# The wait after "Ready to play!" and the load's estimate (2026-11-14)

The user's request:

> There is still a long time, when loading into a map, between 'Ready to play' until the map is actually loaded, add
> verbosity in this part to let the user know what the game is doing.

> The map loading should also get an ETA estimate, it can be trained from previous map loads, please design this part
> to make user able to expect the wait time.

Done by Claude on the branch `qol-load` (worktree `out\worktrees\q-load`, from `main` at `bfbe2350`); **not merged and
not published**. Package only: the engine guard module (`engine_guard/`, shipped in the fixes part) and the companion's
menu script; no loader (`winmm.dll`) or runtime change. Decisions:
[ADR 0214](../decisions/0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md) (after "Ready to play!") and
[ADR 0215](../decisions/0215-the-loads-estimate-learned-from-the-loads-before.md) (the estimate). Facts with file and
line references are in [RESEARCH.md](../RESEARCH.md) ("The wait after 'Ready to play!' and the load's estimate").
Nothing was run in a game (the brief: offline only); the checks a game still needs are listed below.

## Why the wait was silent

"Ready to play!" is the engine's last progress string. The menu's `IsInLoading()` is only whether the loading panel
still has its HTML, which the panel's `OnDeactivate` removes, so R24's overlay hid there. The main thread was not done:
- the client's `InitPostEntity` hooks and add-ons' timers (Extended Spawnmenu's scan, a spawn menu rebuild);
- Remix's first path-traced frames;
- sometimes the Workshop's own fetching.
R26 measured 5.2-12.3 s from `InitPostEntity` until the game ran without a frame over 100 ms for two seconds. While
the main thread is blocked nothing repaints, so the screen kept the loading screen at "Ready to play!".

## What the player sees now

The same small window at the bottom left of the game, drawn by the module's own thread (it updates while the game is
blocked), never taking focus or clicks. Six rows instead of four:

```
Loading gm_construct   0:31
[==========----------]  about 25 s left
The map has loaded; the game is starting  ·  Workshop: fetching subscriptions (120 of 774)
RTX Remix is preparing the scene
Lua: lua/autorun/client/x.lua
File: materials/models/x.vtf
```

- **During the engine's load** as before (the stock status, the load accelerator's count, the Lua file and the game
  file), plus the estimate's row and the activity row.
- **After "Ready to play!"** the window stays, "The map has loaded; the game is starting". It goes once the menu's
  frames have run for two seconds without a freeze (a gap over three times the usual frame, 0.25-1 s), at the latest
  after two minutes (the module hides it by itself after three). A load that ends without a game (cancelled, refused)
  ends it after a second. The game ending or the next load beginning ends it too.
- **The activity row** says what the main thread has mostly been doing in the last two seconds:
  - "RTX Remix is preparing the scene": in the runtime or the Vulkan driver, or waiting on them;
  - "Running add-on scripts", or "Building the spawn menu" when the Lua file is the spawn menu's;
  - "Loading game files": the file system, PNG decoding, the load accelerator.
  The module classes each 250 ms sample by the module the instruction pointer is in, or by the nearest known caller
  for a thread waiting in Windows.
- **The Workshop's own work** (fetching subscriptions, downloading, extracting) goes on the status row while the
  window is up, from GMod's menu hooks. The window does not wait for it.
- **The console line** at the end: `[nativeloader] map loaded in 24.1 s, then 7.1 s until the game ran steadily (31.2
  s in all; expected about 30 s); the main thread: Lua 12.0 s, game files 4.0 s, RTX Remix 3.2 s; Lua files that ran
  longest: ...`.
- All words are in the seven languages (fifteen new messages, agent-written, not yet human-reviewed). The pictures
  the C++ test draws are kept in `out\build\win64-release\engine_guard\scratch\load_overlay_picture` (English, an
  overrun in amber, Japanese).

## How the estimate is learned and shown

- **Recorded** for every load the window followed to its end (steadily or at the limit):
  - when, the map, and for a server joined its name;
  - flags: the first load of the game start, joined, cut at the limit;
  - the add-ons mounted and the map's size;
  - the engine's load, and the wait after it.
  It goes to `garrysmod/data/nativeloader/load_times.txt` (tab-separated, at most ten loads per map, 200 in all),
  which the engine guard reads and writes for the menu script (the menu realm cannot write files). Cancelled loads,
  interrupted ones, demos and anything with the overlay off are not recorded.
- **Estimated** only from loads of the same kind (a server joined, or a game started here):
  - this map's newest five loads: the median of each phase, each scaled to today's add-on count ((150 + now) /
    (150 + then)) and first-load state (the machine's own ratio, learned from maps loaded both ways). **Good** when
    two or more agree within 60 % and none needed a far scaling, else **rough**;
  - a map not loaded before: the machine's newest twelve maps, one point each, fitted to the map's size
    (Theil-Sen, three sizes or more). **Rough**;
  - none of the same kind: no estimate.
- **Shown:** the script passes the whole wait's expected end three times: at the start, again when `GameDetails` names
  the map, and again at "Ready to play!" (the real load plus the expected wait after it). The module counts down
  alone:
  - "about N s left", in steps of five from 20 s; "about N min left" from 90 s;
  - "(rough estimate)" after a rough one;
  - "Taking longer than usual" in amber past the end;
  - "No estimate yet: this load is timed for the next one" without one.
  The bar never goes back, reaches 97 % at the expected end and creeps on.
- **Overruns** are recorded like any load, so the median follows them; a wait cut at the limit carries its flag.

## Verified offline

- **C++** (`nl_engine_guard_tests`, 42 cases, all passing):
  - the activity classes on fake ranges and stacks: the nearest caller, a caller beyond the scan, game code called
    from Lua;
  - code ranges from this executable's PE headers, unreadable headers refused under SEH, LuaJIT-style memory;
  - the smoothing; the estimate's words, the fill of a translation's `%s`, the rounding, the bar;
  - the history file written through a temporary file and read back, bounded;
  - the phase after the load in a process without a game window;
  - the module contract: the new functions only in the menu copy;
  - the window's picture drawn into bitmaps and checked by pixel.
- **Lua under LuaJIT** (`test_loading_status.py`, 22 tests, all passing):
  - the settling phase through a freeze to two steady seconds;
  - a cancelled load, a game a moment late, the game ending or the next load while settling;
  - the 120 s limit, slow steady frames, the Workshop's words, a demo, R24's module (old behaviour kept);
  - an estimate from a history file: the machine's before the map is known, the map's good one after `GameDetails`
    (29.1 s from five loads with the learned first-load factor), the real load plus the expected wait;
  - joined against local loads;
  - the estimator alone: medians, bounds, round trip, outliers, the newest five, add-on scaling, the size fit.
- **Translations:** `companion_i18n.py check` complete (696 messages in each catalog); every new string read back as
  UTF-8 with no `?` in place of a character.
- **The modules:** `tools/ci/repo_builds.py refresh` rebuilt `gmcl_`/`gmsv_nlengineguard_win64.dll` from `fcb3ceee`
  and imported them into `packages/fixes` (record in `tools/ci/pins.json`).

## Gate

`tools\test.ps1 -Config Release` from `out\worktrees\q-load` (`NL_FIXES_CLONE` set to the fixes fork clone) on `cff829da`: the Release build and **35 of 35** CTest tests (`nl_engine_guard_tests` with the new cases among them); Python **1,908** tests in `tools` (1 skipped), 29 in `tools\gmapack` and 26 in `tools\steam` (1 skipped each). The one failure was `check_repo.py`: three links to this report, which was added after that run. With the report, **all checks passed** on `07ca785d`, and again on `77444436` (a hand-edited history's absurd numbers left out, the history serialized inside the save's `pcall`): the same 35 CTest tests and 1,908 + 29 + 26 Python tests.

## In-game checks still needed (the user's call)

1. **A first and a second RTX load of gm_construct** in the PoC with the subscriptions mounted:
   - the window stays after "Ready to play!", reads "The map has loaded; the game is starting", and goes about two
     seconds after the game runs smoothly;
   - the first load says "No estimate yet…"; the second shows a rough estimate before the map is known and the map's
     own after `GameDetails`;
   - the bar and the countdown move while the game is frozen;
   - `garrysmod/data/nativeloader/load_times.txt` holds both loads;
   - the console line's two parts match what was seen.
2. **The menu's `Think` in game:** that the settling phase ends within a few seconds of steady frames. If the menu's
   hooks ran less often in game than the evidence says, the window would stay up to two minutes.
3. **The activity row on real stacks:** sensible words during the client's Lua start, Remix's first frames and the
   file lookups, and no flicker.
4. **At 4K with the GUI Scaler** (the field): the window is now 6.5 lines tall (a line is a 36th of the game's
   height), half the game's width.
5. **A cancelled load** (Cancel on the loading screen): the window goes within a second and nothing is recorded.
6. **A load with the Workshop busy** (a map started right after launching the game): the Workshop's words on the
   status row.
7. **A few days of real loads:** compare "expected about N s" with the console line's actual totals.
8. **`nativeloader_load_overlay 0`:** no window, no line, no file.

## Open questions

1. **When does the game count as playable?** Two seconds of steady frames (R26's "ready" uses the same length) keeps
   the window up about two seconds into the game. One second would end it sooner, at the risk of ending between two
   freezes.
2. **The Workshop:** should the window wait for a Workshop download that runs after the load? It does not now, since
   the game plays meanwhile.
3. **Joined servers' names** are stored in the local history file (to key a server's loads). Keep them, or store only
   a hash?
4. **Merging** needs the user's approval. A commit on `main` publishes the package to item 3829070317 through the hook.
