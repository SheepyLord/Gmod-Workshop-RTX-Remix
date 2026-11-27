# Enhanced sky round 2 — Task R2

The [R3 follow-up](#r3) records the ray changes after the reviewer tested this build.

All four runtime parts are built on `claude/sky-enhanced`. The review DLL and its `numos/` folder are in
`<repo>/out/worktrees/r17/out/runtime-src/_output/`. The initial R2 Release build and tagged install ended
**2026-11-26 19:14:43 UTC**. The final unit suite ended 2026-11-26 19:15:23 UTC. The 0108 package and its build record are intact.
The four review patches are pending in [base.json](../../runtime/base.json).

| Patch | Fork commit | Result |
|---|---|---|
| 0109 | `2abe0e133e` | Camera sun rays, temporal history, depth-aware fill and four diagnostics |
| 0110 | `049468eba5` | Runtime fog selection, finite Remix/NUMOS handoff and history reset |
| 0111 | `d41099e637` | Sunlit primary and secondary rainbows |
| 0112 | `5b0f4abab4` | NUMOS adapter destruction during D3D9 shutdown |

**Review first.** Hold a low sun and partly cloudy weather at a fixed camera. Use ray view 2 to see the available
direct light, then view 1 to see precisely how much the clouds remove. Look across a gap, the edge of a far
dark cloud, and a roof silhouette. At full opacity the existing NUMOS treatment still owns the air in front
of the cloud. Use view 0 for the final picture and GPU timing. For a comparison with round 1, select mist
policy 2, set rainbow strength to 0 and keep exposure fixed. The [round 2 plan](sky-enhanced-round2-plan.md)
and [round 1 observations](sky-enhanced-report.md) give the comparison scenes.

## Sun rays

The new pass runs after NUMOS has rendered its screen clouds and populated its shadow map, before upscaling.
For each tile containing a sky miss it reconstructs a jittered camera ray. With near haze active, the march
starts at the far face of its last froxel, accounting for the angle to the camera's forward direction. With
the near haze off it starts at the camera. The configured range, atmosphere boundary, ground and top of
the shadow-casting cloud shells bound its far end. The range is in haze kilometres. Cloud intersections,
shadow coordinates and wind use NUMOS cloud kilometres. The library can scale those units independently.

At each stratified sample the shader calls the pinned library's medium, phase, solar transmittance and cloud
shadow functions. The same segment extinction weights both the shadowed and the unshadowed direct sunlight.
The implementation accumulates their nonnegative difference directly. The RGB integral is stored per unit of
incident sunlight and regains the current sun colour and exposure in the composite. Multiple scattering, sky
light, stars, the Moon and local lights are outside this integral.

**Who owns each span.** NUMOS integrates cloud-shadowed air and lamp light in its near froxels.
Its cloud marcher accumulates the air in front of the cloud separately and shadows it with
`cloudAirLightKeep` before writing premultiplied cloud radiance. The new subtraction affects only the
uncovered share of the camera sky, using full-resolution cloud transmittance at composition. An opaque far
cloud therefore keeps its own shaded foreground air. A thin cloud transmits the appropriate share of the far
shadow. NUMOS's far height fog already contains the mean cloud shadow. The new term removes only the direct
fog light still present above the local visibility. The pinned host shadow map contains the main volumetric deck
and the cirrus sheet. The separate stratiform layer is visible in cloud opacity and its own air, and does not
supply an independent host shadow map.

**History and edges.** The pass spends one sample per interval, jittered across pixels and frames, with shorter
intervals nearby. It reprojects the sunlight deficit at its weighted mean distance, using the previous jittered
camera and cloud wind. It limits the prior colour, rejects changes in depth and resets for a camera cut, map
change, a skipped frame, abrupt sun motion, changes to resolution, quality, diagnostic or range. Two RGBA16F
images alternate. A negative alpha marks a tile containing only geometry. The full-resolution bilinear fill
rejects those samples. Only a real primary sky miss receives the result. Reflections, virtual PSR paths and
the view-distance fade use the original sky. The base composite compiled to byte-identical SPIR-V against 0108.

| Ray quality at 1920 × 1080 | Ray image | Samples per ray | Maximum samples before culling |
|---|---:|---:|---:|
| High | 320 × 180 | 16 | 921,600 |
| Medium | 240 × 135 | 10 | 324,000 |
| Low | 160 × 90 | 6 | 86,400 |

The High target is 0.5 ms on the RTX 5090. One reduced-resolution dispatch reads the existing LUT and
shadow map. The other substantial cost is up to four history texels per full-resolution sky pixel.
A building that fills a tile skips its march. The mode, enable, zero strength, missing casters, disabled
shadows, authored dome, submerged camera, moon-keyed map or a sun below about −8° can skip the dispatch.
At High I expect a few tenths of a millisecond in a mixed sky view. The full-sky low-sun view is the budget
test. At 0.5 ms the worst-case count requires 1.84 billion samples per second and the four-tap full-resolution
fill requests about 133 GB/s before texture-cache reuse. Medium and Low reduce march work to 35% and 9% of
High respectively. The full-resolution fill is the same size. These counts are work estimates. The reviewer owns GPU timestamps, stability checks and the 0.5 ms verdict.

**First ray check.** Freeze a partly cloudy low sun and a camera looking through a broken bank of cloud.
With `rtx.atmosphere.numos.rays.debugView` set to the values below, compare the same view.

| View | What to look for |
|---|---|
| 1 | Positive brightness where the normal image loses direct light. Cloud-gap shafts should sit next to darker columns. An opaque cloud and a roof contribute zero. |
| 2 | The unshadowed sunlight from the same span. It should be smooth across an open gap and strongest near a low sun. It follows full-resolution cloud transmission like view 1. |
| 3 | The distance-weighted share of the span in cloud shadow, from black to white. It should move with the cloud sheet when wind resumes. |
| 4 | Red is start distance and green is end distance. Both use `log2(1 + distanceKm) / log2(1 + rangeKm)`. Expect black where no march fits, and a longer green span toward the horizon. |

Switch back to view 0. Compare strength 0 and 1 at the same exposure, then turn past a roof and a tree with
DLSS, Ray Reconstruction and frame generation in turn. Check that the shafts stay with the sky, roof edges
stay clean and moving shadows do not leave trails. Profile the pass after the driver has warmed at all three
levels. Repeat at storm noon and during sunset.

## Mist and lamp light

The device samples the requested mist mode and the player's Remix fog switch at frame begin, after resolving
the VR fallback. The default policy deactivates the froxel pass, releases its radiance and reservoir targets,
turns off its GPU enable flag and skips the dispatch. This also avoids reads of a previous illuminated grid
by effects that otherwise sample Remix radiance even when its fog composite is off.

Hybrid uses the actual weather-resolved froxel distance in world units, limited to the usable camera frustum.
The runtime supplies that distance as `FrameInputs::volumetricsHandoffWorldUnits`. In the library's
`aerial_perspective_froxel_integrate` the first integration segment begins at `apStartDistance`; local lamp
glow and the analytic near transmittance start there as well. On a pixel where the host reaches beyond the
NUMOS near grid, the far-table and height-fog cut uses the host distance.

Remix normally appends an unbounded homogeneous or planetary attenuation tail after marching its froxels.
For hybrid, rays intersect the camera-centred handoff sphere before the original attenuation routine runs,
so the user's planetary or homogeneous model still applies within it. The Enhanced composite handles a
distant surface as a full near-fog span, applies host transmittance to the library's air and clouds, and
adds near lamp in-scatter in front. Alpha-blended surfaces keep their own near transmittance and in-scatter.
A policy transition invalidates both temporal lighting and reservoir reuse. A resumed froxel pass allocates
fresh targets, and the NUMOS camera history is reset.

**First mist check.** At a lamp and doorway on `gm_construct`, turn the player's Remix fog switch on and cycle
`rtx.atmosphere.numos.volumetrics` through 0, 1 and 2. At 0 the Remix froxel dispatch should disappear. At 1
the near lamp should light the fog and distant geometry should keep the Enhanced haze. Walk a foreground
object through the configured froxel distance. Check glass and a bright alpha-blended effect for a dark seam or
double lamp glow. At 2 the original exclusive Remix fog should return. Turning the player's switch off in
hybrid should give full Enhanced mist. Return to Standard and check the saved switch and the first frame
of fog. This runtime decision writes no options.

## Sunlit rain

The Enhanced composite evaluates nine wavelengths through a spherical water drop. The angular deviation of
one or two internal reflections places 670 nm red at 42.31° and 50.48°, and 410 nm violet at 40.58° and
53.60°. The second bow has 22% of the primary lobe's peak amplitude. The interval between them loses a little
light and the area inside the primary gains a little. NUMOS sunlight through the atmosphere at the ground
supplies the illuminant, including its change of colour at sunset.

Four evenly spaced samples cover the part of the rain curtain in front of each pixel. They read cloud and
cirrus transmittance towards the sun, the near field's scene sun visibility where available, and the view
transmittance through haze and foreground clouds. The opaque or PSR surface truncates the span. Transparent
layers attenuate the rain behind them. A surface before the curtain receives no bow. The analytic spectrum
needs no texture and runs in the existing Enhanced composite. The dry control and high or unlit sun return
before the rain sampling. A separate GPU time for rain has not been measured.

**First rainbow check.** Keep the ray diagnostic off, set `rainbow.strength` to 1 during a shower and look
away from a low sun. Check red on the outside of the primary and inside of the weaker secondary. Compare
a gap in the clouds with its shadow, a distant wall with a near prop, and white daylight with sunset.
Raise the sun above 42° to lose the primary and above 51° to lose the secondary. At strength 0 both disappear.

## Device shutdown

The round 1 PoC logs show the same teardown callback followed by 51 objects at 0106, 52 at 0108 in Standard,
and 52 at 0108 in Enhanced. `CommonDeviceObject` counts instances from their constructors to their destructors.
The newly counted instance is `RtxNumos`, previously a by-value member of `DxvkObjects`, even when the sky never
created its renderer. The D3D9 shutdown hook was running. The longer-lived DXVK device still owned that member.

The owner now constructs the adapter in an in-place `std::optional` and destroys it inside `DxvkObjects::onDestroy`.
At that point the D3D9 destructor has synchronized the command thread and device, the initializer has joined
its workers, and the scene still owns the adapter's emitted lights. The adapter retires those lights, drops its
recording context and releases its renderer and references to images, shaders and histories. The normal diagnostic counter
observes the actual destructor.

A standalone 64 × 64 D3D9 lifetime probe used the same executable on both builds. It created a hidden device,
issued no draws or presents, released its COM references and exited. Both runs returned `CreateDevice 0x00000000`
and `Device Release 0`. The exit logger counted **48 at 0111 and 47 at 0112**. This fixture constructs fewer
objects than GMod. The reviewer's first check is to exit after a Standard-only session and again after switching
to Enhanced. Compare the line after `FSR FG: onDestroy called` to the round 1 PoC's 52 and the original 51.

## Registered controls

All keys use the prefix `rtx.atmosphere.numos.`. These eleven additions bring that namespace to 241 entries.
The fork's `RtxOptions.md` was regenerated from the linked DLL after every part that added options.
Every option row from 0108 compared identical.

| Suffix | Type | Default | Range and meaning |
|---|---|---:|---|
| `rays.enable` | Boolean | true | Enable the camera-sky pass |
| `rays.strength` | float | 1 | 0–4. Physical deficit at 1, off at 0 |
| `rays.quality` | integer | −1 | −1 follows sky quality, 0 High, 1 Medium, 2 Low |
| `rays.debugView` | integer | 0 | 0–4, as described above |
| `rays.rangeKm` | float | 120 | 1–400 haze km |
| `rays.steps` | integer | 0 | 0 uses the tier's count, 1–64 overrides it |
| `rays.historyWeight` | float | 0.8 | 0–0.95, maximum history share |
| `volumetrics` | integer | 0 | 0 Enhanced mist, 1 near Remix fog, 2 round 1 selection |
| `rainbow.strength` | float | 0 | 0–4, rain amount |
| `rainbow.distanceMeters` | float | 120 | 1–20,000 haze metres to the curtain |
| `rainbow.depthMeters` | float | 600 | 1–20,000 haze metres of rain |

## Build and verification

Run the following from `sky2r` using the configured MSVC and Meson Python. The named build is the existing
Release configuration used for round 1.

```powershell
$repo = (Resolve-Path '..\..\..').Path
$runtime = Join-Path $repo 'out\worktrees\r17\out\runtime-src'
$fork = Split-Path -Parent (git -C $runtime rev-parse --path-format=absolute --git-common-dir)
.\runtime\build_runtime.ps1 -Fork $fork -Worktree $runtime -NoImport -Install -Jobs 6
.\runtime\build_runtime.ps1 -Fork $fork -Worktree $runtime -Verify
Set-Location -LiteralPath $runtime
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
```

Before full compilation, individual changed shaders were built with `external/slang/slangc.exe -entry main
-target spirv -zero-initialize -emit-spirv-directly -matrix-layout-column-major -fvk-use-scalar-layout`
and the Release include paths. The ray pass, both composites, a G-buffer variant and the volume integrator
passed. An independent compile of the 0108 base composite produced the same SPIR-V SHA-256,
`df9217600ad8cfe08105e46fe336d0acbdd8a02bc03826870531bef6aa5781e5`. The Enhanced composite's
reflected ray and rain controls start at byte offsets 0 and 48. The standalone ray pass has bindings 0–8.

The Release wrapper replayed 108 patch files through 0112, checked the two submodule settings and three clones,
compiled twice and installed the output tag. Replay tree `c8d01302e41a2cf6e1dcfb7ff8e00942ce46fb77`. Both the built and installed DLL gave

```text
d3d9.dll 536613376 bytes, SHA-256 38d0d945b9423b35fcc1fc762e5daf7026eef37e5b38ca3f69b10e436d8a194e
```

The unit suite passed after each part and again after the verified build.

```text
Ok:                81
Fail:              0
```

The extended `test_enhanced_sky` checks option registration, the skip combinations, strict decreases in ray
work across the three tiers, every fog selection with the player's switch and VR on and off, history
transitions, rain control layout, both bow radii and their opposite dispersion. The documentation test checks
the actual runtime export. All 55 staged NUMOS shaders, night data and notices matched their pin or build
bytes by SHA-256. The pin `41842c69` is clean, and the Standard atmosphere shader directory has no changes
against 0108.

The aggregate `python tools/check_repo.py` check returned `repo conventions OK` with all four patches pending.

The shutdown probe was compiled with `cl /EHsc /std:c++17 device_probe.cpp /Fe:device_probe.exe /link user32.lib`
and passed the full path of the staged `d3d9.dll`. Its before/after output and the build, shader and suite logs
are under `<repo>/out/worktrees/sky2r/out/task-r2/`.

## Remaining review

No game was started. Shafts and their cost at 1080p, moving-camera stability, Standard frame-time parity,
near/far fog in actual maps, rainbow appearance and the GMod exit count remain to be checked in the PoC.
The shared ray attenuation routine tests the bounded-fog tag and forwards stock rays to their original routine.
A byte-identical base composite alone cannot establish whole-frame cost. Package import, weather tuning and
the release decision remain with the reviewer.

## R3

Patch **0113**, fork commit `bd3cb3226f`, follows the four patches the reviewer tested. The Release build and
tagged install ended **2026-11-26 20:48:11 UTC**. The final unit suite ended 2026-11-26 20:49:03 UTC. The staged runtime is in
`<repo>/out/worktrees/r17/out/runtime-src/_output/`. The pending patch adds no settings. The existing
`rays.strength` help now describes its colour limit.

### Strong rays

Let `S` be the sky RGB before ray subtraction and `D` the requested RGB loss after applying cloud
transmission and ray strength. The composite uses one multiplier for the whole loss vector.

```text
k = min(1, min over channels with D > 0 of (0.75 × S / D))
result = S − k × D
```

A quarter of each channel is the floor. It limits darkening to two stops and leaves room for light
outside the pass's direct-sun estimate. The first channel to reach its budget limits all three.
A zero loss in an already dark channel imposes no limit. At strength 1 the subtraction is identical
to 0109 for the same input whenever `k = 1`. Neither the physical scattering model nor the weather tuning changed.

### Diagonal hatching

0109 reused a single interleaved-gradient jitter for all march intervals in a texel. Its dominant spatial
frequency folds to about (−0.444, +0.309) cycles per ray texel. Its third harmonic folds to (−0.333, −0.072).
In the reviewer's still view 3 images, the strongest high-frequency bin for the humid and noon views was
(−0.328, −0.078), the adjacent measured bin. The phase advanced each frame with the diagonal pattern intact.
Rounding the reprojection to a single texel made history jump while turning. Clipping that history to ±35%
of one fresh estimate also threw away a good average whenever a sample saw little shadow. The four-tap
full-resolution fill enlarged the surviving pattern.

The ray shader now reads the renderer's existing 128 × 128 × 64 spatiotemporal blue-noise array. Each
stratum has a different texel and slice offset, and advances one slice each frame. History is reconstructed
at its fractional reprojected coordinate from a centred 3 × 3 kernel, halfway between a tent and a quadratic
B-spline. Geometry and incompatible light-centroid distances reject individual taps. The current unshadowed
integral bounds old loss. A single clear sample can therefore average with shadow from an earlier frame.
The pass keeps its existing history textures, dispatch count, quality levels, wind correction and resets.

### Horizon

NUMOS ends the distant deck against its virtual planet in `cloudSlabSpan`. On flatgrass, a narrow strip
below that limb still misses game geometry. Here cloud transmission rises, and 0109's full-resolution
fill could borrow the long air column of a neighbouring sky tile. View 1 multiplies that column by the
newly open transmission. View 3 does not. The normal picture subtracts the view 1 term multiplied by
strength, so it receives the same strip.

In the original 3840 × 2160 noon capture, the horizontal projects to row 1231. In columns 200–799, view 1
rose from about 6/255 above the limb to 243/255 in the next few rows. View 3 went from 237 to 225. At strength 3
the normal picture darkened locally by about 18 code values across that strip, against about 4 with rays off.
Those pictures were separate captures. A controlled strength-2 replay below checks the effect at the
requested setting.

0113 rejects planet-side ray tiles from history and fill. It checks the actual camera ray again at full
render resolution, with one render pixel of antialiasing on the sky side. For radius `R` and eye height
`h ≥ 0` the tangent's up cosine is `−sqrt(h × (2R + h)) / (R + h)`. This keeps metre-scale heights precise
and preserves genuine sky below the horizontal when the camera is elevated. Normal subtraction and all
four diagnostics use the same support.

### Verification

- The pinned Slang compiler built the changed sun-ray shader and both composite variants independently
  before the Release build. The preflight SPIR-V matched all three final shader binaries. The base composite
  retained its 0108 SHA-256, `df9217600ad8cfe08105e46fe336d0acbdd8a02bc03826870531bef6aa5781e5`.
- A compute-only Vulkan fixture ran the compiled 0109 and 0113 ray shaders on the RTX 5090 with the same
  synthetic shadow cascades, jittered cameras and depth. At 1920 × 1080, High marched 16 samples on a
  320 × 180 grid. The camera was still or turned 8°/s at 60 updates/s. Each of the last eight frames,
  after 1.2 seconds of history, was compared to a 1,024-sample reference at that same pose.

| Camera | Diagnostic | High-frequency RMS error, 0109 → 0113 | Error power at the two hatch frequencies |
|---|---|---:|---:|
| Still | 1, removed light | 1.68% → 0.51% | −24.5 dB |
| Turning | 1 | 1.74% → 0.56% | −23.9 dB |
| Still | 3, shadowed share | 1.48% → 1.09% | −17.7 dB |
| Turning | 3 | 1.92% → 1.23% | −18.3 dB |

The percentages are high-pass residual RMS divided by the reference signal's RMS in the open-sky region.
The fixture also ran the actual full-resolution ray fill and subtraction against a synthetic deck ending at
the planet limb, with the map silhouette farther below. At strength 2, 0109 removed light in the intervening
pixels. 0113 recorded zero loss there and retained the input RGB at the output's FP16 precision.

On the all-sky case, warmed median GPU timestamps for the High march and the isolated fill/subtraction
were **0.026 ms and 0.020 ms** for 0113, versus 0.024 ms and 0.018 ms for 0109. The sum of the new medians
is about 0.046 ms. These measurements cover the ray work with synthetic inputs. The reviewer measures
whole-frame cost and judges the reconstructed image in GMod.

The `runtime/build_runtime.ps1 -NoImport -Install -Jobs 6` build used the fork and worktree arguments in
[Build and verification](#build-and-verification). `-Verify` confirmed 109 patch files through 0113,
tree `15546efe94b3ce1c70829c3170abdf47ec88428d`, two submodule settings and three pinned clones. The tagged unit install and
`meson test -C _CompRelease_x64 --suite dxvk --no-rebuild` produced

```text
d3d9.dll 536623616 bytes, SHA-256 f236a0d5bd10fe7b5d9ccfa927f4dfe47b9495af79b32eb16bc882b2556351c9
Ok:                81
Fail:              0
```

The sky unit test covers each limiting channel, zero sky and loss channels, an unreduced physical loss
and the ground-level and elevated tangents. All 55 staged NUMOS files matched the build or pin.
`python tools/check_repo.py` returned `repo conventions OK` with 0113 pending. The packaged DLL record
remains at 0108. Fixture scripts, measurements and build logs are under
`<repo>/out/worktrees/sky2r/out/task-r3/`.

### First PoC check

Freeze the low-sun, high-aerosol view that produced blue patches. Compare strengths 1, 2 and 3 beside
the sun at fixed exposure. In views 1 and 3, hold still for one second and then turn at 8°/s across a
cloud gap and a roof. Check that the diagonal pattern is gone and the shafts follow the sky. Return to
view 0 at strength 2 and inspect the narrow strip immediately above the flatgrass silhouette, then check
it in view 1. GMod was not run by Task R3. In-game appearance and timing await the reviewer.
