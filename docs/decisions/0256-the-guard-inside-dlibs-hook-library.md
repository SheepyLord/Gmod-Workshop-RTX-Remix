# 0256: The render guard takes its place inside DLib's hook library

- Status: Accepted 2026-11-21 (a Workshop report, investigated on the user's request "Please investigate what is the
  problem and address it"); package only.
- Decided by: Claude.
- Context: on the distribution item's Workshop page a player asked "What is the "default texture pack is not ready"
  thing in the middle of my screen?", another answered that they had found the add-on causing it, DLib (Workshop
  1153306104), and the owner replied "Thank you. We will fix this soon."
- Extends: [ADR 0054](0054-rtx-rendering-startup-boundaries.md) (the early client guard and its hook dispatch),
  [ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md) (the known effects' skip),
  [ADR 0143](0143-read-backs-font-definitions-and-slow-render-hooks.md) (the slow callbacks' records) and
  [ADR 0210](0210-an-add-ons-notice-of-the-guards-refusal-stays-off-the-screen.md) (MineMod's line), whose protections
  now also hold in games with DLib. [ADR 0052](0052-scoped-rtx-multiplayer-bootstrap.md)'s rule for the late
  multiplayer route stays: a remote server's dispatcher is left as it is.

## What happened

The line is still MineMod's (ADR 0210); DLib has no such text (its Workshop files and its source, checked). DLib
([gitlab.com/DBotThePony/DLib](https://gitlab.com/DBotThePony/DLib), MIT; about 252,000 subscribers, a dependency of
many add-ons) brings its own hook library, `lua/dlib/modules/hook.lua`, which its autorun `!sh_dlib.lua` loads. When it
loads in a fresh game it takes the game's hook library over: it moves every hook registered so far into its own
tables, removes `GetTable`, `Add`, `Remove`, `Run` and `Call` from the global `hook` table with `rawset`, and gives
that table a metatable whose `__index` is DLib's hook table. From then on `hook.Call` is DLib's `Call`, which only
passes the call on to `hook.Call2`, and every `hook.Add` goes into DLib's tables.

The render guard is installed earlier, right after the stock `includes/init.lua` (ADR 0054), and protects the hook
layer by replacing `hook.Call` (its dispatcher) and `hook.Add` (its registration filter) in that same table. DLib's
takeover removes both, so in every RTX game with DLib:

- the hooks added after DLib (nearly every add-on's) never pass the filter, and DLib's dispatcher calls them as they
  are: MineMod's `HUDPaint` callback draws its "Default texture pack is not ready: resource_sampling_unsupported" line
  again, and the known screen-space effects' callbacks run (ADR 0086);
- `NeedsDepthPass` is no longer answered with false;
- no render callback runs through `protectedCall`: an error is no longer contained, what it left open is not closed,
  a callback that fails every frame is never stopped, and slow callbacks are never named.

Disabling DLib gave the hook library back to the guard, so the line went away: that is what the player found. The
offline harness, with a stand-in that takes the hook library over as DLib does, reproduced it against the published
guard: MineMod's line drawn every frame, a known effect run every frame, `NeedsDepthPass` true, a render callback's
error out of `hook.Call`.

## Decision

1. **The guard takes its place inside DLib's hook library** once DLib is in charge: `DLib.ghook` is the hook table and
   `hook.Call` is no longer in it. Where DLib came first (the late multiplayer route; the autorun route) at the guard's
   install; else at the first of `PreGamemodeLoaded`, `OnGamemodeLoaded`, `PostGamemodeLoaded`, `Initialize`,
   `InitPostEntity` and `OnReloaded`, which come after every autorun and before anything draws.
2. **At DLib's own extension points, not over them.** DLib looks `hook.Call2` and `hook.Reconstruct` up anew at each
   call and at each change of an event's hooks. The guard wraps `Reconstruct`: before DLib builds an event's list, each
   record's callback is wrapped, a callback of an event the dispatcher protects through `protectedCall` with its hook's
   name (in the late route only an owned callback of a late event), `NeedsDepthPass` and any other event's through the
   filter. Every event's list is rebuilt once at that moment. It wraps `Call2` (not in the late route) to answer
   `NeedsDepthPass` with false and count the frame at `PreRender`, as its dispatcher does.
3. **DLib stays DLib.** Its order and priorities, disabled hooks, post modifiers, coroutine and object hooks are its
   own; `hook.GetTable()` still gives the add-ons' own functions, since only DLib's records hold the wrappers. A
   wrapper the guard made is never wrapped again; a DLib reloaded by autorefresh is found again at `OnReloaded`.
4. **One console line**, `[nativeloader] RTX guard: hook library: DLib runs the game's hooks from its own lists: the
   guard's protections run inside them (lua/dlib/modules/hook.lua)`, one `adapted` record, and
   `NativeLoaderRenderGuard.hook_library = "DLib"`.

## Consequences

- In RTX games with DLib, MineMod's line stays off the screen again, the known effects are inert again, the depth
  pass is refused, and render callbacks are protected and timed as without DLib.
- The gamemode's own methods for the protected events run as DLib runs them, without the dispatcher's containment
  (a vanilla game's behaviour). The guard's dispatcher contains them only where it still dispatches.
- The guard now depends on four names of DLib's hook library (`DLib.ghook`, `hook.Reconstruct`, `hook.Call2`,
  `hook.GetDLibTable` and its records' `callback`), unchanged in DLib since 2017-2020. A DLib that renames them
  leaves the guard's hook layer out again, as before this change, and nothing worse: the guard checks each name and
  does nothing without them.
- Another hook library that takes the hook table over in its own way is still outside the guard; the state's
  limitation "Later API replacements ... can bypass these guards" stands for them.
- No loader, runtime or native module change: the guard is the companion's `_nativeloader_guard.lua`.

## Alternatives considered

- **Keep DLib from taking over** (set `DLib.ghook` before it loads): its hook library would then not be the game's,
  and the add-ons that use DLib's own hook features (priorities, post modifiers, `hook.Once`, tasks) would break.
- **Put the guard's own dispatcher in DLib's place** (`DLib.hook.Call`, iterating `hook.GetTable()`): it would ignore
  DLib's priorities, call the hooks DLib disabled (they stay in that table), and drop DLib's coroutine hooks (a
  thread id is no valid object to the dispatcher). Rejected.
- **Contain the gamemode's methods too**, by handing DLib's `Call2` a table whose method is protected: every other
  wrapper of `Call2` would then see that table instead of the gamemode. Left out; the methods run as in a vanilla game.
- **Keep only MineMod's line off the screen** (another match for its draw): the effects' skip, the depth pass's refusal
  and the protected calls would stay lost in every game with DLib.
- **Install the guard after DLib:** the guard has to be in place before any autorun (ADR 0054), and DLib's takeover
  removes whatever stood in the hook table before it, which is the case here.
