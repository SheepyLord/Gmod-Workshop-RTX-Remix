# ULib and the render guard: the guard inside ULib's hook library (report)

By Claude, 2026-11-21, on the branch `ulib-hooks` (worktree `out/worktrees/ulib`), built on `dlib-hooks`' changes;
package only (the companion's render guard and lag report). Decision:
[ADR 0257](../decisions/0257-the-guard-inside-ulibs-hook-library.md). Facts with file and line references:
[RESEARCH.md](../RESEARCH.md), "ULib's hook library and the render guard".

## The task

The DLib check ([dlib-hooks-report.md](dlib-hooks-report.md)) named a likely second case: ULib, ULX's library
(Workshop 557962238, about 1.4 million subscribers), replaces `hook.Call` and `hook.Add` from its client autorun too.
The main thread asked to check it, and to fix it in the package if confirmed, without a loader change.

## Confirmed

1. **ULib writes its own hook library over the guard's two fields.** Its client autorun includes
   `ulib/shared/hook.lua`, which reads `hook.GetTable()` and runs `module("hook")`. GMod's hook table is the loaded
   `hook` module, so it becomes the file's environment, and ULib's `GetTable`, `GetULibTable`, `Add`, `Remove`, `Run`
   and `Call` are written into its fields, over the render guard's dispatcher (`hook.Call`) and registration filter
   (`hook.Add`). The hooks registered so far are added again at the default priority. The engine keeps the
   dispatcher that stands in `hook.Call` after the autoruns: ULib's.
2. **That took the guard's whole hook layer away in every game with ULib**, as with DLib: MineMod's line, the known
   effects' skip, the depth pass's refusal, the protected render calls (containment, cleanup, the stop after three
   failures) and the slow callbacks' records.
3. **Offline:** a stand-in written for the test that does what ULib's hook library does
   ([`render_guard_harness.lua`](../../tools/tests/render_guard_harness.lua.md) `ulibTakeover`), against the guard
   before this change (DLib's version): in four frames MineMod's line drawn four times, the effect registered after
   ULib run four times (the one registered before ULib kept the filter's wrapper), two failing render callbacks
   called four times each with eight errors out of `hook.Call`, `NeedsDepthPass` true.
4. **In the game:** see "In the game (PoC)".

## The fix

[`_nativeloader_guard.lua`](../../companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md), in the hook library
block DLib's change added (`adoptULib`, called by `adopt` at the guard's install and at the first loading events):

- **When:** `GetULibTable` is a field of the hook table itself (DLib's alias of it, read through `__index`, does not
  count) and `hook.Call` is still there (DLib's takeover removes it). Where ULib came first (the late multiplayer
  route) at the guard's install; else at `PreGamemodeLoaded` (or the next loading event), after every autorun and
  before anything draws.
- **ULib's records:** each record's `fn` is wrapped by DLib's rule (`wrap`): a callback of an event the dispatcher
  protects runs through `protectedCall` with its hook's name (in the late route only an owned callback of a late
  event), `NeedsDepthPass` and every other event through the filter.
- **Later records:** ULib's `Add` removes the name at every priority, then puts the new record in one priority list:
  a new key there. The guard watches each list (`watchNames`: a metatable whose `__newindex` stores the record, then
  wraps its `fn`) and the registry (`watchEvents`: a new event's lists). So a hook added through `hook.Add`, through a
  reference to ULib's `Add` an add-on kept, or from ULib's own files is wrapped the moment ULib stores it. A list with
  someone else's metatable (VR's takeovers during VR) is left alone and walked again at the next loading event.
- **The dispatcher's other two jobs** (not in the late route, which leaves the remote server's dispatcher as it is,
  and not where the guard's own dispatcher still stands first): two hooks of its own at ULib's priorities.
  `nativeloader_guard_depth` on `NeedsDepthPass` at -1 returns false while the guard is on, before the add-ons'
  answers and the gamemode's; `nativeloader_guard_frame` on `PreRender` at -2 counts the frame for the slow callbacks'
  records.
- **ULib stays ULib:** `hook.Call`, `hook.Add`, `hook.Remove`, `hook.Run` and `hook.GetTable` stay its functions;
  `hook.GetTable()` and `hook.GetULibTable()` give the same tables, the plain one still with the add-ons' own
  functions; priorities, monitors and the removal of gone objects' hooks are ULib's. The gamemode's own methods run as
  ULib runs them (as with DLib).
- One console line, `[nativeloader] RTX guard: hook library: ULib runs the game's hooks from its own lists: the
  guard's protections run inside them (lua/ulib/shared/hook.lua)`, and `NativeLoaderRenderGuard.hook_library` is
  `"ULib"`. The guard's dispatcher has a name now (`dispatcher`), so the ULib part can tell whether it stands first.
- **The lag report** ([`nativeloader_lag_report.lua`](../../companion/nativeloader/lua/autorun/nativeloader_lag_report.lua.md)):
  it put its timer into a ULib record only where the record held the add-on's own function, so with the guard's
  wrapper there it would have left every guarded hook out. It now times what the record holds (`swapIn`), names the
  hook by the add-on's function from the plain table, and gives the record back what it held (`swapOut`).

## Verified

- **Offline (LuaJIT).** `test_render_guard.py` `test_the_guard_works_inside_ulibs_hook_library`: `ulib_hooks` (the
  early route) and `ulib_hooks_multiplayer` (the late route, ULib first) pass on the branch and fail on the guard
  before it, at the check that the library was found (the effects without that check: "Confirmed", 3). Six guards
  changed back one step each (no watch on new names, no walk of the records already there, no depth pass hook, no
  frame hook, a frame counted twice, the own hooks in the late route) each fail one of the scenarios. The DLib, MineMod,
  install, autorun and multiplayer scenarios still pass; the guard suite: 32 tests, OK. `test_lag_report.py`:
  `ulib_guard` passes, and fails on the lag report before this change ("hooks are timed"); the other five scenarios
  pass.
- **The gate:** `tools\test.ps1 -Config Release` in `out/worktrees/ulib` (`NL_FIXES_CLONE` set): "All checks passed."
  (the conventions; the Release build and 35 of 35 CTest tests; Python 29, 26 and 2,186 tests, one skipped each). The
  gate does not discover `companion/tests`; there `test_lag_report.py` and VR's check that the production guard takes
  the wrist canvas (`vr_guard_harness.lua`, which reuses the render guard's harness) pass, and so does the whole
  companion suite (`python -m unittest discover -s tests` in `companion`: 234 tests, OK).
- **In the game:** see below.

## In the game (PoC)

The driver `out/ulib-poc/ulib_session.py` (in the worktree, untracked; the DLib check's driver adapted) held
`out\r10\poc.lock`, moved the PoC's state aside (`vr_session.preserve`) and ran sessions on gm_construct (RTX on, the
packages' add-ons, 1600x900, 45 s in the map, then `report.lua` and two screenshots). The packages: the published one
(`0.0.0-dev.20261122030548+82015679`, a copy of the item's current upload, SHA-256 as in its publish record) and this
branch's (`0.0.0-dev.20261122043634+697bc382`, built from the worktree), each with and without the real ULib; then
the branch's final build (`0.0.0-dev.20261122044708+f38f4abf`) again with and without ULib. The final build differs
from the first by one line: the guard's own `adopt` is no longer marked as a guard wrapper, so DLib and ULib wrap it
like any callback and an error in it stays contained at `Initialize`, as DLib's version had it. ULib is Workshop
557962238, downloaded with steamcmd's anonymous login on the user's approval and placed as a loose add-on; its
`hook.lua` is byte for byte GitHub's. Every session also had a test add-on written for the check, whose client autorun
runs after ULib's and so registers through it: a MineMod stand-in drawing its line from `lua/mc/cl_resource_packs.lua`
with MineMod's failed state, an effect stand-in at `lua/postprocess/pp_ssr.lua`, a `NeedsDepthPass` hook answering
true, a `PostRender` callback that fails its first ten calls (priority 1), HUD hooks at ULib's five priorities (the
monitors returning a value), a HUD hook taking 5 ms, and `nativeloader_lag_report 5` 15 s after `InitPostEntity`.
Counts are calls of each callback during the session:

| Run | ULib in `hook.Call` | `hook_library` | HUD frames | MineMod's line | Effect | `NeedsDepthPass` hook | Failing callback | 5 ms hook named by the guard |
|---|---|---|---|---|---|---|---|---|
| published + ULib | yes | none | 1,517 | 1,517 | 1,517 | 1,517 | 1,517 (ten failures printed by the game) | no |
| published, no ULib | no | none | 1,507 | 0 | 0 (refused) | 0 | 3 (contained, stopped) | 5.0 ms |
| branch + ULib | yes | `ULib` | 1,520 | 0 | 0 (refused) | 0 | 3 (contained, stopped) | 5.0 ms |
| branch, no ULib | no | none | 1,577 | 0 | 0 (refused) | 0 | 3 (contained, stopped) | 5.0 ms |
| final + ULib | yes | `ULib` | 1,678 | 0 | 0 (refused) | 0 | 3 (contained, stopped) | 5.0 ms |
| final, no ULib | no | none | 1,642 | 0 | 0 (refused) | 0 | 3 (contained, stopped) | 5.0 ms |

- **published + ULib reproduces it in the game:** `hook.Call`, `hook.Add` and `hook.GetTable` were ULib's
  (`lua/ulib/shared/hook.lua`); the guard found no hook library and recorded nothing for the hooks (no `adapted`,
  `blocked`, `errors` or `slow` record). MineMod's line was drawn in every frame (its screenshot shows it in the middle
  of the screen), the effect and the depth pass hook ran every frame, and all ten failures of the render callback went
  through as the game's own errors. Without ULib the same package keeps all of that off.
- **branch + ULib, and the final build + ULib:** ULib's functions stayed in the hook table and its order held (monitor
  -2, -1, 0, 1, monitor 2, in each first frame; the monitors' values ignored). The guard found ULib
  (`[nativeloader] RTX guard: hook library: ULib runs the game's hooks from its own lists: the guard's protections run
  inside them (lua/ulib/shared/hook.lua)`), kept MineMod's line off with its ADR 0210 note, refused the effect, answered
  the depth pass (its own `nativeloader_guard_depth` at -1; the add-on's hook was never asked), contained the failing
  callback and stopped it after three failures, and named the 5 ms HUD hook (5.0 ms of every frame). ULib's lists held
  the guard's two hooks at -1 and -2, and MineMod's record a function of the guard's (shown as `lua/includes/init.lua`,
  the loader's view the guard is installed from) while the plain table kept MineMod's own. The lag report listed that
  hook first through the guard's wrapper: `HUDPaint "nltest_heavy"`, 5.02 ms a frame, with its file and add-on. The
  screenshot shows gm_construct path traced, the HUD drawn and nothing in the middle of the screen.
- Without ULib the branch behaves as the published package.
- **Found on the way, not changed:** with ULib, the load accelerator's timing of a load's callbacks (ADR 0241) misses
  every hook added after ULib's autorun, since ULib writes over its `hook.Add` too: in the ULib sessions its end-of-load
  line named a hook registered before ULib (`RTXReady_RenderLightUpdaters`), in the others the probe's 5 ms hook.
- Housekeeping: a field game was running (started outside these tests) and was left alone; each driver run took the
  lock, waited two minutes without a PoC game, and put the PoC back verified clean (`restoration.json`), the `user.conf`
  hash unchanged, the bulk copies removed. Evidence: `out/ulib-poc/runs-1/` and `runs-2/` in the worktree
  (`results.json`, each session's `console.log`, `remix-dxvk.log`, `loader.log` and screenshots).

## Limits and follow-ups

- The gamemode's own methods are not contained in games with ULib (nor with DLib).
- The guard depends on ULib's layout (`GetULibTable`, records' `fn`, lists that are tables, `Add` storing a new key),
  unchanged since 2015; if it changes, games with ULib are back where they were before this change, nothing worse.
- A hook registered during a load before ULib's autorun, while the load accelerator times the load's callbacks
  ([ADR 0241](../decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md)), keeps that timer inside the guard's
  wrapper; after the load it only passes the call on (as the timers' do). Seen while reading, not in a game.
- Not changed, seen while reading: the guard's registration filter decides by a function's source, and a timing
  wrapper (the load accelerator's, the lag report's) has the timer's source, so an effect's hook registered through
  such a timer passes the filter. Protected events still skip it (`protectedCall` looks through `timed`); other
  events do not. A possible follow-up for the filter: look through `timed` as `protectedCall` does.
- ULib loaded before the guard outside the late route (not seen: the early view installs the guard before any
  autorun) keeps the guard's own dispatcher in front, which runs protected events from ULib's plain table without its
  priorities, as before.
- Not run: a multiplayer game with ULib from a server (a ULX server), ULX itself (ULib alone), ULib and DLib together
  (by the source DLib wins: ULib's `hook.lua` returns at once when `hook.GetULibTable` exists, and DLib's library has
  that alias).
- Older gaps of the same kind, seen on the way and not changed: the load accelerator's callback timing (ADR 0241) stops
  at ULib's autorun (see "In the game"), and at DLib's by the source; and the lag report has never timed hooks in games
  with DLib (DLib's lists call each record's `callback`, the report swaps its `fn`).

## For the main thread

- Branch `ulib-hooks`, worktree `out/worktrees/ulib`, from `main` at `9085be02` with `dlib-hooks`' uncommitted changes
  applied first (its five shared docs' conflicts with main resolved by keeping both sides); nothing committed, pushed
  or published. The ULib part alone is the worktree's diff against the tree `447754ee` (main plus DLib's changes):
  `git diff 447754ee` after `git add -A`, or the patch in the session's notes folder.
- Changed by this branch: `_nativeloader_guard.lua` (and `.md`), `nativeloader_lag_report.lua` (and `.md`),
  `render_guard_harness.lua` (and `.md`), `test_render_guard.py` (and `.md`), `lag_report_harness.lua` (and `.md`),
  `test_lag_report.py` (and `.md`), CHANGELOG, ROADMAP, RESEARCH, TESTING, the decision and handover indexes. New: ADR
  0257, this report. Nothing of DLib's part was changed: its `adopt` is now `adoptDLib`, called with `adoptULib` from
  one `adopt`, its body as it was.
- At the merge (the main thread, 2026-11-21): DLib's decision became ADR 0256 and ADR 0257's link follows it;
  AGENTS.md's status line and its list of reports name both.
