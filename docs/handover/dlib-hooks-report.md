# "Default texture pack is not ready" with DLib: the render guard inside DLib's hook library (report)

By Claude, 2026-11-21, on the branch `dlib-hooks` (worktree `out/worktrees/dlib`); package only (the companion's
render guard). Decision: [ADR 0256](../decisions/0256-the-guard-inside-dlibs-hook-library.md). Facts with file and line
references: [RESEARCH.md](../RESEARCH.md), "DLib's hook library and the render guard".

## The report

On the distribution item's Workshop page (2026-11-21): a player asked "What is the "default texture pack is not ready"
thing in the middle of my screen?"; another answered that they had found the add-on causing it, DLib (Workshop
1153306104); the owner replied "Thank you. We will fix this soon." The user's request: "Please investigate what is the
problem and address it."

## Root cause

1. **The line is MineMod's, as in GitHub issue 5** ([issue5-report.md](issue5-report.md), ADR 0210): its texture pack
   probe draws with its own shader, which the render guard keeps inert under RTX, so the bake fails and its `HUDPaint`
   hook draws the line on every map. Since 2026-11-13 the guard skips that one callback. DLib holds no such text (its
   252 Workshop files and its source, searched), and MineMod's files are unchanged since then (the entry still
   matches).
2. **DLib takes the game's hook library over.** DLib (a library about 252,000 players have, because many add-ons need
   it) loads its own hook library from its autorun `!sh_dlib.lua`. In a fresh game it moves every hook into its own
   tables, removes `GetTable`, `Add`, `Remove`, `Run` and `Call` from the global `hook` table, and points that table at
   its own (`__index`). Its `hook.Call` passes the call to `hook.Call2`, which runs a list `hook.Reconstruct` built.
3. **That took the guard's whole hook layer away.** The guard is installed before any autorun (the loader's view of
   `includes/init.lua`) and stands in exactly those two fields: `hook.Call` (its dispatcher) and `hook.Add` (its
   registration filter). After DLib's takeover neither is called again, and every hook added after DLib (MineMod's
   among them) runs from DLib's lists as it is. Disabling DLib gave the guard its fields back, which is why the line
   went away. The same takeover also cost every game with DLib the guard's skip of known screen-space effects, its
   refusal of the depth pass, its containment of failing render callbacks (and their stop after three failures), and
   the slow-callback records.

## The fix

[`_nativeloader_guard.lua`](../../companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md), at its end of the
hook section (`adopt`):

- Once DLib is in charge (`DLib.ghook` is the hook table and `hook.Call` is no longer in it), the guard takes its
  place at DLib's own extension points: at its install where DLib came first (the late multiplayer route, the autorun
  route), else at the first gamemode loading event (`PreGamemodeLoaded` ... `OnReloaded`), after every autorun and
  before anything draws.
- **`hook.Reconstruct`** (looked up by DLib at every change of an event's hooks): before DLib builds an event's list,
  each record's callback is wrapped: an event the dispatcher protects through `protectedCall` with its hook's name
  (the late route: only an owned callback of a late event), `NeedsDepthPass` and every other event through the filter.
  Every event's list is rebuilt once at that moment.
- **`hook.Call2`** (looked up by DLib at every call; not in the late route, which leaves a remote server's dispatcher
  as it is): `NeedsDepthPass` answers false and `PreRender` counts the frame, as the dispatcher does.
- DLib's order, priorities, disabled hooks, post modifiers, coroutine and object hooks stay its own; `hook.GetTable()`
  still gives the add-ons' own functions. The guard's own wrappers (`guardWrappers`) are never wrapped twice; a DLib
  reloaded by autorefresh is found again at `OnReloaded`. The gamemode's own methods run as DLib runs them.
- One console line, `[nativeloader] RTX guard: hook library: DLib runs the game's hooks from its own lists: the guard's
  protections run inside them (lua/dlib/modules/hook.lua)`, and `NativeLoaderRenderGuard.hook_library = "DLib"`.
- The dispatcher's frame start is one function now (`frameBegins`), used by both.

## Verified

- **Offline (LuaJIT harness).** A stand-in written for the test takes the hook table over as DLib does
  ([`render_guard_harness.lua`](../../tools/tests/render_guard_harness.lua.md) `dlibTakeover`). `dlib_hooks` (the
  early route) and `dlib_hooks_multiplayer` (the late route) pass on the branch's guard; the guard suites by discovery:
  56 tests, OK. On the published guard the early scenario fails at its first check; with that check left out, MineMod's
  line was drawn in four frames of four, an effect registered after DLib ran every frame, `NeedsDepthPass` was true
  and a failing render callback's error came out of `hook.Call` (the late scenario: an owned callback registered before
  the guard unprotected).
- **The gate:** `tools\test.ps1 -Config Release` in the worktree (`NL_FIXES_CLONE` set): "All checks passed." (the
  conventions; the Release build and 35 of 35 CTest tests; Python 29, 26 and 2,185 tests, one skipped each).
- **In the game:** see below.

## In the game (PoC)

The driver `out/dlib-poc/dlib_session.py` (in the worktree, untracked) held `out\r10\poc.lock`, moved the PoC's state
aside (`vr_session.preserve`), and ran four sessions on gm_construct (RTX on, the packages' add-ons, 1600x900, 45 s in
the map, then `report.lua` and two screenshots). The packages were the published one (main, `0.0.0-dev.20261122004027+d17b0fb8`)
and this branch's (`0.0.0-dev.20261122022842+591cdc1a`, built from the worktree), each with and without the real DLib.
DLib is Workshop 1153306104, downloaded with steamcmd's anonymous login on the user's approval and placed as a loose
add-on. Every session also had a test add-on written for the check: a MineMod stand-in drawing its line from
`lua/mc/cl_resource_packs.lua` with MineMod's failed state, an effect stand-in at `lua/postprocess/pp_ssr.lua`, a
`NeedsDepthPass` hook answering true, and a `PostRender` callback that fails its first ten calls. Counts are calls of
each callback during the session:

