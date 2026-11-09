# R24: the user's follow-up to R23 (report)

The user's message after R23 (2026-11-08): "No, don't release the current 0.16.1, make further adjustments", with three
items. Standing instructions: no Codex (Claude, with Claude subagents); no loader (`winmm.dll`) change without the user's
approval; edits tested and reviewed. Done on branch `r24` in `out/worktrees/r24`, by Claude, with one Claude subagent for
an independent review. No loader change: everything ships in the package (the Workshop item).

| Item | Result |
|---|---|
| 1: the multiplayer notice in the add-on, as Lua, its text editable there | Done ([ADR 0133](../decisions/0133-the-multiplayer-notice-in-the-companion.md)): the companion's menu script, run in the menu realm by the RTX client module; the loader's notice turned off. The R23 loader branch `r23-loader-mp-notice` is superseded |
| 1.1: make servers believe the game runs at a high DirectX level | Declined: it would hide the client from a server's own rule. The DirectX level's actual harm here, ARC9's warning window, is answered with ARC9's own check (item 2.1) |
| 2: first-person view models, ARC9's custom ones | Fixed what the screenshot shows ([ADR 0135](../decisions/0135-view-model-materials-and-arc9.md)): stickers (a white z-fighting plate) and gun screens (a black square in a green frame) draw with their materials and live text; view model and attachment materials go through the material pipeline |
| 2.1: ARC9's compatibility warning | Gone in RTX sessions (its DirectX check answers "fine"; ARC9's other checks unchanged) |
| 3: say what a map load is doing; make loads faster | An overlay of the engine guard module's own says it, live, during blocking phases too ([ADR 0134](../decisions/0134-what-a-map-load-is-doing.md)); the load measured (below). No speculative speed-up was made |

## Item 1: the multiplayer notice

GMod's main menu (the server browser included) runs in its menu Lua realm, where Workshop add-ons' Lua never runs; the
old notice was JavaScript compiled into the loader. The RTX client module (`gmsv_nlrtxclient_win64.dll`) is a package
module the loader's menu view already requires at menu start in every RTX start, and it already holds a catalog of the
package's Lua checked byte for byte against the committed deployment. It now runs the companion's
`lua/nativeloader/menu/*.lua` from that catalog once in the menu realm, with a read API limited to the companion's own
verified files and removed afterwards (`loader/client/module.cpp`, `run_menu_scripts`).

`nativeloader/menu/multiplayer_notice.lua` is the notice: the user's text (in R23's English wording) and the other two
paragraphs, translated in all seven languages in `companion/i18n/*.po`, on a Derma card over the menu, scaled with the
screen height. "Don't show this again" is a green button of its own (continues and remembers), then "I understand,
continue" and "Back". A few lines of ES5 installed into the menu page ask the script before Angular navigates to the
server browser. At its first run an earlier "Don't show this again" from the loader's notice carries over; the loader's
cookie is then set, and the page's loader script is told through its own entry point, so loaders 0.15.0-0.16.0 no
longer show theirs. `nativeloader_multiplayer_notice` shows the card; `nativeloader_multiplayer_notice_reset` brings it
back.

**Not done: the DirectX level servers see.** Servers that check it (mostly anti-exploit measures for DirectX 8 players)
do so to keep a rule of theirs, and answering falsely would hide this client from it.

## Item 2: ARC9 view models

Reproduced in the PoC with [ARC9] Gunsmith Arms: Source's M249 (the user's weapon), its three sticker slots holding the
Firearms: Source sticker and the Kill Counter charm: exactly the user's white plate and black screen. Findings
(RESEARCH.md, R24):

- RTX draws every view model material with a fixed-function shader (`VertexLitGeneric_DX7`): normal maps and phong never
  reach the path tracer, so custom weapons look flat. That is RTX's shading model here, not a bug this round changes:
  PBR for weapons would be authored replacements or ToPBR, which stays the player's choice (`rtx_topbr_enabled`).
- Under RTX a client-side model's sub-materials do not reach the image (as R7 saw for `SetMaterial`). ARC9 dresses its
  sticker models (which carry only a missing material) and its gun screen charms that way: the white plate is the error
  material z-fighting with the receiver, the black square the charm's screen.
