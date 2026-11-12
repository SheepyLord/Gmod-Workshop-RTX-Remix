# Unsubscribing from the RTX package: report (2026-11-11)

The user's report: "when a player unsubscribes from the item, RTX is not uninstalled. The next game start still runs
with RTX." During the work: "I just checked all 3 Steam accounts logged in on this computer, and non of them subscribed
to the workshop addon. The rtx remix is still loaded"; "I also unsubscribed the addon using 923668359, in this case
Remix was removed"; "Another field game check found that the uninstallation is not clean" (the `remixbinary` error
below); "Loader change is not approved since we can not distribute loader changes to user currently having problems."
Decisions the user took (2026-11-11): an in-game notice on a computer where another account still subscribes; archive
the former RTX files; clean the field at once. Done by Claude on the branch `unsub-fix`; no Codex, no loader
(`winmm.dll`) change, no runtime change. [ADR 0188](../decisions/0188-unsubscribing-with-the-loader-already-installed.md).

## Root causes

1. **RTX stayed after unsubscribing: Steam keeps the item for the other accounts of the computer.** Three Steam accounts
   on the user's computer subscribed to item 3829070317. Steam's `workshop_log.txt` for the first two unsubscribes
   (17:20:15, 17:33:39): "Unsubscribed from item 3829070317", then "Detected workshop change : keeping unsubscribed
   item 3829070317": the folder and the `WorkshopItemsInstalled` entry stayed. The loader installs per computer: for
   the allowlisted item, discovery takes the folder's archive whatever the subscriptions
   (`loader/core/src/discovery.cpp:276-288`); `subscribedby` is read only for content packages, where any account
   counts (`discovery.cpp:105-124`, `:270`). The third unsubscribe (17:36:27) logged "removing unsubscribed item", and
   the next start (17:36:52, loader 0.16.0) removed the package by ADR 0025's rule. Steam's shared record also lags:
   `appworkshop_4000.acf` still named the unsubscribed account until 17:33:49; each account's own
   `userdata\<account>\ugc\4000_subscriptions.vdf` was rewritten at the moment of its unsubscribe
   ([RESEARCH.md](../RESEARCH.md), "Unsubscribing on a computer with several Steam accounts").
2. **The uninstall was not clean: an earlier RTX installation stayed in the game.** The field's journal had started
   over on 2026-11-07 while the RTX package's files of 2026-11-06 were in place. The first deployment kept those that
   differed as originals, put back when the package goes (`deploy.cpp:325-370`), and adopted the identical ones, which
   it never deletes (`deploy.cpp:925`). After the removal 1,164 files were in `garrysmod/addons` and
   `garrysmod/lua/bin`: the whole RTX Lua stack, the companion included, and twelve modules. Without the runtime:
   `[remixbinary] [gmRTX - Binary Module] - remix::loadRemixDllAndInitialize() failed` at
   `addons/remixbinary/lua/autorun/cl_rtx.lua:14`.

## What changed (package only)

- **The notice** ([`unsubscribed_notice.lua`](../../companion/nativeloader/lua/nativeloader/menu/unsubscribed_notice.lua.md),
  menu realm, run by the RTX client module): when the item the package came from is not among the signed-in account's
  subscriptions (`engine.GetAddons()`, once the list is complete), a card explains that Steam keeps the item while
  another account on the computer subscribes and that RTX goes at the first start after no account does. "Don't show
  this again"; console commands; the six languages.
- **The former RTX files** ([`loader/client/former_rtx.cpp`](../../loader/client/README.md), in `gmsv_nlrtxclient`,
  rebuilt and imported with `repo_builds.py refresh`): at a verified RTX start the originals the RTX package displaced
  below `garrysmod/addons/` and `garrysmod/lua/bin/` move from `native-loader/backup/originals` into
  `native-loader/backup/former-rtx/<UTC time>/`; when the menu state closes with the game (no client realm, no other
  gmod.exe of the folder) the adopted ones move into `.../<UTC time>-adopted/`. Under the deployer's lock, renamed,
  never deleted, the journal never written. The installed loaders then put nothing back and install the package's own
  copies, which an uninstall deletes.
- **Docs:** ADR 0188, CHANGELOG, RESEARCH, ROADMAP, the companion's, the client module's and its tests' READMEs, the
  render guard's list of the package's own Lua paths (the new menu script).

## Verified

- **Tests:** `tools\test.ps1 -Config Release` passes (C++ build and CTest, Python, conventions). New:
  `loader/client/tests/test_former_rtx.cpp` (7 cases, two of them through the real deployer: an earlier copy partly
  adopted and partly an original, archived, released, deployed again and uninstalled leaves no file at the add-on and
  `lua/bin` paths), two source-contract cases in `test_module.cpp`, and
  `tools/tests/test_unsubscribed_notice.py` (13 scenarios under LuaJIT).
