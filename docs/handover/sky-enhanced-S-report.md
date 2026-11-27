# Task S — dark edges around the Enhanced Sun and Moon

The 0115 Release install finished **2026-11-27 04:38:11 UTC**. The fork commit is `48e9ae0b4` on `claude/sky-enhanced`, immediately after 0114. The [single runtime patch](../../runtime/patches/0115-Soften-the-visible-Enhanced-sun-and-moon-discs-for-upscaling.patch) is pending on `sky3-s`. The reviewer can take `<repo>/out/worktrees/r17/out/runtime-src/_output/d3d9.dll`. The stored package is still at 0114.

## First check in the PoC

Repeat the MR2 clear-weather shot at 3840×2160, with DLSS, a 10° field of view and the Sun 60° up. The baseline shots are in `<repo>/out/sky2/MR2-mist-ring/`. Compare the uncovered limb to `r1_dlss_disc.png`, then to the native-resolution control `r2_noupscaler_disc.png`. The pass criterion is a continuous bright edge without the old dashed black outline. Check at normal field of view as well.

Repeat the midnight full Moon and inspect its upper-left limb at 1:1. At dusk, look for a lit crescent with a smooth outer edge, a dark side and lunar surface detail. The reduced disc peaks can affect apparent brightness and bloom. Check these at the same exposure. Look at a low red Sun through thin moving cloud and in a mirror, then let the Moon cross the Sun. Cloud should progressively cover the disc, an opaque cloud or the Moon should hide it, and the surrounding atmospheric glow should remain. Switch to Standard for the control.

## What caused the ring

The supplied MR2 PNGs are 3840×2160. In the annulus 74–84 output pixels from the image centre, Enhanced with DLSS had **138 pixels** with all three channels at or below 6/255. The same annulus had **zero** in both Enhanced without an upscaler and Standard with DLSS. In the full-Moon comparison, six DLSS pixels were black and another had zero blue where the native capture averaged above 200/255. These are measurements of the published 0114 build.

At pin `41842c6`, `evalSkyDisksYUp` spreads solar illuminance over the disc's solid angle and caps the result at 60,000 per channel. Its one-pixel rim gives the upscaler a very bright step. `evalMoonDisk` has the same narrow rim and divides the phase-dependent moonlight by the drawn solid angle. Its original pixel-angle argument also chooses the lunar atlas mip. Widening that argument globally would soften the surface map and change star filtering. A clamp on the library's combined RGB result would also come after colour channels had already clipped. The host therefore evaluates the solar limb separately and asks NUMOS for each moon's surface radiance.

## What changed

- The visible solar and lunar rims use `max(2 × skyPixelAngle, 0.02 × sin(radius))`. Two **traced** pixels is the width used by Standard's `evalSunDisc` and `evalSolarEclipse`. The second term retains NUMOS's floor at high magnification. A half-covered lunar pixel shades the midpoint of the covered part of its footprint, which avoids sampling the exact sphere tangent where the projected sunlit area can vanish even at full Moon.
- The solar centre is the lesser of its physical value and **48 times solar illuminance** before atmospheric extinction. Standard's `kSunDiscPeak` supplies 48. The host computes the solid angle as `4π sin²(radius/2)`, retains NUMOS's limb-darkening coefficient of 0.6 and applies one multiplier to RGB. Large, dimmer discs keep their physical centre. Measuring the angle with `atan2` keeps a zoomed rim resolved.
- Each moon is bounded against **its own** phase-dependent illuminance. A disc-only argument copy normalizes the lunar area. NUMOS still shades the real phase, albedo, relief and earthshine, using the original texture footprint. Below 0.001 radians, where the library's single-precision `1 − cos(radius)` can round to zero, the host maps the same point and texture footprint onto a larger reference sphere for shading. Silhouette coverage still uses the authored radius. For a shaded channel peak above 24 times lunar illuminance, a smooth curve approaches 48 times that illuminance. It applies one RGB gain and retains a brightness response on bright lunar terrain and thin crescents.
- The camera and mirrors traced by primary surface replacement (PSR) share the evaluator. The host reuses the physical NUMOS air, ground, star field and cloud samplers. This lets both visible paths use the same solar peak, lunar surface and occultation while keeping the reflected sky behind its cloud dome in one lookup. The camera puts the disc behind the existing screen-cloud and haze composite. The same lunar coverage masks the Sun and stars. Diffuse and glossy gathers still use the disk-free library sky. Distant lights, sky LUTs, aureoles, sun rays and rainbows keep the original arguments.

The two entry points are `compositePrimarySky` in `composite_sky.slangh` and the Enhanced PSR miss in `geometry_resolver.slangh`. The NUMOS checkout, its generated-header tool, Standard's atmosphere sources, the indirect-lighting helper, option defaults and companion code have no changes in this patch.