- The gun screen's content is a render target ARC9 draws text into each frame: black in the path-traced image.

The fixes:

- **The ARC9 patch** (`patcher/addons/cl_arc9.lua` in the fixes): ARC9's DirectX check answers "fine" in RTX sessions;
  while ARC9 draws its custom models, sticker and gun-screen parts (known from ARC9's own tables) are skipped by ARC9 and
  drawn at the pose it gave them through `render.MaterialOverrideByIndex`, which reaches the image.
- **The screens** are redrawn as 2D after upscaling by the companion's toolgun screen redraw, which now takes screens
  from providers (`NativeLoaderScreens.Register`); the ARC9 patch provides gun screens.
- **The material pipeline for view models** (`remixlua/cl/cl_viewmodel_materials.lua`): the view models, the hands and
  the active weapon's attachment models (ARC9, TFA/SCK, CW 2.0, ArcCW) go through the Lua fixers and the
  auto-categorisation as they appear (the pipeline saw only the map and newly created entities). The decal test now also
  reads `MATERIAL_VAR_DECAL` from `$flags`, where model decals such as stickers keep it.

| PoC run | Result |
|---|---|
| `vm-rtx` / `vm-off` | The ARC9 warning ("Outdated DirectX version") under RTX only; the M249's 21 materials `VertexLitGeneric_DX7` under RTX |
| `vm3-rtx` / `vm3-off` | Stickers and the Kill Counter: the white plates and the black screen under RTX; the logo and "KILLS 0 0" without it |
| `vm4-rtx` (patch injected) | Patched: the logo on the receiver, the counter's text, no warning; with `rtx_patcher_arc9_parts 0`: the plates and the black screen again |

## Item 3: what a map load is doing, and how long it takes

**The overlay.** GMod's loading screen is the menu realm's loading panel, and during a blocking phase (the Lua start of
hundreds of add-ons) the engine does not repaint it, so no Lua can change it then. The engine guard module now loads in
the menu realm at menu start (its guard is in place before any map) and has a load overlay: a small window owned by the
game's window, drawn by the module's own thread, showing the time so far, the stock status, the Lua file running and the
game file being read, sampled from the main thread every 250 ms like the watchdog. The companion's menu script
`loading_status.lua` drives it from the menu's `Think` (the stock `IsInLoading()` and `GetLoadStatus()`; the engine keeps
its own reference to the loading panel, so wrapping the panel saw no load) and `GameDetails` (the map, or the server
joined); at the end the console names the Lua files that ran longest. Off: `nativeloader_load_overlay 0`.

The package as built here, checked in the PoC (`out/r24/qa-verify2`, the local `.gma` allowed, ARC9 and the Gunsmith
weapons added):

| PoC run | Result |
|---|---|
| `verify-load` | `menu scripts 2` (the notice and the load status ran in the menu realm); the overlay at the bottom left from 1.5 s into the load: "Loading gm_construct 0:02 / Starting local server... / Lua: .../procedural_glass_tool.lua / File: maps/gm_construct.bsp", then "Lua Started!", "Fully connected!"; the console: "map loaded in 7.9 s; Lua files that ran longest: addons/remixbinary/lua/autorun/cl_rtx.lua (0.8 s), ..."; `nativeloader_multiplayer_notice` opened the card over the menu |
| `verify-arc9` | The patch's state `{"screens":"redrawn in 2D","parts":"drawn with their materials","dxWarning":"hidden"}`, 53 checks passed, no ARC9 warning window, the gun screen redrawn (`"texture":"arc9_gunscreen"`) |

