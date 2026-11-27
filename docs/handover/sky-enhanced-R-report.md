# Enhanced sky runtime — Task R

The review build is in `<repo>/out/worktrees/r17/out/runtime-src/_output`. Keep its `numos` directory beside
`d3d9.dll`. The fork branch `claude/sky-enhanced` ends at `1370af0d2`. The patch records are on `sky-enhanced-r`.
The Release build, tagged install and all 81 runtime unit tests pass. Game testing and the package import await review.

## First check in the PoC

At a fixed camera and time on `gm_construct`, compare Standard in the packaged runtime and the review runtime.
Include the sun, a visible patch of sky behind geometry, and a reflection. Then switch to Enhanced at the same
camera, turn Remix volumetrics off, and switch back. Look for a double-bright or black sky, a stale sun or shadow,
clouds appearing in front of nearby geometry, or haze that persists after switching back. Record frame times
after shaders have warmed. The runtime's option and shader checks below cannot establish visual parity.

For the four [review scenes](sky-enhanced-plan.md), check the cloud bases and shadows at noon, rays and lit mist
around a low sun, the lit cloud tops through twilight, and storm lightning and the library's Moon and stars at night.
Check a local light in haze with Remix volumetrics off and on. Start VR with mode 2 requested, check both eyes on
Standard, then leave VR and check that Enhanced resumes. Verify mode 0 on a map that uses its own sky.

## Source and changes

| Runtime patch | Fork commit | Purpose |
|---|---|---|
| 0107 | `f57c9e4f0` | Preserve literal exclamation marks in the Windows tagged-install helpers. The old converter copy failed after dropping a character from the checkout path, and the USD helper could skip the plugin DLLs. Both now stage into the requested output and propagate copy errors. |
| 0108 | `1370af0d2` | Port the NUMOS adapter, keep both skies, add the native tests and regenerate the option reference from the built DLL. |

