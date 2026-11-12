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
- **Switched off in Steam ([ADR 0189](../../../../../docs/decisions/0189-steams-per-account-switch-turns-rtx-off.md)).**
  Steam's own Workshop pages can switch a subscribed item off for one account ("disabled locally"); GMod then leaves it
  out of its list, which would look like no subscription, but Steam keeps it installed and the loader still deploys
  it. At every check the script first asks the RTX client module for the signed-in account's switch
  (`__NATIVELOADER_MENU_API.rtx_steam_state()`, read from Steam's per-account list). While it is "disabled": no
  unsubscribed card; once, the module writes the item into GMod's own list of disabled add-ons
  (`rtx_addon_list(true)`, `garrysmod/cfg/addonnomount.txt`, which the loaders read), so the next start removes RTX,
  and a card says so and how to undo it (switch it on in Steam, enable it in GMod's Addons list, restart); a write that
  fails is said once. Switched on again before the restart: `rtx_addon_list(false)` takes the entry this session wrote
  out again and the card closes. Disabling RTX in GMod's own Addons list needs nothing: GMod writes the file itself.
  Without the module's answer (an older module, nobody signed in) the script decides from the menu's list alone.
- **The card.** As the multiplayer notice's (dimmed screen, Tahoma with `extended`, scaled by `ScrH() / 1080`, lines
  broken between CJK characters): the title, three paragraphs (the item's id in the first), **OK** (Enter, Escape) and,
  for the unsubscribed card only, **Don't show this again**. Shown once per start, when the verdict becomes "not subscribed"; a change of the
  subscriptions in the menu decides again. A card that cannot be built prints why.
- **The text.** English in `TEXT` at the top, marked `N"..."`; its translations are in `companion/i18n/<language>.po`
  (`tools/companion_i18n.py update`). The language follows the companion's saved `nativeloader_language`, else
  `gmod_language`, as the multiplayer notice reads them; the menu realm's lack of `CompileString` is handled the same way.
- **The choice** is a menu cookie (`mn.db`): `nativeloader.unsubscribed-notice` = `watching` or `dismissed`.
- **Console:** `nativeloader_unsubscribed_notice` shows the card now; `nativeloader_unsubscribed_notice_reset` brings it
  back after "Don't show this again"; `nativeloader_unsubscribed_notice_status` prints the choice, the item, the
  verdict, Steam's switch, whether this session turned RTX off and how many subscriptions the menu lists;
  `nativeloader_addon_state [id]` prints, read only, what the menu says of an item (listed, mounted,
  `ShouldMountAddon`, `IsSubscribed`). The verdict and Steam's switch are also printed when they change.

What it cannot do for an unsubscribed account: remove RTX. With the loaders already installed the files go only when
Steam removes the item, at the first start after no account on the computer subscribes.

Tested by [`tools/tests/test_unsubscribed_notice.py`](../../../../../tools/tests/test_unsubscribed_notice.py.md) (the menu
realm under LuaJIT).
