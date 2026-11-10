# R28 report: GitHub issue 2 resolved in the package; what lags an RTX frame

The user's request of 2026-11-10: "Inspect the report and finding from another Claude session, Resolve Issue 2
(separate session) and make the package more robust by preventing addons like HyperReal FX from lagging the game, and
find and safeguard potential game-lagging methods. Push to GitHub and Workshop after you finish."

The other session's report is [issue-2-memory-report.md](issue-2-memory-report.md) (a diagnosis; merged into `main`
with this round). Done by Claude, with a Claude subagent for the review; no Codex. No loader and no runtime change.

## What issue 2 was, and what resolves it

Issue 2: when the game freezes or crashes, a gmod.exe "will usually persist and refuse to close for a while even after
'end task'", with memory use jumping "to 97-99 percent"; players with 24 GB of RAM and 8 GB cards report near memory
overflow, and lag.

| What the diagnosis found | What R28 does | Decision |
|---|---|---|
| The spike and the lingering process are Windows Error Reporting copying the crashed game: +22 to +26 GB of commit for a 20 GB game | The engine guard module sets `WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH` and `_HANG` for the game, in every realm, from the menu's start. Windows reports from the suspended process: the same report and dump, no copy (measured by the diagnosis with the same flag: +0.06 GB, gone in 5.8 s instead of 11.8 s) | [ADR 0142](../decisions/0142-no-crash-snapshot-of-the-game.md) |
| At the end of every load Source draws every loaded texture once, and the runtime makes a GPU image for each: 7,574 images, 4.9 GB, a peak of 11 GB of VRAM where 7 are needed | `mat_forcemanagedtextureintohardware 0` is one of the package's session settings (the fixes' RTX settings) | ADR 0142 |
| HyperReal FX takes 67 ms of every frame under RTX and shows nothing | Its cost was two screen read-backs a second, each waiting one to two frames for the path tracer. A reader's read-backs have an allowance (eight at once, refilled at 1.25 a second); one that uses it up gets no more until its requests fall back or it is quiet for five seconds, and `render.ReadPixel` is answered from the last picture of the same call | [ADR 0143](../decisions/0143-read-backs-font-definitions-and-slow-render-hooks.md) |
| The package's light updater draws one helper per map light every frame (49 ms on a 4,606-light map) | On a map with 256 lights or more, a helper that can set steady point lights alone is drawn only while such a light is in view, near the eye or near a dynamic light, and in turns (once in 120 frames; the runtime keeps a point light out of view for 1000); a spot light's or a switched light's own helper, and any helper that may set a texture light or the sun, every frame as before | [ADR 0144](../decisions/0144-the-light-updater-draws-what-the-runtime-needs.md) |
| Players cannot tell which add-on lags | `nativeloader_lag_report`: ten seconds of timing, then the most expensive hooks of the client and the local server with their add-ons, also as text files to attach; the render guard names slow render hooks by itself; the guide and [STABILITY.md](../STABILITY.md) say so | ADR 0143 |

Also found while measuring ("find and safeguard potential game-lagging methods"), and handled:

- **A font defined again every frame** (`surface.CreateFont` in a paint hook): the engine rebuilds every font's glyph
  pages each time; twenty such calls a frame took a 12 ms frame to 29 ms. The same definition is now made once.
- **The package's effect categories** rebuilt their lists four times a second whether or not anything had changed (up
  to 4.7 ms of a frame with the 654 add-ons); now only after a change.

Measured and left alone, with the reason (ADR 0143): the screen copies and target passes of post-processing add-ons
(hundredths of a millisecond once their shaders are refused), `render.RenderView` from add-ons (half a frame on
gm_construct; skipping a view leaves the cleared target on screen), per-tick walks over every entity on the server
and heavy `Think` code (the lag report names them). Tried and not used (ADR 0144): the light helpers drawn under a
material the runtime ignores, which still sets their lights; the frame stayed at 40.1 ms against 40.2-40.4, so a
helper's cost is the draw that sets its light, not its geometry.

## What the crash in issue 2 was