The parent is 0106 at `51dde2c63`. The NUMOS source in `submodules/numos` is the full pin
`41842c69e9281f197acff95263260a0149876007`. It is a clone recorded alongside DLSS and SHaRC in
[base.json](../../runtime/base.json). The library checkout is clean. The adapter is based on
[the integration at 1532c782](https://github.com/Kim2091/dxvk-remix/commit/1532c782).

- The pin supplies the core, all 41 standalone compute passes, the pass table, the four night-sky data files and
  their credits. The integration supplies the DXVK GPU backend, camera and light conversions, previous-frame
  light submission, post-depth clouds, haze, the foreground buffer, composite math, cloud depth and motion
  vectors, and the DLSS and XeSS mask handling. Haze and height fog are disabled in the per-frame library
  settings whenever `rtx.volumetrics.enable` is on.
- `effectiveSkyMode` resolves option 2 to Standard for a live VR session. The frame constants, Standard
  atmosphere work, sky rasterization, foreground allocation, volumetrics and stereo checks use the device's
  effective mode. Enhanced creates its renderer, weather state, shaders and GPU resources on first use. The
  Standard atmosphere drops its tracked lights before the Enhanced scene is prepared. On leaving Enhanced its
  lights and foreground image are released, its renderer stops dispatching, and its cached resources stay with
  the device. Returning to it starts a fresh camera history and ground measurement.
- Enhanced primary misses defer their sky radiance to the post-depth composite. SHaRC and indirect or specular
  misses sample the provider on the ray. The adapter uses the fork's existing diffuse-gather payload and its
  distant-light cloud-shadow bit. Two former padding words in `RaytraceArgs` hold the active flag and inverse
  radiance scale. The existing Standard atmosphere shader directory has no diff from 0106.
- The release menu keeps its existing translated texts. The companion drives Enhanced. File-based preset editing,
  seed editing, preset search paths, and first-use file and marker creation are absent from the port.
  The 11 built-ins are calculated by the pinned library over the current settings. A recognized game ID wins
  when `weather.followGame` is enabled. The game can provide its blend factor or use the timed transition.
  Clearing both selectors allows every numeric field to be driven directly by the companion.
- `meson install --tags output` installs the 41 validated SPIR-V files, `nightsky/` with its credits,
  `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md` and the six files in `licenses/` beside the DLL. The runtime's
  `ThirdPartyLicenses.txt` includes the integration's notices. The game folder is never a preset destination.

## Shader name isolation

`scripts-common/numos_host_headers.py` follows the ten headers reachable from `numos/host/numos_host.slangh`
under the library's `host/` and `lib/` directories. It writes the build-local `src/dxvk/numos_host` include
tree. It prefixes 229 identifiers on this pin, including functions, types, constants, resource names and
feature macros such as `ATMOSPHERE_AVAILABLE`. For example, the adapter binds `enhanced_AtmosphereArgs` and
calls `enhanced_evalSkyRadiance`. The already-prefixed public `numos*` and `NUMOS_*` names keep their spelling.
The generator preserves copyright text, comments and include strings. Five shims select Remix's own camera,
math and shader types.

The standalone passes compile from the original checkout and are checked against its pass table. The ray
tracers compile once with access to both host interfaces. The composite has one additional variant, for a total
of 699 Remix SPIR-V files in this build, plus the 41 standalone NUMOS files.

## Rejected integration hunks

The scratch apply test counted 108 textual matches and 17 rejections. These are the original hunk offsets.

| File and old line | Resolution |
|---|---|
| `rtx_lights.cpp` 847 | Kept the fork's distant-light writer signature, which already accepts the atmosphere shadow flag. |
| `rtx_lights.cpp` 877 | Kept the fork's packing of bit 2 and its view-model bit. The Enhanced shader tests the distant light type before reading bit 2. |
| `rtx_lights.cpp` 974 | Used the existing copy of `atmosphereCloudShadowed` in `RtLight::copyFrom`. |
| `rtx_lights.cpp` 1113 | Used the existing forwarding of that flag in `RtLight::writeGPUData`. |
| `rtx_lights.h` 653 | The adapter sets the existing `RtLight::atmosphereCloudShadowed` field. |
| `rtx_light_manager.h` 80 | Added the prepared-light-list accessor beside this fork's externally tracked light table. |
| `rtx_composite.cpp` 33 | The adapter owns the Enhanced managed shader and its binding function. The composite calls it and selects the variant when active. |
| `rtx_context.cpp` 1638 | Bound Enhanced resources at the end of the fork's common-resource bind. The Standard bindings remain on their existing paths. |
| `dxvk_imgui.cpp` 2288 | Omitted the upstream NUMOS developer tabs. |
| `dxvk_imgui_about.cpp` 107 | Omitted the About-panel change. The installed notices carry contributor attribution. |
| `integrator_direct.slangh` 35 | Included the private sky-provider interface after the visibility header. |
| `integrator_indirect.slangh` 36 | Included it next to sparse rendering and kept the Standard sky headers. |
| `common_binding_indices.h` 93 | Appended 400–413 to the existing common parameter list, which already ends with Standard sky resources. |
| `composite.comp.slang` 622 | Kept the existing primary-miss accumulation for Standard and game skies. Enhanced adds its camera sky once in the composite, including foreground throughput and an authored dome light. |
| `RtxOptions.md` 46 | Regenerated the reflected atmosphere rows under the Enhanced prefix. |
| `RtxOptions.md` 771 | Regenerated the existing sky mode description and the Enhanced world-change counter. |
| `RtxOptions.md` 1030 | Regenerated the three numeric and Boolean weather rows under the Enhanced weather prefix. |

Two further hunks matched an unrelated `else` as text. The PSR sky lookup was moved out of the translucent
volume-transmittance block and into the specular miss. The indirect sky lookup was moved out of ReSTIR GI's
hit-geometry recording and into the indirect miss. The submodule and CI changes that fetch the dependency in the
upstream integration are handled here by `runtime/base.json`.

## Verification

Run the wrapper from the `sky2r` worktree with the configured MSVC and Meson Python environment.

```powershell
$repo = (Resolve-Path '..\..\..').Path
$runtime = Join-Path $repo 'out\worktrees\r17\out\runtime-src'
$fork = Split-Path -Parent (git -C $runtime rev-parse --path-format=absolute --git-common-dir)
.\runtime\build_runtime.ps1 -Fork $fork -Worktree $runtime -NoImport -Install -Jobs 6
```

The wrapper replayed all 104 patch files through number 0108 against the base, checked the two submodule settings and three clones,
then reconfigured Release, compiled twice and installed the output tag. It exited 0. The replay tree is
`ac8555e54a336dfcd7dbd8830a823e89f6763250`. Its DLL line was

```text
d3d9.dll 532803072 bytes, SHA-256 d8b30bd8e544a038b8472d7790df76132f307fe3facb123d7a9389e704e3e795
```

Before the first full build, the pinned Slang compiler compiled both composites, a G-buffer variant and the
volumetric pass. MSVC syntax-checked eleven adapter and render translation units. The existing Release
configuration contains the runtime's unit suite. Staging its `unit` tag places the current DLL and USD plugins
beside the test executables.

```powershell
Set-Location -LiteralPath $runtime
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
```

```text
Enhanced sky modes, 221 registered settings and eleven weather presets passed
Ok:                81
Fail:              0
```

The new test covers every reflected key, all three modes with VR off and on, path-like and unknown weather
names, game-ID priority, a controlled blend, and an interrupted timed transition. The documentation test
compared the DLL's exported `writeMarkdownDocumentation` output with the checked-in `RtxOptions.md`.
All 2,411 previously documented `rtx.` keys remain. The only existing row with different text is `rtx.skyMode`,
whose description now includes 2.

A SHA-256 comparison matched all 55 installed NUMOS files to the build or the pin, and matched the installed DLL
to the Release DLL. SPIR-V inspection found none of the 30 Enhanced composite slots in the base composite,
27 distinct slots in the optimized Enhanced composite, and the foreground and argument bindings at 158 and
400 in the G-buffer. The fork touchpoint audit ran against the accepted 0106 parent. Build logs, the Meson
test summary and the install audit are under `<repo>/out/worktrees/sky2r/out/task-r/`.

## Options available to the companion

The reflected DLL contains **230 distinct Enhanced keys**. The library supplies 197 global settings and six
parameters for each of four moons, for 221 live settings. The adapter adds six weather options, the world-change
counter and two motion-vector controls. `rtx.skyMode` is the existing selector. The list below is taken from
the built DLL, including the fully expanded moon keys.

<details>
<summary>All 230 fully qualified Enhanced option keys</summary>

```text
rtx.atmosphere.numos.aerialPerspective
rtx.atmosphere.numos.aerialPerspectiveDebugView
rtx.atmosphere.numos.aerialPerspectiveDisagreementWeight
rtx.atmosphere.numos.aerialPerspectiveEdgeHistoryMargin
rtx.atmosphere.numos.aerialPerspectiveFastReveal
rtx.atmosphere.numos.aerialPerspectiveFroxelDepthSlices
rtx.atmosphere.numos.aerialPerspectiveFroxelRangeMeters
rtx.atmosphere.numos.aerialPerspectiveFroxelSizePixels
rtx.atmosphere.numos.aerialPerspectiveHashedTurnPhase
rtx.atmosphere.numos.aerialPerspectiveHistoryFrames
rtx.atmosphere.numos.aerialPerspectiveLocalLightCutoff
rtx.atmosphere.numos.aerialPerspectiveLocalLightFilterRadius
rtx.atmosphere.numos.aerialPerspectiveLocalLightIntensity
rtx.atmosphere.numos.aerialPerspectiveLocalLightMaxCount
rtx.atmosphere.numos.aerialPerspectiveLocalLightShadows
rtx.atmosphere.numos.aerialPerspectiveLocalLightTileMaxCount
rtx.atmosphere.numos.aerialPerspectiveLocalLightWindow
rtx.atmosphere.numos.aerialPerspectiveLocalLights
rtx.atmosphere.numos.aerialPerspectiveMieAnisotropyMax
rtx.atmosphere.numos.aerialPerspectivePenumbraEveryFrame
rtx.atmosphere.numos.aerialPerspectiveRevealHistoryFrames
rtx.atmosphere.numos.aerialPerspectiveSceneShadow
rtx.atmosphere.numos.aerialPerspectiveSilhouetteFix
rtx.atmosphere.numos.aerialPerspectiveSkipHiddenFroxels
rtx.atmosphere.numos.aerialPerspectiveSkyEveryFrameWithoutSun
rtx.atmosphere.numos.aerialPerspectiveSkyFilterRadius
rtx.atmosphere.numos.aerialPerspectiveSkyHistoryFrames
rtx.atmosphere.numos.aerialPerspectiveUpsampleDepthTolerance
rtx.atmosphere.numos.aerosolDensity
rtx.atmosphere.numos.aerosolTint
rtx.atmosphere.numos.airDensity
rtx.atmosphere.numos.airTint
rtx.atmosphere.numos.atmosphereThickness
rtx.atmosphere.numos.calendarYear
rtx.atmosphere.numos.cameraWorldOverride
rtx.atmosphere.numos.cloudAnchorCutKm
rtx.atmosphere.numos.cloudBaseHeightMeters
rtx.atmosphere.numos.cloudBodyBillowGain
rtx.atmosphere.numos.cloudBodyBillowSizeKm
rtx.atmosphere.numos.cloudBodyBillowStrength
rtx.atmosphere.numos.cloudBoilSpeed
rtx.atmosphere.numos.cloudCellSizeKm
rtx.atmosphere.numos.cloudCirrusBaseHeightMeters
rtx.atmosphere.numos.cloudCirrusCoverageMean
rtx.atmosphere.numos.cloudCirrusEnable
rtx.atmosphere.numos.cloudCirrusHaloStrength
rtx.atmosphere.numos.cloudCirrusNoiseSeed
rtx.atmosphere.numos.cloudCirrusOpticalDepth
rtx.atmosphere.numos.cloudCirrusStreakDirection
rtx.atmosphere.numos.cloudCirrusWindScale
rtx.atmosphere.numos.cloudColor
rtx.atmosphere.numos.cloudColumnBaseVariation
rtx.atmosphere.numos.cloudColumnFeather
rtx.atmosphere.numos.cloudColumnTopShape
rtx.atmosphere.numos.cloudColumnTopVariation
rtx.atmosphere.numos.cloudCoverageMean
rtx.atmosphere.numos.cloudCoverageNoiseScale
rtx.atmosphere.numos.cloudCoverageSpread
rtx.atmosphere.numos.cloudCrossTileFillShortHistory
rtx.atmosphere.numos.cloudCurlStrengthKm
rtx.atmosphere.numos.cloudDensity
rtx.atmosphere.numos.cloudDepthMeters
rtx.atmosphere.numos.cloudDetailLodBias
rtx.atmosphere.numos.cloudDetailLodMode
rtx.atmosphere.numos.cloudDiffuseSunStrength
rtx.atmosphere.numos.cloudDiskAureole
rtx.atmosphere.numos.cloudDropletDiameter
rtx.atmosphere.numos.cloudEmptyPixelSkip
rtx.atmosphere.numos.cloudEnabled
rtx.atmosphere.numos.cloudEvolutionSpeed
rtx.atmosphere.numos.cloudFullRateInsideCloud
rtx.atmosphere.numos.cloudHexTilingEnable
rtx.atmosphere.numos.cloudHistoryDepthTolerance
rtx.atmosphere.numos.cloudLayer2Albedo
rtx.atmosphere.numos.cloudLayer2BaseHeightMeters
rtx.atmosphere.numos.cloudLayer2CameraOffsetMeters
rtx.atmosphere.numos.cloudLayer2CoverageMean
rtx.atmosphere.numos.cloudLayer2DensityScale
rtx.atmosphere.numos.cloudLayer2DepthMeters
rtx.atmosphere.numos.cloudLayer2Enable
rtx.atmosphere.numos.cloudLayer2FollowCamera
rtx.atmosphere.numos.cloudLayer2NoiseSeed
rtx.atmosphere.numos.cloudLayer2TypeMean
rtx.atmosphere.numos.cloudLayer2TypeSpread
rtx.atmosphere.numos.cloudLightingLodByDistance
rtx.atmosphere.numos.cloudLightingLodThreshold
rtx.atmosphere.numos.cloudMarchEarlyExit
rtx.atmosphere.numos.cloudMarchRate
rtx.atmosphere.numos.cloudMarchRayBudgetMillions
rtx.atmosphere.numos.cloudMotionVectorCoverage
rtx.atmosphere.numos.cloudMotionVectors
rtx.atmosphere.numos.cloudMultiScatterOctaves
rtx.atmosphere.numos.cloudNoiseTileKm
rtx.atmosphere.numos.cloudPerformancePreset
rtx.atmosphere.numos.cloudPhaseG1
rtx.atmosphere.numos.cloudProfilingLog
rtx.atmosphere.numos.cloudProfilingMode
rtx.atmosphere.numos.cloudQuarterMarchSchedule
rtx.atmosphere.numos.cloudRenderRTEnable
rtx.atmosphere.numos.cloudSecondaryLutEnable
rtx.atmosphere.numos.cloudSecondaryLutInterleaveMode
rtx.atmosphere.numos.cloudShadowMapBakeRowsPerFrame
rtx.atmosphere.numos.cloudShadowMapEnable
rtx.atmosphere.numos.cloudShadowMapMaxLagDegrees
rtx.atmosphere.numos.cloudShadowMapRebakeDegrees
rtx.atmosphere.numos.cloudShadowMapWindowKm
rtx.atmosphere.numos.cloudShadowStrength
rtx.atmosphere.numos.cloudSkyAmbientCloudOcclusionStrength
rtx.atmosphere.numos.cloudSpatialDenoise
rtx.atmosphere.numos.cloudSunOctaveA
rtx.atmosphere.numos.cloudSunOctaveB
rtx.atmosphere.numos.cloudSunOctaveC
rtx.atmosphere.numos.cloudSunOctaveCount
rtx.atmosphere.numos.cloudTemporalHistoryWeight
rtx.atmosphere.numos.cloudTemporalInCloudMinFrames
rtx.atmosphere.numos.cloudTemporalSmoothLagGradient
rtx.atmosphere.numos.cloudTemporalStableDepth
rtx.atmosphere.numos.cloudTemporalStillSamples
rtx.atmosphere.numos.cloudTypeMean
rtx.atmosphere.numos.cloudTypeNoiseScale
rtx.atmosphere.numos.cloudTypeSpread
rtx.atmosphere.numos.cloudVerticalOffsetWorldUnits
rtx.atmosphere.numos.cloudViewSamples
rtx.atmosphere.numos.cloudViewSamplesMax
rtx.atmosphere.numos.cloudViewStepKm
rtx.atmosphere.numos.cloudVoxelGridRebakeGranularityKm
rtx.atmosphere.numos.cloudVoxelShadowsEnable
rtx.atmosphere.numos.cloudWeatherJumpResetFrames
rtx.atmosphere.numos.cloudWindDirection
rtx.atmosphere.numos.cloudWindSpeed
rtx.atmosphere.numos.dayLengthMinutes
rtx.atmosphere.numos.dayOfYear
rtx.atmosphere.numos.debugDispatchCloudRender
rtx.atmosphere.numos.debugDispatchCloudSkyTransmittance
rtx.atmosphere.numos.debugDispatchSkyLuts
rtx.atmosphere.numos.debugEnableSkyMissShading
rtx.atmosphere.numos.directionalLightRadianceScale
rtx.atmosphere.numos.flipUpAxis
rtx.atmosphere.numos.fogAlbedo
rtx.atmosphere.numos.fogAnisotropy
rtx.atmosphere.numos.fogBaseHeightMeters
rtx.atmosphere.numos.fogHeightFalloffMeters
rtx.atmosphere.numos.fogNearFadeMeters
rtx.atmosphere.numos.fogVisibilityMeters
rtx.atmosphere.numos.groundAlbedo
rtx.atmosphere.numos.groundLevelAuto
rtx.atmosphere.numos.groundLevelWorldUnits
rtx.atmosphere.numos.groundSmoothingMeters
rtx.atmosphere.numos.hazeWorldScale
rtx.atmosphere.numos.latitudeDegrees
rtx.atmosphere.numos.lightningColor
rtx.atmosphere.numos.lightningEnable
rtx.atmosphere.numos.lightningLuminousIntensity
rtx.atmosphere.numos.lightningRangeKm
rtx.atmosphere.numos.lightningSceneLight
rtx.atmosphere.numos.lightningStrikesPerMinute
rtx.atmosphere.numos.mieAbsorption
rtx.atmosphere.numos.mieAnisotropy
rtx.atmosphere.numos.mieScattering
rtx.atmosphere.numos.moon0.angularDiameter
rtx.atmosphere.numos.moon0.color
rtx.atmosphere.numos.moon0.elevation
rtx.atmosphere.numos.moon0.enabled
rtx.atmosphere.numos.moon0.phase
rtx.atmosphere.numos.moon0.rotation
rtx.atmosphere.numos.moon1.angularDiameter
rtx.atmosphere.numos.moon1.color
rtx.atmosphere.numos.moon1.elevation
rtx.atmosphere.numos.moon1.enabled
rtx.atmosphere.numos.moon1.phase
rtx.atmosphere.numos.moon1.rotation
rtx.atmosphere.numos.moon2.angularDiameter
rtx.atmosphere.numos.moon2.color
rtx.atmosphere.numos.moon2.elevation
rtx.atmosphere.numos.moon2.enabled
rtx.atmosphere.numos.moon2.phase
rtx.atmosphere.numos.moon2.rotation
rtx.atmosphere.numos.moon3.angularDiameter
rtx.atmosphere.numos.moon3.color
rtx.atmosphere.numos.moon3.elevation
rtx.atmosphere.numos.moon3.enabled
rtx.atmosphere.numos.moon3.phase
rtx.atmosphere.numos.moon3.rotation
rtx.atmosphere.numos.moonDiscGainStops
rtx.atmosphere.numos.moonlightGainStops
rtx.atmosphere.numos.multiScatterPhysicalStrength
rtx.atmosphere.numos.nightGainStops
rtx.atmosphere.numos.nightSkyStars
rtx.atmosphere.numos.northOffsetDegrees
rtx.atmosphere.numos.nubis3AdaptiveStepKm
rtx.atmosphere.numos.nubis3ErosionStrength
rtx.atmosphere.numos.nubis3JitterAnimateKm
rtx.atmosphere.numos.nvdfCoverageOffsetKm
rtx.atmosphere.numos.nvdfNominalCoverage
rtx.atmosphere.numos.nvdfProfileDepthKm
rtx.atmosphere.numos.nvdfStepScale
rtx.atmosphere.numos.ozoneAbsorption
rtx.atmosphere.numos.ozoneDensity
rtx.atmosphere.numos.ozoneLayerAltitude
rtx.atmosphere.numos.ozoneLayerWidth
rtx.atmosphere.numos.planetRadius
rtx.atmosphere.numos.qualityLevel
rtx.atmosphere.numos.radianceAutoScale
rtx.atmosphere.numos.rayleighScattering
rtx.atmosphere.numos.realMoonAngularDiameter
rtx.atmosphere.numos.realMoonEnabled
rtx.atmosphere.numos.skyIndirectRadianceScale
rtx.atmosphere.numos.skyLutCacheKeySplitEnable
rtx.atmosphere.numos.skyViewAltitudeRebakeGranularityKm
rtx.atmosphere.numos.skyViewRebakeGranularityDeg
rtx.atmosphere.numos.starGainStops
rtx.atmosphere.numos.starScintillation
rtx.atmosphere.numos.sunElevation
rtx.atmosphere.numos.sunIlluminance
rtx.atmosphere.numos.sunIntensity
rtx.atmosphere.numos.sunRotation
rtx.atmosphere.numos.sunShadowSoftnessDeg
rtx.atmosphere.numos.sunSize
rtx.atmosphere.numos.timeCycleEnable
rtx.atmosphere.numos.timeOfDayHours
rtx.atmosphere.numos.unitsPerMeter
rtx.atmosphere.numos.useCameraWorldOverride
rtx.atmosphere.numos.weather.followGame
rtx.atmosphere.numos.weather.gameWeather
rtx.atmosphere.numos.weather.gameWeatherBlend
rtx.atmosphere.numos.weather.gameWeatherOutgoing
rtx.atmosphere.numos.weather.preset
rtx.atmosphere.numos.weather.transitionSeconds
rtx.atmosphere.numos.worldChangeCount
rtx.atmosphere.numos.worldScale
```

</details>

## Review boundary

Both patches are pending in `runtime/base.json`. The packaged DLL and its provenance still describe 0106.
The aggregate `python tools/check_repo.py` check reports one difference and exits 1. Its pending-patch rule
recognizes the two patch hashes. It also compares the candidate and packaged clone lists, and only the candidate
has NUMOS. This records the outstanding package import for the reviewer.
Garry's Mod has not been started. Visual parity, map scale, fog and light appearance, per-weather tuning,
VR transitions and frame times are for the reviewer. The library supplies near-haze rays, directional cirrus and its shadow.
Far-sky rays beyond the haze range, rain shafts and rainbows remain later-round work under the plan.
