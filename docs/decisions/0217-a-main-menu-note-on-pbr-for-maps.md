# 0217: A main-menu note on PBR for maps: the demo resources, and what a map without PBR looks like

- Status: Accepted 2026-11-14 (the user's QoL request)
- Context: the user: "In the main menu, add a note telling user that they can get demo PBR resources from
  https://steamcommunity.com/sharedfiles/filedetails/?id=3834474695, and explain what to expect for a map without PBR."
  Item 3834474695 is SheepyLord's Workshop collection "Mein RTX-Remix" ("NVIDIA RTX Remix Resources published by
  SheepyLord"): the RTX package and content packs such as Modern House RTX. Players who load an ordinary map see real
  path-traced light on colour-only Source textures and can take the flat look for a fault of RTX Remix.

## Decision

1. **A note, not a card at every start.** A small panel at the top right of the main menu says that maps look their
   best with PBR materials and that demo PBR resources are in the collection, with three buttons: open the collection
   (Steam's overlay through `steamworks.ViewFile`, else `gui.OpenURL`), "Maps without PBR" (the explanation) and "Hide"
   (until the next start). It takes mouse clicks and never the keyboard, so the menu's own keys keep working. It is
   never shown while a map loads or runs: the escape menu over a game is the same menu realm, and the note belongs to
   the first screen. The card with the explanation is modal, as the companion's other menu notices, and offers
   "Don't show the note again" (the menu's cookie `nativeloader.pbr-note`); `nativeloader_pbr_note_reset` brings it
   back.
2. **What the card says.** RTX Remix path traces every map, with or without PBR; a map without PBR keeps colour-only
   textures, so its surfaces are lit as smooth and evenly matte or glossy (flat walls, plastic-like metal, painted
   shine or shadows that look doubled); ToPBR can approximate materials from what a map's own materials reference;
   subscribed packs from the collection are installed at the next start, each for the maps or models it was made for.
3. **RTX starts only.** The file is a companion menu script (`lua/nativeloader/menu/pbr_note.lua`), which the RTX
   client module runs in the menu realm of an RTX start only ([ADR 0133](0133-the-multiplayer-notice-in-the-companion.md)),
   in line with [ADR 0206](0206-rtx-a-removed-loader-left-removes-itself.md): nothing of it appears in a start without
   RTX.
4. **Cheap while it waits.** The menu's `Think` decides each frame only whether the note is wanted; the screen size and
   the language (a file read when the companion's convar is empty) are looked at every two seconds, and the note is
   rebuilt only when either changed. A failed build is said once and not retried.

## Consequences

- Eleven new companion messages, translated into the six languages by Claude (not yet reviewed by a person).
- The note's placement at the top right can cover a corner of other menu pages (the server list, the add-on browser);
  "Hide" and "Don't show the note again" clear it. Not yet seen in the game: the PoC check is the user's call.
- Tested offline by `tools/tests/test_pbr_note.py` (the real script in a mocked menu realm).
