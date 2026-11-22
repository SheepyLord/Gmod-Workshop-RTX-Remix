# 0257: The render guard works inside ULib's hook library

- Status: Accepted 2026-11-21 (the follow-up the DLib investigation named, checked and fixed on the main thread's
  request); package only.
- Decided by: Claude.
- Context: ULib (ULX's library, Workshop 557962238, [github.com/TeamUlysses/ulib](https://github.com/TeamUlysses/ulib),
  CC BY-NC-SA 3.0, about 1.4 million subscribers) brings its own hook library, as DLib does. Read from its source, it
  writes over the same two fields of the hook table the render guard stands in.
- Extends: [ADR 0256](0256-the-guard-inside-dlibs-hook-library.md) (the guard inside DLib's hook library), and
  through it [ADR 0054](0054-rtx-rendering-startup-boundaries.md) (the early guard and its
  dispatcher), [ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md) (the known effects' skip),
  [ADR 0143](0143-read-backs-font-definitions-and-slow-render-hooks.md) (the slow callbacks' records and the lag report)
  and [ADR 0210](0210-an-add-ons-notice-of-the-guards-refusal-stays-off-the-screen.md) (MineMod's line).
  [ADR 0052](0052-scoped-rtx-multiplayer-bootstrap.md)'s rule for the late multiplayer route stays: a remote server's
  dispatcher is left as it is.

## What happened

ULib's client autorun (`lua/autorun/ulib_init.lua`) includes `ulib/cl_init.lua`, which includes
`ulib/shared/hook.lua`. That file reads `hook.GetTable()`, then runs `module("hook")`: the hook table itself becomes the
file's environment, so its `GetTable`, `GetULibTable`, `Add`, `Remove`, `Run` and `Call` are written into the hook
table, over whatever stood there. It then adds the hooks registered so far again, at the default priority. Its `Call`
runs `hook.GetULibTable()`'s records, `[event][priority][name] = {fn = ..., isstring = ...}`, priority by priority
from -2 to 2, reading each record's `fn` when it comes to it; a value from -2 or 2 (the monitors) is ignored.

The render guard is installed before any autorun (ADR 0054) and stands in exactly `hook.Call` (its dispatcher) and
`hook.Add` (its registration filter). ULib's autorun writes both over, and the engine calls the dispatcher that stands
in `hook.Call` after the autoruns and keeps it (DLib's in the DLib check; a replacement made during a game was not
called by the engine in the R20 and VR probes). So in every RTX game with ULib, every hook ran from ULib's records as it
was:

- MineMod's "Default texture pack is not ready" line was drawn, the known screen-space effects ran (an effect
  registered before ULib stayed skipped, since its filter wrapper moved over with it);
- `NeedsDepthPass` was the add-ons' and the gamemode's answer;
- no render callback ran through `protectedCall`: errors came out of `hook.Call`, a callback failing every frame was
  never stopped, what it left open was not closed, slow callbacks were never named.

The offline harness, with a stand-in that does what ULib's hook library does, reproduced it against the guard before
this change: in four frames MineMod's line four times, the later effect four times, two failing render callbacks four
times each with eight errors out of `hook.Call`, `NeedsDepthPass` true. In the PoC with the real ULib (Workshop
557962238) the published package let a test add-on's MineMod stand-in, effect, depth pass hook and failing render
callback run in all 1,517 frames of a session, with ULib's `hook.lua` in `hook.Call`, `hook.Add` and `hook.GetTable`;
this change kept them off, contained and stopped, as without ULib (the
[report](../handover/ulib-hooks-report.md)).

## Decision

1. **The guard works inside ULib's records** once ULib is in charge: `GetULibTable` is a field of the hook table
   itself (DLib's alias of it is read through `__index` and does not count) and `hook.Call` is still there (DLib's
   takeover removes it). Where ULib came first (the late multiplayer route) at the guard's install; else at the first
   of `PreGamemodeLoaded`, `OnGamemodeLoaded`, `PostGamemodeLoaded`, `Initialize`, `InitPostEntity` and `OnReloaded`,
   which come after every autorun and before anything draws.
2. **Each record's `fn` is wrapped as DLib's callbacks are**: a callback of an event the dispatcher protects runs
   through `protectedCall` with its hook's name (in the late route only an owned callback of a late event),
   `NeedsDepthPass` and every other event's through the filter.
3. **Every record ULib makes later is wrapped as ULib puts it in place.** ULib's `Add` first removes the name at every
   priority, then puts the new record under that name in one priority list: a new key. The guard watches each priority
   list (a metatable whose `__newindex` stores the record and wraps its `fn`) and the registry (a new event's lists are
   watched as they come). That covers ULib's `Add` however it is reached, also through a reference an add-on kept
   before the guard found ULib. A list that already has a metatable of someone else's (VR's takeovers) is left to the
   walk at the next loading event.
4. **Not `hook.Call`.** The guard does not put its dispatcher back: the engine would not call it, and it would have to
   copy ULib's order and monitor rules. Outside the late route, and where the guard's own dispatcher does not still
   stand first, two hooks of its own at ULib's priorities do the dispatcher's two other jobs: `NeedsDepthPass`
   (`nativeloader_guard_depth`, priority -1, before the add-ons' answers) returns false while the guard is on, also
   where only the gamemode asks; `PreRender` (`nativeloader_guard_frame`, priority -2) counts the frame.
5. **ULib stays ULib.** Its priorities, monitors and dropping of hooks of objects that went away; its functions stay
   in the hook table; `hook.GetTable()` and `hook.GetULibTable()` give the same tables, the plain one still with the
   add-ons' own functions (only ULib's records hold the wrappers). The gamemode's own methods run as ULib runs them.
6. **One console line**, `[nativeloader] RTX guard: hook library: ULib runs the game's hooks from its own lists: the
   guard's protections run inside them (lua/ulib/shared/hook.lua)`, one `adapted` record, and
   `NativeLoaderRenderGuard.hook_library = "ULib"`.
7. **The lag report times what ULib's record holds.** `nativeloader_lag_report` put its timer into a ULib record only
   where the record held the add-on's own function; a record holding the guard's wrapper would have been left out. It
   now times what the record holds, the guard's wrapper among them (so the guard keeps protecting the function while it
   is timed), names it by the add-on's function in the plain table, and puts back what it found.

## Consequences

- In RTX games with ULib (ULX's servers, and players with ULX installed), MineMod's line stays off the screen, the
  known effects stay inert, the depth pass is refused, and render callbacks are protected, stopped after three failures
  in a row and timed, as without ULib.
- The gamemode's own methods for the protected events run as ULib runs them, without the dispatcher's containment (a
  vanilla game's behaviour), as with DLib.
- The guard depends on ULib's layout: `GetULibTable`, records with `fn`, priority lists that are tables, `Add` putting a
  new record under a new key. Unchanged since 2015 (`GetULibTable` came 2015-04-11; `hook.lua`'s last change,
  2025-05-26, cached the gamemode in `Run`). A ULib that changes it leaves the guard's hook layer out again, as before
  this change, and nothing worse: the guard checks each step.
- `hook.GetTable()` shows the guard's two hooks in games with ULib.
- A hook registered during a load before ULib's autorun, while the load accelerator times callbacks (ADR 0241), keeps
  that timer inside the guard's wrapper after the load: the timer then only passes the call on, as the ones left in
  timers do.
- Unchanged: a ULib loaded before the guard outside the late route (not seen: the early view installs the guard before
  any autorun) has the guard's own dispatcher in front, which runs the protected events from ULib's plain table without
  ULib's priorities; another hook library with its own design is still outside the guard ("Later API replacements ...
  can bypass these guards").
- No loader, runtime or native module change: the guard is the companion's `_nativeloader_guard.lua`; the lag report
  is the companion's `nativeloader_lag_report.lua`.

## Alternatives considered

- **Put the guard's dispatcher back in `hook.Call`**, a copy of ULib's `Call` with the guard's protection: the engine
  keeps the dispatcher it took after the autoruns, so this would depend on coming before that moment, which no hook
  marks, and the guard would carry ULib's ordering rules. Rejected.
- **Wrap ULib's `hook.Add` again at the loading events** instead of watching the lists: an add-on that kept ULib's `Add`
  in a local after ULib's autorun, and registers later, would get past it. The watch sees those too, `hook.Add` stays
  ULib's, and VR's check of the hook functions (`cl_view_hooks.lua`) is not disturbed.
- **Put the wrappers into the plain table too** (call ULib's `Add` with them): `hook.GetTable()` would give the guard's
  wrappers to the add-ons, and the lag report names a hook by its function. Rejected.
- **Keep ULib from taking over:** ULX and the add-ons that use its priorities and monitors would break.
