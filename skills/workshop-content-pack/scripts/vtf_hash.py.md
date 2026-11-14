# vtf_hash.py

A module, not a command: the Remix texture hashes of Source VTFs, and the VTFs of every container a
map's textures come from. [rekey_mod_hashes.py](rekey_mod_hashes.py.md) and [fit_mod.py](fit_mod.py.md)
import it. Needs `xxhash` (the system Python has it); the rest is the standard library.

| Function | Does |
|---|---|
| `texture_hashes(blob)` | `[(xxh64, xxh3)]` as 16 upper-case hex digits, for every frame's top mip and every candidate upload layout |
| `iter_vtfs(path)` | `(name, blob)` of every VTF in a Workshop `.gma`, a legacy LZMA `.bin` (decoded in memory), a `.bsp` (its pakfile, lump 40), a `*_dir.vpk` (only `materials/`; data in the dir file or the numbered archives), or a folder (its `.vtf`, `.gma` and `.bsp` files) |
| `source_table(path, cache)` | `[[xxh64, xxh3, width, height]]` for one source; `cache` keeps it per path, size and time |
| `load_cache(path)`, `save_cache(path, cache)` | the cache as one JSON file (written atomically) |
| `Vtf(blob)` | header facts: size, flags, frames, faces, format, mip count, where the high-res data starts (7.0-7.5 layouts, the 7.3+ resource table) |

## What is hashed

The runtime hashes the CPU copy of the top mip as the game uploaded it (`HashTextureData`, `d3d9_texture_hash.h`):
XXH64 with seed 0 when `rtx.useObsoleteHashOnTextureUpload` is True, which the RTX package's classic defaults set,
otherwise XXH3-64, Remix's default. Block-compressed VTFs (DXT1, DXT3, DXT5, DXT1 with one-bit alpha) go up as
stored. Uncompressed ones are converted by the game first; where the layout is not certain the module returns
several candidates, all hashed both ways:

| VTF format | Candidates (first is the expected one) |
|---|---|
| RGBA8888 | BGRA with an alpha flag (0x1000, 0x2000), else BGR0 (the runtime hashes the pad byte as 0); the other as second |
| ABGR8888, ARGB8888 | BGRA, BGR0 |
| BGRA8888 | as stored, BGR0 |
| BGRX8888 | BGR0, as stored |
| RGB888, BGR888 (and the bluescreen variants) | BGR0, BGR with 255 as the fourth byte, as stored |
| everything else (I8, IA88, A8, UV88, RGBA16161616F, the 16-bit formats) | as stored |

A wrong candidate costs nothing: both hashes come from the same bytes, so a candidate whose XXH3 matches a
mod's material gives that texture's XXH64 exactly, and the others match nothing.

Checked (2026-11-12) against rpai's `remixhash.predict` on the 1,131 VTFs of three Workshop maps: the same
XXH64 for all 726 both read (DXT and RGBA8888); this module also reads the 405 in BGR888, RGBA16161616F,
BGRA8888 and I8. On the 2026-11-12 maps, sources of the map item plus GMod's, HL2's and CS:S's VPKs explained
418 of Valley View Mall RTX's 420 materials (323 with the map's DXT and RGBA8888 textures alone).

No side effects besides `save_cache`. Tests: [test_rekey_fit.py](test_rekey_fit.py.md).

## Provenance

Written by Claude for this user on 2026-11-12. The VTF, VPK and GMA layouts follow the Valve Developer
Community's documentation and this repository's `tools/gmapack`; no third-party code.
