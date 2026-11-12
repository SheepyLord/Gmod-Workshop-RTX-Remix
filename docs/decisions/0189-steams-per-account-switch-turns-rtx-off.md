# 0189: Steam's per-account switch turns RTX off through GMod's add-on list

- Status: Accepted 2026-11-11
- Decided by: the user. Asked what the package should do when RTX is off in GMod's add-on list but the loader does not
  see it: "Turn RTX off automatically". After the measurement below showed that GMod's own list already reaches the
  loader and Steam's per-account switch does not: "Yes, for Steam's switch" (2026-11-11). Claude choosing how.
- Builds on: [0188](0188-unsubscribing-with-the-loader-already-installed.md) (the notice in the menu, the RTX client
  module's part in the package), [0025](0025-unsubscribe-removes-the-package.md) (a disabled item is removed, kept for
  a rollback). No loader (`winmm.dll`) change.

## Context

Measured on the PoC on 2026-11-11 with the user's account (evidence `out\unsub\poc2`, [RESEARCH.md](../RESEARCH.md),
"Disabling the RTX item: GMod's list and Steam's switch"):

- **GMod's own Addons list already works.** The menu's Disable button calls `steamworks.SetShouldMountAddon(id, false)`
  and `steamworks.ApplyAddons()` (`garrysmod/html/js/menu/Subscriptions.js`). Called for 3829070317, GMod wrote
  `garrysmod/cfg/addonnomount.txt` (`"addonnomount" { "1" "3829070317" }`) and kept the item in its list as not
  mounted; Enable wrote the list without it. Steam's records did not change. Loader 0.16.0 reads that file
  (`loader/core/src/discovery.cpp:135-150`): the next start skipped the package as "disabled in GMod's addon list",
  and the start after Enable deployed it again.
- **Steam's own switch does not.** Steam's Workshop pages can switch a subscribed item off for one account: Steam logs
  "Set 1 item(s) to disabled locally" and sets `"disabled_locally" "1"` in that account's
  `<Steam>\userdata\<account>\ugc\4000_subscriptions.vdf`. The user's computer has six such items, switched on
  2026-11-10 (the user had meant to unsubscribe). GMod then leaves the item out of its list entirely
  (`engine.GetAddons()` and `steamworks.IsSubscribed` do not have it), but the item stays subscribed and installed,
  so the loader still deploys it: RTX would stay on, and the notice of ADR 0188 would say "not subscribed".

## Decision

1. **The RTX client module reads the switch.** In the menu realm of an RTX start, `api.rtx_steam_state()`
   (`loader/client/steam_switch.cpp`) reads the signed-in account's own list for the verified RTX item (Steam's folder
   from `HKCU\Software\Valve\Steam\SteamPath`, the account from `ActiveProcess\ActiveUser`, advapi32 loaded at run
   time): "disabled", "enabled", "not listed", or nothing when it cannot say.
2. **Switched off: written into GMod's list, automatically.** The companion's menu script asks the module
   (`api.rtx_addon_list(true)`, `loader/client/addon_list.cpp`) to add the item to `garrysmod/cfg/addonnomount.txt`:
   one entry before the block's closing brace, every byte already there kept, GMod's own layout for a missing file,
   written atomically; a file that is not GMod's list is refused unchanged. The next start removes RTX, for every
   account on the computer. A card says so and how to undo it: switch it on again in Steam, enable it in GMod's Addons
   list (which takes the entry out, as GMod's Enable does), restart. Switched on again before the restart, the module
   takes out the entry it wrote this session, and only that.
3. **Never "not subscribed" for a switched-off item.** The notice of ADR 0188 is not shown while Steam's switch is off.
4. **Narrow.** Both functions act on the RTX package's own Workshop item from the verified journal, never on an id or
   path from Lua, only in the engine's menu state; the module reads Steam's files and never writes them.
5. **GMod's own Disable needs nothing:** GMod writes the file itself.

## Consequences

- A player who switches RTX off in Steam gets RTX removed at the next start, with every installed loader; GMod's
  Addons list then shows it disabled, consistent with the switch.
- Switching it on in Steam alone does not bring RTX back: GMod's list still has the entry until the player enables it
  there. The card says both steps.
- Like ADR 0188's notice, it reaches only computers that still have the package; nothing changes for a player who
  never switches the item off.
- Tested: `loader/client/tests/test_addon_list.cpp` (GMod's file byte for byte, a missing or one-line list, refusals,
  links, and through the real deployer: listed removes the package, out of the list brings it back),
  `test_steam_switch.cpp` (Steam's layout, per account), `test_module.cpp` (both functions only for the verified item,
  in the menu realm), `tools/tests/test_unsubscribed_notice.py` (switched off, on again, GMod's own Disable, failures);
  on the PoC with the released loader 0.16.0 ([report](../handover/unsubscribe-report.md)).

## Alternatives considered

- **Read Steam's switch in the loader's discovery.** Fixes it at the start itself; a loader release, which the user
  declined on 2026-11-11.
- **Ask before turning RTX off.** The user chose to turn it off automatically.
- **Notice only.** It would leave RTX on after the player switched it off.
- **`steamworks.ShouldMountAddon` in the menu.** Measured: GMod answers true for an item Steam switched off, because it
  is not in GMod's list at all.
