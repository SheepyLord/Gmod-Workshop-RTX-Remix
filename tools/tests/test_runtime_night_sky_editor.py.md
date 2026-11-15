# test_runtime_night_sky_editor.py

The regression test of the night sky editor's runtime side (runtime patch 0099,
[ADR 0227](../../docs/decisions/0227-the-night-sky-editor.md)): each layer of the night sky image has a brightness and a
colour of its own, the constellations' bright stars are a layer beside the nebula, and the shooting stars have a rate
and a brightness. Part of `tools\test.ps1` (the `tools` folder's Python tests).

- `RuntimePatchTests.test_the_layers_unit_test_from_the_patch`: takes `rtx_night_sky_layers.h` and
  `tests/rtx/unit/test_night_sky_layers.cpp` whole from the committed patch, compiles them with MSVC
  (`/std:c++latest /W4 /WX`, as the runtime builds) under `out\tmp` and runs the test: a brightness of 1 is weight 1 and
  the image's clamp at 1; a layer alone scales by its brightness in linear light; 0, negative and not-a-number turn a
  layer off; brightness and colour are held to 8 and 2; the clamp follows the brightest layer above 1; 1.2 shooting
  stars a minute is the former 8 % of four-second slots; the constellations' file beside the nebula's
  (`nebula.dds` -> `nebula_constellations.dds`, the low tier's `nebula_4096_constellations.dds`). Skipped without the
  MSVC Build Tools.
- `RuntimePatchTests.test_the_options_and_their_ranges`: the four `starMap*Brightness` (1, 0-8) and `starMap*Saturation`
  (1, 0-2) options, `shootingStarsPerMinute` (1.2, 0-15) and `shootingStarBrightness` (1, 0-8); no new path option
  (Lua cannot choose the constellations' file any more than the nebula's).
- `RuntimePatchTests.test_the_arguments_are_per_pixel_and_zeroed_in_the_lut_key`: the twelve new `AtmosphereArgs`
  floats (three whole 16-byte rows) are each zeroed in `normalizeForSkyLutCache`; the two new texture flags.
- `RuntimePatchTests.test_the_constellations_are_a_layer_beside_the_nebula`: binding 222 in the common set and the
  atmosphere range, its texture loaded from the nebula's path and bound, a layer at 0 neither drawn nor kept, and every
  layer off a night without stars rather than the procedural one.
- `RuntimePatchTests.test_the_sky_weighs_each_layer`: in `atmosphere_sky.slangh` each layer's colour and weight, the
  constellations without the galaxy's and nebula's wait for deep night, the sum held at `starMapCeiling`, the image's
  night chosen by its own flag, the shooting stars' chance and brightness from the options.
- `RuntimePatchTests.test_rtx_options_md_has_the_new_rows`: the generated table's rows for the new options.
- `PackageTests.test_the_package_carries_the_split_layers_in_every_tier`: `packages/runtime` holds the nebula alone and
  its constellations beside it, at 8192 and (for the low tier, whose layer names only the nebula) 4096.

```powershell
cd tools; python -m unittest tests.test_runtime_night_sky_editor -v
```

Exit code: unittest's (0 when every test passes or is skipped).
