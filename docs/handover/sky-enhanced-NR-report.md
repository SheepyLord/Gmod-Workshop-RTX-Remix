# Task NR — the Night sky editor in Enhanced

[Runtime patch 0116](../../runtime/patches/0116-Draw-the-Night-sky-editor-layers-in-Enhanced-skies-and-reflections.patch) adds the approved night sky on top of 0115. Fork commit `b090357b4` on `claude/sky-enhanced` is one commit after `48e9ae0b4`. The Release build and install ended **2026-11-27 05:36:40 UTC**. The reviewer can use `<repo>/out/worktrees/r17/out/runtime-src/_output/`. This worktree records 0115 and 0116 as pending.

## First PoC checks

1. Freeze the time at midnight in clear weather on `gm_construct`. Fix the camera and exposure. Use **Final Output (Pre Tonemap), debug view 200** (`rtx.debugView.debugViewIdx = 200`) for linear-light comparisons, then return to normal output to judge the look. Switch the Night sky editor's Stars choice between **Night sky image** and **Real stars**. The four coloured image layers should give way to the catalogue and Gaia band. For the image-band check, set only the Milky Way layer to 1 and its colour to 1, with the master at its default. Compare broad regions or multiple directions. The calibration matches a spherical mean and the two bands have different shapes.
2. Turn all four image layers down and set shooting stars to zero. The visible field should disappear while the physical air, zodiacal glow and moonlit clouds remain. Bring the layers back one at a time. At twilight, stars and constellations should appear first, followed by the galaxy and nebulae. Advance the clock and look at the same pattern in water or a mirror.
3. In partly cloudy weather, watch clouds pass in front of the image, a full Moon and a crescent. Move Moon glow to zero and back. Increase shooting stars to 15/minute, try both star sources and then set the rate to zero. During a solar eclipse, inspect the rose chromosphere and outer streamers at the Sun's limb, the Moon's dark silhouette and the 0115 disc edge with DLSS. Compare Standard and time both Enhanced choices in the same launch.

## Rendering

`rtx.atmosphere.numos.nightSkyImage` is a Boolean, default **True**. It sets NUMOS's effective `nightSkyStars` to the opposite value each frame. Choosing Real stars therefore works even with a previously saved library setting of False. The native Alt+X **Stars and Milky Way** checkbox edits the same source choice. The generated option reference and all six translated runtime catalogs include the option's description. The companion page and its saved choice belong to Task NC.

- The image uses Standard's tiled star hemispheres, galaxy band and equirectangular nebula and constellation mappings, oriented in NUMOS's equatorial frame. The editor's four weights and saturations act before the gamma-space sum, white ceiling, linear decode and master brightness. Its zero-weight layers release their DDS views. Enhanced shares Standard's texture cache and tier-specific paths.
- Stars and constellations fade in for solar depression sine 0.02–0.15 (about 1°–8.6°). The galaxy and nebulae take Standard's additional deep-night fade over 0.14–0.30 (about 8°–17.5°). The image uses the library's star gain, which already includes Night brightness, and its pre-exposed reference illuminance exactly once.
- Both sources get Standard's four-second meteor slots, rate, brightness, trail and time envelope. The Moon's Gaussian glow reaches 2.5 lunar radii and follows the Moon's own phase-dependent illumination. The physical lunar disc and its illumination of clouds and surfaces still come from NUMOS. At solar contact, the host derives coverage from the actual Enhanced disc radii and directions. It adds the chromosphere, prominences and corona outside the existing solar disc and limits their combined peak with 0115's display ceiling.
- The camera and the primary-surface-replacement (PSR) miss use the same stellar frame and lunar coverage. Light from beyond the Moon is attenuated by the air and occulted by the Moon before screen-cloud composition or the reflected dome's transmittance. An 80-byte uniform block reaches the PSR miss before the G-buffer runs. The physical airglow and zodiacal light keep their library settings. Ice halos remain a separate study.

## Milky Way calibration

The comparison uses linear BT.709 luminance over the whole celestial sphere, before extinction, night gains, pre-exposure or tone mapping. In the image, mip-zero raw UNORM RGB is multiplied by alpha, raised to 2.2 and scaled by the default master brightness of 0.12. Its UV latitude is linear in sine latitude. The band occupies `sin(40°) = 0.642788` of the sphere and its three longitudinal repeats have the same mean. For Gaia, the tool decodes the pinned asset's RGB9E5 texels, divides by its storage scale of 10¹⁰ and weights each row by its solid angle.

