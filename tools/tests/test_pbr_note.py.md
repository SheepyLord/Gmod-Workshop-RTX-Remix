# test_pbr_note.py

Tests the companion's main-menu note on more PBR resources for maps
([`nativeloader/menu/pbr_note.lua`](../../companion/nativeloader/lua/nativeloader/menu/pbr_note.lua.md),
[ADR 0217](../../docs/decisions/0217-a-main-menu-note-on-pbr-for-maps.md),
[ADR 0219](../../docs/decisions/0219-the-pbr-note-one-line-three-buttons-ten-seconds.md)).

- Source checks: the script's first line of code returns outside the menu realm and on a second run; it names the
  collection the user gave (Workshop item 3834474695); the companion's guard lists the file as the package's own.
- Each scenario of [`pbr_note_harness.lua`](pbr_note_harness.lua.md) under LuaJIT (on `PATH`, or
  `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`; skipped when neither exists): the note at the top right of the main
  menu with its title, one line and three buttons, never over a running game or a load, "Hide", hidden by itself
  after ten seconds and shown again by `nativeloader_pbr_note`, the time held while the pointer is over it,
  "Don't show again", the console commands, `gui.OpenURL` for the collection (Steam's file view only without it),
  the player's language, the two-second look at the screen and the language, a screen of no size, a failed build
  said once, a second run.

## Usage

```powershell
python -I tools\tests\test_pbr_note.py
```

Run by `tools\test.ps1` with the other tests. No side effects; exit code 0 when every test passes.
