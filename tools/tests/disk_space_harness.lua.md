# disk_space_harness.lua

The LuaJIT side of [test_disk_space_notice.py](test_disk_space_notice.py.md): runs the companion's real menu script
[`nativeloader/menu/disk_space.lua`](../../companion/nativeloader/lua/nativeloader/menu/disk_space.lua.md)
([ADR 0260](../../docs/decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md)) in a mocked menu
realm, then checks one scenario.

```powershell
luajit tools\tests\disk_space_harness.lua <repo> <scenario>
```

Scenarios: `failed_need`, `failed_full`, `low`, `enough`, `old_module`, `unrelated`, `preview`, `translations` (what each checks:
the table in [test_disk_space_notice.py.md](test_disk_space_notice.py.md)).

The mocks: the loader's start-up report (`file.Read` of `native-loader/status.json` and `util.JSONToTable` hand over a
table), the RTX client module's menu API (`read` for the companion's translation catalog, `disk_space` answering free
space, total, drive and package sizes, or nil and why, or absent for an older module), cookies, convars, timers run by
`tick`, console commands, a screen size, Derma panels that record what their `Paint` draws (the card's text, its wrapped
lines joined by a space) and their buttons. Each run loads the script again with the same cookies, as a new start does.
The loader's messages in the scenarios are its own: `deploy.cpp`'s refusal and `fs.cpp`'s write error.

**Output:** `PASS <scenario>`, exit 0; a failed check raises an error naming what was expected (exit 1).
**Writes:** nothing on disk.
