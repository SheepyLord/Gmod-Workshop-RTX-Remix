# 0188: Unsubscribing with the loader already installed: a notice for shared computers, former RTX files kept aside

- Status: Accepted 2026-11-11
- Decided by: the user. Report: "when a player unsubscribes from the item, RTX is not uninstalled. The next game start
  still runs with RTX", then "Another field game check found that the uninstallation is not clean" (the error of
  `addons/remixbinary/lua/autorun/cl_rtx.lua:14`). Constraint: "Loader change is not approved since we can not
  distribute loader changes to user currently having problems." Choices (2026-11-11): an in-game notice on a computer
  where another account still subscribes; "Yes, archive them" for the former RTX files; the field cleaned at once.
  Claude choosing how.
- Builds on: [0025](0025-unsubscribe-removes-the-package.md) (an unsubscribe removes the package),
  [0111](0111-content-packages-only-from-subscribed-items.md) (subscribed means Steam's record names a subscriber),
  [0133](0133-the-multiplayer-notice-in-the-companion.md) (the companion's menu scripts),
  [0042](0042-legacy-remix-migration.md) (an uninstall must not revive a former RTX installation).
- Amends [0035](0035-restore-automatically.md) for one kind of original: those the RTX package displaced below
  `garrysmod/addons/` and `garrysmod/lua/bin/` are kept in `native-loader/backup/former-rtx/` instead of being put back.
  Nothing is deleted (AGENTS.md rule 3). No loader (`winmm.dll`) change.

## Context

What happened on the user's computer on 2026-11-11 ([RESEARCH.md](../RESEARCH.md), "Unsubscribing on a computer with
several Steam accounts"):

- **Steam keeps an item another account of the computer subscribes to.** Three Steam accounts on the computer
  subscribed to item 3829070317. Each unsubscribe was logged at once ("Unsubscribed from item 3829070317"), and the
  first two were followed by "Detected workshop change : keeping unsubscribed item 3829070317": the item's folder and
  its `WorkshopItemsInstalled` entry stayed. Only the third, with no subscriber left in Steam's record, logged
  "removing unsubscribed item", and the next start (loader 0.16.0) removed the package, by ADR 0025's rule. Nine
  other items on that computer were installed for the other accounts only.
- **Steam's record lags.** `appworkshop_4000.acf` still named the unsubscribed account for 13 minutes (17:20 to 17:33,
  rewritten at an account switch), and later named an account the user had unsubscribed elsewhere. Each account's own
  list, `<Steam>\userdata\<account>\ugc\4000_subscriptions.vdf`, was rewritten the moment that account unsubscribed.
- **The loader installs per computer.** Discovery takes an allowlisted item whenever its folder holds the archive
  (`loader/core/src/discovery.cpp:276-288`); `subscribedby` is read only for content packages, and there any account of
  the computer counts (`discovery.cpp:105-124`, `:270`). So RTX stayed, for every account, until no account was listed.
- **The uninstall left an earlier RTX installation in the game.** The field's journal had restarted on 2026-11-07
  over an earlier deployment's files (2026-11-06). The first deployment kept each such file one of two ways
  (`deploy.cpp:862-886`): one that differed from the package's became an original, kept aside and put back when the
  package goes (ADR 0035, `restore_originals`, `deploy.cpp:325-370`); one byte for byte the package's was adopted,
  which the loader never moves or deletes (`deploy.cpp:925`). After the uninstall 1,164 files were there: the whole
  RTX Lua stack of 2026-11-06, the companion included, and twelve RTX binaries in `garrysmod/lua/bin`. With the same
  files the PoC gave 1,108 adopted and 49 originals. Without the runtime, `remixbinary`'s `require` of
  `RTXFixesBinary` failed. ADR 0042 already archives such files permanently, but only for a recognised RTXLauncher
  installation found by a migration (`deploy.cpp:1041-1050`).
- **No loader change.** The fix in discovery (the signed-in account's own list, read through
  `HKCU\Software\Valve\Steam\ActiveProcess\ActiveUser`) was not approved: players with the problem cannot be made to
  replace `winmm.dll`, and a computer whose other accounts subscribe still gets the package's updates from the
  Workshop. What reaches them is the package.

## Decision

1. **A notice in the menu, from the package.** In the menu realm of an RTX start, the companion's
   `lua/nativeloader/menu/unsubscribed_notice.lua` (run by the RTX client module, ADR 0133) compares the Workshop item
   the loader deployed the package from (`status.json`) with the menu's own list of the signed-in account's
   subscriptions (`engine.GetAddons()`, once that list is complete). When the account does not subscribe, a card says
   so, that Steam keeps the item while another account on the computer subscribes, and that RTX goes at the first
   start after no account does; to remove it, unsubscribe on every account. Shown once per start; "Don't show this
   again" is a menu cookie. It removes nothing: on a shared computer the subscribed accounts keep RTX, as Steam keeps
   the item for them, and a computer-wide off switch from the package could not come back by itself when the player
   subscribes again.
2. **Former RTX originals are kept aside, not put back.** In every verified RTX start, before its menu scripts, the
   RTX client module (`loader/client/former_rtx.cpp`) moves the kept copy of every original that the RTX package
   (`gmod-rtx-remix`) displaced below `garrysmod/addons/` or `garrysmod/lua/bin/` from `native-loader/backup/originals/`
   into `native-loader/backup/former-rtx/<UTC time>/`, beside an `index.json` (path, size, SHA-256, what it was, why). A
   kept copy whose size is no longer the recorded one stays. At the uninstall the loader of every released version notes
   that the original "is gone or changed, so the loader no longer puts it back" and leaves the path empty.
3. **Adopted former RTX files leave at the end of a session.** When the menu state closes with the game, no client realm
   is left and no other game of the folder runs (`-multirun`), the module moves the current generation's adopted files of
   the RTX package below the same paths, each whose size and time are still the recorded ones, into
   `native-loader/backup/former-rtx/<UTC time>-adopted/`. The game no longer reads them then. The next start finds those
   paths empty and installs the package's copies as the loader's own (`deploy.cpp:862-863`), which an uninstall deletes;
   if the next start is the uninstall, the loader drops the records of the files that are gone. A timestamp change is
   not enough: for a file whose time differs the loader compares the hash (`deploy.cpp:212-217`).
4. **How both move.** Under the deployer's lock (no deployer runs while the game does; nothing moves while one holds the
   lock), renamed within the volume, never copied or deleted; the journal is never written.
