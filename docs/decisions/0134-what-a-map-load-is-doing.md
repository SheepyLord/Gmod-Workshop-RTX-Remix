# 0134: What a map load is doing, in a window of the engine guard module's own

- Status: Accepted 2026-11-08 (R24, the user's item 3)
- Context: the user: "Increase verbosity when the map loads, show what the game is doing instead of just 'loading
  resources, starting lua'." and "Investigate what cause the slow load time ... (additional binary module is okay,
  distributed via the workshop addon)". GMod's loading screen is the menu realm's loading panel; during a blocking phase
  (the Lua start of hundreds of add-ons, file lookups across every mounted add-on) the engine does not repaint it, so
  no Lua can change what it shows then.

## Decision

1. **A window of its own.** The engine guard module (R23, [ADR 0130](0130-an-engine-guard-for-lua-start-up.md)) gets a
   load overlay: a small layered window owned by the game's window, drawn by the module's own thread, so it keeps
   updating while the main thread is busy. It never takes focus or clicks (`WS_EX_NOACTIVATE`, `WS_EX_TRANSPARENT`).
   It shows the heading and the time so far, the stock status line, the Lua file running and the game file being
   read. The last two come from sampling the main thread every 250 ms, as the watchdog does: suspended only for
   `GetThreadContext` and one copy of its committed stack into a 256 KiB buffer allocated beforehand, so nothing waits
   on a lock the main thread holds. It appears after 1.5 s of a load, at the bottom left of the game's window.
2. **Driven from the menu realm.** The companion's menu script `nativeloader/menu/loading_status.lua` (run by the RTX
   client module, [ADR 0133](0133-the-multiplayer-notice-in-the-companion.md)) requires the module there at menu start
   (the guard is then in place before any map) and follows the stock loading state from a `Think` hook: `IsInLoading()`
   becoming true starts the overlay, `GetLoadStatus()` passes through, `GameDetails` names the map or the server, the
   end of the load hides it (the engine keeps its own reference to the loading panel, so wrapping the panel's methods
   through `GetLoadPanel` saw no load in the PoC). The
   overlay's functions exist only in the menu realm: the client and server realms, where any server's Lua runs, cannot
   put text in a native window. The menu realm is the engine's own menu Lua state (`lua_shared`'s
   `GetLuaInterface(MENU)`), never the `MENU_DLL` global, which any Lua can set (the R24 review found a server could
   have set it and required the client copy), and only the `gmsv_` copy, the one the menu loads, has the functions
   at all. The RTX client module recognizes the menu the same way.
3. **What took long.** At the end the console gets the load's length and the Lua files seen running longest (at least
   half a second each, at most three), so a slow add-on can be named.
4. **Load time.** PoC measurements with the user's 772 subscriptions mounted (RESEARCH.md, R24): the load itself takes
   about 43 s in an RTX start (29 s without RTX), Lua and file lookups across the mounted add-ons on the main thread
   (single-threaded by the engine: Lua cannot run on other cores); ARC9's Lua is about a tenth of it, this package's
   about a twentieth. Lua's own file and material calls, timed per calling script, are about 4 s on the server and
   6 s on the client (5 s without RTX), led by Extended Spawnmenu (2,274 `file.Find` calls, 3.5 s) and ARC9's
   attachment files (`Material`, about 2.5 s); this package's largest is the RTX fixes' material fixer (724
   `Material` calls, 0.4 s). A wait of about 340 s at the menu before the load, seen in five PoC runs, was the test driver's:
   Windows kept calling the unfocused window hung after the Workshop remount while it answered messages at once, and
   `poc_session.py` sent nothing to a "hung" window (it now confirms the verdict with a `WM_NULL`). No speculative
   prefetch or engine file-system change is made: on this machine's NVMe the load is not waiting on the disk.

## Consequences

- `nativeloader_load_overlay 0` (archived, menu realm) turns the overlay and the summary off.
- The window thread lives for the process once a load has started (the module is pinned) and costs nothing between
  loads (no timer, a blocking wait).
