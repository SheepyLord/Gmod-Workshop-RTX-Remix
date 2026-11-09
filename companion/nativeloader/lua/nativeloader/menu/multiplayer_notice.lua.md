# multiplayer_notice.lua

R24 ([ADR 0133](../../../../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)): the notice before the
server browser, in the companion add-on instead of the loader, so its text and look change with the package. It
replaces the notice that loaders 0.15.0 to 0.16.0 showed from their own menu script (`loader/proxy/ui/mainmenu.js`).

- **Where it runs.** In the menu realm of an RTX start. Workshop add-ons' Lua does not run there: the RTX client
  module (`gmsv_nlrtxclient_win64.dll`, [loader/client](../../../../../loader/client/README.md)), which the loader's
  menu view loads at menu start, runs every verified `lua/nativeloader/menu/*.lua` of the companion once. While it
  runs, `__NATIVELOADER_MENU_API.read(name)` returns the companion's own verified files (this script reads
  `nativeloader/i18n_data.lua` through it); afterwards the global is gone. A start without RTX has neither the
  module nor this notice.
- **The text.** The English text is in `TEXT` at the top, marked `N"..."`; `tools/companion_i18n.py update` takes it
  into `companion/i18n/nativeloader.pot` and the six `.po` catalogs, where its translations are. The language follows
  the companion's `nativeloader_language`, else `gmod_language`. That setting is a client convar, which the menu
  realm cannot see (`GetConVar` there returns nothing, PoC R24), so the companion keeps a copy of it for the menu in
  `data/nativeloader_companion/language.txt` ([`nativeloader/i18n.lua`](../i18n.lua.md)), read here. The menu realm
  has no `CompileString` either: the translation table is run through `RunString` (as the stock menu's `lua.Run`)
  into a global that is taken and cleared at once.
- **When.** Angular's navigation event to `/servers` (the menu's server browser route, `/servers/`, in any case), in
  the main menu and the pause menu, asks `NativeLoaderMultiplayerNotice.Open(target)` first and holds the navigation
  only once that call was made. No click is swallowed: a failing call, a target over 512 characters, or anything else
  the page held that is not the server browser's goes on at once, and a card that cannot be built prints why and lets
  the browser open.
- **The card.** A dimmed screen and a card scaled with the screen height (`ScrH() / 1080`, at least 0.65), in Tahoma
  with `extended` fonts (as the guide's: a GMod font without it draws Latin-1 only, so the Russian and CJK texts
  would be blank): the title, three paragraphs (lines broken at spaces, and between characters in CJK text), then
  **Don't show this again** as a green button of its own (it continues and remembers), **I understand, continue**
  (Enter) and **Back** (Escape: the browser stays closed). Continue lets that one navigation through.
- **The choice** is a menu cookie (`mn.db`): `nativeloader.multiplayer-notice` = `active` or `dismissed`. At its first
  run, "Don't show this again" from the loader's notice (`nativeloader.multiplayer-warning-dismissed` = `1`) carries
  over; then that cookie is set to `1`, so the loader's notice stays off from its next read. On the page already open,
  the page's half calls the loader's `NativeLoaderReceiveMenuState` with its session token, the update reminder's two
  fields as the loader reads them, and `multiplayer_dismissed`.
- **The page's half** (`PAGE`, plain ES5 for both menu engines) is installed through `pnlMainMenu:Call`, again every
  two seconds (a timer; it is installed once per page: a reloaded page gets it again), never while the page is
  loading (JavaScript queued then piles up in the panel).
- **Console:** `nativeloader_multiplayer_notice` shows the card now (continuing opens `/servers/`);
  `nativeloader_multiplayer_notice_reset` brings it back after "Don't show this again";
  `nativeloader_multiplayer_notice_status` prints the choice, the language it uses and where that came from, whether
  its translations were read, and its title in that language.

Tested by [`tools/tests/test_multiplayer_notice.py`](../../../../../tools/tests/test_multiplayer_notice.py.md) (the
menu realm under LuaJIT, the page under Node).
