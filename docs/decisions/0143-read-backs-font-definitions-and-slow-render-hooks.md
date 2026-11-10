# 0143: Periodic screen read-backs stop under RTX; repeated font definitions are made once; slow hooks are named

- Status: Accepted 2026-11-10 (R28)
- Context: the user, 2026-11-10: "make the package more robust by preventing addons like HyperReal FX from lagging the
  game, and find and safeguard potential game-lagging methods." The issue 2 diagnosis
  ([handover/issue-2-memory-report.md](../handover/issue-2-memory-report.md)) had measured HyperReal FX (Workshop
  3830761570) at 67 ms of every frame under RTX (49.4 ms in `PreDrawViewModels`, 17.9 ms in
  `RenderScreenspaceEffects`; 0.46 and 0.31 ms without RTX), with the game at 7 frames a second.
- Adds to: [ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md) (the render guard's policy).

## What a frame's calls cost under RTX (the R28 probe)

A test copy of the game with the published package, gm_construct, 1920x1080, about 82 frames a second (12.2 ms a
frame), each call made from a render hook once a frame (`out/r28/cost_probe.lua`):

| Call | Cost |
|---|---|
| `render.UpdateScreenEffectTexture()`, once / four times | 0.008 / 0.012 ms |
| `render.UpdateRefractTexture()`, `render.CopyRenderTargetToTexture(full screen)` | 0.009, 0.011 ms |
| A full-screen target pushed, cleared and popped | 0.021 ms |
| Eight passes into a full-screen target, plain material / a refused shader material | 0.079 / 0.180 ms |
| **`render.CapturePixels()`** (a 1x1 target or the back buffer), every 15th frame | **20 to 29 ms each** |
| `render.CapturePixels()` every frame | 12.4 ms each; the frame goes from 12.2 to 24.5 ms |
| `render.ReadPixel` alone | 0.002 ms |
| `render.RenderView` into a 256x256 target | 2.6 ms, the frame +6.5 ms |
| `render.Capture` (JPEG of the screen), once | 76 ms |
| **`surface.CreateFont` with the same name and definition, 20 times a frame** | 0.4 ms in the calls; **the frame goes from 12.2 to 29.4 ms** |

So the copies and passes of a post-processing add-on cost nearly nothing once the guard has refused its shaders;
what stalls the game is the read-back. `render.CapturePixels` waits until the GPU has drawn everything queued, which
under the path tracer is one to two whole frames: 20-29 ms at 82 frames a second, and about 200 ms at the 7 of the
issue's session (the hooks' worst calls there: 207 and 196 ms). HyperReal FX reads a 1x1 target back twice a second
for its fog colour and exposure: two stalls of a frame and a half every second is the 67 ms a frame.

## Decision

All in the companion's render guard (`_nativeloader_guard.lua`), active in RTX starts with `nativeloader_guard 1`.

1. **A periodic reader's read-backs stop.** Each reader of `render.CapturePixels` (the calling Lua file together
   with the file that called it, so two add-ons that read through one shared library are two readers; through
   `pcall` or another native function, the first Lua caller outside the guard) has an allowance: eight read-backs
   at once, refilled at 1.25 a second. A reader that uses it up is refused: two read-backs a second do after
   nineteen, a pair every half second (HyperReal FX) after eleven, one every frame after eight. Every request
   counts, made or refused, so a reader that keeps coming stays refused; it is let in again when its requests have
   fallen back under half the allowance (a reader of one sample a second that overran once, after about twenty
   seconds), or when it has asked nothing for five seconds. `render.ReadPixel` after a refused read-back answers,
   without a native read, from the last picture really read by the same call, which is the calling line and the
   render target read: two targets read through one helper function keep a picture each, and a picture is kept
   until the next read-back's first pixel is read. A pixel that picture does not hold gets the picture's last
   pixel; while it holds none, the engine's own last picture is read and remembered. Coordinates are truncated as
   the engine truncates them, and a call that was never made yet is made, allowance or not. One console note per
   call site. Never limited: a caller
   that asks about once a second, a single batch of up to eight, a file that reads more than 1,024 pixels of one
   picture (it scans an image, an icon or a map, which cannot be answered from memory), `render.Capture` (a
   screenshot is something the player asked for), the package's own tools (the bundled paths of ADR 0086), and
   everything when `nativeloader_guard_readbacks` is 1 (a saved client setting, default 0). At most 256 readers are
   followed (further ones are not limited), eight pictures a reader (further calls share one) and 1,024 pixels a
   picture; a refused picture stops answering five seconds after its last read-back. Only the pixels the reading
   file itself reads make it a scanner.
