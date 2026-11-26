# Garry's Mod's main branch: the plan for the next loader release

Postponed by the user on 2026-11-25: "Postpone this, we will accumulate more loader changes and ship as a new release
in the future". Nothing is built yet. This file says what the next loader release, the runtime and the package need so
that RTX loads on the main and prerelease branches, and what was found. The facts are also in
[RESEARCH.md](../RESEARCH.md) ("Garry's Mod's main branch").

## The report

The user switched Garry's Mod from the x86-64 branch to prerelease and then to the main branch (`public`), and RTX did
not load. On the main branch, the 64-bit launch option starts `gmod_win64.exe` in the game folder.

## What happens

- **Builds** (Steam's content log, 2026-11-25). Main and prerelease were both build 25375506 (depot 4001 manifest
  2904029089870460835, depot 4002 manifest 8456439456790142762). x86-64 was build 26623711. The main build's
  executables carry the PE date 2026-09-15, two months older than x86-64's.
- **Layout.** The main branch's game folder holds two executables. `gmod.exe` is 32-bit (980,816 bytes): it sets
  `PATH=<root>\bin\;...` and loads `bin\launcher.dll`. `gmod_win64.exe` is 64-bit (1,040,208 bytes): it sets
  `PATH=<root>\bin\win64\;...` and loads `bin\win64\launcher.dll`. `bin\win64` has no `gmod.exe`. The 64-bit engine
  and the rest of `bin\win64` sit where they do on x86-64. The Model Hotloader's natives already allow for this layout:
  their comment dates main's layout from 2026-09-17
  ([installation.cpp](../../packages/model-hotloader/source/mmdhl/native/installation.cpp)).
- **Why the loader never runs.** `gmod_win64.exe` imports `WINMM.dll` (`timeGetTime`) and `dbghelp.dll` itself.
  Windows resolves an executable's imports from the executable's folder first, then from System32. System32's
  `winmm.dll` is therefore loaded at process start, and `bin\win64\winmm.dll` never is. In those starts the loader
  writes no `loader.log`.
- **Not a `winmm.dll` beside `gmod_win64.exe`.** The 32-bit `gmod.exe` in the same folder imports `WINMM.dll` too.
  Windows does not load a 64-bit DLL into a 32-bit process, so the 32-bit game would no longer start.
- **What would load.** `gmod_win64.exe` loads the launcher with
  `LoadLibraryExA("<root>\bin\win64\launcher.dll", NULL, LOAD_WITH_ALTERED_SEARCH_PATH)`: flags 8, at VA `0x140056C73`
  in build 25375506. So Windows looks for `launcher.dll`'s imports in `bin\win64` first. `launcher.dll` imports
  `WSOCK32.dll` by name (`WSAStartup`, `WSACleanup`). That DLL is not a KnownDLL, and nothing loads it earlier. The
  checked candidates were:
  - the executable's 16 start-up DLLs;
  - `tier0.dll`, which imports `WS2_32` instead;
  - `vstdlib.dll` and `steam_api64.dll`;
  - Steam's `GameOverlayRenderer64.dll`.

  A `bin\win64\wsock32.dll` therefore loads with `launcher.dll`. That is before `LauncherMain`, the engine,
  `shaderapidx9.dll` and `d3d9.dll`. `ServerBrowser.dll` and `menusystem.dll` import `WSOCK32.dll` later, also by
  name.
- **On x86-64**, `bin\win64\gmod.exe` is the application. A `bin\win64\wsock32.dll` would load there too, with
  `launcher.dll`, after `winmm.dll` has started the loader.
- **Today, with the loader installed, on the main branch:**
  - the game starts vanilla;
  - nothing hides the RTX-only add-ons, because ADR 0013's hiding is done by the loader;
  - the leftovers window ([ADR 0235](../decisions/0235-a-window-when-rtx-is-left-without-its-loader.md)) stays silent,
    because `bin\win64\winmm.dll` is present.

## The plan

1. **A second loader file, `bin\win64\wsock32.dll`.**
   - Built from the same sources, with the 75 exports of System32's `wsock32.dll` (names and ordinals; 71 of them are
     forwarders). They are resolved at load, as `winmm.dll`'s are.
   - It activates only when the process is `<root>\gmod_win64.exe` and the file is in `<root>\bin\win64`. `winmm.dll`
     keeps activating only for `<root>\bin\win64\gmod.exe`. In the other layout, each file stays a plain proxy.
   - Two builds rather than one file under two names, so that an import by ordinal finds the right function. The
     game itself has none; injected DLLs are unknown.
2. **A start-up phase at `LauncherMain`.** When `wsock32.dll` loads, the executable's entry point has already run, and
   its `DllMain` runs under the loader lock.
   - Its `DllMain` patches the start of `launcher.dll`'s exported `LauncherMain`, as `bootstrap.cpp` patches the entry
     point now. The hook restores those bytes, runs `startup_guarded()` and then calls `LauncherMain`.
   - The command-line swap (`cmdline::append_arguments`) already works after the entry point. Check that GMod's
     `LauncherMain` reads `GetCommandLineA()` and not its `lpCmdLine` argument: the executable passes the pointer it
     read before the swap.
   - `SetEnvironmentVariableW` still reaches the runtime, since DXVK reads its settings with
     `GetEnvironmentVariableW`. The executable's CRT copy of the environment does not see the change.
   - `loader.log`'s `phase=` line says which phase ran.
3. **Every check for `bin\win64\gmod.exe` also accepts `gmod_win64.exe` in the game folder:**
   - `loader/proxy/activation.cpp` (`game_root`, `should_activate`);
   - `loader/proxy/observer.cpp`;
   - `loader/client/module.cpp`, `loader/client/former_rtx.cpp` and `loader/client/leftovers.cpp`;
   - `loader/core/src/deploy.cpp`, the running-game check (Chromium's helpers are `gmod_win64.exe` processes there);
   - the tests of each.
4. **The bundle and the player README:** both files go in `bin\win64`. The release record and the update reminder cover
   both.
5. **The runtime** (a runtime patch, package side).
   - `env::getExeName() == "gmod.exe"` gates the wait for Chromium in `rtx_initializer.cpp`, which is a crash fix.
   - It also gates the managed texture defaults in `d3d9_options.cpp`: `deferManagedTextures`,
     `managedTextureBudgetMiB` and `releaseManagedHostCopies` (runtime patches 0022 and 0024).
   - A conf's `[gmod.exe]` section does not apply to `gmod_win64.exe` (`config.cpp`). rpai's `remixhash.py` reads
     `[gmod.exe]`.
6. **The package.**
   - The fixes' ToPBR finds the game folder three levels above `bin\win64\gmod.exe` (`to_pbr.cpp`).
   - The advanced material editor's bridge assumes the same layout
     ([rtx_bridge/README.md](../../packages/advanced-material-editor/source/rtx_bridge/README.md)).
   - The leftovers window could tell a main-branch player with an older loader what is missing.
7. **The older build.** On build 25375506, these need a run:
   - the engine guard's and the fixes' machine-code searches;
   - the seven render recipes;
   - the natives.
8. **Tests:**
   - a vanilla PoC copy of the main branch, made from the cached manifests (`tools/steam`);
   - the proxy's tests for both layouts;
   - PoC sessions on each branch.

Until then, RTX needs Garry's Mod's x86-64 branch.
