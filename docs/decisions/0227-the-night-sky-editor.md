# 0227: The night sky editor

- Status: Accepted 2026-11-15 (the user's request; the in-game checks in the report)
- Decided by: the agent, on the user's request: "make skybox enhancement, add a sky editor in the tab to allow user to
  customize how each element in the night sky looks (allow changing brightness of stellar elements). Note if the night
  sky is a whole picture, don't proceed and report honestly". Which elements, which controls and how they reach the
  runtime were the agent's choice.
- Builds on: [0031](0031-physical-sky-time-and-weather.md) (the companion drives the physical sky),
  [0032](0032-real-moon-stars-eclipses-and-fog-presets.md) (the real Moon and the night sky image),
  [0064](0064-performance-tier-defaults.md) (the low tier's 4096 sky textures),
  [0139](0139-the-sky-without-a-horizon.md) (a look setting that reaches a map's own sky without taking it over).
- Runtime patch: `runtime/patches/0099-Atmosphere-the-night-sky-editor-each-layer-on-its-ow.patch`
  ([runtime/README.md](../../runtime/README.md)); report: [night-sky-editor-report.md](../handover/night-sky-editor-report.md).

## Context

**Is the night sky one picture?** Not quite, and not in the way that would stop an editor. The runtime draws the
night from parts (ADR 0032; RESEARCH.md, "The night sky editor"):

- the night sky image, three textures sampled on their own through the Skyrim mod's sky-mesh mappings: a star layer
  (small sharp stars tiled over two hemispheres), the galaxy band (the Milky Way) and a nebula sphere;
- the real Moon (its own maps), the airglow (a colour times the weather's brightness), the shooting stars (a hash per
  four-second slot), and, as the other choice, the procedural stars with their own Milky Way glow.

But the shader added the three image layers in gamma space and scaled the sum with one brightness
(`starMapBrightness`), so no layer could be changed alone, and **the mod's constellations were baked into the nebula
picture** by `bake_nightsky.py`: their bright blue and violet stars could only brighten and dim with the nebulae.
Within the star layer the stars are one picture: single stars cannot be told apart, so the layer's brightness and
colour are what can change.

The constellations could come apart: the mod's files are still here (`out\downloads\nightsky8k`), and the bake knows
their 58 triangles. Their layer is sparse: 71,905 of the nebula map's 67 million texels carry light (0.107 %).

## Decision

1. **Each layer of the night sky image has a brightness and a colour of its own** (runtime patch 0099):
   `rtx.atmosphere.starMap{Star,Constellation,Galaxy,Nebula}Brightness` (1, 0-8, a multiple of the image's) and
   `...Saturation` (1; 0 grey, 2 twice as strong). The shader still adds the layers in gamma space, as Skyrim does, and
   decodes the sum: a brightness b becomes the gamma-space weight b^(1/2.2), so a layer alone scales by b in linear
   light. The colour moves each layer's gamma-space value from its grey (Rec. 709 weights) or away from it. The sum is
   still held at the image's white, 1; a layer brightened past 1 lifts that limit to its weight, so it can reach its own
   brightness. At the defaults the image is as it was. `rtx_night_sky_layers.h` holds the arithmetic,
   `test_night_sky_layers.cpp` tests it.
2. **The constellations are a layer of their own.** `bake_nightsky.py` writes the nebula alone and
   `nebula_constellations.dds`, the constellations in the nebula's mapping and size (BC1: mostly black, point-like stars;
   44.7 MB with mips, 81 KB with xz). The runtime finds it beside the nebula's file by name (`<name>_constellations.dds`;
   the low tier's `nebula_4096.dds` gives `nebula_4096_constellations.dds`) and binds it at 222, a slot no pass uses.
   No new path option: the RTX fixes refuse Remix's texture paths from Lua (R19), and a sidecar of a refused option
   needs no new entry there. The constellations come out with the stars in the twilight; the galaxy and the nebulae keep
   waiting for deep night (R17). The default look is the old one to a mean of 1e-5 (gamma), a few texels on bright
   constellation stars differing by up to 0.11 (BC1 against BC7).
3. **A layer at brightness 0 is neither drawn nor kept**: its texture is freed and loaded again when turned up (a
   hitch while it loads), so hiding the nebulae saves 89.5 MB of video memory. The image's night has its own flag
   (`SKY_TEXTURE_NIGHT_IMAGE`): with every layer at 0 the night has no stars at all, rather than the procedural field,
   which stays only while no layer's file could be loaded.
4. **The shooting stars** keep their look, with two options: `rtx.atmosphere.shootingStarsPerMinute` (1.2, the former
   fixed 8 % of four-second slots; 0-15, at most one a slot) and `shootingStarBrightness` (1, 0-8).
5. **The arguments are per pixel**: three new 16-byte rows of floats at the end of `AtmosphereArgs`, zeroed in
   `normalizeForSkyLutCache`, so a slider re-bakes nothing. `RtxOptions.md` has their rows. They are not in the Remix
   menu (Alt+X), where the star map's options never were; the companion is their interface.
6. **The companion's Night sky editor** (`nativeloader_sky.lua`), a page beside "Sky and weather" in the RTX Remix tab:
   Go to night, Time passes and the Night sky choice; the image's layers (all of them, then each layer's brightness and
   colour); the simulated stars (brightness, density, twinkle: `starBrightness`, `starDensity`, `starTwinkleSpeed`); the
   moon (brightness: `moon0.brightness`, its disc and its light on the map; size: `moon0.angularRadius`; glow:
   `haloMoonBrightness`; earthshine: `moon0.darkSideBrightness`); the shooting stars; the night glow (the weather's
   airglow); Reset the night sky. Each is a saved client setting and a multiple of the element's own look, except the
   moon's size (degrees across, 1.6 as before) and the shooting stars (a minute).
   - **The moon's size keeps the night's light**: the moonlight on the ground scales with the disc's area, so the
     companion sends `surfaceMoonBrightness` times (1.6 / size)^2; the moon's brightness is what changes the light.
     The eclipse geometry, sized in moon radii, follows its radius.
   - **Like No horizon, these settings are how the player sees whichever physical sky is shown**: a change goes out at
     once and takes no map's sky over; on a map whose add-on owns the sky only the settings off their defaults go out.
7. **Translations**: the editor's 31 new texts in the six languages (agent-written, like the earlier sky texts);
   French keeps "Constellations".

## Consequences

- The RTX package carries the re-baked nebula (36.5 MB and 10.7 MB stored, new LFS objects) and the constellation
  layers (81 KB and 27 KB stored). The night sky image takes 268 MB of video memory at 8192 instead of 224 (the low
  tier 67 instead of 56); hiding a layer frees its share.
- The constellations now show from the twilight on, where they waited for deep night with the nebulae before.
- With every image layer at 0 the night has only the moon, the airglow and the shooting stars.
- A brightened layer can saturate where it overlaps others only at its own, higher white; the colour control works on
  gamma-space values, an artistic control, not a physical one.
- The star layer's stars stay one picture: there is no control for a single star or a magnitude range.

## Alternatives considered

- **Leave the constellations in the nebula.** No new texture, but the nebulae's slider would also dim the brightest
  stars, and "each element" would not hold.
- **A path option for the constellations' texture.** It would need the RTX fixes' Lua path policy (a native module)
  rebuilt to refuse it; a file found beside the nebula's needs nothing new.
- **The constellations drawn from the mod's atlas through their 58 triangles in the shader.** No baked map, but the
  atlas is 89.5 MB and every sky pixel would test the triangles.
- **BC7 for the constellations, or a 4096 map at every tier.** BC7 doubles the memory for the same look (BC1's mean
  error on lit texels is 0.006); 4096 would blur stars that 4K screens resolve at 8192.
- **Weights in linear light** (decode each layer, then add). It would change the default look where layers overlap:
  Skyrim adds them in gamma space, and the image was tuned that way.
