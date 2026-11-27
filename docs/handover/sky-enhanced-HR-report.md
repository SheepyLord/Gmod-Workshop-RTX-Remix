# Enhanced horizon handover

## Ground below the horizon (0118)

Start at the gm_flatgrass edge in the HZ1 elevated camera with No horizon off. At noon, look down
past the floor for lit ground and cloud shadows. Tilt slowly across the limb and repeat with the
Sun eight degrees up and at night. The ground should fade with distance. At ground level a clear
horizon can be sharp. Toggle Mist off for the published library view, then try a mirror facing the
void. The far side of the reflection uses the reflected ray's origin and direction.

The finite endpoint is the near intersection with the NUMOS planet at the sky's ground datum.
The composite converts the sky distance to world units before the library converts it to air
kilometres. This preserves the ground position under independent sky and haze scales. It lights the
ground with the library's cloud shadow, Sun, moons and hemispherical ambient before applying view
extinction. A partially covered pixel receives both its finite surface and its open-sky share.
The depth visibility of the screen clouds also controls their motion-vector coverage and colour bias.
The rainbow stops contributing behind the ground and the sun-ray fill already stops at the limb.

Reflection and transmission each retain their final ray origin, octahedral direction, ground
distance and coloured throughput in a compacted array. The post-depth composite samples the
current NUMOS air along each such segment (up to eight near and sixteen far steps) before applying
the ordinary camera-to-first-surface haze. The dome supplies reflected clouds. Only active PSR
surfaces clear and use these records. The allocation is 32 bytes per compacted pixel with haze
and PSR enabled, about 112.5 MiB at 2560×1440 or 63.3 MiB at 1920×1080 with dense tracing.
The change adds no dispatch. Off-screen portions of a reflected segment use the library's
unoccluded atmospheric light and omit nearby lamps. The secondary lighting gather keeps the pinned sky.

A headless Vulkan dispatch on the RTX 5090 compared 3,084 samples of the production intersection
against double precision, including sea level, 2 m and 510 m, a displaced reflection origin and
directions through the limb. The maximum distance difference for fully covered ground was
0.0069 m. Maximum error at half coverage was 0.00000143. The isolated base composite and
indirect miss matched 0117 byte-for-byte. Both composites, two G-buffer compute variants and
the dedicated PSR and indirect miss matched their Release SPIR-V.

Fork `eaef0bb05`, tree `2bee2b924bb03aeefcbf891682f8534d3a7dd639`. The Release install build with
`-NoImport` ended **2026-11-27 10:33:52 UTC**. The installed DLL was 548,306,944 bytes,
SHA-256 `8b5af585e83583286bbec978feef18b4b01850680fdfb05551399a94addd564f`. The patch SHA-256 is `c1ed15f82a5d0414f091b39cac3556a92979361ae4fef6393ff114c11e00dade`.
All 81 runtime unit tests passed, the patch reconstruction matched the fork tree, and all
55 installed NUMOS files matched the previous build. Scratch logs are under `out/hr118/`.

## No horizon in Enhanced (0119)

At the elevated HZ1 camera, enable No horizon and pan from level to 50 degrees down. Look first
for detailed moving clouds below the map, a continuous horizon and one solar aureole with the
Sun eight degrees up. Strafe as well as turn with DLSS on. Clouds should stay behind buildings.
At night try the image, Real stars, a moon below eye level and a mirror facing the void. Switch
back to the physical horizon at the same time of day to compare with 0118.

The host bakes a 512 × 128 RGBA16F lower sky view on the first enabled frame and on each main
sky-view rebake. It uses the pin's 32-sample atmospheric march, multiple scattering, lunar light,
airglow, zodiacal light and stellar illumination. The path and extinction follow the mirrored
elevation. The Sun and moons keep their true scattering angle. The catalogue and night image
keep their celestial coordinates, including the blurred field that the high-resolution catalogue
subtracts back out. Solar disc and corona disappear below eye level. Main and opposite screen
clouds fade into the horizon air across the last half degree on each side. Reflections and
indirect rays use the main cloud dome at the antipode and honour their disc-sampling rule.