## Offline checks

From the runtime tree, the pinned `external/slang/slangc.exe` compiled six shader variants separately before the Release build. The shared flags were `-entry main -target spirv -zero-initialize -emit-spirv-directly -D__SLANG__ -matrix-layout-column-major -Wno-30081 -fvk-use-scalar-layout` with the Release include paths. The composites selected `COMPOSITE_SKY_PROVIDER=0` and `1`. The G-buffer ray queries used the `no_psr` and `psr_prepare` feature rows, the latter with `GBUFFER_PSR`. The dedicated PSR miss and the indirect miss with `NEE_CACHE_ENABLE=0` also compiled. All six exited 0 and matched their final build SPIR-V files. Across all 700 host SPIR-V binaries, only the Enhanced composite and 108 G-buffer variants changed. Every indirect-lighting binary matched 0114 byte for byte. The base composite retained SHA-256 `df9217600ad8cfe08105e46fe336d0acbdd8a02bc03826870531bef6aa5781e5`.

A compute-only Vulkan fixture on an RTX 5090 ran the production shader against the pinned physical evaluation for 1,001 directions in each of 13 cases. Inputs included the library's lunar atlas, a 60° and a 2° Sun, an eclipse, full and crescent phases, disc-gain changes, a subpixel moon, a large physically dimmer Sun and a below-horizon view. It ran with dome transmittance 0, 0.25 and 1. Values below are linear shader radiance before DLSS or tone mapping.

| Probe | Result |
|---|---|
| 60° Sun, input RGB (20, 18, 14) | Centre after air fell from (60,000, 60,000, 60,000) to (909.96, 762.09, 495.11). The unattenuated centre was exactly 48 times the input. |
| 2° Sun, same source | Centre after air was (387.72, 103.09, 3.80). The low Sun retained its red colour. |
| Full Moon and dusk crescent | The untextured full Moon's centre was 36.01 times its illuminance. The brightest crescent sample was 47.34 times its own. With the lunar atlas the maxima were 39.11 and 46.97. The lit and earthlit sides remained distinct. |
| Coverage and eclipse | Full-Moon coverage at the centre, geometric edge and outside was 1.000, 0.500 and 0.000. The overlapping Moon removed all direct sun at the solar centre while the uncovered crescent remained lit. |
| Mirror and horizon | Camera and PSR returned identical RGB with the dome disabled. With the dome enabled, the three runs matched cloud RGB plus transmittance times the sky within 0.00025 HDR units. The below-horizon disc returned zero. |

The scratch checks ran from `sky2r` in the x64 build environment.

```powershell
python -B out/task-s/evidence.py
python -B out/task-s/preflight.py
python -B out/task-s/gather.py
python -B out/task-s/fixture-run.py
python -B out/task-s/measure.py
```

```text
Indirect miss byte-identical to 0114.
NVIDIA GeForce RTX 5090 13013 rays, dome transmission 0.25
PASS sampled full/crescent, hue, eclipse, horizon, author gain, relief, angle limits, camera and PSR cloud order.
```

The extended `test_enhanced_sky` case checks the cap, solid angle, edge coverage, the partial-pixel lunar sample and the smooth lunar highlight response. The five aggregate tests in `python -m unittest discover -s tools/tests -p test_moon_daylight.py` also passed. The final Release and unit commands used the runtime fork and its prepared worktree in the same x64 environment.

```powershell
& $buildScript -Fork $fork -Worktree $runtimeTree -NoImport -Install -Jobs 6
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
& $buildScript -Fork $fork -Worktree $runtimeTree -Verify
```

`$buildScript` is `runtime/build_runtime.ps1` in this worktree. `$fork` identifies the fork checkout and `$runtimeTree` its prepared worktree. The Meson commands run from the latter.

```text
d3d9.dll 539393024 bytes, SHA-256 0362625c8170add66fa144727144661b57f6c9bf79bbb01f112384bd8483e2de
Ok:                81
Fail:              0
```

The unit suite ended **2026-11-27 04:39:03 UTC**. The verifier reconstructed tree `61c578456c51bcb5096579bebd34bb14b7090019` from 111 patches through 0115, two submodule settings and three pinned clones. The built, staged and unit-test DLLs matched. All 55 staged NUMOS assets matched the 0114 install and the source data or built shaders. The exported patch's SHA-256 is `9faf9d82f3383cdecd8186fee4439423c828e5c3c867422f087d9a940d975f20`. `python tools/check_repo.py` returned `repo conventions OK`.

The shader preflight, fixture source, GPU measurements and build logs are under `out/task-s/` in this worktree. No game was started. The remaining checks are DLSS reconstruction in motion, the perceived brightness at dusk and midnight, and acceptance of the staged runtime in the PoC.
