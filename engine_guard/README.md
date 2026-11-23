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
- **After "Ready to play!" and the estimate ([ADR 0214](../docs/decisions/0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md),
  [ADR 0215](../docs/decisions/0215-the-loads-estimate-learned-from-the-loads-before.md)).** `LoadSettling()` keeps the
  overlay up after the engine's load until the menu script sees the game run steadily (at most 180 s after it: the
  window then hides by itself). Each 250 ms sample is also classed by the module its instruction pointer is in, or for
  a thread waiting in Windows by the nearest known caller in the first 4 KiB of the copied stack: RTX Remix (the
  runtime's `d3d9.dll` by its export, its libraries, the Vulkan loader and drivers), add-on scripts (`lua_shared`,
  LuaJIT's compiled code, game code called from Lua, a Lua file being run; the spawn menu's by its file name) or game
  files (`filesystem_stdio`, `resources.dll`, the load accelerator's hooks). The modules' code ranges come from their PE
  headers, read on the main thread at the load's start. The activity line names the class seen at least twice in the
  last two seconds, and `LoadEnd()` gives the seconds of each. `LoadExpect(seconds, confidence)` gives the window the
  whole wait's expected end: its own thread counts down to it ("about 25 s left", minutes from 90 s, "(rough
  estimate)", "Taking longer than usual", or the line without an estimate) and moves a bar that never goes back (amber
  past the end). The words are the menu script's translations; a translation's one `%s` is filled here, never used as
  a format. `LoadTimes()` and `LoadTimesSave(text)` read and replace `garrysmod/data/nativeloader/load_times.txt`
  (at most 64 KiB, through a temporary file) for the menu script, which learns the estimate from it: the menu realm
  cannot write files. All of these exist only in the menu realm, like the rest of the overlay.
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

