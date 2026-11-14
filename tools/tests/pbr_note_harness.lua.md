# pbr_note_harness.lua

Runs the companion's real
[`nativeloader/menu/pbr_note.lua`](../../companion/nativeloader/lua/nativeloader/menu/pbr_note.lua.md)
([ADR 0217](../../docs/decisions/0217-a-main-menu-note-on-pbr-for-maps.md)) in a mocked menu realm: whether a game runs
or loads (`IsInGame`, `IsInLoading`), the clock (`SysTime`), the screen size, cookies, the companion's catalog as the
RTX client module's menu API reads it, Steam's overlay (`steamworks.ViewFile`), `gui.OpenURL` and Derma (popups, buttons
and the text their labels draw).

## Usage

```
luajit tools\tests\pbr_note_harness.lua <repo> <scenario>
```

Scenarios: `shows`, `game-and-loading`, `hide`, `card`, `dismissed`, `open`, `french`, `throttle`, `tiny-screen`,
`build-fails`, `once`. Each prints `PASS <scenario>` and exits 0, or raises an error (exit 1) naming what differed.

Run by [`test_pbr_note.py`](test_pbr_note.py.md). No side effects.
