# pbr_note.lua

A note on the main menu of an RTX start ([ADR 0217](../../../../../docs/decisions/0217-a-main-menu-note-on-pbr-for-maps.md)):
demo PBR resources for maps are in SheepyLord's RTX Remix collection on the Steam Workshop
(<https://steamcommunity.com/sharedfiles/filedetails/?id=3834474695>), and what a map without PBR materials looks like
under RTX Remix.

## What the player sees

- **The note**: a small panel at the top right of the main menu, scaled with the screen height (1080 lines = 1), with
  "PBR materials for maps", one sentence, and three buttons: **Open the collection** (Steam's overlay through
  `steamworks.ViewFile`, else `gui.OpenURL`), **Maps without PBR** (the card) and **Hide** (until the next start). It
  takes mouse clicks, never the keyboard, and is never shown while a map loads or runs (`IsInGame()`, `IsInLoading()`;
  the escape menu over a game is the same menu).
- **The card**: "What to expect on a map without PBR": RTX Remix path traces every map; a map without PBR keeps colour
  only textures, so surfaces can look flat or plastic and painted shine or shadows can look doubled; what ToPBR can do;
  where the demo resources are and that RTX Remix installs subscribed packs at the next start. Buttons: **OK**, **Open
  the collection**, **Don't show the note again** (remembered in the menu's cookie `nativeloader.pbr-note`). Modal, as
  the companion's other menu notices; closed when a map starts loading.

## How it runs

The RTX client module (`gmsv_nlrtxclient`) runs the companion's menu scripts once in the menu realm of an RTX start
([ADR 0133](../../../../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)), so the note never appears
without RTX. A `Think` hook decides each frame only whether the note is wanted; the screen size and the language (a file
read when the companion's convar is empty) are looked at every two seconds, and the note is rebuilt when either changed.
A failed build is said once in the console and not tried again. The text is translated from the companion's catalog
(`nativeloader/i18n_data.lua`, read through the module's menu API), as in the other menu notices.

## Console

- `nativeloader_pbr_note`: shows the card now.
- `nativeloader_pbr_note_reset`: brings the note back after "Hide" or "Don't show the note again".

## Tests

[`tools/tests/test_pbr_note.py`](../../../../../tools/tests/test_pbr_note.py.md) runs this file in a mocked menu realm
([`pbr_note_harness.lua`](../../../../../tools/tests/pbr_note_harness.lua.md)).