| Asset or check | Measured result |
|---|---:|
| Packaged 8192×4096 galaxy band, before conversion | 0.000408276873482 |
| NUMOS 2048×1024 Gaia background, per steradian in reference-sun units | 1.13190391140×10⁻⁹ |
| Single multiplier, Gaia mean divided by image mean | **2.772392915×10⁻⁶** |
| Packaged 4096×2048 tier band, before conversion | 0.000409206848801 |
| Independent Vulkan integration using the actual DDS and Gaia samplers, 2,097,152 directions | **100.44%** of Gaia at mip zero and **99.98%** at a traced-pixel angle of 0.00095 radians |

Run the [calibration tool](../../tools/sky/calibrate_enhanced_night.py.md) on the unpacked assets. It prints both means and the ratio as JSON.

```powershell
python tools/sky/calibrate_enhanced_night.py <runtime-assets>/atmosphere/galaxy.dds <numos>/assets/nightsky/milkyway.bin
```

## Light scattered by the air

At pin `41842c6`, turning off `nightSkyStars` removes both the catalogue's blurred background in the sky-view LUT and half of 80 S10 of stellar illumination scattered by the air. The host leaves the direct field off. For the sky-view bake alone, it restores `40 × 6.61e-12 × nightSkyGain × nightSkyIlluminance` to the RGB in-scatter when the celestial assets are ready and the sky is dark. It checks the actual pass, binding kind, uniform-buffer handle, offset and size before updating those 12 bytes. NUMOS's pre-exposure is already in `nightSkyIlluminance`.

A recording backend ran the pinned renderer with the real night assets and captured its sky-view dispatch. At Night brightness +10 stops and pre-exposure 4096, red in-scatter was 0.128662974 with the stellar contribution removed. The corrected value was 0.146794707 at zero extra star stops and 0.201189876 at +2. All three channels matched the corresponding real-star bake exactly in both cases. The native unit also exercises an unrelated pass, a different buffer slice and a source change across frames.

## Cost and verification

The RTX 5090 fixture timed the visible-sky shader with the shipped maps and catalogue. Each case contributed 40 warmed GPU timestamp samples, interleaved on the same device with a device-local output. The view was all sky at midnight. These times cover the isolated sky evaluation; the reviewer measures whole frames, clouds and reflection coverage in the game.

| Traced resolution | 0115 real | 0116 real | 0116 image |
|---|---:|---:|---:|
| 1920×1080 | 0.0272 ms | 0.0284 ms | 0.0251 ms |
| 3840×2160 | 0.1241 ms | 0.1275 ms | 0.1193 ms |

The default image added no measurable penalty against the prior real sky in this fixture. I expect a small whole-frame change in ordinary views. First-time texture upload is separate from the warmed cost.

Six shaders compiled individually with the pinned `external/slang/slangc.exe` and the Release include paths. They were the base and Enhanced composites, a regular and a PSR G-buffer ray query, the dedicated PSR miss and the indirect miss. Each output matched the final build. Relative to 0115, only the Enhanced composite and 108 PSR-labelled G-buffer variants changed among 700 host SPIR-V files. The base composite retained `df9217600ad8cfe08105e46fe336d0acbdd8a02bc03826870531bef6aa5781e5`. All 55 staged NUMOS files matched 0115 and the pinned assets or built shaders.

The Vulkan checks isolated each DDS layer, zeroed all four, changed saturation and brightness, rotated the celestial frame, doubled the star gain and quadrupled pre-exposure. They exercised both meteor controls with both star sources, half-lunar illumination, an occultation and the corona. A clear, quarter-transmitting and opaque dome matched the same sky behind its premultiplied cloud colour. SPIR-V reflection confirmed the 80-byte CPU layout, camera slots 97–102, and PSR controls at 414 with the existing four image slots and wrap-U sampler.

The final Release and native checks used the x64 build environment, the runtime fork and its prepared worktree. The Meson commands run from the runtime root.

```powershell
& $buildScript -Fork $fork -Worktree $runtimeTree -NoImport -Install -Jobs 6
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
& $buildScript -Fork $fork -Worktree $runtimeTree -Verify
```

```text
d3d9.dll 544636416 bytes, SHA-256 d15ae2329fc96d8d64a3cd8f6b32d251b26effb329c43d5f18e61735af45673d
Ok:                81
Fail:              0
```