The second renderer uses the same GPU adapter and main weather, pre-frame wind, evolution and
clock, including a scrub of the authored time. Its eye position and projection jitter match the
main camera. Current and previous orientations and the forward vector are point-reflected.
Its manual ground is the main measurement. It has no near-field air, probes, local lamps,
lightning, night assets or secondary dome. Cloud colour is converted to the main pre-exposure.
Both screen-cloud depth tests accept every finite pixel as sky with a miss threshold of zero.
The composite uses the opposite colour and cloud distance only behind actual camera misses.
DLSS depth uses the apparent positive distance, and motion projects the cloud about the
previous eye. The colour bias follows the selected cloud and haze contributions.

Only the real screen column contains shadowed air and nearby lamps. On a sky miss those terms
fade over two degrees below eye level while the mirrored far air and height fog take over. **Real
surfaces retain the original haze.** A floating island's underside can still sit in dense fog
below the datum. Addressing that separately would require a host near-field density or ground
mask that also preserves fog and lamp glow around real geometry. The distant-wall speckle in
the user's screenshot still needs an in-game comparison.

### Headless checks and cost

- A Vulkan fixture on the RTX 5090 ran the pin and the host bake on the same inputs, enabling
  upper-row writes in the diagnostic copy. At 35° Sun, 3° Sun, catalogue night and image night
  with restored stellar in-scatter, **all 786,432 upper-half RGB channels matched bit-for-bit**.
  Each case contained 65,536 upper texels. The lower sky differed from duplicating that upper
  image, as expected from the actual scattering angle.
- The visible-sky shader matched 0118 exactly on all 24,576 probes with No horizon off.
  With it on, all 2,048 lower moon probes received light. The brighter solar disc and corona
  contributed zero below the line. The test found 578 lower meteor samples, 1,935 image
  contributions and 425 positive catalogue residuals. Reflected colour agreed with
  premultiplied dome composition to within 0.00000018.
- With an opaque depth of 0.1 host units everywhere, the second renderer still produced
  3,360,831 cloud pixels above 1% opacity at Quality and 1,896,298 at Performance.
  Current and previous camera rotations reversed; the running wind, evolution and clocks
  matched on every sampled frame. Across 567 camera probes near the HZ1 coordinates, the
  opposite ray direction matched exactly. The largest jittered reprojection error was
  0.0000272 in normalized device coordinates, about 0.035 pixel at DLSS Quality.
- At 3840 × 2160 output, the fixture measured Vulkan image and buffer memory requirements
  for the second renderer after 12 frames. It used quality level 2, 65% cloud coverage and
  the pin's temporal filter. The 30 live allocations totalled **488.25 MiB** at DLSS Quality
  (2560 × 1440) and **356.05 MiB** at Performance (1920 × 1080). The host air table adds
  0.50 MiB of texels. Shared adapter scratch, driver pools, samplers and pipelines are outside
  those figures. Releasing the second renderer returned its live allocation count to zero.
  The physical-ground PSR arrays from 0118 are released while No horizon is active.
- On the measured steady frame the second renderer dispatched the cloud-sky transmittance
  LUT, fast fallback, full-resolution fast march, full rebuild and denoise. Its first frame
  also dispatched the transmittance, multiscattering and sky-view LUTs, cumulus noise and
  seven detail mips, placement map, vertical optical depth, NVDF occupancy, ten jump-flood
  steps, NVDF resolve and eight shadow-map updates. Weather, cirrus and dirty inputs change
  this list. The main renderer keeps its usual passes. With the option off there is no second
  renderer, lower air table or extra dispatch.

### Release and remaining review

Fork `4c3c1177f`, tree `f983ee0c4154ead4c4991563d82fde2a055cfcc6`. The final Release install used
`-NoImport -Install -Jobs 6` and ended **2026-11-27 11:13:07 UTC**. The staged DLL was
575,782,912 bytes, SHA-256 `a2d3976ef80fe0a83af842a67d265a448fe3256240c01a9f2e48089aa34dbd8e`. The patch SHA-256 is `4575717243e12ec1e9bd999d4bd9be1f60e440b06e123534ecb8db2803fd6905`.
Both composites, the host bake, two G-buffer variants, the dedicated PSR miss and the indirect
miss compiled separately with the pinned Slang and matched the integrated build. The base
composite retained the 0117 hash. All 81 runtime unit tests passed and the verifier reproduced
the fork tree from the patch series. The night editor retained its 96-byte shader interface.
All 55 installed NUMOS files matched the pin or its prior build. The translation check passed with
3,987 messages and all six catalogs complete. Only the shared checkbox’s source reference changed. Scratch is in `out/hr119/`.