- **PoC, released loader 0.16.0** (the field's own `winmm.dll`), game folder reached through a junction in a fixture
  library under `out\u` so that Steam's record and the item folder were fixtures; Steam's real files were never written;
  the signed-in account (322575385) really did not subscribe; the field's own 1,164 earlier files put in place first.
  Evidence `out\unsub\poc\<run>`:

  | Run | Steam's state | Package | Result |
  |---|---|---|---|
  | `01-before-kept` | kept for account 923668359 | published (Workshop) | deployed, RTX active: the bug (this start then crashed, below) |
  | `02-before-removed` | removed | published | uninstalled; the earlier files stayed; console: the user's `remixbinary` error |
  | `03-after-kept` | kept | fixed | RTX active; menu: "former RTX files kept at ...: 49"; the notice (`menu.png`); quit: 1,108 adopted files released |
  | `04-after-next-start` | kept | fixed | 1,108 files installed as the loader's own, 0 adopted; RTX active, no Lua error |
  | `05-after-removed` | removed | fixed | uninstalled; nothing put back; `lua/bin` empty; system `d3d9.dll`; no `gmRTX` line, no Lua error |
  | `06`, `07` | kept, then removed | fixed (final build) | the same with the module that ships: 47 originals, 1,108 released, a clean uninstall |

  What stays after the clean uninstall is inert: empty folders the earlier installation had made (the loader removes
  only folders it made) and, in the PoC, the two `gm_construct` maps the package no longer ships. The PoC was restored
  afterwards (its own 0.14.0 `winmm.dll`, its `config.json`, the test copies and their empty folders removed); its
  `native-loader\backup\former-rtx` keeps the test's archives.
- **The field:** the 1,164 leftover files moved to `out\unsub\field-backup\2026-11-11\` with a manifest
  (`python -I out\unsub\move_field_leftovers.py --restore` puts them back; read only the field before it); the
  journal's 9,151 own files of the user's eleven other packages checked intact, the user's `vrmod` modules and their
  `rtx-remix/mods/~gmod_topbr/materials.usda` left as they were.

## Published

- **2026-11-12 01:46 UTC.** `main` fast-forwarded to `26ae9747` and pushed to GitHub with one new Git LFS object (the
  module, 195 KB). The merge's hook built the package from `packages/` and uploaded it to item 3829070317 as
  **0.0.0-dev.20261112014628+0c72c174** (2,085,389,645 bytes, SHA-256
  `f4d03742396af7bf1b0119f9c4caa23fd60b02cd5c6dff225a224f2638dc2288`, content digest `942c5cba...`), through the
  publisher's reviewed fallback for the stale Steam process record (`Couldn't initialize Steam!`, then "Success!").
  The push's hook found the same inputs and uploaded nothing. No GitHub Action was started.
- **What was published is what the PoC ran,** but for one file's line ends: the package of runs `06` and `07` (digest
  `66a69bc5...`) was built in the branch's worktree, where `unsubscribed_notice.lua` still had the LF ends it was
  written with (13,032 bytes); the main checkout has it with CRLF, as every companion file there (13,309 bytes, its
  277 lines). The manifest differs only in that file's hash; every other file of the 1,777 is the same.

## Loader or package?

Package only: every change ships with Workshop item 3829070317 and works with the installed loaders (0.14.0-0.16.0
read the same journal format). On a shared computer the player who unsubscribed is told why RTX stays, and RTX goes once
no account subscribes; a computer with one account already uninstalled at the next start. What only a loader release
could add: deciding from the signed-in account's own subscription list at start-up, so the next start after an
unsubscribe is vanilla on any computer (designed, not implemented; the user declined a loader release on 2026-11-11).

## Follow-up: switched off in Steam (ADR 0189)

The user asked to check whether disabling the RTX item in GMod's add-on list still removes RTX, and chose to turn RTX
off automatically when the loader does not see it.

- **Measured with the user's permission** (temporary probe build, never committed; `out\unsub\poc2`): GMod's own
  Disable writes `garrysmod/cfg/addonnomount.txt`, Enable writes it back without the item, and loader 0.16.0 honours
  it (generation 268 skipped the package as "disabled in GMod's addon list", generation 269 deployed it again). That
  path needed nothing. What the loader misses is Steam's own per-account switch ("Set 1 item(s) to disabled locally"):
  GMod hides such an item, Steam keeps it installed, so RTX would stay, and the notice above would wrongly say "not
  subscribed". The user chose to apply the automatic turn-off to that switch.
- **What changed (package only):** the RTX client module reads the signed-in account's switch from Steam's per-account
  list (`loader/client/steam_switch.cpp`) and, when RTX is switched off, writes it into GMod's list
  (`loader/client/addon_list.cpp`, every other byte kept); the companion's menu script does it once, shows a card with
  the way back (switch on in Steam, enable in GMod's Addons list, restart) and never shows the unsubscribed card for a
  switched-off item. Switched on again before the restart, the entry it wrote is taken out.
- **Verified:** `tools\test.ps1` passes, with `test_addon_list.cpp` (5 cases, one through the real deployer),
  `test_steam_switch.cpp` (2), two more source-contract cases and seven more notice scenarios. On the PoC with the
  released loader: the module read "enabled in Steam for this account" for the RTX item (run `e4`), and GMod's list
  with and without the item removed and restored RTX (runs `e5`, `e6`). The switch-off itself was not triggered on the
  user's account: it is Steam's own control, for the user to try.

## Not done, seen on the way

- The PoC's first start with the published package crashed once (0xC0000005 during the first Workshop mount, after
  "Failed to create shader" errors); the dump is in `out\unsub\poc\01-before-kept`. Not investigated.
- Followed up above: GMod's own add-on list still writes `garrysmod/cfg/addonnomount.txt`; Steam's per-account switch
  is the separate case ADR 0189 handles.