`$buildScript` denotes `runtime/build_runtime.ps1`. The verifier reconstructed tree `02898bbb8a681764df2fff77a30e0a46f65a6d51` with 112 patches through 0116, two submodule settings and three pinned clones. The built, installed and unit-test DLLs matched. The native suite ended **2026-11-27 05:37:25 UTC**. The generated `RtxOptions.md` adds one Boolean row. Patch SHA-256 is `477003ab05d92d8b01410ef0f0f0544a300681d13af2877dfa17441061e7714c`.

`update_strings.py --check` exited 0. The font and printf checks reported 3,987/3,987 in each of zh-CN, zh-TW, ja, ko, fr and ru, and the five embedding tests passed. The seven Standard night-editor regressions and five Moon daylight regressions passed. `python tools/check_repo.py` returned `repo conventions OK`. The shader preflight, light-recording fixture, Vulkan checks and timing logs are in this worktree's `out/task-nr/`.

No game ran. The look in the PoC, DLSS reconstruction of moving streaks, the companion page in use and whole-frame timing await the reviewer.

## NR2

[Patch 0117](../../runtime/patches/0117-Brighten-the-authored-night-and-eclipse-the-Enhanced-daylight.patch) follows the tested 0116 as one fork commit, `d3a4cea74` on `claude/sky-enhanced`. The final Release build and install ended **2026-11-27 06:44:01 UTC**. The reviewer can use `<repo>/out/worktrees/r17/out/runtime-src/_output/d3d9.dll`. This worktree keeps 0116 and 0117 pending for import.

### First PoC comparison

1. Repeat NIGHT2 at a clear, moonless midnight with fixed exposure and the editor defaults. Compare the sky and zenith against `g5_*`, `g7_*` and Standard's `gs_*`. The coloured nebulae should now be apparent at zero extra Starlight stops. Switch to Real stars to check the catalogue, and set shooting stars to 15/minute and brightness 8. Watch in motion for several four-second slots with plenty of sky in view.
2. Repeat NIGHT1's clear, 40° Sun and scrub the solar eclipse from first contact through 100% and back. Watch the air away from the Sun, a cloud and a sunlit wall together. At totality, look for the Moon's silhouette, exposed corona and stars in both source modes. Compare against `n9_eclipse_wide.png`, `n9_eclipse_sun.png` and Standard's `n10_eclipse_standard_sun.png`. Use **debug view 200, Final Output (Pre Tonemap)** at fixed exposure for the lighting comparison, then check normal output, DLSS and a reflection.

### Image and shooting stars

NIGHT2 put Standard's two sky-region means at 0.067 and 0.075. Enhanced gave 0.017/0.018 at the former default, 0.050/0.068 at +5 stops and 0.066/0.094 at +7. The new named `kNumosNightLookGain` applies the chosen midpoint, **+6 stops (64×)**, after the physical Gaia calibration. The combined conversion is `2.772392915e-6 × 64 = 1.7743314656e-4`. Night brightness and Starlight still scale the result.

The authored image and meteors share this gain. Meteors retain Standard's slot timing, brightness control, trail and colour in both source modes. At default brightness a streak head is 2 in Standard's pre-conversion units and image white is 0.12. The native regression checks their 16⅔-to-1 ratio. An RTX 5090 dispatch comparing 0116 and 0117 measured **64.000×** for both the image mean and the meteor peak, and zero RGB difference for ordinary Real stars without a streak. At 15/minute and brightness 8, 1,023 of 1,024 sampled slot heads produced light with both builds. One slot had a projected segment shorter than Standard's 0.001 cutoff.

### Solar eclipse

0116 used disc coverage in the visible sky after NUMOS had baked the atmosphere and clouds with full sunlight. At pin `41842c6`, `sunVisibleFromMoon` measures sunlight reaching the Moon during a lunar eclipse. NR2 computes **sunlight reaching the observer** before the library's frame begins. It uses the current weather-resolved Sun and moon sizes and directions, including the pin's topocentric lunar ephemeris and the coming step of its own clock. A game moon still occults the Sun when its emitted light is zero.

