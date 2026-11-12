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
- **No Windows Error Reporting snapshot of the game (R28, [ADR 0142](../docs/decisions/0142-no-crash-snapshot-of-the-game.md)).**
  Every realm's load (the menu's at menu start, so before any map) sets `WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH`
  and `_HANG` for the process with kernel32's `WerSetFlags` (resolved at run time; the process's other flags are
  kept). Without them Windows copies a crashed game before it reports it and charges the copy the game's whole
  private memory again: 20 GB and more with hundreds of add-ons under RTX, which on a 24 GB computer is the freeze,
  the memory gauge at 97-99 % and the gmod.exe that stays after End task (GitHub issue 2). With them the same report
  and dump are made from the suspended process (measured: +0.06 GB of commit instead of +23 GB, the game gone in
  5.8 s instead of 11.8 s). `nlengineguard.crash_snapshots_off` and `.crash_snapshots` ("ok", or the reason) say how
  it went.
- **Material colours above 1 capped for Remix ([ADR 0190](../docs/decisions/0190-material-colours-above-1-capped-for-remix.md)).**
  Under RTX a material's tint (`$color2` on a model, `$color` elsewhere, a render colour) reaches the GPU as
  `D3DRS_TEXTUREFACTOR`, one byte per component, made by `shaderapidx9.dll`'s `Color3f`, `Color3fv`, `Color4f` and
  `Color4fv` with `cvttss2si` of value x 255 and its low byte: 1.5 becomes 126, 1.3 becomes 75, and the runtime
  multiplies the albedo by that (gm_construct's tree cards, `$color2 [1.3 1.4 1.5]`, came out dark blue-grey). Every
  realm's load (the menu's first) wraps the four vtable slots, so each component is clamped to [0, 1] before the
  engine converts it; within [0, 1] it reaches the engine unchanged. Found by their code, only where sure: one run of
  four consecutive slots in `shaderapidx9.dll`'s read-only data, each its own function that loads 255.0 rip-relative,
  converts with `cvttss2si` and calls `SetRenderState(D3DRS_TEXTUREFACTOR)` (`mov edx,3Ch` ... `call [rax+1C8h]`),
  the 3-component ones setting alpha to `FFh`, the vector ones reading through `rdx`, `Color4f` taking alpha from the
  stack (`shaderapidx9.dll` rva `0x7b568` in build 26229091; no direct call bypasses the vtable). Only when the
  process's `d3d9.dll` exports `remixapi_InitializeLibrary`: a flat start never changes. The second copy finds the
  first's export `nl_engine_guard_colour_cap_v1` and shares its switch and count. `nlengineguard.colour_cap` says how
  it went; `nlengineguard.ColourCap([enabled]) -> enabled, capped` switches it for a comparison in one session and
  counts the colour calls it changed. The game's console says once: "Material colours above 1 are capped at 1 for
  Remix".

