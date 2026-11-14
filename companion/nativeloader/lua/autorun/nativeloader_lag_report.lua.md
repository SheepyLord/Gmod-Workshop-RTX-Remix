# nativeloader_lag_report.lua

The console command **`nativeloader_lag_report [seconds]`** (R28,
[ADR 0143](../../../../docs/decisions/0143-read-backs-font-definitions-and-slow-render-hooks.md)): which add-ons'
Lua costs the most of every frame. A shared autorun file of the companion, so it exists in RTX starts (without RTX
the loader hides the package's add-ons); it is not sent to other players' clients (no `AddCSLuaFile`).

## Usage

```
nativeloader_lag_report        // 10 seconds
nativeloader_lag_report 30     // 2 to 120 seconds
```

Play as usual while it measures (stand where the game lags). In a local game the client's command also starts the
server's half, `nativeloader_lag_report_server`, which only the server's console or the hosting player may run; its
report follows in the same console.

## What it does

1. Puts a timer in the place of every function in `hook.GetTable()`, of every function of the gamemode
   (`GAMEMODE`, listed as the hook `"the gamemode"`) and of every receiver in `net.Receivers` of its realm
   (`SysTime()` before and after, inclusive time, the call count and the slowest call; arguments, return values and
   errors pass through), and counts frames (the client's `Think`) or ticks (the server's `Tick`). A hook's function
   is swapped in the hook table itself, not with `hook.Add`, whose checks and other add-ons' wrappers of it would
   run again: GMod's `hook.GetTable()` is the live table; with ULib's hook library (`hook.GetULibTable`) the
   function is swapped at the hook's own priority and in the plain table ULib keeps beside it (the render guard
   runs its events from that table). With any other hook library the hooks are left alone and the report says how
   many. A hook of a panel or entity that is gone is skipped. On the client each timer is entered in
   the render guard's `NativeLoaderRenderGuard.timed`, so the guard keeps naming, and treating, the function it times.
2. After the given time puts back every hook, gamemode function and net receiver that is still the timer it
   installed (one its add-on replaced or removed meanwhile is left alone). This happens even when the report itself
   fails (it says so), and the next report can start.
3. Prints, each line starting `[nativeloader]`: the map, the time, the frames and the average and worst frame; what
   all hooks and all net receivers take of a frame; the fifteen most expensive hooks and five net receivers, each
   with milliseconds per frame (or tick), its worst call, its call count, the event and the hook's name, the file
   and line it is defined at, and the add-on that file belongs to: the folder under `addons/`; else the mounted
   Workshop item whose archive has the file, found with `file.Exists(path, title)` over `engine.GetAddons()` (also
   for a file under a folder the game has itself, such as an item's gamemode or post-process effect); else "Garry's
   Mod" for a file under the game's own folders (`lua/includes`, `lua/derma`, `lua/vgui`, `lua/menu`,
   `lua/postprocess`, `lua/matproxy`, the base, sandbox and terrortown gamemodes). On the client, what the render
   guard did this session (repeated screen read-backs answered from the last picture, repeated font definitions left
   out, the render callbacks it found slow).
4. Writes the same text to `garrysmod/data/nativeloader/lag_report_client.txt` or `lag_report_server.txt`.

Not counted: timers, entity and weapon `Think`, panels' `Paint`; a hook added while it measures. A time includes
what the function calls, so a hook that runs other hooks is counted with them. English only: the text is meant to be
pasted into an issue report.

**Inputs:** the seconds. **Outputs:** the console lines and the data file. **Side effects:** none that stay; a
second run while one is measuring is refused. No exit code (a console command).

Checked in a game (the R28 report) and by [lag_report_harness.lua](../../../tests/lag_report_harness.lua.md).

Only in this machine's RTX starts ([ADR 0206](../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md)): its first line of code returns when `NativeLoaderRTXStart()`, set by `!!!!nativeloader_engine_guard.lua`, says the loader did not activate RTX (a start through an off switch, a removed loader, files a loader left behind).