The diagnosis found every crash ending in a fail-fast at `engine.dll+0x34b6bc` and left its caller open. Its dumps
hold the answer (RESEARCH, R28): that thread is **GMod's own crash handler**, writing the text half of its crash
report. The C runtime's `_write` finds the report's file descriptor closed, calls its invalid-parameter routine, and
that fails fast because the engine sets no handler; the buffer it was writing starts `-Console Buffer-`, and every
report GMod left ends just before that section. So Windows Error Reporting saw GMod's handler die, after a first
fault that GMod's own minidumps name:

- an access violation at `studiorender.dll+0x6603b` (three sessions, two of them during an NPC wave with the 654
  add-ons);
- an access violation at `shaderapidx9.dll+0xd7ff` / `+0xd759`, a null vertex buffer (three sessions, one on
  gm_construct with nothing mounted), the same fault as R27's two PoC crashes that afternoon.

Every GMod crash that takes this path ends in Windows Error Reporting, whatever its cause, which is why the snapshot
mattered so much. The first faults themselves are not fixed here: they are the engine's, and both afternoons' crashes
fell on a GPU shared by several RTX games and AI jobs. What R28 removes is what made a crash into a frozen computer.

## Measured

This round's own vanilla copy of the game (`out/r28/game` in the main checkout, 2,877 depot files; another session
held the PoC), RTX on, 1920x1080, `-noworkshop`, an RTX 5090; every lab ended with a clean rollback and the game's
registry key unchanged.

