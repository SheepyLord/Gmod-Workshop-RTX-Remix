# RTX fixes package inputs

The GPL-2.0 fixes are imported from the user's fork; [LICENSE](LICENSE) applies. Binary payload
changes go through [`inputs.py import`](../../tools/inputs.py.md). Part notes and corresponding
source under `licenses/` are reserved documentation, excluded from the payload index. The package
builder includes the existing `licenses/oversized-skinning/` tree in the remixbinary add-on as its
native source bundle, including the R6 change below.

## The flashlight's automatic brightness (2026-11-14)

The user's request ([ADR 0208](../../docs/decisions/0208-the-rtx-flashlights-automatic-brightness.md)): the
flashlight adjusts its brightness to what it lights, on by default. Imported with `inputs.py --file`; every other
indexed input is unchanged.

- `remixlua/cl/remixapi/cl_remix_flashlight.lua`: seven traces across the beam each frame make one distance; the light
  eases to (distance / `rtx_flashlight_auto_distance`)^(2 x `rtx_flashlight_auto_strength`), within 1/64 and
  `rtx_flashlight_auto_max`, down fast and up gently; the haze is not boosted; `rtx_flashlight_auto 0` is the light as
  before. The menu's Automatic Brightness section and Reset.
- `remixlua/cl/remixapi/cl_remix_light_gain.lua` (new): the distance maths, this project's own code (MIT), byte for byte
  the character motion importer's `mmd_vmd_npc/cl_light_gain.lua`, which its dance light uses
  ([ADR 0209](../../docs/decisions/0209-the-dance-lights-uniform-lighting-and-options.md)).

## The fixes never read a queued draw's renderable (2026-11-12)

The VR work's crash triage found a crash in the fixes, not in VR
([ADR 0192](../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)): on the queued render thread
the prop lighting hook called `GetModel()` through an entity the main thread had already deleted, and the game ended
at instruction pointer 0. Imported 2026-11-12 with `inputs.py --file`; every other indexed input is unchanged.

- `modules/gmcl_RTXFixesBinary_win64.dll` (5,518,848 bytes, SHA-256 `a2f091ab...743ab`): the public base with the ten
  patches of `tools/ci/pins.json`, built with `tools/ci/build_modules.ps1 -Only fixes`. The tenth,
  [queued-draws.patch](licenses/oversized-skinning/queued-draws/queued-draws.patch): the lighting hook takes the
  model's bone count from studiorender's own state and never reads the renderable; the lighting rule is unchanged;
  the skinning hooks read an entity's model-to-world matrix only in the two diagnostic transform-chain modes that use
  it ([source, tests](licenses/oversized-skinning/queued-draws/README.md)).

## Material colours above 1 capped for Remix (2026-11-11)

The user's rule ([ADR 0190](../../docs/decisions/0190-material-colours-above-1-capped-for-remix.md)): "in Remix,
`$color` should be capped at 1 wherever it exists". `modules/gmcl_nlengineguard_win64.dll` and
`modules/gmsv_nlengineguard_win64.dll` were rebuilt from this repository's `engine_guard/` (MIT, not part of the
GPL-2.0 fixes) and imported with `repo_builds.py refresh`; every other indexed input is unchanged. The engine guard now
wraps `shaderapidx9.dll`'s four float colour functions in Remix starts and clamps each component to [0, 1] before the
engine turns it into the 8-bit texture factor (which wrapped: 1.5 became 0.49). See
[engine_guard/README.md](../../engine_guard/README.md).

## gm_construct_in_flatgrass_rtx removed (2026-11-10)

The user's answer "Remove it too" ([ADR 0155](../../docs/decisions/0155-gm-construct-in-flatgrass-rtx-leaves-the-rtx-package.md)):
the fixes' other map left the index and the part, its four files under `garrysmod/garrysmod/addons/remixbinary/maps/`
(`gm_construct_in_flatgrass_rtx.bsp`, `.prt`, `.vmf`, `.vmx`; it had no thumbnail or Remix layer). The folder is gone;
every other indexed input is unchanged. [`test_removed_content.py`](../../tools/tests/test_removed_content.py.md)
keeps it out of a later import from the fixes repository.

Published 2026-11-11 UTC: `main` was pushed at `a50fc0b` after `tools	est.ps1 -Config Release` passed (in a
short-path worktree) and a package built from that commit differed from the published one only by the four files
and the manifest. The merge's hook uploaded it to item 3829070317 as **0.0.0-dev.20261111002201+f3f533a6**
(2,083,860,807 bytes, SHA-256 `e17d4d0e2d54bb4fe6c5570fc4f9ecc517eea0a46548835832a76a4f5f514901`); Steam's public
record shows that size, updated 00:22:55 UTC. The push's hook found the same inputs and uploaded nothing. No
GitHub Action was started; the loader is unchanged.

## gm_construct_rtx removed (2026-11-10)

The user's request ([ADR 0154](../../docs/decisions/0154-gm-construct-rtx-leaves-the-rtx-package.md)): the map
gm_construct_rtx confused players beside the gm_construct RTX remaster of GMod's own map. Its five files under
`garrysmod/garrysmod/addons/remixbinary/maps/` (`gm_construct_rtx.bsp`, `.png`, `.prt`, `.vmf`, `.vmx`) and
`garrysmod/rtx-remix/mods/base_mod/maps/gm_construct_rtx.usda` left the index and the part. `base_mod/mod.usda`
was imported with `inputs.py import --file` without that sublayer (514 bytes, SHA-256 `d037f80f...7eb682`); every
other indexed input is unchanged. The fixes repository still has the map: a part imported from it again must
leave it out, which [`test_removed_content.py`](../../tools/tests/test_removed_content.py.md) checks.

Published 2026-11-10 UTC: `main` was pushed at `e2978c0` after `tools\test.ps1 -Config Release` passed (in a
short-path worktree) and a package built from that commit differed from the published one only by the six files
and the two edited ones (`base_mod/mod.usda`, the manifest). The merge's hook built the package here and uploaded
it to item 3829070317 as **0.0.0-dev.20261110235744+da03eba6** (2,119,614,344 bytes, SHA-256
`b70226a752a62aa40786a51ec1a1a58546bcc358060aca610b5e3d3c41ad989b`); Steam's public record shows that size, updated
23:58:30 UTC. The push's hook found the same inputs and uploaded nothing. No GitHub Action was started; the loader
is unchanged.

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
  ([ADR 0154](../../docs/decisions/0142-no-crash-snapshot-of-the-game.md)).
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
