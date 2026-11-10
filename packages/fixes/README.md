# RTX fixes package inputs

The GPL-2.0 fixes are imported from the user's fork; [LICENSE](LICENSE) applies. Binary payload
changes go through [`inputs.py import`](../../tools/inputs.py.md). Part notes and corresponding
source under `licenses/` are reserved documentation, excluded from the payload index. The package
builder includes the existing `licenses/oversized-skinning/` tree in the remixbinary add-on as its
native source bundle, including the R6 change below.

## Seamless Portals off the GetRenderMesh path (2026-11-10)

Imported 2026-11-10 with `inputs.py --file`; every other indexed input is unchanged
([ADR 0153](../../docs/decisions/0153-no-entity-hands-gmod-a-lua-mesh-to-draw.md)).

- `garrysmod/garrysmod/addons/GMod-Seamless-Portals-Remix/lua/entities/seamless_portal/cl_init.lua`: a local change
  (GPL-2.0, as the part is). A portal drew its frame (backface) with `self:DrawModel()` from `ENT:DrawStenciled`,
  through an `ENT:GetRenderMesh` that returned the portal's cylinder mesh scaled by its size, re-entering `ENT:Draw`
  through a `draw_model` flag. That is the path that crashes the material system's render thread under queued
  rendering (`mat_queue_mode 2`; `studiorender.dll+0x6603b`, ADR 0152, reproduced in the PoC with the Model
  Hotloader's static props). The entity has no `GetRenderMesh` now: the frame is the same mesh drawn by
  `ENT:DrawModelMesh` (the portal's world matrix scaled by its size) with the portal's material bound, before the flat
  face and the stencilled inside; `ENT:Draw` no longer re-enters itself. Checked without a game by
  [`tools/tests/seamless_portal_draw_harness.lua`](../../tools/tests/seamless_portal_draw_harness.lua.md), and
  `tools/tests/test_render_mesh_entities.py` fails on any Lua in the package whose `GetRenderMesh` returns something.

## R28: the light updater's draw list, no texture preload, the engine guard's crash switch

Imported 2026-11-10 (`inputs.py --file` for the two text files, `repo_builds.py refresh` for the modules); every
other indexed input is unchanged.

- `garrysmod/garrysmod/addons/remixbinary/lua/remixlua/cl/cl_rtx_light_updater.lua`: a local change (GPL-2.0, as
  the part is). `RenderLightUpdaters` drew every light's helper every frame (6.5-10.7 us a light: 1.1 ms of every
  frame on gm_construct, about 49 ms on a map with 4,606 lights). A helper's draw makes the engine set its four
  strongest lights there, and the Remix runtime drops a light the frame it is not set, except a point light out of
  view, which it keeps for 1000 frames. On a map with 256 lights or more the updater now works out once, from
  the map's world lights (NikNaks), which helpers can set steady point lights alone, and draws those only while
  such a light is in view, within 450 units of the eye or of a known dynamic light (a lamp, a `DynamicLight` from
  Lua, noted through a wrapper of that function and of the light object's `__newindex`, since the object cannot be
  read), and in turns, once in 120 frames; every other helper (a spot light's, a named or styled light's, a lamp's, and
  any that may set a light no helper of its own sets, such as a texture light, or the sun) every frame as before. It
  reads the runtime's options it relies on from `rtx.conf`. `rtx_lightupdater_all 1` (not saved) draws all of them as before, `-1` uses the list on every map;
  `rtx_lightupdater_status` prints the counts
  ([ADR 0144](../../docs/decisions/0144-the-light-updater-draws-what-the-runtime-needs.md); checked without a game by
  [`tools/tests/light_updater_harness.lua`](../../tools/tests/light_updater_harness.lua.md)).
- `garrysmod/garrysmod/cfg/autoexec.cfg`: `mat_forcemanagedtextureintohardware 0` in the RTX section, so it is one
  of the package's session convars: Source no longer draws every loaded texture once at the end of a load, which
  made the runtime create a GPU image for each
  ([ADR 0142](../../docs/decisions/0142-no-crash-snapshot-of-the-game.md)).
- `modules/gmcl_nlengineguard_win64.dll`, `modules/gmsv_nlengineguard_win64.dll`: rebuilt from
  [engine_guard](../../engine_guard/README.md) with `crash_report.cpp`: each realm's load switches Windows Error
  Reporting's crash and hang snapshots off for the game (ADR 0142). `tools/ci/pins.json` records the builds.

## Endfield NPC, weapon and item maps; game emission maps glow (after R25)

Imported 2026-11-09 with `inputs.py --file`; every other indexed input is unchanged
([ADR 0137](../../docs/decisions/0137-endfield-npc-weapon-and-item-maps.md),
[ADR 0138](../../docs/decisions/0138-imported-game-emission-glows.md)).

- `modules/gmcl_RTXFixesBinary_win64.dll` (5,519,360 bytes, SHA-256 `477c2266...859545`): the public base with
  the nine patches of `tools/ci/pins.json`, built with `tools/ci/build_modules.ps1 -Only fixes`. The eighth,
  [endfield-maps.patch](licenses/oversized-skinning/endfield-maps/endfield-maps.patch): ToPBR's imported game maps
  recognise Arknights: Endfield's NPC, weapon and item families (`T_npc_major_*`, `T_wpn_misc_*`,
  `T_item_widget_*`) by a `_P` under their `t_<word>_` prefix and pair them by exact name; UV matching and the
  conversion are unchanged ([source, measurements](licenses/oversized-skinning/endfield-maps/README.md)). The ninth,
  [game-emission.patch](licenses/oversized-skinning/game-emission/game-emission.patch): imported game materials
  with an emission map are written with `enable_emission = 1`, so their `_E` maps glow
  ([source, measurements](licenses/oversized-skinning/game-emission/README.md)). The seventh patch, R23's
  [wuwa-maps](licenses/oversized-skinning/wuwa-maps/README.md), gave Wuthering Waves characters their game's
  roughness and metalness.

