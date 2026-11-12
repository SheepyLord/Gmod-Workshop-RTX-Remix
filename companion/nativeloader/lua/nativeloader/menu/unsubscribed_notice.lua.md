# unsubscribed_notice.lua

[ADR 0188](../../../../../docs/decisions/0188-unsubscribing-with-the-loader-already-installed.md): the notice for a Steam
account that does not subscribe to the RTX package while it is installed. Steam keeps a Workshop item on a computer
while any other Steam account there still subscribes to it (its workshop log says "keeping unsubscribed item"), and
the loader installs per computer, not per account: RTX then stays for every account until the last one unsubscribes
([RESEARCH.md](../../../../../docs/RESEARCH.md), "Unsubscribing on a computer with several Steam accounts"). Loaders that are already installed cannot tell (the user
declined a loader change, 2026-11-11), so the package says it in the game.

- **Where it runs.** In the menu realm of an RTX start, run once by the RTX client module (`gmsv_nlrtxclient_win64.dll`,
  [loader/client](../../../../../loader/client/README.md)) with the companion's other verified menu scripts, as
  [`multiplayer_notice.lua`](multiplayer_notice.lua.md). A start without RTX has neither.
- **Which item.** The Workshop item the loader deployed the RTX package (`gmod-rtx-remix`) from, as its start-up report
  `data/native-loader/status.json` names it (`packages[].source` `workshop`, `label`). A local or development source,
  or a report that cannot be read, means nothing to watch: no hooks, no timer.
- **When it decides.** From the menu's own list of the account's subscriptions, `engine.GetAddons()`, which lists every
  subscribed item, mounted or not (the RTX package cannot be mounted by GMod and is listed all the same). The list is
  empty until Steam has listed the subscriptions, so only a list that is not empty and kept its size from one check to
  the next counts: a partial list must never tell a subscribed player that they are not. The item in the list, or
  `steamworks.IsSubscribed(item)` where the menu has it, means subscribed at once. Checks run every five seconds for two
  minutes and one second after the menu's `WorkshopSubscriptionsChanged` and `GameContentChanged` hooks. With
  `-noworkshop` (an empty list) it never decides.
- **The card.** As the multiplayer notice's (dimmed screen, Tahoma with `extended`, scaled by `ScrH() / 1080`, lines
  broken between CJK characters): the title, three paragraphs (the item's id in the first), **OK** (Enter, Escape) and
  **Don't show this again**. Shown once per start, when the verdict becomes "not subscribed"; a change of the
  subscriptions in the menu decides again. A card that cannot be built prints why.
- **The text.** English in `TEXT` at the top, marked `N"..."`; its translations are in `companion/i18n/<language>.po`
  (`tools/companion_i18n.py update`). The language follows the companion's saved `nativeloader_language`, else
  `gmod_language`, as the multiplayer notice reads them; the menu realm's lack of `CompileString` is handled the same way.
- **The choice** is a menu cookie (`mn.db`): `nativeloader.unsubscribed-notice` = `watching` or `dismissed`.
- **Console:** `nativeloader_unsubscribed_notice` shows the card now; `nativeloader_unsubscribed_notice_reset` brings it
  back after "Don't show this again"; `nativeloader_unsubscribed_notice_status` prints the choice, the item, the
  verdict and how many subscriptions the menu lists. The verdict is also printed when it is reached or changes.

What it cannot do: it does not remove RTX. With the loaders already installed the files go only when Steam removes the
item, at the first start after no account on the computer subscribes.

Tested by [`tools/tests/test_unsubscribed_notice.py`](../../../../../tools/tests/test_unsubscribed_notice.py.md) (the menu
realm under LuaJIT).