| File | Purpose |
|---|---|
| `CMakeLists.txt` | `nl_engine_guard` (static, with the load overlay; links user32 and gdi32), the client and server modules (the server's with `NL_ENGINE_GUARD_MENU`), `nl_engine_guard_tests` (given `module.cpp`'s path for its contract test), and the end-to-end `nl_engine_guard_detour_tests` with its stand-in `materialsystem.dll`; the colour cap's end-to-end `nl_engine_guard_colour_tests` with its stand-in `shaderapidx9.dll` (linked without incremental thunks) and Remix `d3d9.dll`, both in `colour_fakes/` (a `d3d9.dll` beside other programs would be loaded by them) |
| `guard.h`, `guard.cpp` | The patterns (call site, GetName call), name comparison, the cycle rules, the filter, the stub and the detour's installation (SEH-guarded scan, pins the module, idempotent across the two copies) |
| `colour_cap.h`, `colour_cap.cpp` | Material colours above 1 capped for Remix (ADR 0190): the engine's conversion (`engine_byte`) and the cap, the shape of the four functions (`classify`), their vtable slots (`find_slots`), the wrappers, the slots switched (pinned, one aligned store each, Remix starts only), the export the other copy reads and the switch |
| `crash_report.h`, `crash_report.cpp` | Windows Error Reporting's crash and hang snapshots switched off for the process (R28): the flags, `WerGetFlags`/`WerSetFlags` from kernel32 at run time, once per process and copy |
| `watchdog.h`, `watchdog.cpp` | The start-up watchdog: sampling the committed stack, Lua chunk names on it, the deadline, the report and the message |
| `load_overlay.h`, `load_overlay.cpp` | The load overlay (R24): the window thread, its sampling of the main thread, the game file paths and Lua chunk names it shows, the elapsed time and the tally behind the summary |
| `module.cpp` | `gmod13_open`: installs the guard, switches the crash snapshots off (`crash_snapshots_off`, `crash_snapshots`) and caps material colours for Remix (`colour_cap`, `ColourCap([enabled])`, every realm); in the client and server realms starts the watchdog for its realm (`NL_ENGINE_GUARD_REALM`, set per target) and publishes `nlengineguard` (`installed`, `reason`, `Status()`, `StartupDone([seconds])` -> recovered, `SetMessage(title, body)`); in the menu realm publishes `installed`, `reason`, `Status()` and the overlay's `LoadStart`, `LoadHeading`, `LoadStatus`, `LoadEnd` |
| `tests/fake_materialsystem.asm`, `tests/fake_materialsystem.cpp` | A stand-in `materialsystem.dll` for the end-to-end test: one function whose machine code (exact bytes in the code segment) holds the call site (key values in r13, the material in r14), the loop's GetName call and a stand-in `KeyValues::GetString`; the C++ file exports its address |
| `tests/fake_shaderapi.asm`, `tests/fake_shaderapi.cpp` | A stand-in `shaderapidx9.dll` for the colour cap's end-to-end test: its `Color3f`, `Color3fv`, `Color4f`, `Color4fv` in assembly with the game's shape (255.0 rip-relative, `cvttss2si`, the low byte, `SetRenderState(3Ch)` through the device's vtable), an API object whose read-only vtable names them among other slots, and a device that records the texture factor |
| `tests/fake_remix_d3d9.cpp` | A stand-in `d3d9.dll` exporting `remixapi_InitializeLibrary`, what marks a Remix start |
| `tests/test_colour_cap.cpp` | The colour cap: the engine's wrap and the cap (1.3, 1.5, NaN, negative), the four slots found once in an installed game's `shaderapidx9.dll` (`NL_SHADERAPI_DLL`, else the PoC's; skipped without a game), nothing changed outside a Remix start, `module.cpp`'s contract |
| `tests/test_colour_cap_e2e.cpp` | End to end, in its own process: through the stand-in's vtable, a wrapped texture factor before, nothing changed without the Remix `d3d9.dll`, capped after (within [0, 1] the same bytes, the caller's colour never written, only out-of-range calls counted), the switch, idempotence, and functions of another shape refused |
| `tests/test_detour.cpp` | End to end, in its own process: `install()` finds and detours the stand-in's call site, which then gets `""` for a fallback to the material itself and the fallback for another |
| `tests/test_overlay.cpp` | The load overlay: game file paths and Lua chunk names as shown, the elapsed time, UTF-8 clipping, the bounded tally, `start()`/`finish()` in a process without a game window, and `module.cpp`'s contract (the menu realm from `lua_shared`, the overlay functions only with `NL_ENGINE_GUARD_MENU`) |
| `tests/test_crash_report.cpp` | The crash report switch (R28): the flag values, this test process as the game (the flags read back with `WerGetFlags`, a second call answers the same), and `module.cpp`'s contract (called before the realms part, the two fields published) |
| `tests/test_guard.cpp` | The patterns (on the real bytes, and on an installed `materialsystem.dll` when there is one, with its GetName calls), names, the cycle rules, the filter with fake materials, the stub, the watchdog's stack scan and report |
