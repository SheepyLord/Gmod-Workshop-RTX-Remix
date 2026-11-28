# 0278. Workshop character updates follow the model in its pack

Accepted 2026-11-28 for task WU. The user's report: updates of their Workshop character packs did not reach the game
without a resubscribe, and Faelynn (Gym Uniform)'s head still sat forward after the corrected build arrived. Their
instruction for the work: Codex does the work, and Claude reviews, runs the game tests and publishes. Checked in two
PoC launches: one library entry, the player's choices moved, the old save loads.

## Context

Steam delivered the corrected Faelynn (Gym Uniform) in GF2 part A. The Hotloader installed it,
but the library still offered the old head and the saved Citizen and player models still used it.
A second problem affected revisions written to the same asset paths with the same byte counts.
The player accepts using the next launch when Steam finishes a download during a session.

## Decision

Identify a deployed pack by the owner of its add-on directory in the loader journal. Workshop
deployments use the Steam item ID, local packages use the outer package ID, and each includes the
add-on directory. Standalone archives use their mounted Workshop item ID and ordinary loose
add-ons use their physical folder. Within that pack use the author's item key, falling back to a
unique source path or the source filename in the item's terms. Store this identity at install.
For older records the previous journal generation can identify the former export directly.
When that generation is gone, an unchanged sibling can identify the pack if the old Workshop terms
also agree on its title. Ambiguous identities, local imports, adopted demo models and
models still supplied by another pack cannot establish a replacement.

Keep the old model available while its successor installs. After the new character checks out,
switch the library entry, keep personal library choices, and refit the published NPC, player and
hands carriers against the new mesh with their chosen role, scale and voice. Move the recent-use
time and record which previous player-model selectors correspond to the new carrier. A later
manual player-model selection takes precedence.

An old generated carrier can be referenced by a save outside the game directory. Keep its original
asset and immutable archive available for restoration, hidden from the library. A previous revision
without a live entity or a saved carrier goes through the existing cache cleanup. Multiplayer
restoration still requires server approval. A save whose earlier approval expired can use the
approved replacement from the mounted pack.

For updates within one asset ID, record the declared SHA-256 values of the character manifest and
model binary. A changed digest schedules installation even when file sizes and timestamps match.
Record the pending repair before moving files and clear it after validation. Unchanged files keep
their existing fast path. A loaded copy can continue to draw until the next game start.

## Verification

The install, publication and persistence harnesses exercise these paths in both Lua realms. The
field timeline and the two-build PoC procedure are in the [handover](../handover/workshop-updates-report.md).
