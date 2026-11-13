# 0162: Thin reconstructed colour needs matching depth coverage in VR

- Status: Implemented on `v2r` for VR V2, 2026-11-11; awaiting integration review. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.
- Context: the user's V1 look showed ghost shades in the headset and mirror. In a controlled
  gm_construct scene, the centre image has one thin ring while the eye images have displaced
  dotted copies. The colour reconstructed at full resolution extends beyond the surface in the
  half-resolution primary depth. A correct nearest-surface search can therefore still place that
  colour at the background's disparity.
- Amends: [ADR 0156](0156-the-vr-warp-finds-the-nearest-visible-surface.md), for colour coverage
  and the nearest guaranteed projection depth. The near-to-far intersection search remains.

## Decision

Before warping, make a VR-only depth image at the primary depth's size. Across a depth discontinuity,
extend the nearest valid depth by one primary texel in each direction. Use it only when the nearest
of the nine samples is less than 90% of the centre depth; smooth gradients keep their original depth.
The CPU reference and shader use the same rule (`rtx_vr_math.h:116` and
`vr_depth_coverage.comp.slang:20` in the runtime fork at `36df1ef0`). Save both depth images when capturing a centre
view, so the coverage change can be inspected rather than inferred from the eyes.

Use 0.4 m as the guaranteed nearest eye depth. The centre projection covers both translated eyes
down to that distance, and the inverse-depth search starts there. At the recorded parallel Index
projections and recommended 2468 x 2740 pixels per eye, its centre is 3112 x 2752 pixels, 1.3% more
pixels than V1's 3072 x 2752 pixels. The tested 0.2 m candidate needs 3272 x 2752 pixels, 6.5% more,
and 83 search intervals instead of V1's 34. It takes 1.46 ms for depth preparation plus warp on the
RTX 5090 in the simulated near-prop scene. The 0.3 m candidate takes 1.04 ms. Both exceed the plan's
1.0 ms limit. The 0.35 m candidate uses 48 intervals and measures 0.79 ms in the 0.5 m prop run,
but 1.05 ms in the Index's moving thin-feature scene. Use 0.05 m experiment steps rather than
selecting a fine boundary from noisy GPU clocks. The 0.4 m candidate uses 42 intervals;
the report separates the scenes and retains the Index checks. The final 60 s moving-ring run
on the live Index takes 0.94 ms combined depth preparation/warp in quiet profiles, while its
60 s barrel run takes 0.90 ms. Both use 2468 x 2740 pixel eyes on the RTX 5090 at 90 Hz, with
no field game running and about 7% GPU utilization before launch.

The launch-only `RTX_VR_TEST_NEAR_METRES` diagnostic accepts 0.2 to 0.5 m for those comparisons.
It is read at Start, never from Lua or a saved graphics setting. It is not automatic quality control.

## Consequences

In matched 30 s simulated gm_construct captures, the extra dark-contrast pixel count outside a
two-pixel allowance of the projected centre edges falls from 713 to 165 in the left eye and from
878 to 187 in the right eye. The centre reference is zero. Depth preparation itself takes 0.013 ms
on the RTX 5090 in that run. The metric, its masks, full images and crops are retained in
[the runtime task report](../handover/VR-V2-R-report.md); these counts describe that scene and threshold,
not a promise that every temporal artifact is removed. The final live 0.4 m run reduces 709/836
extra left/right pixels to 153/183, about 78% fewer in both eyes. Its barrel widths are
284.2/284.0/281.8 pixels in centre/left/right order, preserving the accepted V1 silhouettes.

The CPU regressions retain mirrored discontinuities, thin surfaces and layered intersections and add
a reconstructed-colour case which produces displaced pixels with raw coarse depth. A centre view
still cannot supply a surface hidden from it. Small breaks, true disocclusions, temporal reconstruction
already visible in the centre, and eye-dependent shading remain phase 1 limits for V7's true stereo.
Objects closer than 0.4 m have no coverage guarantee even when a particular central prop remains visible.