That run showed one mistake, fixed after it: a single-player load's heading turned into "Joining My Garry's Mod Server ·
gm_construct" when the engine named its own server and `IsHostingGame()` already read false; a load that hosts its server
(one player, or a call while hosting) now keeps "Loading <map>" to its end (the harness's `local` scenario).

After the review's fixes (below) the rebuilt package was checked again (`out/r24/qa-verify3`): `menu scripts 2` with the
menu found through `lua_shared`; the overlay "Loading gm_construct" from 0:02 to 0:08 ("Loading resources...", "Lua
Started!", "Fully connected!", the Lua file and game file lines); "map loaded in 9.3 s"; the card in Tahoma; the ARC9 run
as before (53 checks, no warning window, the FAS logo on the receiver, the counter's "KILLS PLY | NPC 0 0"). With the
companion's language set to Japanese (`out/r24/qa-noticeja`, the setting seeded in `client.vdf` and put back by the
snapshot's rollback), the card is Japanese throughout: "サーバーに参加する前に", the three paragraphs wrapped between
characters, "今後表示しない", "理解して続行", "戻る"; the status line "language ja (from nativeloader_language (saved));
translations read".

**The measurements** (PoC, the user's 772 subscriptions mounted, gm_construct, the main thread sampled every 10 ms):

| | RTX start | Remix off |
|---|---|---|
| The load (first map material to five seconds after `InitPostEntity`) | about 43 s | about 29 s |
| Server Lua / file lookups / client Lua | about 20 s / 8 s / 18 s | |
| From the game's start to the map (`seconds_to_map`: the Workshop fetch, the load) | 83.8 s | 57.1 s |

Inside the load, ARC9's Lua is about a tenth of the samples and this package's about a twentieth; the file-lookup phase is
`filesystem_stdio.dll` searching every mounted add-on, CPU-bound with almost no disk reads; disk reads peak at 530 MB/s
on this NVMe drive.

Lua's own file and material calls, timed per calling script (`out/r24/file_probe.lua` as the first autorun, the same
772 add-ons; `files` runs):

| | RTX start | Remix off |
|---|---|---|
| Server realm, all such calls | 4.1 s | 3.7 s |
| Client realm, all such calls | 6.1 s | 5.0 s |
| Extended Spawnmenu (`rb655_extended_spawnmenu.lua`, client): 2,274 `file.Find` | 3.5 s | 3.3 s |
| ARC9's attachment files (`attachments_bulk/*.lua`, server): `Material` | about 2.5 s | about 2.2 s |
| `util.PrecacheModel` (server, stock `util.lua`) | 0.6 s | 0.7 s |
| This package: the RTX fixes' material fixer, 724 `Material` (client) | 0.4 s | (RTX only) |

**No speed-up was built, and why.** The engine loads on one thread: the add-ons' Lua runs in one Lua state per realm,
in order, and every file lookup walks the search paths of all mounted add-ons in `filesystem_stdio.dll`. A module cannot
spread either over cores without replacing the engine's file system or Lua state, which no add-on can do safely. What a
load costs is mostly the add-ons themselves: Extended Spawnmenu alone spends 3.5 s of every load on `file.Find`, ARC9
about 2.5 s on its attachments' icons. This package's own share is small (its largest, the material fixer, 0.4 s) and
needed before the first frame. The overlay and the console summary now name the add-ons that take long, so a slow one
can be seen and turned off; the 340 s that looked like the largest cost was the test driver's (below).

**A wait of about 340 s before the load was the test driver's, not the game's.** In five PoC runs (RTX, the Workshop
add-ons mounted) the map came about 416 s after the start against 57 s with Remix off, and nothing in the game was busy
meanwhile: the main thread ran the engine's main loop (messages pumped, the menu drawn at about 230 frames a second).
Windows' `IsHungAppWindow` kept calling the unfocused game window hung after the Workshop remount (a blocking moment),
and `tools/poc_session.py` sends nothing to a "hung" window, so it held the map command. A probe sent the window a
`WM_NULL` at 76 s: answered in 0.4 ms, Windows' verdict cleared, and the map loaded at 83.8 s. A focused game gets input
all the time and never keeps that verdict; players did not wait for it. `poc_session.py` now confirms Windows' verdict
with a `WM_NULL` (2 s limit) before it calls a window hung (its tests: `test_a_window_windows_calls_hung_that_answers_is_not_hung`).
R8's field note of minutes-long stalls with hundreds of add-ons may have included the same wait.

## Review

An independent Claude review of the branch found eight problems; all are fixed and tested:

| # | Finding | Fix |
|---|---|---|
| 1 | Any realm's Lua could set `MENU_DLL`: a server's client Lua could then `require` the engine guard's client copy and put its own text in the overlay window; a listen server's add-on could take the RTX client module's menu part and end its catalog | Both modules take the menu's part only in the engine's own menu Lua state (`lua_shared`'s `GetLuaInterface(MENU)`); only the `gmsv_` copy of the engine guard has the overlay functions at all; contract tests in both |
| 2 | The notice's fonts lacked `extended`: Russian, Chinese, Japanese and Korean drew nothing | Tahoma with `extended`, as the guide; the harness checks the fonts |
| 3 | The ARC9 patch drew parts ARC9 did not draw in that call: a preset icon's world model, a world model in an RT scope or at LOD 2 (floating stickers at distant players), charms and translucent parts twice | It draws only what ARC9 draws: the same early returns, the preset's models, never charms, animation proxies or translucent parts; a new LuaJIT harness (`test_arc9_patch.py`, 8 tests) |
| 4 | A server-browser click could be swallowed (the page held it before Lua checked it); the console command went to `/servers/internet`, not a route | Held only once Lua has it; whatever Lua does not open the card for goes on; `/servers/`; harness and page tests |
| 5 | The gun-screen provider depended on load order; a failing provider callback turned the toolgun screen off; the mesh cache ignored the screen test | The provider waits in the table the companion keeps; callbacks protected; the cache keyed by the test, one function per provider; toolgun harness scenarios |
| 6 | The notice's timer queued JavaScript every 2 s also while the menu page loaded, which piles up in the panel | Skipped while the page loads |
| 7 | The overlay: a finish/tick race could show system uptime, a failed start leaked a buffer per retry, clipping could cut a UTF-8 character, a wrong comment, a full-size bitmap per paint | Checked under the lock, each resource made once, UTF-8-safe `clipped()`, an unowned window replaced, the paint buffer kept per size; tests for clipping and `start()`/`finish()` |
| 8 | The view-model pass keyed sub-materials 0-7 but processed 0-31 | One range for both, the model's material count |

Two more came from the checks after it. The full test gate's completeness check wanted the round's four new Lua files
in the render guard's exact list of bundled sources (added; no policy change). And a PoC run with the companion's
language set to Japanese still showed the card in English: the menu realm cannot see the companion's client convar
`nativeloader_language` (`GetConVar` returns nothing there, and reading `cfg/client.vdf` from the menu did not give
it either), so the companion now keeps a copy of the setting for the menu in
`data/nativeloader_companion/language.txt`, which both menu scripts read before falling back to `gmod_language`, and
`nativeloader_multiplayer_notice_status` prints the language and where it came from. With the language found, the
next run showed the menu realm has no `CompileString` either: both scripts now load the translation table through
`RunString`, which the stock menu uses.

## Tests

`tools\test.ps1 -Config Release` passed on the final tree: repository conventions, 29 of 29 C++ tests (the engine
guard's overlay and realm-contract tests and the RTX client module's contract tests among them) and 731 Python tests,
with the Lua harnesses for the notice (12), the load status (11), the ARC9 patch (8, new), the toolgun screen's
providers and the companion's language copy. The first run of the gate found the render guard's bundled-source list
short of the round's four new Lua files (fixed, above). The packaged build was checked in the PoC after every change
that reached the game (`verify 2`, `verify 3`, `notice ja`).

## Published (2026-11-09 UTC)

`main` was pushed at `8df9539` (three Git LFS objects: the engine guard's two modules and the RTX client module). The
merge's hook built the package here and uploaded it to item 3829070317 as **0.0.0-dev.20261109012903+a4e42ab9**
(2,182,350,494 bytes, SHA-256 `991204760b9e9c8e95da5df567e409540400abf885dc0c6a02e4f1fe15a34d6f`); Steam's public
record shows that size, updated 01:29:36 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub
Action was started: this session's one was R23's package run. The notice, the ARC9 fixes and the load overlay reach
players with the Workshop item; the loader is unchanged (0.16.0).

## Not changed

- The loader: no change. The unreleased R23 branch `r23-loader-mp-notice` is superseded (the notice is the package's
  now); a later loader release can drop its notice code.
