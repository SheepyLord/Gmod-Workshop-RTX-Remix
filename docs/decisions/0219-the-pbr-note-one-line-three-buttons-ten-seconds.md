# 0219: The PBR note: one line, three buttons, ten seconds

- Status: Accepted 2026-11-14 (the user's request); supersedes the card, the note's text and the way the collection
  opens of [ADR 0217](0217-a-main-menu-note-on-pbr-for-maps.md); its placement, RTX-only start, keyboard rule and
  per-frame cost stand.
- Context: the user, on a screenshot of ADR 0217's note with an arrow on "Open the collection": "The PBR materials for
  maps menu does not work. Change title to "Obtaining more PBR resources". Remove the maps without PBR button. Replace
  it with the Hide button. Change it with just 1 line of text as summary. Make it hide automatically after 10 seconds.
  Add a button to hide it forever." The button asked Steam's overlay first (`steamworks.ViewFile`), which shows
  nothing where the overlay is off or not ready, and the call reports no failure, so `gui.OpenURL` was never tried.

## Decision

1. **The note is a title and one line.** "Obtaining more PBR resources", then "Demo PBR packs for maps are in
   SheepyLord's RTX Remix collection on the Workshop." The note is as wide as that line (at most the screen less its
   margins), in each of the companion's languages.
2. **Three buttons: Open the collection, Hide, Don't show again.** The explanation card of ADR 0217 and its "Maps
   without PBR" button are gone. Hide closes the note until the next start; Don't show again keeps it closed for good
   (the menu's cookie `nativeloader.pbr-note` = `dismissed`, as before); `nativeloader_pbr_note_reset` brings it back.
3. **The collection opens through `gui.OpenURL`.** That is GMod's own route: Steam's overlay browser when the overlay
   is on, otherwise GMod's prompt to open the address in the system browser (`lua/menu/openurl.lua`). Steam's file view
   (`steamworks.ViewFile`) is the fallback only where `gui.OpenURL` is missing or fails; the console line names the
   address in every case.
4. **It hides itself after ten seconds on screen.** The time counts only while the note is shown on the main menu and
   the pointer is not over it, so a player reading or reaching for a button keeps it. `nativeloader_pbr_note` shows it
   again for ten seconds (unless Don't show again was chosen).

## Consequences

- Three new companion messages, translated into the six languages by Claude (not yet reviewed by a person); the
  card's eight messages are gone from the catalogs.
- What a map without PBR looks like is no longer explained in the menu; the guide and the Workshop pages carry it.
- Tested offline by `tools/tests/test_pbr_note.py` (thirteen scenarios of the real script in a mocked menu realm) and
  seen in the PoC's main menu at 1280x720 (`out/qa-poc/issue1-final/02-menu/menu.png`).
