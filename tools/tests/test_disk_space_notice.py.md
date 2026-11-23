# test_disk_space_notice.py

Runs [disk_space_harness.lua](disk_space_harness.lua.md) under LuaJIT, once per scenario, without starting Garry's Mod.
The harness loads the companion's real menu script
[`nativeloader/menu/disk_space.lua`](../../companion/nativeloader/lua/nativeloader/menu/disk_space.lua.md)
([ADR 0260](../../docs/decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md)) in a mocked menu realm.

```powershell
python -I -m unittest discover -s tools/tests -p test_disk_space_notice.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_a_start_the_loader_refused_for_space_says_what_to_free` | With the loader's own refusal in `status.json` (deployment `failed`, "not enough free disk space: the new files need 2300 MiB and 64 MiB should stay free, but only 1500 MiB are free"): no card before the menu is up or on a screen under 640x360, then a card with what was needed, kept and free (2.3 GB, 64 MB, 1.5 GB), the drive from the RTX client module, that nothing changed, and how much to free (needed + spare - free + 512 MiB for the game: 1.4 GB, rounded up); only OK, which closes it; the timer gone |
| `test_a_drive_that_filled_while_unpacking_is_said_too` | A write that failed with Windows error 112 (or 39) while unpacking: the card says the drive ran out of space, how much to free from the module's measure (the largest package + 64 + 512 MiB - free), never the loader's path; another wording of the check gets the card with "Free some space" |
| `test_too_little_space_for_the_largest_package_is_said_before_an_update` | Less free space than the largest deployed package (payload + other files) + 64 + 512 MiB: the warning card with the free space, the largest package's size (rounded up) and how much to free, with OK and Don't show this again, which is kept in a cookie: the next start shows none, the console command still does, a failure still shows; the reset command |
| `test_enough_space_shows_nothing` | No card with room to spare, at exactly the space wanted, or without package sizes; one MiB short shows the warning; the status command and the command's "no card" line |
| `test_an_older_client_module_still_explains_a_failure` | Without the module's `disk_space`: no timer and no line with nothing to show; a failure's card takes the drive from the activated runtime folder in `status.json`; a module whose measure fails gets "Free some space" |
| `test_other_failures_and_other_realms_show_nothing` | A deployment that failed for another reason (a running game, another deployment, access denied), no report, or a realm that is not the menu: no card |
| `test_the_sample_cards_show_and_leave_the_real_state` | `nativeloader_disk_space_preview` with no argument, `full` and `low` shows each sample card (2.3 GB needed on drive H:; a full drive and 2.3 GB to free; 2.0 GB free), and afterwards the real report and measure are as they were (no card with enough space) |
| `test_the_cards_follow_the_players_language` | The companion's catalog through the menu API's `read`: title, paragraph, units ("%s GB", "%s MB") and button translated; text without a translation stays English |
| `test_the_script_compiles` | The script compiles under LuaJIT |
| `test_the_loaders_words_are_the_ones_the_script_reads` | The loader's refusal text, its 64 MiB spare (`deploy.cpp`) and its write error's "(Windows error N)" (`fs.cpp`) are still what the script parses |

LuaJIT is optional: without it (CI) the LuaJIT tests are skipped. Writes nothing. Exit code 0 on success.
