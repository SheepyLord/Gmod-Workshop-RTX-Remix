# topbr_harness.lua

Loads the packaged GPL ToPBR client driver under a fake GMod API. Checks syntax, diagnostics,
convar/command collisions, callbacks, independent game/world switches, hash retry and one-time
metadata submission, source-less queueing, and clear/requeue while preserving the off switch.
Usage: `luajit tools/tests/topbr_harness.lua <driver.lua>`. Reads only its driver;
no game, network or filesystem mutation. Exit 0 on success, nonzero on a failed assertion.

The driver includes the R12 panel under its existing trusted path; registration is exercised here,
and `game_pbr_panel_harness.lua` separately executes that exact marked section with Derma stubs.

R23 (the user's item 3): `RTXGamePBRProgress()` counts a queued imported game material as pending while
its native view says `waiting`, ends the batch once none is, and counts an unreadable view as finished.

Issue 6 ([ADR 0212](../../docs/decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md)): turning
`rtx_topbr_enabled` on queues the materials already drawn (`QueueMaterialsForProcessing`), so ToPBR needs no
map reload; turning it off queues nothing.

A character imported again (ADR 0263, the fixes'
[game-rescan](../../packages/fixes/licenses/oversized-skinning/game-rescan/README.md) patch): the hook
`RTXToPBR_GameRescan` listens to `MMDHL.Imported` and returns nothing. With two characters' materials submitted, the
import of one (its full asset id, 64 hex digits) asks `RescanGameSource` with its library entry's source and the prefix
`mmd/<the id's first 16 digits>/`, takes its materials out of the progress batch, and a pass at the same moment submits
them again (the other character's not), each counted once; the next pass submits nothing. A refused or failing
rescan submits nothing again; a module without `RescanGameSource` gets the submissions again only. An id that is not
64 lower-case hex digits (16 or 63 digits, upper case, other characters, not a string) and a library entry without a
source (or no library, no Model Hotloader) ask nothing and submit nothing again. Asset order follows LuaJIT's `next`,
so the checks hold in any order.