2. **The same font definition is made once.** `surface.CreateFont(name, data)` with the definition that name
   (without case, as the engine knows it) already has returns without calling the engine, for ten seconds after it
   was last made; then it is made again, in case the engine's font was changed by a route the wrapper does not see.
   Any change (a value, a key more or fewer) is made as before; a call with other arguments, or with a table that
   has a metatable, goes to the engine as it is. The engine otherwise builds every font's glyph pages again on each
   call. At most 4,096 names are remembered.
3. **Slow render callbacks are named, not stopped.** The guard times every callback of the events it protects
   (two clock reads a call) and `PreDrawViewModels` joins those events. A callback that takes 4 ms or more of every
   frame over a window of at least five seconds and thirty frames gets one console line with its hook's name, its
   cost and its file, and a record in `NativeLoaderRenderGuard.slow` (at most 32). A hook added under a name is
   counted by its event and name, so a function put in its place continues the count; a hook of an object and a
   gamemode's function by the function.
4. **`nativeloader_lag_report [seconds]`** (the companion, `lua/autorun/nativeloader_lag_report.lua`) times every
   hook, every function of the gamemode and every net receiver of the client, and in a local game of the server, for
   2 to 120 s (10 by default), puts everything back and prints the fifteen most expensive hooks and five net
   receivers per realm: milliseconds per frame or tick, the worst call, the hook's event and name, its file and
   line and the add-on that file belongs to (a folder under `addons/`; else the mounted Workshop item that has the
   file, also under a folder the game has too; else the game for its own folders), then what the guard refused or
   found slow this session. The same text goes to `garrysmod/data/nativeloader/lag_report_<realm>.txt`, for an
   issue report. A timer is put in a hook's place in the hook table itself (at the hook's own priority in ULib's
   hook library), not with `hook.Add`; with a hook library it does not know the hooks are left alone and counted.
   Under ULib the timer also goes into the plain table ULib keeps beside its own, because the guard runs its
   events from that one. Each timer is entered in `NativeLoaderRenderGuard.timed`: the guard then names the
   function it times in its records, keeps leaving out a callback it leaves out, and keeps a hook it stopped after
   repeated errors stopped. That table can only add to what is left out, so it is no way round the guard (an
   add-on could use it to switch another add-on's callback off, as it could by removing the hook).

## Consequences

- An add-on built like HyperReal FX costs its Lua and nothing more under RTX: eleven stalls in its first
  three seconds, then none (the test copy, R28 report). Its picture was already missing (ADR 0086 refuses
  screen-space shaders); now its cost is too.
- An add-on that samples the screen continuously for something it draws itself (a crosshair that takes the colour
  under it) gets a frozen sample under RTX instead of halving the frame rate; `nativeloader_guard_readbacks 1` gives
  the reads back with their cost. A reader of about one sample a second or less is untouched.
- A read-back made by a tail call (`return render.CapturePixels()`) is counted for the caller of the function that
  made it: Lua keeps no frame for it. Add-ons that do this share an allowance per calling file.
- A font made in a paint hook no longer rebuilds the game's glyph pages every frame.
- Players and the project can see which hooks cost a frame's time without a debugger: one command, a text to paste.
- Not handled: `render.RenderView` from add-ons (a mirror or a map view costs half a frame on gm_construct), per-tick
  walks over every entity on the server (the issue's NPC and status add-ons), heavy `Think` code. The lag report names
  them; nothing limits them.

## Alternatives considered

- **Skip the screen copies and target passes of an add-on whose shaders are refused.** Measured: they cost
  hundredths of a millisecond. Not worth a rule.
- **Stop a slow callback whose draws the guard refuses.** A callback can hold a refused blur and the player's HUD;
  the guard sees binds, not text and rectangles (those calls are not wrapped: thousands a frame, ADR 0141). Naming
  it leaves the choice with the player.
- **Limit every reader to one read-back in N seconds.** A periodic reader would still stall the game every N
  seconds, and a tool the player clicks a few times would be refused. The allowance lets a batch and a slow
  reader through and stops only what keeps coming.
- **"Asked again within a second, four times running".** This round's first rule. The review showed what it
  misjudged: a reader of one sample a second whose timing wavers was refused for good after a while, four reads at
  once every 1.1 seconds passed for ever, and a single batch of six was cut. An allowance that refills judges the
  rate, not the gaps.
- **One remembered picture per file.** Also the first build: two targets read through one helper answered each
  other's values once refused. A picture per calling line and target does not.
- **Answer a refused read with zeros.** Code that divides by a brightness would get infinities; the last real
  values are what the add-on last saw.
- **Throttle `render.RenderView`.** Most callers clear their target before the view; a skipped view leaves the
  cleared target on screen until the next one: flicker instead of a slow mirror.
- **Time every hook all the time.** Events such as `Think` and `HUDShouldDraw` call thousands of hooks a frame with
  hundreds of add-ons; replacing the game's dispatch for all of them to time each is itself a cost and a risk. The
  guard times only the render events it already dispatches; the lag report times everything, for seconds, on request.
