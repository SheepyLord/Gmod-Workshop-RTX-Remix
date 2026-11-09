# astra_companion.py

Converts a map's **Astra RTX companion** into the two halves of a native-loader content pack: a Lua
add-on folder and a Remix mod folder, which `tools\package_content.py` then packs.

An Astra companion is a Workshop `.gma` made in September 2026 for the old route: the RTXLauncher
install with the Astra startup loader (a `d3d9.dll` proxy plus `astra_rtx_prepare_assets.exe` under
`bin\win64\astra-startup\`) and the `AstraRTXBridge` Lua provider. It stores its Remix mod as data GMod
mounts (`data_static/astra/<map>/rtx/*.dds.dat`, `mod.usda.dat`, `startup.json`) and a large client
runtime that publishes it through the bridge, with PNG atlases as a fallback. The native loader
removes that loader (legacy migration) and has no bridge, so on the new project such a companion's
Lua waits for the bridge forever and no Remix material loads. Two exist: Cathedral of Mercury RTX
(3797839157) and the Korolevskiy Theater's PBR resources (3803057911).

```powershell
$K = '<repo>\skills\workshop-content-pack\scripts'
python -I "$K\astra_companion.py" --gma <companion.gma> --profile "$K\astra_companion\<map>.json" --out <build folder> --bc4
```

## What it does

1. **Reads the archive** (plain GMAD v1-v3, the form Steam keeps in `workshop\content\4000\<id>\`):
   the one `data_static/astra/<map>/rtx/startup.json` (version 1), the profile's `index.json` (or the
   one `data_static/<folder>/<map>/rtx/index.json`), checks both (versions, the map's name, texture
   descriptors `textures/<sha256>.dds`, hash aliases of 16 hex digits).
2. **Writes the Remix mod** `<out>\mod\<mod>\`: `mod.usda` from `mod.usda.dat` and every texture the
   layer references from its `.dds.dat`, each one's size and SHA-256 checked against `startup.json`
   first. Every `./textures/<sha>.dds` the layer names must be among the payloads, every hash alias of
   `index.json` must have its `over "mat_<HASH>"`, and no hash may be overridden twice.
3. **`--bc4`**: a texture whose every use is an input Remix reads one channel of
   (`reflectionroughness_texture`, `metallic_texture`, `height_texture`) and that is stored as
   `BC7_UNORM` is re-encoded as `BC4_UNORM`, half its size on disk and in video memory. Each mip of
   the original is decoded (Pillow's BCn decoder) and its red channel encoded again (a range fit, then
   two least-squares endpoint passes), so the original mip chain is kept; the file is renamed by its
   new SHA-256 and `mod.usda`'s references follow. A map whose worst mip of 16 px or more falls below
   `--bc4-min-psnr` (default 36 dB, against the BC7 decode) keeps its BC7: detail BC4's eight levels a
   block cannot hold (sharp metal/non-metal edges in the middle mips).
4. **Writes the Lua add-on** `<out>\addon\<addon>\`:
   - `lua/autorun/<addon>.lua`: on the server it sends the files to clients; on the client, on the
     profile's map only, it calls the runtime with the profile;
   - `lua/<addon>/runtime.lua`: a copy of [`astra_companion/runtime.lua`](astra_companion/runtime.lua.md);
   - `lua/<addon>/profile.lua`: what the runtime does on this map (below);
   - `lua/<addon>/hashes.lua`: per material the hash aliases the mod replaces, read only by the
     `<prefix>_status` coverage check;
   - `addon.json` from the profile.
5. **Leaves out** what only the old route needed: the PNG fallback atlases, `startup.json`,
   `index.json` and every old Lua file.
6. **`<out>\report.json`**: the counts, what became of each group of the companion's files
   (`converted_to_mod`, `replaced_lua`, `left_out_png_fallback`, `read_manifests`), the lights left
   out by the companion itself, and every BC4 conversion with its PSNR (`bc4`) or why it kept BC7
   (`bc4_kept`). The same summary, without those lists, goes to stdout.

## The profile

`astra_companion/<map>.json` holds what the old Lua did by hand, as data, with notes on its source.

| Key | |
|---|---|
| `schema` | `1` |
| `map`, `addon`, `mod`, `title`, `prefix`, `global` | the map; the add-on and mod folder names (`a-z 0-9 _`); the display name (ASCII); the console prefix (`<prefix>_status`, `<prefix>_enable`, `<prefix>_reload`); the Lua global of the runtime |
| `index` | optional: the path of the companion's `index.json` |
| `sky_owner` | answer the companion's `NativeLoaderSkyOwner` hook (the map keeps its own sky unless the player chose theirs) |
| `fog_owner` | answer `NativeLoaderRemixFogOverride` while the runtime runs (the weather leaves `rtx.volumetrics.*` alone) |
| `sky_keys` | the options left to the companion while the player's sky is in charge (default `rtx.skyMode`) |
| `clear_light2rtx` | call `Light2RTX.Clear()` at the start (default true) |
| `remix` | ordered `[key, value]` Remix options set while the map is loaded; `rtx.ignoreGame*` only while the add-on's lights exist |
| `runtime_defaults` | the runtime's own default of a key the RTX package's layer does not set |
| `engine` | `[convar, value]` set from the file's load and put back after the map (`rtx_api_map_lights_autospawn 0`) |
| `tint` | `keys` (`$color`, `$color2`), `materials` (`"pbr"`: every material of `index.json`, or a list), `recompute` |
| `categories` | each `{name, flag, materials}`: `flag` one of `particle`, `animated_water`, `legacy_emissive`; `materials` a list or `"baked_fallback"` (the index's UnlitGeneric bakes) |
| `hooks_off` | `[event, id]` hooks of the base map removed while the runtime runs |
| `addon_json` | the add-on's `addon.json` |

The restore value of each `remix` key comes from `--defaults-layer` (default: this repository's
`packages\runtime\layers\classic_remix_defaults.conf`, the RTX package's Remix defaults layer), else
`runtime_defaults`; a key with neither is refused.

**Lights.** `index.json`'s `lighting.lights` become RemixLight API arguments as the old runtime made
them: types `sphere`, `rect`, `disk`, `distant` with finite values and unit axes (anything else is
refused); `volumetricRadianceScale` defaults to 1; a distant light's radiance (Cycles' emitted
radiance) is multiplied by sin(half angle)^2, since the API divides by it, and its cone widened to at
least 0.0573 degrees after the energy is fixed. The companion's `unsupported` lights stay out.

## Options

`--gma` and `--profile` and `--out` are required. `--bc4`, `--bc4-min-psnr DB`, `--defaults-layer FILE`,
`--force` (replace an earlier conversion in `--out`: only a folder holding a `report.json` is removed).

## Requirements, side effects, exit codes

Python 3.10+ with `-I`; `--bc4` needs numpy and Pillow (the system Python has both). Reads the
archive, the profile and the layer; writes only `--out` (which must be empty, or an earlier conversion
with `--force`). Exit 0 on success, 1 when a check refuses (the reason on stderr), 2 for a bad command
line. A refused conversion can leave a partial `--out`; run it again with `--force`.

Measured on the two companions (2026-11-09): Cathedral of Mercury 680 textures, 2.21 GB, nothing to
re-encode (its single-channel maps were BC4 already), 2 s; the Korolevskiy Theater 513 textures, 189
roughness and metallic maps BC7 to BC4 (236 MiB less, worst kept mip 36.1 dB, 24 kept as BC7),
1.10 GB, 107 s.

Tests: [test_astra_companion.py](test_astra_companion.py.md).
