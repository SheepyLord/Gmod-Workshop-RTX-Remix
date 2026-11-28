# 0277. Read only BSP collision for broken glass

Accepted 2026-11-28 for task GL. The user's report: "For the gm_csgoagency (and other large maps), an error is
thrown". Their instruction for the work: Codex does the work, and Claude reviews, runs the game tests and publishes.
Checked in the PoC on `gm_csgoagency`: Jolt instead of the capped fallback, and no error line.

## Context

The client used to pass the entire mounted BSP to Jolt's importer. The 256 MiB input limit
rejected Agency even though its collision lumps total 1.71 MiB. An embedded pakfile and two
lighting lumps account for 297.21 MiB of the map. [Measurements](../RESEARCH.md#broken-glass-on-large-maps-2026-11-28)

## Decision

Lua opens the map through GMod's `GAME` search path. The glass module asks Lua for byte ranges
synchronously, so Workshop-mounted maps and loose maps use the same code. The module validates the
original directory and builds a compact VBSP containing the data its existing worker understands.
This keeps engine file access on the client thread and leaves a single geometry parser for both
the range and byte-string interfaces.

Static-prop directory entries contain absolute BSP offsets, even when their data is outside the
game lump. Resolve those offsets against the original file and rewrite them in the compact copy.
Inflate a compressed game directory to discover its entries. Regular collision lumps and compressed
static props reach the worker in their original encoding.

Limit both stored collision bytes and declared expansion to 256 MiB. Validate ranges, LZMA lengths,
dictionary size and remaining expansion before allocating the corresponding buffers. The compact
directory has a fixed 1,036-byte header allowance. The existing shape, record, work and cancellation
limits still apply.

## Consequences

Older Lua can use the existing byte-string entry points. Updated Lua detects an older DLL and uses
its bounded byte-string import for a map it can take. On a larger map it explains that a restart
loads the updated module. A failed import uses the capped client physics and reports its reason once
on the ordinary console channel for that map.