5. **Unchanged:** originals of other packages, and the RTX package's originals of Remix mods and `garrysmod/data`, are
   put back as ADR 0035 says; the loader, its allowlist and its discovery; ADR 0025 and 0111.
6. **The field** (the user's choice): the 1,164 files put back on 2026-11-11 were moved to
   `out\unsub\field-backup\2026-11-11\` with a manifest (`move_field_leftovers.py --restore` puts them back); the
   journal's own files and the user's other add-ons were not touched.

## Consequences

- A player on a computer with one Steam account: unchanged, the item goes when they unsubscribe and the next start
  removes RTX (ADR 0025). On a computer where another account still subscribes: the unsubscribed player is told why
  RTX stays and how to remove it, at every RTX start until they dismiss it.
- An uninstall after one RTX session of this package leaves no earlier RTX file the package ships behind: no Lua, no
  module in `garrysmod/lua/bin`. What stays is inert: the folders the earlier installation made (the loader removes
  only folders it made, so they stay empty) and files at paths the current package no longer has (in the PoC, the two
  `gm_construct` maps that ADRs 0154 and 0155 took out of the package). A player who had installed an add-on of their
  own at one of the RTX package's add-on folders before (a loose copy of one of the bundled add-ons) finds it in
  `native-loader/backup/former-rtx/` after the uninstall instead of in place; `index.json` says what each file is and
  where it was.
- The start after a session that released adopted files installs them again (1,108 files in the PoC, a few seconds),
  once.
- Players who already uninstalled are not reached: the package is gone from their game. Their leftovers are an
  earlier RTX installation's files in `garrysmod/addons` and `garrysmod/lua/bin`.
- A later loader can do what this cannot: decide from the signed-in account's own subscription list at start-up, so
  the next start after an unsubscribe is vanilla on any computer. That is a loader release, for the user to approve.
- Tested: `loader/client/tests/test_former_rtx.cpp` (which files; the move of originals and of adopted files, their
  index; the lock; through the real deployer: deployed over an earlier copy, archived, released, deployed again, then
  uninstalled with nothing left and the archive kept), `test_module.cpp` (originals only in a verified RTX start, before
  the callbacks; adopted files only when the menu state closes without a client realm or another game),
  `tools/tests/test_unsubscribed_notice.py` (the notice's decisions, under LuaJIT); on the PoC with the released loader
  0.16.0 and the field's own earlier files ([report](../handover/unsubscribe-report.md)).

## Alternatives considered

- **The signed-in account's subscription list in the loader's discovery.** It would fix every case at the next start,
  including the minutes in which Steam's shared record still names the account; designed, not implemented: the user
  declined a loader release.
- **An off switch the package sets for the computer** (`native-loader/config.json`, `garrysmod/cfg/addonnomount.txt`
  or `native-loader/disable`). The installed loaders read these, but each one also takes RTX from the accounts that
  still subscribe, and none comes back when the player subscribes again: nothing of the package runs in a start without
  it. GMod no longer writes `addonnomount.txt` either (its add-on list keeps disabled items in Steam's per-account
  `disabled_locally`), so it would be a file only the loader reads.
- **Deleting the former RTX files.** Rule 3: they are kept.
- **Archiving every RTX original, Remix mods and data included.** Remix mods do nothing without the runtime and may
  be the player's own; data files are never displaced (create-only).
