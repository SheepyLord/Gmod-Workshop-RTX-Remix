# loading_status_harness.lua

Runs the companion's real `nativeloader/menu/loading_status.lua` (R24) under LuaJIT in a mocked menu realm: the engine
guard module's overlay functions (recorded), the stock `IsInLoading`, `GetLoadStatus`, `GameDetails` and
`IsHostingGame`, the menu's `Think` hook (called by the harness), convars, `CreateConVar`, `SysTime` and the RTX client
module's `__NATIVELOADER_MENU_API.read`.

Usage: `luajit loading_status_harness.lua <repo root> <scenario>`; prints `PASS <scenario>` or fails with a Lua error
(exit 1). Scenarios: `load` (nothing while not loading; the start, the trimmed status sent once per change, the map's
name, the end and the console summary; the next load), `details-first` (a map named just before the load is seen is
the first line; an old one is not), `joining` (a server's name and map), `local` (a single-player game and a listen
server stay "Loading <map>" when the engine later names its own server and `IsHostingGame()` reads false, as in the
PoC; the stock function gets every argument; the next load, a server joined, is named as one), `translated` (the
catalog's words), `menu-compile` (the catalog through `RunString` without `CompileString`, as in GMod's menu realm),
`saved-language` (the companion's language from the copy it keeps in
`data/nativeloader_companion/language.txt`, its client convar not being visible in the menu realm), `off`
(`nativeloader_load_overlay 0`), `no-module` (no hook, and the console says why) and `not-menu`. No files are read or
written besides the script. Run by [`test_loading_status.py`](test_loading_status.py.md).
