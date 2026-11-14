# 0214: After "Ready to play!" the load overlay stays until the game runs, and says what the main thread is doing

- Status: Accepted 2026-11-14 on the branch `qol-load` (the user's QoL request; not merged; the in-game checks are the
  user's, see the [report](../handover/load-eta-report.md)).
- Context: the user: "There is still a long time, when loading into a map, between 'Ready to play' until the map is
  actually loaded, add verbosity in this part to let the user know what the game is doing." R24's overlay
  ([ADR 0134](0134-what-a-map-load-is-doing.md)) follows the menu's loading panel and hides when the panel goes.
- Amends: ADR 0134 (when the overlay ends, what it shows). Builds on [ADR 0140](0140-the-load-accelerator.md) (the status
  line's lookup count). The estimate shown with it is [ADR 0215](0215-the-loads-estimate-learned-from-the-loads-before.md).

## What happens after "Ready to play!"

- "Ready to play!" is the last of the engine's progress strings (`engine.dll`, after "Fully connected!"; RESEARCH).
  The menu's `IsInLoading()` is only whether the loading panel still has its HTML (`lua/menu/loading.lua:225`), which
  `OnDeactivate` removes (`:73`, with `system.FlashWindow()`, "the game is ready"). So R24's overlay hid there.
- The main thread is not done then. The client's `InitPostEntity` hooks, add-ons' timers (Extended Spawnmenu's scan,
  a spawn menu rebuild), Remix's first path-traced frames (the scene's acceleration structures, textures) and sometimes
  the Workshop's own work follow. R26 measured 5.2-12.3 s from `InitPostEntity` until no frame took over 100 ms for 2 s
  (RESEARCH, R26). While the main thread is blocked nothing repaints: the screen keeps its last picture, often the
  loading screen at "Ready to play!".

## Decision

1. **A second phase: settling.** When the menu's `Think` sees `IsInLoading()` go false and `IsInGame()` is true (within
   a second: a load that ends without a game was cancelled or refused), the companion's
   [`loading_status.lua`](../../companion/nativeloader/lua/nativeloader/menu/loading_status.lua.md) calls the new
   `LoadSettling()` and the overlay stays, its status "The map has loaded; the game is starting". It ends when the
   menu's `Think` has run for two seconds without a freeze. A freeze is a gap between two `Think` calls longer than three
   times the median of the last sixteen gaps, at least a quarter and at most a whole second, so a slow but steady game
   counts as running. The wait ends after 120 s whatever happens, and the module hides the window by itself 180 s after
   `LoadSettling()` even if the script never ends it. The game ending, or the next load beginning, ends it untimed.
   The menu realm's hooks run on the main thread every frame, in a game too: GMod's own menu draws its Lua error
   notices in game from `DrawOverlay` (`lua/menu/errors.lua:94`), and the load accelerator's menu script already ends
   its start-up marker from `Think` after a load. So the gaps between `Think` calls are the main thread's freezes.
2. **What the main thread does, in plain words** ([`load_activity.h`](../../engine_guard/load_activity.h)). The overlay
   already samples the main thread every 250 ms (ADR 0134). Each sample is now also classed by the module its
   instruction pointer is in. For a thread waiting in Windows, a C runtime or tier0, the nearest known module's code in
   the first 4 KiB of the copied stack decides.
   - **RTX Remix**: the runtime's `d3d9.dll` (by its `remixapi_InitializeLibrary` export), its libraries and the
     Vulkan loader and drivers. The line says "RTX Remix is preparing the scene".
   - **Add-on scripts**: `lua_shared.dll`, LuaJIT's compiled code (executable memory of no module, `VirtualQuery`),
     the game's code called from Lua, or a Lua file being run. "Running add-on scripts", or "Building the spawn menu"
     when that file is the spawn menu's.
   - **Game files**: `filesystem_stdio.dll`, `resources.dll` (PNG decoding) and the load accelerator's hooks.
     "Loading game files".
   The module ranges come from each module's own PE headers, read on the main thread at the load's start. The window
   thread never takes the loader lock and reads nothing while the main thread is suspended. The line names the class
   seen at least twice in the last eight samples (two seconds), the most frequent one; a tie goes to the newer. It
   shows in both phases, under the status line.
3. **The Workshop's own work**: fetching the subscriptions, downloading, extracting. GMod's menu hooks
   (`WorkshopSubscriptionsProgress`, `WorkshopDownloadTotals`, `WorkshopExtractProgress`, `WorkshopStart`/`End`;
   `lua/menu/mount/mount.lua`) put it on the status line while the overlay is up. The overlay does not wait for it,
   since the game plays meanwhile. A word older than ten seconds is dropped.
4. **The console line** at the end, in English: `[nativeloader] map loaded in 24.1 s, then 7.1 s until the game ran
   steadily (31.2 s in all; expected about 30 s); the main thread: Lua 12.0 s, game files 4.0 s, RTX Remix 3.2 s; Lua
   files that ran longest: ...`. A cancelled load, a game that ended and a load that followed say so instead.
5. **Safety as before.** The same window, which never takes focus or clicks. The same sampling rules: suspended only for
   `GetThreadContext` and one copy into a buffer allocated beforehand. The new functions exist only in the menu realm,
   in the `gmsv_` copy recognized through `lua_shared`'s menu state. The client and server realms, where any server's
   Lua runs, still cannot put anything in the window. `nativeloader_load_overlay 0` turns all of it off.

## Consequences

- The overlay stays about two seconds into a running game (the confirmation), at the bottom left, transparent to
  clicks.
- Freezes more than two seconds apart after the overlay has gone are not covered; they are the game's frame-rate
  hitches, not the load.
- The activity line is a heuristic. A stale code address on the stack can mislabel one sample, so a class needs two
  of the last eight samples.
- The window is two lines taller (six rows and a half; a line is a 36th of the game's height).

## Alternatives considered

- **A signal from the client realm** (its `InitPostEntity`, or the spawn menu built): the client realm runs any
  server's Lua (ADR 0134); the menu cannot see the client's convars (RESEARCH, R24); and it would not see Remix's
  first frames.
- **Hooking the engine's frame or `Present`** to count frames: a detour for a status line, where the menu's own
  `Think` already counts them.
- **A `WM_NULL` sent to the game's window to test that it answers**: a cross-thread send into the game's window
  procedure four times a second for a status line.
- **Exact stack unwinding** (`RtlVirtualUnwind` over the copy): the frames would have to be rebased into the copy, and
  LuaJIT's compiled code has no unwind data. The nearest known caller is enough for words.
- **Reading LuaJIT's state for the running function**: exact, but bound to LuaJIT's internal layout in a module that
  must keep working across GMod updates.