No game session was run. The reviewer owns the visual comparison with Standard, stability while
moving and whole-frame timing against the 1.4–3.2 ms target. The DLL is staged for that test.

## Companion checkbox

The Sky and weather page keeps No horizon enabled in Enhanced. Testing the open page uncovered
a second block in `pushHorizon` that discarded the convar in Enhanced. Both modes now send
`rtx.atmosphere.noHorizon` from the existing `nativeloader_sky_no_horizon` convar, including
at map start and on reset. The Standard Night sky selector still follows the active mode.
The existing help, guide and translations apply to both skies.

All 66 companion sky tests passed under LuaJIT. The panel test ran its update loop through
Enhanced → Standard → Enhanced and checked both widget states and the option received by Remix
at each toggle. The separate reset test checked the default physical horizon in both modes.
The saved checkbox also took effect on the first map frame with either physical sky. The seven
night-editor and five moon-daylight regressions passed, and the repository convention check
reported `repo conventions OK`.

## HR2

Patch **0120**, fork `1b6b6ea99`, follows the two patches the reviewer tested.
The first PoC run accepted the elevated physical horizon and the No horizon sky. It measured
1.6 ms for No horizon looking level or 15° down and 2.7 ms looking 50° down at 4K with DLSS.
0120 addresses the floor-view ground and the memory used by a reflected ground miss.

### The bright strip

In HZ3's overcast floor capture the mean sRGB luminance across columns 1800–2000 was about
149 above the strip, 185 at row 972 and 106–110 on the nearer virtual ground. The same feature
is visible with 0118 alone. The capture requested (15500, 0), but its console recorded
`placed=false` and an eye at (640, 576, −12215.08). The BSP's platform is at −12288 and its
broad grass plane at −12800. The logged 52.4934 world units per metre put the eye about 1.39 m
above the platform and 11.14 m above the grass. The headless checks cover the plan's 64 units,
the probe's 72 units, the height above the grass and the 510 m elevated case.

Two mechanisms let direct sunlight across the distant ground. First, 0119 intersected a second
sphere at the cloud-frame eye altitude. Moving the cloud deck could remove that intersection and
leave the key light at full strength even when the cloud map shadowed the actual ground point.
0120 translates the original hit directly into cloud coordinates, the same mapping used for
ordinary scene surfaces. Second, even with identical datums, a shallow pixel can cover many
shadow texels. Sunlit gaps in the deck then project into a narrow bright row against a shaded
foreground. The captures do not record the per-pixel shadow data. The GPU fixture reproduced
both cases independently. In each, the peak included pixels with **full** ground coverage.

On a low view, the filter estimates a traced pixel's ground footprint from the hit distance,
pixel angle and incidence on the spherical ground. From half to one and a half fine shadow texels
it progressively limits the direct Sun or key moon to the shadow under the ray origin. Darker
distant samples survive. The filter fades out between one and two fine texel widths of eye height.
Clear skies, the ground's ambient light, the finite haze endpoint and the one-pixel limb blend
retain their existing paths. Sunlit patches can still appear where the foreground is sunlit or
the shadow is resolved.

The headless Vulkan fixture ran the pinned renderer, the companion's overcast and partly cloudy
settings, the production ground shader and the finite cloud and air composites on the RTX 5090.
The table gives **linear luminance before exposure or tonemapping**. Each ground value is the
peak of the central 16-column average in the first 0.8° of fully covered ground below the limb.
The pixel angle corresponds to 4K DLSS Quality. The deliberately lowered deck independently
tests the two-datum fault.

| Eye height and weather | Cloud deck offset | Adjacent sky | 0119 ground | 0120 ground |
| --- | ---: | ---: | ---: | ---: |
| 1.22 m, overcast | 0 m | 0.522 | 0.419 | 0.419 |
| 1.22 m, overcast | −495 m | 0.501 | 1.463 | 0.304 |
| 11.14 m, overcast | 0 m | 0.523 | 0.693 | 0.468 |
| 11.14 m, partly cloudy | 0 m | 1.169 | 1.414 | 1.242 |
| 510 m, overcast | 0 m | 0.534 | 0.549 | 0.549 |

