# multiplayer_notice_harness.lua

Runs the companion's real `nativeloader/menu/multiplayer_notice.lua` (R24) under LuaJIT in a mocked menu realm:
`MENU_DLL`, the menu cookies, convars, the RTX client module's `__NATIVELOADER_MENU_API.read`, Derma panels (a
removed panel takes its children), `surface`/`draw`, `utf8`, `util.TableToJSON`, timers and `pnlMainMenu:Call`.

Usage: `luajit multiplayer_notice_harness.lua <repo root> <scenario>`; prints `PASS <scenario>`, or fails with
a Lua error (exit 1). Scenarios: `first-start` (the loader's notice turned off, the page's half installed, a second
run changes nothing), `carry-over` (an earlier "Don't show this again" from the loader's notice), `open` (the card,
its fonts `extended` for every language, Back, Continue, Don't show this again), `commands` (the console commands;
the command's card goes on to `/servers/`; the status line names the state, language and title), `targets` (only the server browser's routes, in any case, get the card;
anything else the page held, or an overlong target, goes on at once), `loading-page` (nothing is queued for the menu
page while it loads), `translation` (the catalog read through the module's API; English reads none),
`menu-compile` (the catalog loads through `RunString` when there is no `CompileString`, as in GMod's menu realm, and
its global is cleared; English without either), `saved-language` (the companion's language from the copy it keeps in
`data/nativeloader_companion/language.txt` when
its client convar is not visible, before the game's language; the status line names that source), `failure` (a
card that cannot be built opens the browser) and `not-menu`. No files are read or written besides the script itself. Run by
[`test_multiplayer_notice.py`](test_multiplayer_notice.py.md).
