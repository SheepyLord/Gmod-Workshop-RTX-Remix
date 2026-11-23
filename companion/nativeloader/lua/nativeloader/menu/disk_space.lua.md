# disk_space.lua

[ADR 0260](../../../../../docs/decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md): the notice about
free disk space for the loader's unpacking. At each start the loader (`winmm.dll`) unpacks the new versions of RTX Remix
and its content packs, after checking that their new files fit on the game's drive with 64 MiB to spare
(`loader/core/src/deploy.cpp`, `ensure_space`). When they do not, or when the drive fills while it unpacks, it changes
nothing, undoes what it staged, and the game runs the versions it had; its start-up report
`data/native-loader/status.json` says why (deployment `outcome` `failed`, `reason`), and nothing a player sees does.
Installed loaders cannot be changed (the user's rule), so the package says it.

- **Where it runs.** In the menu realm of an RTX start, run once by the RTX client module (`gmsv_nlrtxclient_win64.dll`,
  [loader/client](../../../../../loader/client/README.md)) with the companion's other verified menu scripts, as
  [`unsubscribed_notice.lua`](unsubscribed_notice.lua.md). A start without RTX has neither; a first installation that
  did not fit has no RTX start and no companion yet, so it cannot show (the loader's own report is all there is then).
- **After a start whose updates did not fit** (the failure card, always shown): from `status.json`, the loader's refusal
  ("not enough free disk space: the new files need N MiB and M MiB should stay free, but only K MiB are free": what was
  needed, kept and free) or a write that failed with Windows error 112 or 39 (a full disk); that nothing was changed; and
  how much to free: N + M - K + 512 MiB for the game's own caches, or, after a full disk, what the warning below wants,
  or "some space" when the numbers are unknown. Only **OK** (Enter, Escape): each start whose updates do not fit shows
  it again.
- **Before it happens** (the warning card): when the drive's free space is below what the largest deployed package
  would need to unpack again (its payload folder, unpacked whole for each new version, and its other files, unpacked
  again when they change) + the loader's 64 MiB + 512 MiB for the game. **OK** and **Don't show this again** (a menu
  cookie, `nativeloader.disk-space-notice` = `watching` or `dismissed`); a failure card shows whatever was chosen.
- **The numbers** come from the RTX client module's menu API, `disk_space()`: the drive's free and total bytes, read
  when asked (`GetDiskFreeSpaceExW` on the game folder, as the loader measures), its letter, and per package of the
  committed generation the bytes of its payload folder and of its other files, from the loader's journal. An older
  module has no `disk_space`: no warning then, and a failure card takes the drive from the activated runtime's folder
  in `status.json`.
- **When.** Two seconds after the script runs, and every two seconds for half a minute until the screen is at least
  640x360, so the card does not sit under the menu's own panels. One line goes to the console at the start when there
  is something to say.
- **The card.** As the unsubscribed notice's (dimmed screen, Tahoma with `extended`, scaled by `ScrH() / 1080`, lines
  broken between CJK characters), amber instead of blue. Sizes as Windows shows them: tenths of a GB from 1 GB, whole MB
  below; amounts to free rounded up; a no-break space between the number and its unit, so a line never ends between
  them.
- **The text.** English in `TEXT` at the top, marked `N"..."`, the units included (`%s GB`, `%s MB`); its translations
  are in `companion/i18n/<language>.po` (`tools/companion_i18n.py update`). The language follows the companion's saved
  `nativeloader_language`, else `gmod_language`, as the other menu scripts read them.
- **Console:** `nativeloader_disk_space` measures again and shows the card that applies now (the warning even after
  Don't show this again), or says why there is none; `nativeloader_disk_space_reset` brings the warning back;
  `nativeloader_disk_space_status` prints the drive's space, the largest package and what it wants free, and the last
  start's deployment; `nativeloader_disk_space_preview need|full|low` shows a card with sample numbers (2300 MiB
  needed and 1500 free; a full drive; 2000 MiB free against a 3700 MiB package), to look at its layout and translations,
  and leaves the real state as it was (`NativeLoaderDiskSpace.Preview(kind)`).

Tested by [`tools/tests/test_disk_space_notice.py`](../../../../../tools/tests/test_disk_space_notice.py.md) (the menu
realm under LuaJIT) and the module's `disk_space` by `loader/client/tests/test_disk_space.cpp`.
