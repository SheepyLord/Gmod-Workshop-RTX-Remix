# 0260: The package says when the disk is too full for updates

- Status: Accepted 2026-11-22 (the user's request of 2026-11-22: "during installation, when the payload is being
  unpacked, there might be risk that the user's disk is nearly full and a full disk will cause a failure. Without
  modifying the loader, try to handle this situation")
- Package only: the companion's menu script `nativeloader/menu/disk_space.lua` (new) and its translations, the RTX
  client module's menu API (`loader/client`: `disk_space.cpp`, `module.cpp`; `gmsv_nlrtxclient_win64.dll` ships in
  the fixes part, as for [ADR 0246](0246-the-directx-level-servers-see.md)), the render guard's list of the package's
  Lua, the translation tool's units. No `winmm.dll` change.

## Context

At each start the loader unpacks what is new in its packages (RTX Remix and the content packs) and checks the space
first (`loader/core/src/deploy.cpp`): the new files, a new version's payload folder whole and the other files that
changed, must fit on the game's drive with 64 MiB to spare (`ensure_space`, `kSpareBytes`); a package declaring more
than the whole volume holds is skipped as broken. When they do not fit the run stops before anything in place changes;
a write that fails while unpacking or moving (Windows error 112, `ERROR_DISK_FULL`, or 39) stops it too, and what it
did is undone; the next start removes the staged files first (`begin`, `collect`). The start then runs the last
committed generation ("deployment failed (...); using the current committed generation", `startup.cpp`
`after_deployment`). The loader is therefore safe on a full disk: nothing is left half installed.

What it does not do is tell the player. The failure is in `garrysmod/data/native-loader/status.json` (deployment
`outcome` `failed`, its `reason`) and the loader's log; the loader shows no window for it (its one message box is the
previous session's exit report). An update that does not fit is retried at every start and fails at every start,
while the game runs the old version and the Workshop item shows the new one. A first installation that does not fit
leaves no RTX at all.

In the user's game (read only, 2026-11-22): 25 deployed packages; the RTX package's payload folder holds 1.36 GiB
(unpacked whole for each new version, and the previous one is kept for a rollback: 2.8 GB) and its other files 0.8 GiB;
each map content pack 3.5-3.65 GiB.

Installed loaders cannot change (the user's rule since 2026-11-08), so only the package can speak, and only where
its own code runs: in an RTX start, which the loader allows after a failed update (the previous generation), but not
after a first installation that did not fit (nothing of the package is deployed then, and GMod cannot mount the item
itself, [ADR 0015](0015-workshop-route-for-native-packages.md)).

## Decision

1. **The RTX client module measures** (`disk_space()` in its menu API, menu realm only): the free and total bytes of
   the volume that holds the game folder, read when asked with `GetDiskFreeSpaceExW` as the loader reads them, the
   drive's letter, and for each package of the committed generation the bytes of its payload folder and of its other
   files, from the journal the module already reads at its verification.
2. **After a start whose updates did not fit**, the companion's menu script shows a card at the main menu: from
   `status.json`, the loader's refusal (what the new files needed, what it keeps free, what was free) or a full disk
   while unpacking (Windows error 112 or 39); that nothing changed and the game runs the versions it had; and how much
   to free: what was missing + 512 MiB for the game's own caches and logs (after a full disk, what the warning below
   wants). It shows at every such start.
3. **Before it happens**, a warning card when the drive's free space is below what the largest deployed package would
   need to unpack again (its payload folder and other files) + the loader's 64 MiB + 512 MiB: the free space, that
   package's size and how much to free. **Don't show this again** keeps it away (a menu cookie); a failure card shows
   whatever was chosen.
4. **The text** is the companion's, in its six languages; sizes as Windows shows them (tenths of a GB, whole MB), the
   units themselves translatable (`%s GB`, `%s MB`; kept as they are in Chinese, Japanese and Korean, so the
   translation tool allows them unchanged). Console commands show the card that applies, print the numbers, bring the
   warning back, and preview each card with sample numbers.

## Consequences

- A player whose updates do not fit learns it at the main menu with the numbers and the remedy; the next start after
  freeing space installs them, as before. A player whose drive is getting full is warned before an update fails.
- A first installation that does not fit still shows nothing in the game: only the loader's report and log say it.
  Only a loader change could (the user's rule keeps the loader as it is).
- The warning's estimate is conservative: an update unpacks a payload folder whole but other files only when they
  changed, and new subscriptions are not counted. The loader's own check decides; the warning only says that it may
  refuse.
- The script reads the loader's own wording; `test_disk_space_notice.py` pins it to `deploy.cpp` and `fs.cpp`, and a
  check worded otherwise still gets a card without numbers.
- An older RTX client module (no `disk_space`) gets the failure card only, its drive taken from the runtime folder in
  `status.json`.

## Alternatives

- **A loader change** (a window on a failed space check, a smaller staging): ruled out by the user's rule.
- **The engine guard as the measuring module**: it has no access to the journal; the client module reads it already
  and serves the menu scripts.
- **A fixed threshold**: the packages' needs range from 2.2 GB (RTX Remix alone) to 3.7 GB and more (map packs).
- **Measuring in Lua**: GMod's Lua has no free-space call.