Published 2026-11-09 UTC: `main` was pushed at `bb9d5ad`, rebased on the skills commits that had landed meanwhile.
The merge's hook built the package here and uploaded it to item 3829070317 as
**0.0.0-dev.20261109091040+1d2e5aab** (2,182,488,545 bytes, SHA-256
`85d98b215c6d5ad35983f55ae5cd8b679f1a10a27341d9ea23acd5004a00579d`); Steam's public record shows that size, updated
09:11:11 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub Action was started; the loader
is unchanged (0.16.0).

## R20-Q client-bootstrap refresh

The stored `modules/gmsv_nlrtxclient_win64.dll` is rebuilt from the current
[loader/client](../../loader/client/README.md) and `nl_core`, replacing the R4 build that rejected
the current `remix.performance_tier` configuration key in the menu realm. The Release native
checks and real menu/client lifecycle checks pass before its single final `inputs.py import`.
The new input is 460,800 bytes, SHA-256
`f23c711c4e6b3678661cbed45cf34d034d064b0444cd45c77a3e8b66851c508b`.
Native source allowlisting and immutable catalog policy are unchanged. Rebuild/import this module
when its linked config/catalog code changes; a local package build otherwise uses the stored input.

After R20 its entry in `tools/ci/pins.json` `repository_builds` records what it was built from
([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)):
`tools\check_repo.py` fails while `loader/client`, `loader/core`, LZMA, the GMod headers or the root
CMake files differ from the record, and `python tools\ci\repo_builds.py refresh` rebuilds it, imports
it if it is another image, and records it. A build of commit `a5a3ff1` in a folder of the same path
length is the same image as this one, so the first record kept it.

## R19 Lua inputs, ToPBR switches and the flashlight

Imported 2026-11-05 with `inputs.py --file`; every other indexed input is unchanged
([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)).

- `modules/gmcl_RTXFixesBinary_win64.dll` (5,512,192 bytes, SHA-256 `ba3fb505...4a0da`): the public
  base with the five patches, the fifth being [lua-paths.patch](licenses/oversized-skinning/autopbr/lua-paths.patch).
  Paths the module's Lua functions take stay inside the game (no network share, drive or `..`):
  ToPBR's output folder, game-map sources, VMT and VTF reads, Remix material and dome-light textures,
  and Remix options that name files. ToPBR turns on only while the player's `rtx_topbr_enabled` (world
  conversion) or `rtx_topbr_game_maps` (imported game maps) is on.
  [Source and rebuild](licenses/oversized-skinning/autopbr/Source.md).
