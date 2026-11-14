# 0210: An add-on's notice of the guard's refusal stays off the screen

- Status: Accepted 2026-11-13 for GitHub issue 5; merged on the user's approval the same day, without an in-game
  check (the user's choice).
- Decided by: Claude, from the session's brief (the user replied on the issue "Working on a fix, ready today").
- Context: [GitHub issue 5](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/5), "Default texture pack is
  not ready: resource_sampling_unsupported" (opened 2026-11-13): the line stays in the middle of the screen on every
  map, also after the player disabled their only HUD add-on, "everything seems to be functioning fine", and "if theres
  any way to just prevent the message of showing up it would be good enough". The session's brief: no loader change;
  the notice should not appear when RTX works, with a quieter path if the condition can still mean a real problem.
- Amends: [ADR 0086](0086-inert-shader-effects-and-safe-guard-fallbacks.md) decision 2, whose list of skipped
  known callbacks gains a second kind. Nothing of its shader policy changes.

## What happened

The line is not the package's. It is MineMod's ("MineMod Engine", [schweiziske/MineMod](https://github.com/schweiziske/MineMod),
MIT; Minecraft's block worlds in Garry's Mod), which the player has installed. MineMod builds its default texture pack
from PNG at start, and that bake first measures how the engine samples mip levels: `lua/mc/resources/cl_sampling.lua`
creates six `screenspace_general_8tex` materials with its own `$vertexshader` and `$pixshader`, draws each into a
16x16 render target cleared to black, reads the centre pixel back (`render.CapturePixels`, `render.ReadPixel`) and
expects 16, 56, 96, 136 and 176 from the mip levels it uploaded. Under RTX the render guard refuses binding a custom
shader (ADR 0086) and binds its transparent material instead, which leaves the target as it was cleared: every sample
is the clear colour, `[0,0,0]` (the player's screenshots), and the bake fails with
`resource_sampling_unsupported:[[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0]]`.
MineMod's `HUDPaint` hook in `lua/mc/cl_resource_packs.lua` then draws "Default texture pack is not ready: <error>" at
the centre of the screen for as long as the default pack is pending, which is the rest of the game, whatever the map.
It tries the bake again once per catalog revision, not every frame.

The refusal is right and stays: MineMod's blocks and its passes also draw with its own shaders (`screenspace_general_8tex`
with a shader pack's programs), which the guard keeps inert under RTX for the reasons ADR 0086 gives, and MineMod draws
no world while that pack is pending anyway. MineMod does not work in RTX sessions, with or without its texture pack.
What was wrong is only the line: a full-time notice over the path-traced image whose sole cause is the guard's own
refusal, on maps that have nothing to do with MineMod.

## Decision

1. **The guard keeps an add-on's own on-screen failure off the screen when its only cause is the guard's refusal,**
   for known add-ons only, each matched by the exact virtual path of the callback that draws the notice, its event,
   and the add-on's own failure code read from its state. Such a callback is skipped through the guard's dispatcher
   and through the registration filter (`policy.filter`), so a cached original `hook.Call` and the verified
   multiplayer route skip it too, as for the known effect callbacks of ADR 0086.
2. **One entry: MineMod's texture pack line.** `HUDPaint` from `lua/mc/cl_resource_packs.lua`, skipped while
   `MC.TexturePackPending` is set and MineMod's last apply job (`MC.ResourcePacks.jobs[MC.ResourcePacks.lastId]`) has
   the state `failed` and an error that starts with `resource_sampling_unsupported`. With the guard on, the probe's
   draws are always refused, so that failure in an RTX session is always the guard's.
3. **The quieter path is the console.** The first time, one `adapted` record and one console line: `[nativeloader] RTX
   guard: hook.HUDPaint: MineMod's default texture pack cannot be baked while its shaders are inert under RTX: its
   "Default texture pack is not ready: resource_sampling_unsupported" line is kept off the screen
   (lua/mc/cl_resource_packs.lua)`. MineMod's own console fault (`[MC fault] resource_default_bake: ...`) and the
   guard's refusal of the probe (`render.SetMaterial: unsupported RTX shader draw (lua/mc/resources/cl_sampling.lua:...)`)
   stay as they were. No notice window: the condition is no fault of the player's RTX session, the player who reported
   it asked for no message, and ADR 0086 makes the guard's records the place where inert add-ons are reported.
4. **Everything else stays MineMod's.** Its baking line while a bake runs, any other failure code (a probe that raised
   an error, a missing file, a restore error), its other hooks and its own windows (its texture pack manager still
   shows "Could not apply: ..." when the player asks it for a pack), other add-ons' hooks, sessions without RTX (no
   guard) and `nativeloader_guard 0`. The add-on's state is read in `pcall`: state the guard cannot read shows the line.

## Consequences

- A player with MineMod installed sees no line in RTX sessions. MineMod itself still does not work under RTX; to play
  it, start the game without RTX (MineMod works there as before) or switch the guard off (`nativeloader_guard 0`, at
  the risk ADR 0086 describes).
- A MineMod release that renames the file, the hook's event, its state or the failure code brings the line back in
  RTX sessions; nothing worse. The entry is a compatibility match, not a trust boundary (ADR 0086's caveat on source
  labels applies).
- The guard's dispatcher reads and normalizes a callback's source once per call for the effect and notice checks; the
  per-frame cost is one table lookup more than before.
- No loader, runtime or native module change: the guard is the companion's `_nativeloader_guard.lua`, which the loader's
  early stage and the companion's autorun take from the package as before (its marker is unchanged).

## Alternatives considered

- **Let MineMod's probe through** (custom shaders into small Lua render targets): its bake would pass, but its blocks
  would still be inert, so MineMod would gain nothing, and drawing arbitrary custom shaders through the runtime is the
  native/GPU risk ADR 0086 declines.
- **Answer the probe with the values it expects:** MineMod would then try to draw a world it cannot draw, and the guard
  would be faking an engine result.
- **Remove MineMod's hook, or change its state:** loses its baking line and its other failures, and changes MineMod's
  behaviour beyond the one line.
- **A one-time notice ("don't show again"):** considered; the player asked for no message, MineMod's failure is not
  something the RTX session can fix, and a notice at every start for a player who never plays MineMod there is the
  same nuisance in a smaller box. The console line keeps it findable.