The host integrates the union of lunar silhouettes against 0115's solar intensity profile `I(μ) = 0.4 + 0.6μ`. Rings split at contact radii and use analytic annular area and flux weights. The transmitted factor is `floor + (1 − floor) × uncovered flux`, with `rtx.atmosphere.eclipseTotalityLight` supplying the floor (0.0006 by default). The frame's transient solar intensity supplies the sky, haze, screen clouds, cloud dome and the distant Sun used on surfaces. The normal one-frame scene handoff for the emitted light still applies. Sudden changes greater than a factor of two reset NUMOS's temporal histories. The camera and PSR carry the full, pre-exposed solar colour separately so the exposed photosphere and corona retain their surface brightness even at a zero floor.

The pin opens its night gate from Sun elevation. In a midday total eclipse the native flags were still 5 for the image and 7 for Real stars, with the night bit clear. The host starts revealing the catalogue below 3% transmitted daylight and fully reveals it by 0.1%. It blends in the configured stellar gain as that window opens. The physical sources keep their catalogue units. The high-Sun bake contains no blurred stellar field, so the host draws the full catalogue and Gaia contribution through the air and lunar mask. The image uses the existing totality fade and its new display gain.

### Measured lighting

A surface-free Vulkan fixture ran the pinned NUMOS renderer and its installed SPIR-V on an RTX 5090, with fixed weather, camera and a 40° Sun. These are linear fractions of the clear reading. The sky column covers the upper-hemisphere sky-view LUT. The cloud columns use texels covered in the clear reference frame.

| Solar disc area covered | Incident sunlight | Baked sky | Screen clouds | Reflected cloud dome | Emitted map Sun |
|---:|---:|---:|---:|---:|---:|
| 0% | 1.00000 | 1.00000 | 1.00000 | 1.00000 | 1.00000 |
| 46.38% | 0.53439 | 0.53439 | 0.53498 | 0.53409 | 0.53439 |
| 90.69% | 0.07550 | 0.07550 | 0.07556 | 0.07539 | 0.07550 |
| 100% | 0.000600 | 0.000600 | 0.000600 | 0.000599 | 0.000600 |

The baked sky recovered its clear value on egress. Setting the floor to zero removed the measured solar illumination completely. Using these LUTs and the actual night assets, the wide camera-sky mean at totality was 0.001810 with the image and 0.000225 with Real stars, against 0.373250 in daylight. The central photosphere was fully hidden and the peak visible corona was 0.135609 with either the default or zero floor. Reflected radiance matched the sky behind the dome's transmittance and premultiplied colour.

The native unit checks first contact, smooth ingress/egress, annular and total eclipses, overlapping and disjoint moons, the horizon and the automatic clock. A recording backend separately compared the host result with a 601×601 integration of the actual rendered discs across a clock scrub using the real April 2024 Moon. It exercised 26 partial frames and totality. Maximum absolute area/flux discrepancy was **0.000058**.

### Build and remaining review

The pinned Slang compiler compiled the base and Enhanced composites, ordinary and PSR ray queries, the dedicated PSR miss and the indirect miss separately. All six matched the final build. SPIR-V reflection confirmed the 96-byte night block on the camera and PSR paths. Of 700 host shaders, only the Enhanced composite and 108 PSR-labelled G-buffer variants changed. Standard's base composite kept its recorded hash. All 55 installed NUMOS files matched 0116 and the pin or its built shaders.

```powershell
& $buildScript -Fork $fork -Worktree $runtimeTree -NoImport -Install -Jobs 6
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
& $buildScript -Fork $fork -Worktree $runtimeTree -Verify
```

```text
d3d9.dll 545485824 bytes, SHA-256 e533151a152d2eb26f3801fd117026e0035fc0d0414c9302438b53976cf6fe9c
Ok:                81
Fail:              0
```

The unit suite ended **2026-11-27 06:44:44 UTC**. The verifier reconstructed tree `75ae209c875f9e30d3e4bee7c14c288b72a829c4` from 113 patches through 0117, two submodule settings and three pinned clones. The build, unit-test and installed DLLs had the same SHA-256. The 0117 patch SHA-256 is `6bade23a8824bbf92f3b6e72cce591a5e733f91e74e8f3ae1f58b5e0a1bdfeab`. The seven Standard night-editor and five Moon daylight regressions passed, `update_strings.py --check` exited 0 and `python tools/check_repo.py` returned `repo conventions OK`. Scratch commands, fixtures and logs are under `out/task-nr2/`.

No game was started and no runtime was imported. The in-game visual match to Standard, meteor visibility with DLSS, automatic exposure during totality and whole-frame timing remain for the reviewer.