## Alternatives considered

- Filtering colour would blur the user's thin objects and would not repair their disparity.
- Replacing every depth with a neighbourhood minimum would change smooth surfaces unnecessarily.
- A wider expansion could join separate strands and extend silhouettes; the selected one-texel change
  is checked with the existing barrel-width test and the controlled ring captures.
- Keeping 0.2 m despite its measured cost would break the explicit V2 budget. Keeping V1's 0.5 m
  would leave avoidable loss of coverage for hands approaching the eyes.

## Follow-up, 2026-11-11: the frame's depth selects the search range

Claude accepted the first measurements and changed the near-range requirement for hands and guns.
The projection remains fixed at 0.4 m. The coverage pass reduces valid absolute primary view depths
into 8 x 8 tile minima, and another GPU pass produces one minimum. Search starts clamp between
0.15 m and the fixed limit. In close frames each ray conservatively bounds its possible inverse-depth
segment with the tile rectangle, including the filtered coverage at tile boundaries. Normal interval
spacing stays at most one primary texel as the range grows; the old adaptive ceiling of 128 is removed.
Out-of-frame coordinates are unavailable depths, rather than invented border hits.

The reduction also writes two indirect dispatch commands. Exactly one has nonzero dimensions:
the original fixed-range kernel in a far frame or the adaptive kernel in a close frame. The CPU
never reads, selects or waits for the minimum. Captures alone save the minimum as a float sidecar.
The original far shader body and 80-byte constant layout are retained. The selected near shader
and coverage source match the physically validated version. API 3 and all public structures remain.

The matched normal-scene Index result is 0.869 ms preparation plus warp, versus 0.853 ms for the
unchanged accepted runtime: 0.016 ms overhead, within the 0.05 ms allowance. Both use recommended
2468 x 2740 pixel eyes at 90 Hz on the RTX 5090, driver 617.42, and start at 13% GPU utilization
with no field game. The earlier 0.94 ms belongs to the first task's run. The physical held-prop
results, at 7% pre-launch GPU utilization, are:

| Front depth, m | Preparation plus warp, ms | GPU command work, ms | Maximum eye-width error |
|---|---:|---:|---:|
| 0.15 | 1.249 | 12.359 | 0.35% |
| 0.2 | 1.045 | 11.674 | 0.55% |
| 0.3 | 1.108 | 11.690 | 0.96% |
| 0.4 | 0.909 | 11.621 | 0.82% |

The centre stays 3112 x 2752 pixels. All props are whole in both eyes where represented by the
centre. H's near-020/030/050 cases retain whole fingers and palms in simulation and on the Index;
native crops beside H's V1 images are in the task report. The closest command sum fits the derived
80 Hz 12.5 ms budget with only 0.14 ms margin; no 80 Hz throughput is claimed. This machine still
runs near 45 submitted pairs/s at 90 Hz, with a 22.2 ms half-rate interval.

The barrel remains 284.2/284.7/281.8 centre/left/right pixels. The absolute old 153/183 ghost
snapshot is not fully reproduced in the merged context: selected steady counts are 163/178,
against 172/195 for the unchanged accepted runtime with the same scene and pose. Thus the matched
control shows no worsening, but the left absolute guard still misses by ten pixels. This is an
explicit measurement/review limitation, not a literal numeric pass. Early captures and all control
data are retained. A wider footprint and colour-based rejection both eroded foreground coverage
or worsened the count and are rejected. The accepted 3 x 3 depth rule is retained.

The selected source is runtime 39e2ab77, through patch 0085. The V2 runtime was imported once;
native module provenance was refreshed and its existing executable image kept. The Release gate
passes with 34 native and 964 Python tests; the runtime reference has 326 assertions. Exact
identities, import receipts, source-equivalence audits, rejected trials and picture paths are in
[the task report](../handover/VR-V2-R-report.md). No SteamVR setting was changed and the server was
left running. True stereo, hidden surfaces and fine depth/colour seams remain later work.