At the Performance pixel angle, the 11.14 m overcast peak went from 0.978 to 0.466 beside
a 0.522 sky. The 510 m aligned-datum controls and all cloud-disabled controls matched 0119
pixel-for-pixel at both DLSS footprints. The sphere intersections, limb coverage, sky samples
and cloud coverage also matched throughout the comparison.

### Reflected ground memory

A PSR miss now shades its reflected or transmitted segment immediately. It uses its own origin
and direction, finds the physical ground, and samples NUMOS's existing far-scatter and RGB
transmission volumes up to that distance. The height fog starts at the mirror's altitude in
the haze frame. The result combines the lit ground, that segment's air, the premultiplied cloud
dome and the finite host-volume transmission. Normal path throughput carries it back. The
composite still applies the air from the camera to the first real surface.

**Dedicated ground memory is now 0 bytes.** The two sampled 3D views already exist for Enhanced
aerial perspective. There is no ground array, clear, post-depth record read or additional
dispatch. Removing 32 bytes per compacted pixel saves 63.28 MiB at 1920 × 1080, 112.50 MiB at
2560 × 1440 and 253.125 MiB at native 3840 × 2160 with dense storage. Sparse savings follow the
actual compacted extent. SPIR-V inspection confirmed that the old PSR storage image at binding
159 and composite reader at 103 are gone, and that the PSR miss reads sampled 3D images at 416
and 417. The extra cloud-shadow sample for unresolved ground uses the existing shadow map.
The Release DLL grew by 7.17 MiB with the compiled shader variants. The driver-specific
pipeline footprint was outside the headless allocation check.

A mirror looking down past the map now shows cloud-shadowed ground through the finite atmosphere
and height fog. Open sky occupies its share of a grazing pixel. The outgoing leg uses the
camera-height atmospheric table and the ray-origin height for fog. The post-depth near field's
local lamps and scene shadows still apply on the camera side of the mirror. Those local effects
are omitted on the outgoing leg.

A second headless dispatch used the production PSR helper, real NUMOS tables and a known
coloured host transmission. Across 294,912 rays at three displaced ray origins, it compared
the result with independently composed atmosphere, fog, surface, dome and host transmission.
There were 116,736 full ground hits and 12,288 partially covered rays. Maximum absolute RGB
difference was 0.00000888, including segments up to 94.17 sky km. The sky-only control
matched exactly. At Haze World Scale 1.75, all 294,912 PSR results agreed before and after the
library's post-depth dispatch. The reference difference was at most 0.000000135.

### Build and reviewer checks

The pinned Slang compiler built both composites, two G-buffer query variants and the dedicated
PSR and indirect misses separately. All six matched the integrated Release. The base composite,
ordinary query and indirect miss retained their 0119 hashes. The 81 runtime unit tests passed.
The verifier reconstructed tree `e4aca864cb8ac4ab05322aa06a34581b0a9b0aa5` from 116 patches, two submodule settings and
three pinned clones. The 55 staged NUMOS files and the host No horizon air-bake shader
matched 0119. The 66 companion sky tests, seven night-editor tests, five moon-daylight tests,
translation check and repository convention check passed.

The `-NoImport -Install -Jobs 6` Release build ended **2026-11-27 12:05:25 UTC**. The staged DLL is
583,298,048 bytes, SHA-256 `cf41a48e4ecbf9b37da24610e9fbc7f3abd1a60a3443107a53d550cd97b513dc`. Patch 0120 SHA-256 is `c340d46cb6cc33b7eb26cd6aaa1ea709edce4a77798667a5065214962e34caca`.
Scratch shaders, Vulkan fixtures, row measurements and verification logs are under `out/hr120/`.

Start in the HZ3 overcast floor view, look five degrees down, and compare the strip across
columns 1800–2000. Repeat at partly cloudy noon and at 510 m. Then place a mirror so it sees
past the edge. In-game appearance, motion under DLSS and frame timing remain for the reviewer.