| Run | DLib took the hook table | `hook_library` | MineMod's line drawn | Effect | `NeedsDepthPass` hook | Failing callback |
|---|---|---|---|---|---|---|
| main + DLib | yes | none | 909 | 909 | 909 | 909 (all ten failures printed by the game) |
| main, no DLib | no | none | 0 | 0 (refused) | 0 | 3 (contained, stopped) |
| branch + DLib | yes | `DLib` | 0 | 0 (refused) | 0 | 3 (contained, stopped) |
| branch, no DLib | no | none | 0 | 0 (refused) | 0 | 3 (contained, stopped) |

- **main + DLib reproduces the report in the game:** the guard recorded nothing at all (no `adapted`, `blocked` or
  `errors` record). MineMod's line was drawn in every frame, as were the effect and the depth pass, and the failing
  callback's errors went through. Without DLib the same package keeps the line off: what the player found by disabling
  DLib.
- **branch + DLib:** the guard found DLib (`[nativeloader] RTX guard: hook library: DLib runs the game's hooks from its
  own lists: the guard's protections run inside them (lua/dlib/modules/hook.lua)`), kept MineMod's line off with its
  ADR 0210 note, refused the effect, answered the depth pass, contained the failing callback and stopped it after three
  failures. Its screenshot (`poc/branch-dlib/screenshot-1.png` in the evidence) shows gm_construct path traced, the
  HUD drawn and nothing in the middle of the screen. Without DLib the branch behaves as main.
- The main + DLib session's screenshot failed: "the game window has no client area" (`GetClientRect` gave no size: a
  minimized window), right after the report Lua had run; the game was then ended without a normal quit. That run has
  no picture; it was not repeated, since the next queued session took the PoC at once.
- The 28 `GetShaderModule: Out of range of supported shader model` lines in each Remix log are in all four runs alike
  (the engine's start-up), not DLib's.
- Housekeeping: the shared lock was held by a pack-install session's process (pid 4400) that no longer ran; another
  session's long gm_mallparking tour was using the PoC without the lock. The driver waited until no game had run in
  the PoC for two minutes, then removed the dead process's lock (its text kept as `stale-lock-taken-over.json`) and
  took it; the pack-install session's next run took the lock right after this one released it. The PoC was put back
  and verified clean (`restoration.json`), the `user.conf` hashes unchanged, the bulk copies removed.
- Evidence: `out/dlib-poc/runs-2/` in the worktree (`results.json`, each run's `console.log`, `remix-dxvk.log`,
  `loader.log` and screenshots).

## Limits and follow-ups

- **ULib** (ULX's library) replaces `hook.Call` and `hook.Add` from its client autorun too (`ulib/shared/hook.lua`,
  `module("hook")` with its own `Call` and `Add`), after the early guard: the same loss of the guard's hook layer is
  likely in games with ULib, read from its source and not run. ULib has no `Call2` or `Reconstruct` to stand in; it
  needs its own adaptation (its records' `fn`, its `Add`).
- The gamemode's own methods are not contained in games with DLib.
- The guard depends on DLib's names (`DLib.ghook`, `Reconstruct`, `Call2`, `GetDLibTable`, `callback`); if DLib
  renames them, games with DLib are back where they were before this change, nothing worse.
- MineMod itself still does not work under RTX (ADR 0210).

## For the main thread

- Branch `dlib-hooks`, worktree `out/worktrees/dlib`, from `main` at `11e21cf0`; nothing committed, pushed or published.
- Changed: `companion/nativeloader/lua/autorun/_nativeloader_guard.lua` (and `.md`), `tools/tests/render_guard_harness.lua`
  (and `.md`), `tools/tests/test_render_guard.py` (and `.md`), CHANGELOG, ROADMAP, RESEARCH, TESTING, the decision and
  handover indexes (one row each). New: ADR 0256, this report.
- Left to the merge: AGENTS.md's status line and its list of reports.

## Draft reply for the Workshop thread (for the owner to post)

> Thanks for tracking that down! The line itself comes from MineMod (the Minecraft blocks add-on): its texture pack
> can't be built while its shaders are switched off under RTX, and the RTX package hides that line. But DLib replaces
> the game's whole hook system when it loads, and that took away the package's hold on the hooks added after it, so the
> line came back. The next update of the RTX package works inside DLib's hook system, so the line stays hidden with
> DLib installed, and DLib keeps working as before. Until then, if you don't use MineMod, disabling it removes the
> line too. MineMod's blocks don't show with RTX on in any case; to play MineMod, start the game without RTX.

## Published

Merged by the main thread with the other pieces of 2026-11-21 on the branch `integrate-1122`: the content packs'
install (ADR 0255), the render guard inside DLib's and ULib's hook libraries (ADR 0256, ADR 0257) and the library
window's rows (ADR 0258). DLib's decision, drafted as 0254, became 0256 there. The gate passed on that branch
(`tools\test.ps1 -Config Release`). Under the standing permission (AGENTS.md rule 5) `main` was fast-forwarded from
`602f401d` to `6dca0e9b` and pushed; the merge's hook built the package here and uploaded item 3829070317 as
**`0.0.0-dev.20261122060047+34cd2c57`** (content digest `cdf287a621f3760c`).
