# test_astra_companion.py

Tests [`astra_companion.py`](astra_companion.py.md) on a synthetic Astra companion it builds itself (no
game files): a GMAD v3 archive with `startup.json`, an `index.json` (two materials with two hash
aliases each, a distant and a sphere light, a light the companion left out, a baked fallback), a
`mod.usda.dat`, three BC7 textures made of real BC7 mode 6 blocks (a roughness ramp, an sRGB albedo, a
map shared by a metallic and an emissive input), an old Lua file and a PNG atlas.

```powershell
cd skills\workshop-content-pack\scripts
python -I -m unittest discover -v -p "test_astra_companion.py"
```

| Test | Checks |
|---|---|
| `test_plain_conversion_keeps_every_payload` | the mod's textures and `mod.usda` byte for byte; the report's counts and left-out groups; the add-on's files; `runtime.lua` copied unchanged |
| `test_lights_in_remix_units` | a distant light's radiance times sin(half angle)^2, its cone widened to the minimum, `volumetricRadianceScale` kept or 1; a light with skewed axes refused |
| `test_bc4_for_single_channel_maps_only` | only the roughness map becomes BC4 (DXGI 80, the same size and mip count, renamed by its SHA-256, `mod.usda` follows); the albedo and the map shared with an emissive input stay; every mip of the BC4 within 10 levels of the BC7 decode |
| `test_low_psnr_keeps_bc7` | a map under `--bc4-min-psnr` keeps its BC7 and is listed in `bc4_kept` |
| `test_profile_data` | restore values from the layer and from the profile's runtime defaults; `baked_fallback` resolved; category flags as numbers; the companion's left-out light not in the profile |
| `test_refusals` | a payload whose SHA-256 differs, a texture `startup.json` lacks, a hash alias without an override |
| `test_output_rules` | a non-empty `--out` without `--force`; `--force` only on an earlier conversion; a profile for another map |
| `Bc4Test` | constant, binary and two-level blocks exact; random data within range/14 of each block; a smooth map above 45 dB |
| `LuaTextTest` | Lua string escapes (three-digit decimal escapes, so a following digit stays apart), numbers, keyword keys, a non-finite number refused; a UTF-8 string written as Lua reads back the same in LuaJIT |
| `RuntimeTest.test_harness_scenarios` | [`astra_companion_harness.lua`](astra_companion_harness.lua.md) passes every scenario on the converted add-on |

numpy and Pillow are needed for all but the light test (skipped otherwise); LuaJIT for the harness
(found on `PATH` or in `%LOCALAPPDATA%\Programs\LuaJIT\bin`, skipped otherwise). Writes only a
temporary folder under `TEMP`, removed afterwards.
