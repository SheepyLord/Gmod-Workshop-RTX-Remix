# The Enhanced sky's horizon: plan (2026-11-27)

The user, after the night round was published: "Nice work. Please improve the look of the horizon and fix the
no-horizon mode for the enhanced sky mode. Currently the horizon looks a bit off." Their screenshot,
`<repo>/out/sky2/reference/user-horizon-2026-11-27.webp`, shows a map whose floor ends: beyond it, below the horizon,
one flat pale wall of fog; above it the clouds end along a straight line; distant walls dissolve into speckled haze.

`<repo>` below is the main checkout. The sky's research notes and scratch are in `<repo>/out/sky2` (not tracked).

## What the PoC shows

Run `HZ1`, the published package (runtime patches 0001-0117), 3840x2160 with DLSS, one launch per run:

- `<repo>/out/sky2/HZ1-edge`: gm_flatgrass from the air near its edge, R26's place (12500, 0, 14000), about 510 m
  above the floor, where every ray from the horizon to 75 degrees down passes beyond the floor into the void.
  - **Enhanced, No horizon off** (`e1_enh_*`, `e5_enh_low_*`, `e7_enh_night_*`): clouds down to the horizon, then a
    perfectly straight line, then one flat colour to the bottom of the screen: grey at noon, orange-brown with the sun
    8 degrees up, black at night. Looking 50 degrees down, a dark smudge hugs the floor's edge (the near field's
    shadow of the floor in that fog).
  - **Enhanced, No horizon on** (`e2_enh_nh_*`): the same pictures. The option does nothing in Enhanced, and the
    companion greys its checkbox out there (`standardOnly` in `nativeloader_sky.lua`).
  - **Standard, No horizon on** (`e4_std_nh_*`, `e6_std_nh_low_*`, `e8_std_nh_night_*`): the reference look, sky and
    clouds below the horizon, the sun's glow only around the sun, the night image everywhere.
  - Frame-time medians, level view at noon: Enhanced 11.05 ms, Standard 10.48 ms, Standard with No horizon 12.45 ms.
- `<repo>/out/sky2/HZ1-ground`: from gm_flatgrass's ground the floor reaches the horizon, and both skies look alike.
  The fault shows wherever the view meets the void below the horizon: past a map's edge, from a height, on maps that
  float.
- Crops: `<repo>/out/sky2/judged/horizon/`.

## Why

