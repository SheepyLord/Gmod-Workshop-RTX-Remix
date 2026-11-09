# 0133: The multiplayer notice in the companion, run in the menu realm by the RTX client module

- Status: Accepted 2026-11-08 (R24, the user's item 1). The notice of loaders 0.15.0-0.16.0
  (`loader/proxy/ui/mainmenu.js`, R20-A) is turned off by the package; the unreleased loader branch
  `r23-loader-mp-notice` (its new text in the loader) is superseded and not to be released.
- Context: the user: "Migrate the multiplayer notice to the workshop addon, it should be implemented using lua
  instead of binary modules. At least, the text should be editable in the gmod addon." and, in R23, "make the
  (Don't show again) button more obvious". Loader changes need the user's approval; the package does not.

## Decision

1. **Menu scripts.** Workshop add-ons' Lua never runs in GMod's menu realm, where the server browser lives. The RTX
   client module (`gmsv_nlrtxclient_win64.dll`, a package module the loader's menu view already requires at menu
   start in RTX starts, [ADR 0052](0052-scoped-rtx-multiplayer-bootstrap.md)) runs the companion's verified
   `lua/nativeloader/menu/*.lua` once there, in name order, from the catalog it already checks byte for byte
   against the committed deployment. While they run, `__NATIVELOADER_MENU_API.read(name)` returns the companion
   add-on's own verified files (nothing else); the global is removed afterwards. No loader change.
2. **The notice is Lua.** `nativeloader/menu/multiplayer_notice.lua` holds the English text (marked `N"..."`, its
   translations in `companion/i18n/*.po`) and draws a Derma card over the menu, scaled with the screen height. Its
   page half, a few lines of ES5 installed through `pnlMainMenu:Call`, asks the script before Angular navigates to
   `/servers` (main and pause menus). "Don't show this again" is a green button of its own (it continues and
   remembers); "I understand, continue" and "Back" stay.
3. **The loader's notice goes.** At its first run the script carries an earlier "Don't show this again" of the
   loader's notice over (`nativeloader.multiplayer-warning-dismissed` = `1`), then sets that cookie to `1`, so the
   loader's notice stays off; on the page already open it tells the loader's script so through its own entry point
   (`NativeLoaderReceiveMenuState`, its session token and the update reminder's two fields as the loader reads them).
   A later loader release can drop its notice code.
4. **Not done: a different DirectX level for servers.** The user also asked to make servers believe the game runs at a
   high DirectX level. A server that checks it does so to keep a rule (such checks are mostly anti-exploit measures),
   and answering it falsely would hide the client from that rule. That was declined; what the DirectX level actually
   broke, ARC9's warning window, is answered in [ADR 0135](0135-view-model-materials-and-arc9.md) with ARC9's own check.

## Consequences

- The text, its translations and the card's look change with the package (a Workshop update), not the loader.
- `nativeloader_multiplayer_notice` shows the card now; `nativeloader_multiplayer_notice_reset` brings it back after
  "Don't show this again".
- A start without RTX has no client module in the menu, so no notice (as before: the loader showed it only in RTX
  starts).
