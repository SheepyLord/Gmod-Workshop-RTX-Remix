# pbr_note.lua

A note on the main menu of an RTX start ([ADR 0217](../../../../../docs/decisions/0217-a-main-menu-note-on-pbr-for-maps.md),
[ADR 0219](../../../../../docs/decisions/0219-the-pbr-note-one-line-three-buttons-ten-seconds.md)): demo PBR resources
for maps are in SheepyLord's RTX Remix collection on the Steam Workshop
(<https://steamcommunity.com/sharedfiles/filedetails/?id=3834474695>).

## What the player sees

A small panel at the top right of the main menu, scaled with the screen height (1080 lines = 1): the title
**Obtaining more PBR resources**, one line ("Demo PBR packs for maps are in SheepyLord's RTX Remix collection on the
Workshop."), and three buttons:

- **Open the collection**: the collection's address through `gui.OpenURL` (Steam's overlay browser when the overlay is
  on, otherwise GMod's prompt to open it in the system browser); Steam's file view (`steamworks.ViewFile`) only where
  `gui.OpenURL` is missing or fails. The console line names the address.
- **Hide**: closes the note until the next start.
- **Don't show again**: closes it for good (the menu's cookie `nativeloader.pbr-note` = `dismissed`).

The panel is as wide as its line (at most the screen less its margins). It hides itself after ten seconds on screen; the
time counts only while the pointer is not over it (`vgui.GetHoveredPanel`). It takes mouse clicks, never the keyboard,
and is never shown while a map loads or runs (`IsInGame()`, `IsInLoading()`; the escape menu over a game is the same
menu).

## How it runs

The RTX client module (`gmsv_nlrtxclient`) runs the companion's menu scripts once in the menu realm of an RTX start
([ADR 0133](../../../../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)), so the note never appears
without RTX. A `Think` hook decides each frame only whether the note is wanted and counts its time on screen (each
frame's step at most half a second); the screen size and the language (a file read when the companion's convar is
empty) are looked at every two seconds, and the note is rebuilt when either changed. A failed build is said once in the
console and not tried again. The text is translated from the companion's catalog (`nativeloader/i18n_data.lua`, read
through the module's menu API), as in the other menu notices.

## Console

- `nativeloader_pbr_note`: shows the note again for ten seconds, unless "Don't show again" was chosen.
- `nativeloader_pbr_note_reset`: forgets "Hide" and "Don't show again" and shows the note again.

## Tests

[`tools/tests/test_pbr_note.py`](../../../../../tools/tests/test_pbr_note.py.md) runs this file in a mocked menu realm
([`pbr_note_harness.lua`](../../../../../tools/tests/pbr_note_harness.lua.md)).