| Check | Before (the published package) | With R28's package |
|---|---|---|
| A test add-on shaped like HyperReal FX (three stages, 18 refused shader passes, two 1x1 read-backs every 0.5 s), gm_construct: its read-backs | 78 in 20 s, 11.4 ms each (worst 26 ms) | the same calls 0.02 ms each: eleven made in the first three seconds after the add-on starts (and eleven again after it had been off for twenty seconds), the rest answered from the last picture read |
| ... frame time, average / 95th percentile / worst | 9.64 / 11.95 / 90.8 ms | 7.99 / 9.08 / 13.4 ms (7.80 / 8.75 / 11.9 ms with the add-on off) |
| Windows Error Reporting's flags of the running game, read from outside | none (`0x80070490`) | 384 (both flags) from 25 s after the process started, all session |
| The light updater on gm_construct (142 lights, 78 of them steady point lights), six views: the hook / the frame | 0.90-1.00 ms, 142 helpers / 7.3 ms | the same by default: the map has fewer than 256 lights. With the list asked for (`rtx_lightupdater_all -1`; all 78 bounded): 65-71 helpers looking away from the buildings, 88-121 looking at them, 0.46-0.84 ms / 5.4-6.8 ms |
| The light updater on gm_backrooms_classic (Workshop 2732733089: 1,126 map lights, all point lights; 1,125 helpers bounded), six views from one spot: the hook | 9.1-9.2 ms a frame, 1,126 helpers | 0.4, 1.3, 5.3, 4.3, 0.3 and 0.3 ms (28, 142, 652, 536, 13 and 13 helpers) |
| ... the frame | 38.5-38.6 ms | 9.4, 12.4, 26.1, 22.8, 9.2 and 9.2 ms: a helper left out gives back 27-35 us, three times its own call |
| ... the picture: pairs of screenshots, every helper against the list (the scene's left 60 %) | | the same within noise in all six pairs: mean differences 0.6-0.8 of 255 levels, the largest of 64 blocks 1-2; and after 400 frames facing one way, the opposite view settled matches |
| The same on modern_house (Workshop 3495468649: 1,032 lights with helpers, 989 of them steady point lights, 959 bounded; 1,800 texture lights among its 2,811 world lights), six views, a fixed clear sky: the hook | 8.3-8.6 ms a frame, 1,032 helpers | 5.2, 2.2, 3.7, 4.8, 2.8 and 1.9 ms (634, 252, 431, 564, 318 and 197 helpers) |
| ... the frame | 38.2-38.9 ms | 27.7, 17.5, 22.8, 26.4, 20.0 and 16.4 ms |
| ... the picture | | the same within noise: mean differences 0.5-1.3, the largest block 1-3 (7 where a cloud drifted), and the settled picture after a turn; six more pairs with a light 260 units behind the camera, looking away from it, 0.6-0.8 and 1-2. Without the fixed sky the pairs differ by 20-30 levels: the sun goes behind a cloud between two screenshots |
| GPU images the runtime made for game textures, base content only (gm_construct, then gm_backrooms_classic; the minimum memory profile and the low tier): by the first pass / after the second load | 663 (243 MB) / 720 (279 MB), `mat_forcemanagedtextureintohardware` 1 | 216 (97 MB) / 265 (128 MB), the convar echoed as 0; the picture as before. With the diagnosis' 654 add-ons the same convar gave 470-642 images where the preload made 7,574 |
| The same test add-on at 3840x2160: its read-backs | 78 in 20 s, 15.9 ms each (worst 34 ms) | 0.02 ms each |
| ... frame time, average / 95th percentile / worst (with the add-on off: published 12.22 / 14.44 / 118 ms, R28 11.04 / 12.58 / 33 ms) | 12.76 / 15.82 / 95.4 ms | 11.05 / 12.95 / 22.2 ms: the add-on costs what it costs switched off |

`nativeloader_lag_report 5` in that game timed 483 hooks, 161 gamemode functions and 100 net receivers of the client and 137, 144 and 84 of the server, put back 483 of 483 and 137 of 137 hooks,
and reported "49 repeated screen read-backs (render.CapturePixels) answered from the last picture read, 11 made". Its first client lines: the light updater 0.97 ms a frame, the fixes' category
manager 0.41 ms, the test add-on's stages 0.30 and 0.15 ms, the companion's model layers 0.24 ms. The server's first line is the base gamemode's `CalcMainActivity`, 0.016 ms a tick, listed as
`"the gamemode"` with `[Garry's Mod]`.

## Test installs skip the user's other subscriptions

The user, 2026-11-10, while this round ran: "In PoC, currently at each launch the game takes a long time to unpack
assets ... Additional assets should be skipped to save load time in testing." The PoC's loader was deploying ten
content packages of the user's own subscriptions (map and character packs of 1-4 GB each) whenever a lab had moved
`native-loader\` aside and deployed afresh. [`poc_session.py`](../../tools/poc_session.py.md) `install` and
`config` now write `"allow": {"subscribed_content": false}` unless `--subscribed-content on`, and the PoC's own
`config.json` has the switch: its next start removed the ten packages once (8,698 file changes, 84.7 s), and the
start after that deployed nothing (0.4 s; the whole session to gm_construct and out again took 23 s). Sessions in
older worktrees write a config without the switch until they take `main`.

## What it leaves

- **RAM during play** (the diagnosis' fix 5): the add-ons' textures are held as CPU copies in memory Windows cannot
  page out (5.6-5.9 GB with the 654 add-ons). Making them pageable is a runtime change (ordinary memory, uploaded
  through staging); not started.
- **Lights in view, spot lights and texture lights still cost a helper every frame.** The runtime drops a spot or
  directional light the frame it is not set, and any light in view; a texture light is a spot light for it. A map
  lit mostly by `light_spot` or by texture lights, or seen from a corner with everything ahead, gains little
  (ADR 0144). Changing that needs the runtime to keep such lights for a few frames; not started.
- **What a helper may set is worked out with a margin, not read from the engine** (ADR 0144): Lua cannot ask the
  engine which lights it set for a draw. The study assumes the engine's four are among the lights it lists;
  `rtx_lightupdater_all 1` draws every helper every frame if a map ever shows a light that comes and goes.
- **The runtime can hand a light that stops to a new dynamic light** (the second review; ADR 0144). The lights
  near the eye, near lamps and near Lua's dynamic lights never stop. The engine's own dynamic lights more than 450
  units from the eye (a Source weapon's muzzle flash, an explosion, something burning or flying) can still take a
  steady light out of view beside them, for up to 120 frames each time, and leave a copy of themselves out of
  view; and with the Remix free camera the lights outside the game's own view are not kept at all. Both only on maps with 256 lights or more, where the list is
  used. The clean fix is in the runtime (tell a map light from a moving one in `dynamicLightMatching`, keep lights
  with the free camera, let Lua read the camera's state): proposed as the next round's work, not started.
- **A moving dynamic light can leave copies of itself out of view with every helper drawn too** (the control
  of this round's last probe: three poses of six, 32-34 levels brighter after 760 frames at one place). That is the
  runtime keeping a point light out of view for 1000 frames when its move found no match; it is older than this
  round and belongs to the same runtime work.
- **Maps under 256 lights keep every helper every frame** (gm_construct: 1 ms of a 7.4 ms frame). The list would
  give back up to 2 ms there (`rtx_lightupdater_all -1`); the default leaves them as they were until the runtime
  part is done.
- **The flags are set when the menu's Lua starts**, about 25 s into the process here. A crash before that, and a
  start without RTX, still get the snapshot. The loader could set them at its own start (three lines next to
  `observer::disable_window_ghosting()` in `loader/proxy/startup.cpp`); that is a loader change, so it is offered,
  not made.
- **The first faults** (`studiorender.dll+0x6603b`, `shaderapidx9.dll+0xd7ff`) are open.
- **A real 24 GB / 8 GB computer and an AMD card** were not available, as in the diagnosis; the snapshot is
  Windows' own and applies to any GPU. HyperReal FX itself was not run here (the diagnosis' copy was deleted and the
  user is not subscribed): the test add-on makes its calls as the diagnosis describes them.
- The three new guide lines are translated by Claude into the six languages and not human-reviewed
  ([companion/i18n/README.md](../../companion/i18n/README.md)).

## Review

An independent Claude subagent reviewed the round's code (the guard's three safeguards, the light updater's list, the
lag report, the effect categories' change and the crash-report switch), replaying cases against each. It confirmed
the bookkeeping bounds, the pass-through of arguments and results, the timing's overhead (about 8 % on a callback
that does nothing else), the `dirty` flag, that the view test is a superset of the runtime's frustum, the rebuild
and warm-up, and the crash report by reading. It ran no game. Its fourteen findings, none high, and what became of
them:

| # | Finding | Outcome |
|---|---|---|
| 1 | Medium: one remembered picture per file, so two targets read through one helper answered each other's values once refused | A picture per call: the calling line and the render target read (eight a file, further ones share one); in the `cost_safeguards` scenario |
| 2 | Medium: "four fast reads running" misjudged: a once-a-second reader with uneven timing was refused for good after a while, four at once every 1.1 s passed for ever, a single batch of six was cut | An allowance per file: eight read-backs at once, refilled at 1.25 a second. About one a second is never limited (330 uneven ones in the scenario), a batch of eight is made in full, the bursts are cut in the third |
| 3 | Medium, not checked in a game by the reviewer: lights that reach the runtime only as the neighbours of another light's helper (texture lights, which have no helper; a light whose helper could not be placed; the sun without the package's sky) would be set one frame in 120 when that helper is out of view | True, and it mattered: a texture light is a spot light for the runtime, which drops it the frame it is not set. The list is rebuilt on what a helper may set, worked out from the map's world lights (ADR 0144): a helper is bounded only if no light without a helper drawn every frame can be among the lights it sets, and a texture light is such a light (1,800 of modern_house's 2,811 world lights). In the game the difference did not show on that map (the first build's pictures matched there too, and helpers drawn beside texture lights alone changed nothing visible): the rule is kept for the rooms a texture light lights alone |
| 4 | Medium: the lag report called an add-on's file under a folder the game also has (`lua/postprocess`, a gamemode, `lua/includes/modules`) "Garry's Mod" | The mounted items are asked first; the game is named only for a file none of them has, under the game's own folders |
| 5 | Medium-low: a fractional pixel coordinate was answered black once refused | Coordinates are truncated as the engine does; a pixel the picture does not hold gets the picture's last pixel |
| 6 | Medium-low: `pcall(render.CapturePixels)` made every such caller one reader; a tail call is counted for the caller's caller | Through a native frame the first Lua caller outside the guard is taken; a tail call cannot be told (the frame is gone) and is documented |
| 7 | Medium-low: every `render.ReadPixel` looked its caller up while any reader was refused, and a refused reader that stopped asking was never cleared | `render.ReadPixel` belongs to the latest read-back, with no caller lookup; a refused picture stops answering after five seconds |
| 8 | Medium-low: slow-callback records were kept by function, so the lag report's timers and closures added again made duplicates (32 at most) | A named hook is counted by event and name; a timer enters itself in `NativeLoaderRenderGuard.timed`, and the guard names, and treats, the function it times |
| 9 | Low: the lag report swapped functions with `hook.Add` (errors for hooks of removed panels, a second wrapper from the guard, the default priority in ULib) | It swaps in the hook table itself, at the hook's priority under ULib; a hook library it does not know is left alone and counted |
| 10 | Low: the light list relied on runtime options a user's Remix settings can change | `rtx.conf` is read for the four it relies on (anti-culling of lights, its frame count and angle, the free camera): the list is switched off, or its turns shortened and its view widened, and `rtx_lightupdater_status` says why. A change made in the Remix menu and not saved to `rtx.conf` cannot be seen from Lua: `rtx_lightupdater_all 1` |
| 11 | Low: a font definition was remembered for the session, also when the engine's font was changed by a route the wrapper does not see | Names without case, the same definition made again after ten seconds, a table with a metatable left to the engine |
| 12 | Low: a hook's name could be carried to the next protected call when its callback was left out | Taken and cleared before that test |
| 13 | Low: the lag report stayed "already measuring" after an error in its report, did not time the gamemode's own functions, and its document said there was no harness | Everything is put back and the next report can start whatever fails; the gamemode's functions are timed and listed as `"the gamemode"`; the document names the harness |
| 14 | Nits: `render.ReadPixel` always returned four values; a failed read of the flags after a successful `WerSetFlags` was reported as "not set"; two locals shadowed | What the engine returns is returned; set flags that cannot be read back are reported as set; the locals are gone |

**A second review**, by another independent Claude subagent, of the code written for the first one's findings (the
light list, the read-back rewrite, the lag report, the crash switch), with replays under LuaJIT and a model of the
runtime's light rules driven by the real hook. It confirmed that all harness scenarios pass, that odd maps (no or
over 20,000 world lights, a sun alone, NaN values, lights outside the world, colliding origins, failing visibility
calls) fall back to every helper, the costs with 5,000 lights (0.13-0.26 ms a view to choose the helpers, 0.14-0.8 ms
a helper to study), the allowance's figures and the bounded tables. Its findings, none high:

| # | Finding | Outcome |
|---|---|---|
| 1 | Medium-high: the runtime takes a light that was set in the last frame and not in this one for a light that moved, and hands it to a new point light within 300 units (`dynamicLightMatching`). A helper that stops is in that state for a frame: with a dynamic light near the eye, map lights out of view went dark between turns (its model: one missing within 600 units in 14-15 % of frames) | The lights within 450 units of the eye, of a lamp and of a light made with `DynamicLight` from Lua never stop being set. Checked in the game (gm_backrooms_classic, six poses, a white Lua light going round the eye at 120 units with a model of its own, the exposure held): with the build before this fix the list's picture differed from every helper's in all six pairs, brighter by 12-42 of 255 levels in red and green and whiter (largest block 17-72): each time a stopped map light took the moving light's match, the moving light's own last copy found none and stayed, out of view, for the runtime's 1000 frames. With the final build the three poses where the probe leaves no such copies by itself match within noise (0.3-0.6 levels, blocks 1-2.5); in the three others the pictures differ by less (23-25) than they do in a control with every helper in both (32-34). A Lua light that stands still gives the same picture either way (share of blue 0.248 and 0.249; 0.03 without the light). What is left, the engine's own dynamic lights farther from the eye, is in ADR 0144 and under "What it leaves" |
| 2 | Medium: the Remix free camera is switched on in the menu, not in `rtx.conf`, and with it the runtime keeps no light: the list then leaves the lights outside the game's own view unset | Lua cannot see it. The list is used only on maps with 256 lights or more; `rtx_lightupdater_status`, STABILITY and ADR 0144 say to use `rtx_lightupdater_all 1` with the free camera. A live getter in the runtime is left for a later round |
| 3 | Medium: under ULib the lag report missed the render hooks: the guard runs its events from the plain table ULib keeps beside its own (its replay: a 49 ms hook not listed) | The timer goes into both tables and comes out of both; in the `ulib` scenario |
| 4 | Medium-low: the runtime tests a frame's lights with the projection of the frame before, so a fast zoom dropped lights for up to a turn | A light that left the view counts as in view for two more frames |
| 5 | Low-medium, read-backs: a reader of one sample a second that overran once stayed refused for good; a picture with no pixel answered black for ever; two add-ons through one shared library were one reader; another file's reads could mark a reader a scanner | Every request counts and the allowance drains while refused, with re-entry at half; a picture is kept until new pixels arrive, and the engine's own last picture is read when nothing is remembered; a reader is the file and its caller; only the capturing file's own reads count. Each in the `cost_safeguards` scenario |
| 6 | Low, the light list: the trace filter's variable was assigned above its declaration (a global written, the filter's own left empty); a rebuild during the first study started it over; the steady lights "in sight" were not tested against the PVS | Fixed, each |
| 7 | Low: a hook the guard had stopped ran again under the report's timer; `timed` could be used to switch another add-on's callback off; the crash switch reported "ok" when the flags could not be read back | A stopped hook stays stopped under a timer and after it; the second is no more than removing the hook, and the record says so; the reason reads "ok (set; the flags could not be read back)" |

## Tests

`tools\test.ps1 -Config Release` on the final tree, from `out\worktrees\r28`: conventions OK, the C++ build and its
30 tests, and the Python suites (29, 26 and 787 tests; one skip in each, as before the round). New or extended in
this round:

- [`test_render_guard.py`](../../tools/tests/test_render_guard.py.md), the `cost_safeguards` scenario: the
  read-back allowance and its pictures (thirty-odd cases, the two reviews' among them), font definitions, slow
  callbacks by hook name, timers entered in `NativeLoaderRenderGuard.timed`, a stopped hook under a timer.
- [`test_light_updater.py`](../../tools/tests/test_light_updater.py.md), new: the packaged light updater under a
  fake GMod API, 20 scenario runs: which helpers a frame draws (view, the 450 units round the eye, the hold, the
  turns, the list by map size), texture lights, the map's visibility data, lights set by their own helpers, a
  light only its neighbours set, the sun, lamps and Lua dynamic lights, the runtime's options, unusable world
  lights, a rebuild.
- [`test_lag_report.py`](../../companion/tests/test_lag_report.py.md): five scenarios (client, server, ULib's hook
  library, one it does not know, a report that cannot be written).
- [`test_effect_categories.py`](../../companion/tests/test_effect_categories.py.md): the `quiet` scenario.
- `engine_guard/tests/test_crash_report.cpp`: the flags, the test process as the game, the module's contract.
- [`test_poc_session.py`](../../tools/tests/test_poc_session.py.md): test installs leave subscribed content out.

In the game: the labs under "Measured" (this round's own vanilla copy; every lab ended with a clean rollback, the
game's registry key unchanged and Windows Error Reporting's flags of the running game at 384). The package checked
last in the game was built from the committed tree's code (only documents changed after it).

## Published

`main` was fast-forwarded to `a37e704` and pushed (a9b9c16..a37e704). With it went the VR plan's commit (`a0074b1`,
made on `main` by the plan's session) and the diagnosis as one commit (`1643c1a`): its two local commits and this
branch's merges were made into a linear history with the same content, so that no commit message refers to the issue
by its number and GitHub adds nothing to the issue's page by itself. The merge's hook built the package here and
uploaded it to item 3829070317 as **0.0.0-dev.20261110142116+be270f89** (2,183,922,826 bytes, SHA-256
`e98e9b6e7f9a5e068b4dfd87748e53206fcce14842b6275dbc896556538a6373`); Steam's public record shows that size, updated
14:21:52 UTC. No GitHub Action was started, and nothing was written on the issue. The loader (0.16.0) and the runtime
are unchanged.