- `modules/gmcl_rtxwater_win64.dll` (281,088 bytes, SHA-256 `970f9dbd...fe5a9`): Version 4 with
  [rtxwater-lua-input.patch](licenses/oversized-skinning/rtxwater/rtxwater-lua-input.patch): surface
  polygons of an even length of at least six, texture paths below the game folder.
  [Source and rebuild](licenses/oversized-skinning/rtxwater/Source.md).
- `remixlua/sv/sv_remix_flashlight.lua`: a 0.3 s cooldown per player on switches, colours coalesced to
  one broadcast per 0.1 s, and no flashlight where the gamemode or `CanUseFlashlight()` refuses one
  (the dead, spectators). `remixlua/cl/remixapi/cl_remix_flashlight.lua`: a repeated "on" replaces the
  player's light instead of leaking it.

## R8-B Backrooms native candidate (pending import)

The local source commit `7094baf6edf6797fd5c3f0b58ca668f9307b4906` ports the Backrooms
model-miss cache, lazy model-transform read and optional PAS visibility onto the packaged R6
source, preserving its oversized-skinning and memory-limit protections. It adds validation,
owned visibility restoration at module close and offline production-code regressions. The
existing remixbinary Lua already provides the add-on's lighting API and patch synchronization.
The DLL/PDB are built under `out/`; Claude imports the DLL after review. The package index and
binary inputs are unchanged by R8-B. See [source, pins, hashes and rebuild notes](licenses/oversized-skinning/backrooms/Source.md).
This layer is inside the already bundled `licenses/oversized-skinning/` source tree.

## R6 T5 memory-limit compatibility

The current module uses fixes source commit `a2c8dbc5e00e3effe49a8de9609dd1b8af34d552`, a single
commit on the preceding packaged source `b23c58fa72e8ac2d9a7dfb0bcad8b03fe247edbe`. The module
no longer submits unsupported resource-limit options at map load. The old Lua method is a
documented no-op that logs once when explicitly called, preserves the two numeric arguments and
`true` result, and never writes configuration. See the [source, pins and rebuild notes](licenses/oversized-skinning/memory-limits/Source.md).

## R6 T5 ToPBR compression

All 83 DDS files in `garrysmod/rtx-remix/mods/~gmod_topbr/textures` are now BC7_UNORM (linear):
33 normal maps and 50 roughness maps, all referenced as `colorSpace = "raw"`. Their names,
dimensions and 816 mip levels remain; the material files are unchanged. DDS size falls from
142,869,484 to 35,729,420 bytes (75%); xz input size falls from 16,454,204 to 15,000,576 bytes.
See [encoder, measurements and import instructions](licenses/topbr-bc7/README.md) and the
[per-file conversion record](licenses/topbr-bc7/conversion.json). Rendering acceptance belongs
to R6 integration; offline decoding alone does not prove the rendered look.

## R11 automatic PBR

The R11-B DLL is built from fixes `633fd5e000aca862a8ae58b5c722d678ac4fa053` on the shipped
R8/R11-A base, preserving the oversized/model/PAS and memory-limit fixes. It is 5,167,104 bytes,
SHA-256 `526a6584d4ab68e657b7f1cead25db88beb6cbfa568ad31f92028ddc3345f792`.
Only the rebuilt DLL and ToPBR client driver were imported, each with `inputs.py --file`; every
other indexed fixes input is retained. [Corresponding source and rebuild tests](licenses/oversized-skinning/autopbr/Source.md)
are nested in the existing bundled source tree. Vanilla ToPBR stays opt-in; imported game maps
have an independent default-on setting. R11-B retains successful game materials by live hotloader
texture identity when their source is unavailable, with complete DDS validation and persistent
record-version policy ([ADR 0093](../../docs/decisions/0093-cached-imported-game-materials.md)).
The second review restores once-per-worker texture resolution and keeps USD publication ownership
across restarts, retaining backups for foreign/edited files and missing/damaged ownership records.
Runtime patch 0020 supplies absolute authored-pack precedence
([ADR 0092](../../docs/decisions/0092-generated-fallback-mods-rank-last.md)).