1. **A fog wall below the horizon.** A camera miss goes through `compositeOverSkyInternal` and `applySkyHaze` to the
   library's `numosApplyAerialPerspective` with `primaryMiss`. Its miss branch applies the height fog from the near
   field's range to 2000 km (`apFogOpticalDepth(dir, range, 1e30)`). Below the fog base the fog's density grows
   (`apFogExtinctionAt` clamps it only at 10 scale heights under the base, e^10 times the base density), so for any
   ray that goes down the column is endless, `fogT` is 0, and the pixel is the fog's flat radiance
   (`apFarFogRadiance`). The library assumes the host's terrain covers every direction below the horizon. What it
   draws there itself, the sky-view LUT's lower half (the air in front of the ground) and `evalSkyGroundRadiance`
   (the lit ground with the clouds' shadows), is hidden by that fog. The near field's froxels likewise integrate
   the fog below the ground level for the void's pixels.
2. **No horizon is ignored.** Nothing on the Enhanced path (`numosVisibleSky`, `compositeOverSkyInternal`,
   `skyProviderRadiance`, the PSR miss in `geometry_resolver.slangh`) reads `rtx.atmosphere.noHorizon`. The library's
   screen clouds end at the planet (`cloudSlabSpan`), and its haze below the horizon is the fog wall above.

## The design

### A. The horizon (No horizon off, the default)

Below the horizon the Enhanced sky ends at the ground the library draws there. A camera ray, or a mirror's ray, that
leaves the scene below the library's horizon is composited as a surface where it meets the planet's ground (the
ground-level datum, the sphere `evalSkyGroundRadiance` uses). Its radiance is the library's lit ground, and the near
field, the far field and the fog apply only up to that distance: no fog below the ground, no air counted twice.

For the player: past a map's edge or under a floating map the ground goes on at the ground level and fades into the
haze toward the horizon, which becomes a hazy horizon instead of a line over a wall of fog. With the haze off (Mist 0,
or Mist on the map Off) nothing changes, because the composite already shows the library's own sky there.

### B. The sky without a horizon, in Enhanced

As Standard's (ADR 0139), with Enhanced's parts:

- **The air** below the horizon is the mirror's gradient, `(x, -y, z)`, with the true direction's angle to the sun
  and the moons: the aureole, the twilight's warm side and the moonlit glow stay where the bodies are, and no second
  glow appears below. The library's LUT cannot be baked differently, so a host pass bakes the lower hemisphere.
- **No ground** below the horizon.
- **Clouds** below the horizon are those of the opposite side (the antipode, `-dir`), at the screen clouds' quality.
  The library's dome LUT (256 by 256) is far too coarse for the camera; it serves reflections and indirect light, as
  in Standard.
- **The haze** below the horizon is the mirror's: the far field and the fog as along the mirrored ray, so no fog
  wall. The near field (shadowed air, lamp glow) cannot be mirrored and its fog grows below the ground level; below
  the horizon it gives way to the mirror's air without a seam at the horizon.
- **The night:** the image layers, shooting stars, the moons' glow, the library's real stars, and the moons drawn lit
  (not black), all through the mirror's air. The sun still sets: its disc and everything it lights keep the time of
  day.
- **Reflections and indirect light** below the horizon read the same air, and the main renderer's cloud dome at the
  antipode.
- **The companion's No horizon checkbox** works in Enhanced.
- **Off,** nothing changes and no extra resource exists. VR keeps Standard.

## Task HR: the runtime and the companion

The fork branch `claude/sky-enhanced` in `<repo>/out/worktrees/r17/out/runtime-src` ends at patch 0117
(`d3a4cea74`); build on it. Two runtime patches, in this order.

### Part 1: the ground below the horizon (patch 0118)

- **Where:** the camera miss (`compositePrimarySky`, `compositeOverSkyInternal`, `applySkyHaze`) and every miss of a
  reflected ray that the composite hazes (the PSR paths in `compositeSkyOverSurfaceInternal` and what
  `geometry_resolver.slangh` stores for them). Secondary rays (`skyProviderRadiance`, the library's
  `evalSkyRadiance`) get no fog today and already see the library's ground; leave them.
- **The ground hit:** a ray below the library's horizon (`skyAboveHorizon`'s test, the planet's limb seen from
  `cameraAltitudeKm`) meets the ground at a distance from the same sphere and datum as `evalSkyGroundRadiance`.
  The haze has its own frame (`apCameraAltitudeKm`, `apWorldUnitsPerKm`, which differ from the sky's when Haze World
  Scale and World Scale differ): give the composite the distance in the haze's frame and document the choice.
- **The surface:** the pixel is composited as a surface at that distance (`numosApplyCloudComposite` and
  `numosApplyAerialPerspective` with `primaryMiss` false, or an exact equivalent), so the near field is read at the
  ground point and the far field and the fog end there. Its radiance is the library's lit ground without the air in
  front of it: `evalSkyGroundRadiance` includes `viewTransmittance`, so use a host copy without it (keep the library's
  Apache-2.0 notice on any copied code) rather than a division by a transmittance that reaches 0 at the horizon.
- **The horizon line:** where the ground is far (a high camera, a hazy day) the ground and the sky meet in the haze;
  where it is near (a camera at the ground level on a clear day) a sharp line is physical. Either way the line is
  antialiased over a pixel (`skyPixelAngle`), and the sky-to-ground handover has no gap or bright row.
- **The haze off** (`skyHazeActive` false): unchanged, the library's sky as today.
- **Everything else** (the sun rays' fill, the rainbow, the clouds' motion vectors, the bias mask, debug views):
  consistent with a surface at that distance, or unchanged where they already stop at the horizon.

### Part 2: No horizon in Enhanced (patch 0119)

- **The air: a host bake.** A host compute pass bakes the lower hemisphere's sky radiance in the library's sky-view
  LUT parameterization (or another documented one), from a host copy of `evalAtmosphereRadiance` whose march follows
  the mirror and whose phase terms (Rayleigh and Mie, for the sun and each moon) use the true direction. Multiple
  scattering, the night glow, the blurred starlight of the catalogue night and every other term the library's bake
  has come out as the library's, and the night-image mode's restored starlight (`m_starAir` in `rtx_numos_gpu.cpp`)
  applies to it too. It runs only while No horizon is on in Enhanced, when the library bakes its own LUT. Prove the
  copy: with the phase direction equal to the march direction it must reproduce the library's LUT for y >= 0 within
  the bake's precision (a test, or a one-off comparison whose numbers go in the report).
