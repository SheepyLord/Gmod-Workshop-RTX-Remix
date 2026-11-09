# engine_guard

Two binary modules from one source, `gmcl_nlengineguard_win64.dll` and `gmsv_nlengineguard_win64.dll`
(R23, [ADR 0130](../docs/decisions/0130-an-engine-guard-for-lua-start-up.md)), shipped in the `fixes`
part and loaded by the companion's `!!!!nativeloader_engine_guard.lua` before the add-ons' autoruns (and in
the client realm by the early view of `includes/init.lua`, which also covers remote servers).

- **The material fallback guard.** Under RTX the game takes materials' `"<dx90"` blocks; a
  `$fallbackmaterial` there that names the material itself (ARC9 Gunsmith Reloaded's
  `particle/warp5_explosion`) or leads round a cycle made `CMaterial::InitializeShader` in
  `materialsystem.dll` reload it forever, and the game stopped at "Starting Lua". The module detours
  the one call in that loop that reads `$fallbackmaterial` through a stub allocated within a call's
  reach: `mov r9, r14` (the material), then the hook. The hook answers `""` for a fallback that is the
  material itself, or for the seventeenth fallback followed for one material while they come less than
  2 s apart; an empty fallback read for the material ends its chain, so separate initializations never add
  up. Only the key `$fallbackmaterial` is filtered.
- **Only where it is sure.** The call site is a unique 36-byte pattern whose `lea` must point at the string
  `$fallbackmaterial`; the loop must also call r14's `GetName` (`mov rax,[r14]; mov rcx,r14; call [rax]`)
  within 0x100 bytes after the call, so r14 is the material; the call's displacement must be 4-byte aligned
  (it is rewritten with one interlocked store). The image is scanned under SEH. A build that fails any check
  gets no guard and says why (`nlengineguard.reason`).
- **The start-up watchdog.** From the module's load to the companion's `StartupDone()` at the realm's
  `Initialize` (or its first tick; at the latest 150 s after the gamemode loaded, or 15 minutes), it samples
  the main thread every 3 s: suspended only for `GetThreadContext` and one copy of its committed stack (from
  `StackLimit` up, never the guard page) into a buffer allocated beforehand and freed when the watch ends.
  When the nearest Lua chunk name on that stack has not changed for 90 s, it writes
  `garrysmod/data/native-loader/startup-stall.json` and shows one message per process, translated by the
  companion (only its first `SetMessage` call counts), naming the file; the companion names the add-on in a
  notice at the next start, or removes the report when the start went on after all.
- **Two copies, one process.** In a local game the server and the client module are both loaded: the
  first installs the detour, the second finds its stub and reads the counts from it
  (`nl_engine_guard_cut_v1`, exported); a named mutex keeps the message to one.
- **The menu realm and the load overlay (R24, [ADR 0134](../docs/decisions/0134-what-a-map-load-is-doing.md)).**
  The companion's menu script `nativeloader/menu/loading_status.lua` requires the `gmsv_` copy in the menu realm at
  menu start, so the guard is in place before any map loads. There no watchdog runs; instead `LoadStart(heading,
  {lua=, file=})`, `LoadHeading(text)`, `LoadStatus(text)` and `LoadEnd()` drive a small window of the module's own,
  owned by the game's window and drawn by the module's thread: the time so far, the stock status, the Lua file
  running and the game file being read, sampled from the main thread's stack every 250 ms (suspended only for one
  copy into a 256 KiB buffer allocated beforehand, as the watchdog does). It shows after 1.5 s of a load, never takes
  focus or clicks, and hides at the end; `LoadEnd()` returns the load's length and the three Lua files seen running
  longest. The client and server realms, where any server's Lua runs, have none of these functions: the menu realm is
  the engine's own menu Lua state (`lua_shared`'s `GetLuaInterface(MENU)`), not the `MENU_DLL` global any Lua can
  set, and only the `gmsv_` copy is built with them (`NL_ENGINE_GUARD_MENU`). The window thread keeps its paint buffer
  while the window keeps its size, never cuts a UTF-8 character, and lets an unowned window go (the game's window
  went) to own the next one.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | `nl_engine_guard` (static, with the load overlay; links user32 and gdi32), the client and server modules (the server's with `NL_ENGINE_GUARD_MENU`), `nl_engine_guard_tests` (given `module.cpp`'s path for its contract test), and the end-to-end `nl_engine_guard_detour_tests` with its stand-in `materialsystem.dll` |
| `guard.h`, `guard.cpp` | The patterns (call site, GetName call), name comparison, the cycle rules, the filter, the stub and the detour's installation (SEH-guarded scan, pins the module, idempotent across the two copies) |
| `watchdog.h`, `watchdog.cpp` | The start-up watchdog: sampling the committed stack, Lua chunk names on it, the deadline, the report and the message |
| `load_overlay.h`, `load_overlay.cpp` | The load overlay (R24): the window thread, its sampling of the main thread, the game file paths and Lua chunk names it shows, the elapsed time and the tally behind the summary |
| `module.cpp` | `gmod13_open`: installs the guard; in the client and server realms starts the watchdog for its realm (`NL_ENGINE_GUARD_REALM`, set per target) and publishes `nlengineguard` (`installed`, `reason`, `Status()`, `StartupDone([seconds])` -> recovered, `SetMessage(title, body)`); in the menu realm publishes `installed`, `reason`, `Status()` and the overlay's `LoadStart`, `LoadHeading`, `LoadStatus`, `LoadEnd` |
| `tests/fake_materialsystem.asm`, `tests/fake_materialsystem.cpp` | A stand-in `materialsystem.dll` for the end-to-end test: one function whose machine code (exact bytes in the code segment) holds the call site (key values in r13, the material in r14), the loop's GetName call and a stand-in `KeyValues::GetString`; the C++ file exports its address |
| `tests/test_detour.cpp` | End to end, in its own process: `install()` finds and detours the stand-in's call site, which then gets `""` for a fallback to the material itself and the fallback for another |
| `tests/test_overlay.cpp` | The load overlay: game file paths and Lua chunk names as shown, the elapsed time, UTF-8 clipping, the bounded tally, `start()`/`finish()` in a process without a game window, and `module.cpp`'s contract (the menu realm from `lua_shared`, the overlay functions only with `NL_ENGINE_GUARD_MENU`) |
| `tests/test_guard.cpp` | The patterns (on the real bytes, and on an installed `materialsystem.dll` when there is one, with its GetName calls), names, the cycle rules, the filter with fake materials, the stub, the watchdog's stack scan and report |
