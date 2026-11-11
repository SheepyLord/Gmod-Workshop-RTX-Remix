# 0146: V1 path traces one centre view and warps it to both eyes

- Status: Accepted 2026-11-10 for V1 on `vr`; true stereo remains V7.
- Amended by: [ADR 0156](0156-the-vr-warp-finds-the-nearest-visible-surface.md). The original
  far-first edge algorithm below is historical; the current warp searches for the nearest visible surface.
- Context: the user's [phase 1 design](../handover/VR-plan.md), spikes S2, S6 and S7, and the
  measurements in [C](../handover/VR-V1-C-report.md) and [Q](../handover/VR-V1-Q-report.md).
  Two independent path-traced views would require separate histories and substantially more work.

## Decision

Render one path-traced view at the head, then gather that colour image backwards through its
primary depth into each eye. The centre projection contains both eyes' corner rays at infinity
and at an axial depth of 0.5 m, including each eye's translation and rotation. Its pixel density
comes from the eye projections and their mapping into the centre, not from the desktop window.

The Index on this machine reports parallel eye rotations and asymmetric projections, rather
than the canted rotations the plan assumed. The direction-only union is 114.072 degrees
horizontal by 109.363 degrees vertical. The half-metre margin is additional: with the measured
68.5366 mm IPD it adds 0.0685366 to the horizontal tangent. At the Index's recommended
2468 x 2740 pixels per eye at 90 Hz, render scale 1, the margin takes the centre from
2944 x 2752 to 3072 x 2752 pixels, 4.35% more pixels. DLSS Performance traces
1536 x 1376 pixels. The game window remains 1280 x 720 pixels in the acceptance fixture.

Each eye ray uses the full eye-to-head transform. The shader iterates the depth lookup up to
eight times. At a depth discontinuity it keeps the farther observed sample's coordinate, so it
uses colour that was actually seen rather than sampling behind the foreground on the strength
of a depth value alone (`src/dxvk/shaders/rtx/pass/vr/vr_warp.comp.slang:35` in the runtime fork at
`9d22eef6`). This avoids a gap becoming a foreground smear, but cannot recover a hidden surface.
The mirror crops and scales the left eye into the game's original target before ordinary 2D
draws. The headset and desktop therefore share the same world picture.

The fine profile matters more than an undivided GPU elapsed time. In C's gm_construct control
on the RTX 5090 at these dimensions, the serial-paced frame recorded 0.348 ms of preparation,
6.291 ms of path tracing, volumetrics and lighting, 0.049 ms of demodulation, less than 0.001 ms
of separate NRD denoising, 0.331 ms of composition, 2.159 ms of upscaling with Ray Reconstruction,
0.302 ms of post-processing, 0.111 ms for both eye warps, 0.008 ms for the mirror, 0.056 ms in
the SDK submission interval and 0.005 ms of late raster work. The covered work was about
9.66 ms; a 9.395 ms queue gap made the elapsed span 19.055 ms. These are that control's
measurements, not the later render-paced profile; both modes' final profiles are in
[RESEARCH](../RESEARCH.md). Ray Reconstruction fuses denoising into the upscaler, and the SDK
interval can contain host or IPC waits.

## Consequences

The engine uses a wide culling view (145 degrees in the tested 16:9 fixture) while the runtime
uses the SDK-derived projection. It retains a main camera without repeated camera cuts. Q's
scripted 20 degree turns measured 20.236 and 20.303 degrees in opposite directions, and a
0.2 m lean moved a near feature 77.5 pixels against 76.294 pixels predicted by projection.

V1 is an approximation. Hidden surfaces at disocclusions, objects closer than the 0.5 m coverage
margin, foreground edges and eye-dependent reflections or lighting cannot be made correct by
warping one view. Comfort and the picture seen by a person have not been judged through an
unworn headset. V7 must settle two true eye views and their separate temporal histories before
offering a quality mode.

## Alternatives considered

- Two path-traced eyes would remove these geometric limits but is the separate V7 design spike.
- A projection covering directions alone clips near geometry displaced by the IPD; the
  half-metre corner-ray test bounds that coverage explicitly.
- Filling a disocclusion from a reprojected depth without retaining the observed coordinate
  invents correspondence and can pull foreground colour across a gap.
- Enlarging the desktop window would bind VR density to the monitor and change the flat UI.