- **GMod's `poster` command under RTX ([ADR 0226](../docs/decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md),
  GitHub issue 3).** `client.dll`'s ConCommand `poster` only sets a multiplier; the view renderer then draws the
  poster's tiles through sheared projections and reads back the raster image, and RTX Remix's camera manager rejects
  a sheared projection, so under RTX none of it was path traced. The client realm's load (the `gmcl_` copy) in a start
  whose `d3d9.dll` exports the runtime's poster API (`rtxposter_*` of version 1, [`rtxposter_api.h`](rtxposter_api.h),
  byte-identical to the runtime's `rtx_poster_api.h`) takes the command over for the process: it pins the module,
  finds the command in `client.dll` (its help text once in read-only data, then the one object in writable data
  holding it at 32, named `poster`, its callback at 48 inside `client.dll`'s code and of the kind that takes the
  arguments, bit 1 of the byte at 64; Source SDK 2013's x64 layout, read from `ConCommand::ConCommand` in the game's
  `client.dll`) and swaps the callback with one interlocked exchange. The new callback reads the arguments as the
  engine's does (`(int)atof(argv[1])`, the tiles when `argv[2]` starts with `1`; a `CCommand`'s count at 0 and its
  pointers from 1032, each checked to point into the object's own text), leaves a call without a multiplier to the
  engine's callback (its usage line), answers below 1 with the engine's own "silly size" line and above 16 with one of
  its own, and otherwise asks the runtime for the poster, written as `garrysmod\screenshots\poster-yy-mm-dd
  HH-MM-SS.png` (the engine's own name, " 2", " 3" ... added when taken). A `Think` hook of the client realm
  (`nlengineguard_poster`, a C function) prints in the console how it goes (the size and tiles, "Saving poster to
  ...", "Saved poster to ..." or why it was not made): from the main thread, which draws the game's console. Lua gets
  only `nlengineguard.poster` (how the takeover went) and the read-only `nlengineguard.PosterStatus()`, which the
  companion's sky reads to hold its clock: no Lua, a server's included, starts a poster other than by the command
  itself, as without RTX. Any client Lua, a server's included, can call `PosterStatus()`, so (review finding 18) its
  `path` is the name the console prints, `screenshots/poster-yy-mm-dd HH-MM-SS.png` (`poster::shown_name`: a file
  elsewhere shows only its name), never the absolute path the runtime writes, which names the player's folders and
  often their Windows account; its `why` names the poster the same way (`shown_reason`). `poster::view` reads the
  runtime's status into those fields; `PosterStatus()` only pushes them.

- **Queued render calls checked before the game leaves threaded rendering ([ADR 0247](../docs/decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md)).**
  At `disconnect`, and so at every `map`, the engine closes the client side and then calls
  `IMaterialSystem::AllowThreading(false)`, whose `ForceSingleThreaded` runs on the main thread what both queued render
  contexts still hold. Seven field games (2026-11-14 to 2026-11-19, each in a start that had just deployed new RTX
  content) crashed there on a call whose object had been freed and its memory reused (its first word a heap address;
  exit 0xC0000409 from GMod's crash handler failing after it). Every realm's load (the menu's first) wraps
  `AllowThreading`'s vtable slot: before the engine leaves threaded rendering the wrapper takes the material system's
  lock (`Lock()`: the render thread finishes the frame it was given), walks both contexts' call lists and unlinks every
  call whose object's first word is not a vtable in a loaded image's read-only data with its call slot (3) in a loaded
  image's code; live calls keep their order. Found by machine code, only where sure: the one slot whose function refers
  to both "Queued Material System" messages, Lock and Unlock by their timing messages, `ForceSingleThreaded` (the call
  after "DISABLED!"), its loop over the contexts (stride, first context, count, `EndQueue`), `EndQueue`'s call of
  `CallQueued` and `CallQueued`'s loop and reset (the list's offset, `{head, tail, next free byte}` before its arena);
  the material system object and both contexts by their RTTI classes. Remix starts only; the second copy reads the
  first's counts through `nl_engine_guard_queue_check_v1`. A check that drops calls writes
  `garrysmod/data/native-loader/render-queue-check.log` (each call's place, why, its memory and first words, and the
  classes of the live calls around it) and says so in the console. `nlengineguard.queue_check` says how the install
  went; `nlengineguard.QueueCheck() -> checks, dropped` counts (read only). The launch option `-nl_queue_check_test`
  makes each check first queue one call whose object is gone, so a test session goes through the drop path.

- **And checked again while the game runs them ([ADR 0254](../docs/decisions/0254-queued-render-calls-checked-again-while-the-game-runs-them.md)).**
  The field's crash of 2026-11-22 came after that check had run and passed every call: the 660th element of context 1
  (the 2026-11-19 crash's too) seemed written over while `ForceSingleThreaded` ran the 659 calls before it (GMod keeps
  every queued call in the context's own arena, never on the heap, yet the call then went through freed heap memory).
  That was ADR 0254's reading; ADR 0261 found the element intact and its call's material variable destroyed (below).
  So after its walk the check keeps every element (its two words, its object's first four words, the 16 bytes before
  it), and for the length of the engine's own `AllowThreading(false)` it rewrites `CallQueued`'s per-call dispatch
  (`mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]`, the start of the pattern the queue check finds) in memory to
  `mov rcx,rbx; call [rip+slot]; nop`, the slot a read-only page within reach (`allocate_near`) holding the step. The
  step puts back an element whose words changed and runs its call if its object did not change, skips a call whose
  object changed, never runs an element twice (that pass ends there), puts back a link its call changed (unless the
  last call appended one), and runs an element it never saw only if the judge finds it live, ending a link that leaves
  the arena. The bytes go back as soon as the engine's function returns. Events go to the queue check's log with the
  classes of the eight calls run before each; the console says how many were put back and skipped.
  `nlengineguard.run_check` says how its install went; `QueueCheck()` also returns runs, put back, skipped, ended. In a
  test session each check also queues a pair of the module's own calls, the first writing over the second's element
  as the field found it; the console says when the run check put it back.

- **What the field's crashes were, and the fix (ADR 0261).** ADR 0254 read the crash of 2026-11-22 as an element
  written over during the run. ADR 0261 found otherwise: the element and its functor were intact; the functor was a
  queued `CMaterialVar` setter (`CMemberFunctor1<CMaterialVar*, ...>`, which keeps the raw variable pointer) whose
  variable was gone. The RTX fixes' `ShutDown` hook `RTXTextureCleanup_MapExit` calls `RTX_CleanupMapTextures`, which
  calls `IMaterialSystem::UncacheAllMaterials`: every file-based material's variables are destroyed at once while
  setters the main thread queued (any `ShutDown` hook's `SetTexture`, `SetInt`..., the companion's restores among
  them) still wait; `AllowThreading(false)` then ran them on freed memory. The put-back mechanism stays as a guard.
  Three parts, package only:
  - **The queued context's own flush.** At install the guard finds, in the live `CMatQueuedRenderContext`'s vtable
    (materialsystem.dll's read-only data), the one slot whose code is `mov rcx,[rdi+ms]; mov rax,[rcx]; call
    [rax+Lock]; xor edx,edx; mov rcx,rdi; mov rbx,rax; call CallQueued; mov rcx,[rdi+ms]; mov rdx,rbx;` then
    `mov r8|rax,[rcx]; call [r8|rax+Unlock]`, with Lock and Unlock the slots `find_layout` found times 8, the call
    reaching `find_layout`'s `CallQueued` and both loads of the material system pointer the same (`find_flush`):
    exactly once, never the two look-alike synchronous methods that call something between `CallQueued` and `Unlock`,
    and only when the match starts within `kFlushStart` (0x60) bytes of the slot's own function (the game's starts
    at +0x35): functions follow each other without padding, so a slot's window can reach into the next function.
    `flush()` (main thread only, the installing thread; refused while a watched run is in progress) takes the lock,
    sees whether this thread records into a queued context (nothing queued: done, with a flush number of its own),
    and goes the way
    `AllowThreading(false)` does (the walk that drops stale calls, the run check's `see`, the dispatch rewritten,
    events logged), with the context's flush as the engine's function; `hook_allow` and the flush share that path
    (`check`, `run_watched`). The copy of the module that did not install forwards the flush to the one that did
    (`nl_engine_guard_queue_flush_v1`, its counts through `nl_engine_guard_queue_flush_status_v1`). Lua, client and
    server realms: `nlengineguard.RunQueuedRenderCalls() -> ok, calls, why`. `ok` is true once the context's flush has
    run: inside a render block the engine's flush queues one call of its own after itself, so the list need not be
    empty (`why` then says `N call(s) queued again by the flush`). The fixes' hook calls it before the cleanup and
    skips the cleanup when it returns false; without the function it runs the cleanup only with `mat_queue_mode` 0.
    `-nl_queue_check_no_flush` (tests): the flush runs nothing and reports success, so the net below is exercised in
    the real game. `use_for_test`/`reset_for_test` give the flush stand-ins (tests only).
  - **The target check, the net (`target_check.h`).** At install: `CMaterialVar`'s and `CMaterial`'s vtables by RTTI;
    the owner's offset from `CMaterialVar`'s slot 24 (`GetOwningMaterial`, exactly `mov rax,[rcx+dd]; ret`), the
    parameter count's and array's from `CMaterial`'s slots 40 (`movzx eax,byte ptr [rcx+dd]; ret`) and 41
    (`mov rax,[rcx+dd]; ret`), both cross-checked against `CMaterial::CleanUpShaderParams`' closing stores
    (`mov qword ptr [r+params],0; mov byte ptr [r+count],0`, one base register), which must occur in the image's code;
    the image's range and read-only sections are kept. A queued functor is judged when its class's RTTI name is a
    `CMemberFunctorN` on a `CMaterialVar*` and its call (slot 3) is argument loads, `mov rax,rcx`, `mov rcx,[rcx+dd]`,
    `jmp [rax+pp]`, or the string setter's exact shape (`push rbx; sub rsp,20h; mov rbx,rcx; add rcx,d8; call rel32;
    mov rcx,[rbx+dd]; ...; jmp rax`; `dd`: where it keeps the variable); classes are cached by vtable (48). Right
    before the run check's step runs a call (seen or stranger), the judge reads under SEH. Gone: the variable cannot be
    read or its first word is not `CMaterialVar`'s vtable. Owner 0: not judged. Owner a `CMaterial`: the owner offset
    is proven for the process, and the owner's parameter array (count entries) must list the variable. Owner another
    vtable in the image's read-only data (`CMaterialSubRect`): not judged (`other_owner`). Anything else (the owner
    unreadable, its first word no vtable of the image): gone only once the offset is proven, else not judged
    (`unproven`). A gone call is skipped, counted (`gone`, also in `skipped`) and recorded with what was found. A
    variable an earlier call of the same run destroyed is caught at its own call. Without the run check it is off.
  - **The log when it happens.** Each event of a watched run is written to `render-queue-check.log` as it happens (a
    header line at the run's first event, a summary line at its end), so a run that crashes still leaves its log
    (before, `record_run` wrote only after the engine's function returned, and the field never had a log). At most 32
    events per run are written (the rest counted in the summary), so a run cannot rotate its own header away; the
    routine line of a flush only for the first 64 flushes of a process (any client Lua can call it every frame).
    Nothing written while the engine runs the list takes the loader lock: module names come from bases captured at
    install and before each check's lock (materialsystem, studiorender, engine, client, shaderapidx9, this module),
    else the image's base address, and the log's path is captured with them. The console says once per run how many
    calls on a gone variable were skipped.
  `nlengineguard.queue_flush` and `nlengineguard.target_check` say how each install went; `QueueCheck()` returns two
  more numbers at its end: the flushes done and the calls skipped because their variable was gone.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | `nl_engine_guard` (static, with the load overlay, its activity classes and its estimate; links user32 and gdi32), the client and server modules (the server's with `NL_ENGINE_GUARD_MENU`), `nl_engine_guard_tests` (given `module.cpp`'s path for its contract test), and the end-to-end `nl_engine_guard_detour_tests` with its stand-in `materialsystem.dll`; the colour cap's end-to-end `nl_engine_guard_colour_tests` with its stand-in `shaderapidx9.dll` (linked without incremental thunks) and Remix `d3d9.dll`, both in `colour_fakes/` (a `d3d9.dll` beside other programs would be loaded by them) |
| `guard.h`, `guard.cpp` | The patterns (call site, GetName call), name comparison, the cycle rules, the filter, the stub and the detour's installation (SEH-guarded scan, pins the module, idempotent across the two copies); `allocate_near`, a page within a rel32 of an address (the stub's, and the run check's slot) |
| `colour_cap.h`, `colour_cap.cpp` | Material colours above 1 capped for Remix (ADR 0190): the engine's conversion (`engine_byte`) and the cap, the shape of the four functions (`classify`), their vtable slots (`find_slots`), the wrappers, the slots switched (pinned, one aligned store each, Remix starts only), the export the other copy reads and the switch |
| `poster.h`, `poster.cpp`, `rtxposter_api.h` | GMod's `poster` command under RTX (ADR 0226): the command found in `client.dll` (SEH-guarded reads of its sections), a `CCommand`'s arguments, the callback swapped and given back, the engine's reading of the arguments (`plan`), the engine's file names, the runtime's exports, the takeover (pinned, once per process) and the console's lines (`poll`, called by the client realm's `Think` hook); what Lua and the console see of the poster (`shown_name`, `shown_reason`, `view`: never an absolute path; review finding 18); `rtxposter_api.h` is the runtime's API header, byte-identical |
| `queue_check.h`, `queue_check.cpp` | Queued render calls checked before the game leaves threaded rendering (ADR 0247): the layout read from `materialsystem.dll`'s code (`find_layout`, `find_vtable` by RTTI; with ADR 0254 also `CallQueued`'s dispatch), the judge (`judge_memory`: VirtualQuery and the images' section headers, no loader lock), the walk that unlinks stale calls (`clean`) and the engine's way of appending (`append`), RTTI names (`rtti_name`, `rtti_name_into`), the wrapped `AllowThreading` slot (pinned, Remix starts only, the lock around the walk, SEH), the log and the console lines, the exports the other copy reads and the test call; the run check's install (the dispatch's bytes, the slot within reach), its rewrite of the dispatch around the engine's function, its log and console lines and the test pair; ADR 0261: the queued context's flush found (`find_flush`) and run through the same path as `AllowThreading(false)` (`check`, `run_watched`, `flush`, main thread only, forwarded by the other copy, `-nl_queue_check_no_flush`), the target check's install and judge hook, each event written to the log as it happens |
| `run_check.h`, `run_check.cpp` | Queued render calls checked again while the game runs them (ADR 0254): the dispatch's ten bytes and their rewrite (`dispatch_patch`), the engine's call through slot 3 (`call_object`), and `Run`: what the check saw of every element (`see`, SEH-guarded reads of the objects), the per-element step that puts back, skips, ends and judges strangers, the records with the calls run before each, the totals; ADR 0261: the hooks given at `begin` (the target judge asked right before each call, a gone target skipped as `target_gone` and counted in `gone`; the notify told each event as it happens) |
| `target_check.h`, `target_check.cpp` | Queued calls on a material variable that is gone (ADR 0261): the layout (`find_layout`: `CMaterialVar`'s and `CMaterial`'s vtables, the owner, count and array offsets from slots 24, 40 and 41 by their exact code), the functor classes judged (`classify`: the RTTI name and the call's shape), the class cache and the game's resolver (RTTI and code read under SEH), and the judge (`judge`: every read under SEH; the verdicts and what was found) |
| `crash_report.h`, `crash_report.cpp` | Windows Error Reporting's crash and hang snapshots switched off for the process (R28): the flags, `WerGetFlags`/`WerSetFlags` from kernel32 at run time, once per process and copy |
| `watchdog.h`, `watchdog.cpp` | The start-up watchdog: sampling the committed stack, Lua chunk names on it, the deadline, the report and the message |
| `load_overlay.h`, `load_overlay.cpp` | The load overlay (R24): the window thread, its sampling of the main thread, the game file paths and Lua chunk names it shows, the elapsed time and the tally behind the summary; the phase after the engine's load (ADR 0214), the estimate's row with its bar, the activity row, `draw()` (one frame into any device context) and the history's file for the menu realm (ADR 0215) |
| `load_activity.h`, `load_activity.cpp` | What the main thread is doing (ADR 0214): the known modules by name and kind, their code ranges from PE headers (SEH), LuaJIT's executable memory, one sample's class (instruction pointer, nearest known caller, a Lua file being run, the spawn menu's files) and the two-second smoothing |
| `load_eta.h`, `load_eta.cpp` | The estimate (ADR 0215): a translation's `%s` filled safely, how a remaining time is said, the bar's fraction (toward its cap, creeping past it, never back), and the history file (`garrysmod\data\nativeloader\load_times.txt`: found from the executable, read bounded, written through a temporary file) |
| `module.cpp` | `gmod13_open`: installs the guard, switches the crash snapshots off (`crash_snapshots_off`, `crash_snapshots`), caps material colours for Remix (`colour_cap`, `ColourCap([enabled])`, every realm) and checks queued render calls before the game leaves threaded rendering (`queue_check`, `run_check`, `queue_flush`, `target_check`, `QueueCheck()` with eight numbers, every realm); in the client and server realms starts the watchdog for its realm (`NL_ENGINE_GUARD_REALM`, set per target) and publishes `nlengineguard` (`installed`, `reason`, `Status()`, `StartupDone([seconds])` -> recovered, `SetMessage(title, body)`, ADR 0261's `RunQueuedRenderCalls()` -> ok, calls, why), and in the client realm (the `gmcl_` copy) takes the poster command over (`poster`, `PosterStatus()`); in the menu realm publishes `installed`, `reason`, `Status()` and the overlay's `LoadStart`, `LoadHeading`, `LoadStatus`, `LoadExpect`, `LoadSettling`, `LoadEnd`, `LoadTimes`, `LoadTimesSave` |
| `tests/fake_materialsystem.asm`, `tests/fake_materialsystem.cpp` | A stand-in `materialsystem.dll` for the end-to-end test: one function whose machine code (exact bytes in the code segment) holds the call site (key values in r13, the material in r14), the loop's GetName call and a stand-in `KeyValues::GetString`; the C++ file exports its address |
| `tests/fake_shaderapi.asm`, `tests/fake_shaderapi.cpp` | A stand-in `shaderapidx9.dll` for the colour cap's end-to-end test: its `Color3f`, `Color3fv`, `Color4f`, `Color4fv` in assembly with the game's shape (255.0 rip-relative, `cvttss2si`, the low byte, `SetRenderState(3Ch)` through the device's vtable), an API object whose read-only vtable names them among other slots, and a device that records the texture factor |
| `tests/fake_remix_d3d9.cpp` | A stand-in `d3d9.dll` exporting `remixapi_InitializeLibrary`, what marks a Remix start |
| `tests/test_colour_cap.cpp` | The colour cap: the engine's wrap and the cap (1.3, 1.5, NaN, negative), the four slots found once in an installed game's `shaderapidx9.dll` (`NL_SHADERAPI_DLL`, else the PoC's; skipped without a game), nothing changed outside a Remix start, `module.cpp`'s contract |
| `tests/test_colour_cap_e2e.cpp` | End to end, in its own process: through the stand-in's vtable, a wrapped texture factor before, nothing changed without the Remix `d3d9.dll`, capped after (within [0, 1] the same bytes, the caller's colour never written, only out-of-range calls counted), the switch, idempotence, and functions of another shape refused |
| `tests/test_detour.cpp` | End to end, in its own process: `install()` finds and detours the stand-in's call site, which then gets `""` for a fallback to the material itself and the fallback for another |
| `tests/test_overlay.cpp` | The load overlay: game file paths and Lua chunk names as shown, the elapsed time, UTF-8 clipping, the bounded tally, `start()`/`finish()` in a process without a game window, the phase after the engine's load and the estimate (`settling()`, `expect()`), the estimate's and the activity's words, the window's picture drawn into bitmaps (the bar, the amber overrun, Japanese through font linking; kept in `scratch\load_overlay_picture` beside the test executable), and `module.cpp`'s contract (the menu realm from `lua_shared`, the overlay functions, the new ones included, only with `NL_ENGINE_GUARD_MENU`) |
| `tests/test_load_activity.cpp` | The activity classes: modules by name, an image's code ranges from its headers (this executable's, and headers that cannot be read), this process's known modules, LuaJIT-style executable memory, one sample classed from fake ranges and stacks (the nearest known caller, a caller beyond the scan, game code called from Lua), the spawn menu's files and the smoothing |
| `tests/test_load_eta.cpp` | The estimate: a translation's `%s` filled or the English, how a remaining time is said, the bar (cap, creep, never back), the history file's path and its writing and reading (bounded, whole, no temporary file left) |
| `tests/test_poster.cpp` | The poster command: found in this test executable as `client.dll` builds it (a stand-in object in writable data, its help text the module's own constant), refused for another kind of callback, a callback outside the code, another name or two objects; the callback swapped once and given back, someone else's left alone; the arguments read from a stand-in `CCommand` (both of its buffers, case, too many, outside the object, unterminated); the engine's reading of the arguments; the engine's file names; nothing taken over without the runtime; review finding 18: the names Lua and the console see (screenshots, other folders, shares, drives, Unicode), the reasons, `view` from a stand-in runtime whose status holds the absolute path (no drive, share or backslash in `path` or `why`), and `module.cpp`'s `PosterStatus` pushing only the view |
| `tests/test_queue_check.cpp` | The queue check: the layout found once in an installed game's `materialsystem.dll` (`NL_MATERIALSYSTEM_DLL`, else the PoC's or the game's install from Steam's libraries; skipped without a game), with `CallQueued`'s dispatch holding the engine's ten bytes, and not in another class's vtable; the judge on real memory (a live object, a freed-and-reused one, none, a vtable in writable data, a call slot that is not code, reserved memory); stale calls unlinked and live ones kept in order (first, last, all, several lists, the drop records' limit); lists that cannot be walked left as they are; the engine's appending; RTTI names and `find_vtable` on this executable; nothing installed outside a Remix start (the run check neither); `module.cpp`'s contract (`run_check` published too); ADR 0261: the queued context's flush found once in a synthetic image (never its look-alikes, never twice, never with the wrong Lock, Unlock, call or material system pointer) and in an installed game's `materialsystem.dll` (not in `CMaterialSystem`'s vtable), a match beyond `kFlushStart` in a slot's window (an unrelated method followed by the flush without padding) refused and the flush's own slot accepted, `module.cpp` publishing `queue_flush`, `target_check`, `RunQueuedRenderCalls` (client and server realms) and eight `QueueCheck()` numbers, the flush refused outside an install |
| `tests/test_target_check.cpp` | The target check (ADR 0261): the functor classes classified by RTTI name and call (every shape materialsystem.dll has, the string setter from its real bytes; other classes, other objects, the string setter's near misses, wrong orders, other bases, xmm0, no jump, bad offsets refused), the layout found in an installed game's `materialsystem.dll` (skipped without a game; owner +0x31, count +0x32, parameters +0x38 asserted, the vtables in its read-only data) and refused for this executable and for copies whose `GetOwningMaterial` or `ShaderParamCount` is not the expected getter or whose `CleanUpShaderParams` clears other offsets, the game's material variable functors all classified, the judge on fake variables and materials in test memory (live, proving the owner offset; the variable's first word wrong; another material class's vtable: not judged; an owner of no vtable or unreadable: not judged before the offset is proven, gone after; no array, no count; not in the array; the variable or the array unreadable; no material; unknown classes), the class cache and the game's resolver on this executable |
| `tests/test_run_check.cpp` | The run check on engine-like lists (each call's 32-byte object in the arena, its element after it) run through `Run::step` as `CallQueued` would: nothing changed when nothing is written over; the field's case (an element written over with a heap block's address) put back and its call run, the record naming the calls run before it; calls whose object or the bytes before their element changed skipped; a call's own link put back; a nested run and a link leading back never running a call twice; calls appended during the run followed, strangers judged, links out of the arena ended; a list the check could not keep run as strangers; records past the limit counted; other threads and idle runs only calling; and the rewritten dispatch executed as machine code (the engine's loop in a page of its own, its dispatch patched to a slot from `allocate_near`, the field's case put back, the original bytes restored); ADR 0261: the target judge asked right before each call (seen elements and strangers), gone targets skipped, counted, recorded and told at the event, a variable an earlier call of the same run destroyed caught (with a fake judge and with the real one on fake memory), events past the record limit still told, and the queued context's flush executed as machine code (Lock, `CallQueued`, Unlock through stand-ins) with its run going through step; `queue_check::flush` on stand-ins (`use_for_test`: the machine-code flush, a fake material system object): nothing queued (ok, its own number, no line), three calls run between Lock and Unlock, one call queued again after the flush (ok, said), another thread refused, the routine log line only for the first 64 flushes, the test option, and refused again after `reset_for_test` |
| `tests/test_crash_report.cpp` | The crash report switch (R28): the flag values, this test process as the game (the flags read back with `WerGetFlags`, a second call answers the same), and `module.cpp`'s contract (called before the realms part, the two fields published) |
| `tests/test_guard.cpp` | The patterns (on the real bytes, and on an installed `materialsystem.dll` when there is one, with its GetName calls), names, the cycle rules, the filter with fake materials, the stub, the watchdog's stack scan and report |
