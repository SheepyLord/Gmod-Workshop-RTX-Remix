# 0222: The Workshop change notes carry the changelog, in full

- Status: Accepted 2026-11-14 (the user: "Update the standard, from now on the changelog should also be posted fully
  to the Steam workshop update log."); tooling and rules only, no package, loader or runtime change.
- Context: every upload of the distribution item 3829070317 ([ADR 0016](0016-one-workshop-item-kept-current.md))
  posted a one-line change note: `<version> from <commit> (<reason>)` for a development build from the hooks
  ([ADR 0108](0108-releases-built-on-github-by-hand-development-built-here.md)), the run and the `.gma`'s SHA-256 for a
  release (`--from-ci`). The item's change notes page told a player nothing about what had changed.

## Decision

1. **Every upload posts the update's changelog in full.** After that first line, the change note carries each entry
   of `CHANGELOG.md`'s `[Unreleased]` section that the uploaded commit has and the commit of the item's last upload
   lacked (`commit_sha` in `out\workshop\published.json`): added or reworded entries, word for word, in the
   changelog's order, each under its `###` heading. An entry is a top-level bullet (or paragraph) with its wrapped and
   nested lines. A commit that did not change the package uploads nothing, so its entries go with the next upload.
   Without a usable record (another item, a commit the clone does not have), the entries the uploaded commit added
   over its first parent. `tools/publish_workshop.py` does this for development builds and releases alike.
2. **Steam's markup, in ASCII.** A bullet's wrapped lines become one line, nested bullets stay nested, `**bold**`
   becomes `[b]`, a link to the web `[url=...]`, a link into the repository its text; code marks go.
   `gmpublish.exe` reads its command line in the system's ANSI code page (it imports `GetCommandLineA`), so anything
   else would arrive garbled: dashes, quotes, arrows and the like are spelled in ASCII, accents lose their marks.
3. **Nothing is cut.** Steam keeps 8000 characters of an update's note (`k_cchPublishedDocumentChangeDescriptionMax`).
   What one note (held to 7800) cannot hold goes up in further notes, `<version> (changelog, part 2 of 3)`, each by
   uploading the same archive again: Steam uploads only changed chunks, so a repeat costs the time to read the
   archive (the 2 GB package's last upload sent 16.3 MB and took 25 s, 2026-11-14). An entry longer than a note is
   cut after a sentence. More than eight notes end with a pointer to the rest of `CHANGELOG.md` on GitHub, so a lost
   record cannot post dozens of updates.
4. **The changelog is written for players too.** Its entries are public on the Workshop from now on: each says first
   what changed for the player, then as much detail as before. They hold nothing private (the repository is public
   already, AGENTS.md rule 7).
5. `python tools\publish_workshop.py --show-notes` prints the notes the next upload of `HEAD` would post, without
   building.

## Consequences

- The item's change notes page lists every change with each update; the version line still names the commit.
- A round with a long changelog posts two or three updates of the same content within a minute; the item's
  subscribers get nothing new to download from the repeats.
- `published.json` records `notes` (and `notes_posted` when there were several); a further note that fails is logged
  and the upload still counts, since the item holds the new content.
- Characters outside ASCII in the changelog reach the Workshop as their nearest ASCII spelling.