- **Camera misses below the horizon** (y < 0 at eye level, as in Standard): that air, no ground; the moons drawn and
  lit through the mirror's air transmittance; the night image, shooting stars, the moons' glow and, in the catalogue
  night, the library's stars through the same air. The sun's disc and corona show only above the horizon.
- **Clouds below the horizon: a second renderer.** Preferred design, which the library's API supports:
  - A second `numos::Renderer`, created on first use while No horizon is on in Enhanced and released
    (`releaseGpuResources`) when it goes off and at device shutdown (patch 0112's path).
  - Its camera is the main camera point-reflected, so pixel p marches `-d(p)`: the view's rotation negated in this
    frame's and the previous frame's matrices, the same jitter, forward negated. Check that the library's camera
    math accepts a determinant -1 view; if it does not, report what fails.
  - Every frame it gets the main renderer's resolved settings, with its own aerial perspective, ground probes
    (`opaqueTlas` 0, `groundLevelAuto` off and the main renderer's measured `groundLevelWorldUnits`), lightning and
    night assets off, and the main renderer's `SimulationState` from before the main `beginFrame`, so that after its
    own `beginFrame` the two cloud fields and their evolution match. Its emitted lights are ignored. It uses the
    same `IGpu`.
  - It marches every pixel as sky: give `dispatchPostDepth` the main depth with a miss threshold that classes every
    texel as sky, or a texture of its own if the library needs one.
  - The composite takes its `cloudRender` and `cloudDepth` for camera misses below the horizon, in place of the
    main renderer's, through bindings of their own. Surfaces below the horizon get no antipode clouds: those clouds
    are a sky at infinity behind everything. The clouds' motion vectors and the upscaler's bias mask treat them as
    the screen clouds are treated, with their distance along the view ray.
  - The handover at the horizon must not show as a line: near it both sides' clouds are distant and hazed.
  - If the second renderer cannot work, report why with what you measured. Do not fall back to the dome LUT for
    camera rays.
- **The haze below the horizon:** a host version of the library's miss composite (`numosEvaluateAirImpl` and
  `numosApplyAir`) whose far field and fog follow the mirror, while the near field gives way across a narrow band
  under the horizon so that no seam shows. Surfaces keep today's haze. Report what the near field still does below
  the ground level (a floating island's underside sits in the fog the library makes there) and any remedy you see.
- **Reflections and indirect light:** below the horizon `skyProviderRadiance` and the PSR miss read the no-horizon
  air, with the main renderer's cloud dome at the antipode (premultiplied, as the library composites it), no ground,
  and the disks as their `skyDisks` rule says.
- **The Remix menu:** if no page shown in Enhanced has the No Horizon checkbox, add it to the Enhanced Sky page with
  the existing label and tooltip (already translated in the six catalogs).
- **Off:** output identical to patch 0118's build, no second renderer allocated, no extra pass dispatched.
- **Cost:** say what each part dispatches and allocates (the second renderer's VRAM in MiB at 3840x2160 with DLSS
  Quality and Performance). Claude measures the time; the aim is Standard's No horizon cost, 1.4 to 3.2 ms at
  3840x2160 on the PoC.

### Part 3: the companion

- The No horizon checkbox on the Sky and weather page stays enabled in Enhanced (it leaves `standardOnly`). Its
  convar and the option it sends are unchanged. Keep the page's other Standard-only controls as they are.
- Its help and the guide's line (`guide_pages.lua`) already fit both skies; change them only if they no longer do,
  with every catalog.
- `tools/tests/test_companion_sky.py` covers the checkbox in Enhanced; the script's `.md` says what changed.

### Deliver

- Commits on your branch and on the fork branch only. The fork commits exported as `runtime/patches/0118-*.patch`
  and `0119-*.patch`, `runtime/base.json`'s `pending_patches`, `runtime/README.md`, and in the fork
  `documentation/NumosSky.md` (a section "Below the horizon") and `docs/fork-touchpoints.md`.
- Your report, `docs/handover/sky-enhanced-HR-report.md`: what you built, what you checked and how, what you could
  not do, the known limits, and when your last build ended. Add facts you dug for to `docs/RESEARCH.md`.
- Leave the CHANGELOG, the ROADMAP and the decision record to Claude.

## Rules

Round 2's "Rules for both tasks" (`sky-enhanced-round2-plan.md`) hold: no game sessions, the library at its pin and
unmodified, Standard untouched (modes 0 and 1 render as at patch 0117), no loader change, nothing outward, commits as
the repository's git identity with no co-author trailer, `-NoImport` builds (Claude stores the runtime), no absolute
local paths or account names in tracked files, documentation duties, and a report instead of a workaround when
blocked.

## What Claude does

- Reviews the diff and the report and merges them into `sky-enhanced-4`.
- Tests in the PoC with the HZ1 scenes again: the horizon over gm_flatgrass's edge at noon, a low sun and night;
  No horizon in both skies; Standard unchanged; frame times in one launch; the companion's checkbox in Enhanced.
- Looks for the speckled haze of the user's screenshot on a map's distant walls in front of the void.
- Stores the runtime, runs the gate, writes the decision record, merges to `main` and publishes, and shows the user.

## Task HR2: after the first PoC test

Claude's runs, 3840x2160 with DLSS: `<repo>/out/sky2/HZ1-*` (the published package), `HZ2-*` (patch 0118 alone) and
`HZ3-*` (0118 and 0119 with Part 3's companion). Scenes: `<repo>/out/sky2/capture/horizon-edge2.json` (from the air at
gm_flatgrass's edge) and `horizon-flooredge.json` (from its floor at (15500, 0), the eye 64 units above the floor).

**What works.** From the air the ground below the horizon fades into the haze at noon, with a low sun and at night,
and the fog wall is gone (`HZ3-edge/e1_*`, `e5_*`, `e7_*`). No horizon in Enhanced shows detailed clouds below, a
horizon without a seam, one aureole around a low sun, the night image everywhere and an overcast below
(`e2_*`, `e5b_*`, `e7b_*`, `e9_*`). In that run No horizon cost 1.6 ms looking level or 15 degrees down and 2.7 ms
looking 50 degrees down; Standard's cost 1.4 ms. Standard's pictures are unchanged apart from drifting clouds.

**To fix:**

1. **A bright band where the distant ground meets the sky, seen from the floor.** Past the map's edge the library's
   ground shows up to its limb. Its farthest rows, about 15 pixels at 3840x2160 (0.35 degrees), are brighter than the
   sky above them. Overcast, `HZ3-flooredge/f6_enh_overcast_down5.png`, columns 1800-2000, sRGB luminance: the sky 148,
   the band 165 to 183, the nearer ground 106 to 110, the map's floor 72. At noon partly cloudy
   (`f1_enh_level.png`) the same streak shows, weaker. Patch 0118 alone has it (`HZ2-flooredge/f6_*`). Under an
   overcast deck that ground should be as shadowed as the ground in front of it. Find the cause and fix it. One
   candidate: the clouds' frame puts the eye at another height than the sky's, so `numosBareGround`'s cloud-frame
   hit misses for the directions just under the sky frame's limb and the sun lights them unshadowed. Another is the
   limb blend. Prove the fix with a headless check at both eye heights, the floor's and 510 m.
2. **The reflected ground's memory.** Patch 0118's records cost 32 bytes per compacted pixel for every Enhanced player
   whose haze and reflections are on, which are the defaults: 63 to 253 MiB at 3840x2160, for the rare mirror that
   sees past a map's edge below the horizon. Make it cost next to nothing. The preferred way has no records: the PSR
   miss evaluates the reflected ground and the air along its segment itself, from the library's far field and fog
   (as `numosAerialPerspectiveAlongRay` does), so the path arrives with its own air and the composite treats it like
   any other PSR path. Otherwise, records allocated only while a frame needs them. Report what it costs afterwards and
   what a mirror over the void shows.
3. **Everything else stays as it is.**

Deliver the fixes in patch 0118 (with 0119 rebased on it), or as a patch 0120. Either way the series must reproduce the
fork's tree; say which you chose. Add an "HR2" section to your report, with the time your last build ended.
