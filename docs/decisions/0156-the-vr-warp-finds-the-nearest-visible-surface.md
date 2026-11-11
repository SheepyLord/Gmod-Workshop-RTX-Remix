# 0156: The VR warp finds the nearest surface visible in the centre view

- Status: Accepted 2026-11-10 for the second V1 review on `vr`; release still requires the user's approval.
  Approved by the user and merged on 2026-11-10.
- Context: the second independent review, recorded in
  [Q's runtime review report](../handover/VR-V1-Q-runtime-review-report.md). The fixed-point warp of
  [ADR 0146](0146-one-centre-view-warped-to-the-eyes.md) began at infinite depth. A self-consistent wall
  could hide a closer object that the centre view had actually seen.
- Supersedes: ADR 0146's choice of a surface at an edge. Its centre projection, half-metre coverage,
  mirror and phase 1 limits remain unchanged.

## Decision

Walk each eye ray from the nearest covered head-axial depth, 0.5 m, toward infinity. The ray's
coordinate in the centre image is linear in inverse depth, so this is a segment in that image.
Find the first stored surface that the ray reaches and refine its intersection. Carry the preceding
tap's depth across the interval containing an edge, so a crossing cannot fall between two taps.
A refinement that jumps beyond the depth already searched is deferred while the search continues;
otherwise it could still choose a far wall before an intervening visible surface. Both observed
depths bordering an interval are tried, so a rejected nearer candidate cannot hide a valid middle layer.

Use the observed-background fallback only when the search cannot resolve a visible intersection,
as at a real disocclusion. The CPU reference and shader use the same search and refinement
(`src/dxvk/rtx_render/rtx_vr_math.h` and `src/dxvk/shaders/rtx/pass/vr/vr_warp.comp.slang` in
the runtime fork at `8d348e14`, `rtx_vr_math.h:104`). Normal spacing comes from the segment's
length in the actual depth texture: no interval exceeds one depth texel at the tested resolution,
with one extra interval and a ceiling of 128. The Index's 1536 x 1376 pixel depth input needs
34 intervals, 35 search positions. This is a sampling rule, not V6's automatic quality preset.
The launcher-only diagnostic `RTX_VR_WARP_TAPS` allows a reproducible comparison of fixed intervals
without a Lua option or a saved graphics setting.
It is read only when VR initializes. Picture and GPU measurements belong to the runtime review report.

## Consequences

The old algorithm made visible foreground objects too narrow in both eyes. The review measured a
285 pixel lantern in the centre and 277 pixels in each eye on modern_house. Q's independent check
of the earlier gm_construct captures measured a barrel about 283 pixels wide in the centre, 271 in
the left eye and 269 in the right. These are RTX 5090/Index captures with recommended
2468 x 2740 pixel eyes at 90 Hz. The new search is tested against nearest intersections, including
both mirrored edges, thin objects and alternating near, middle and far surfaces; a plane alone
cannot establish correct edge selection.
The CPU suite also checks a foreground surface only one depth texel wide at the measured Index
projections; sparse fixed intervals miss some of those intersections. The edge-search revision had 246
assertions, including the camera, allocation, focus and timing policies. ADR 0158's startup regression
raises the final reference to 249 without changing the search formula.

This still uses one centre view. Surfaces hidden there, objects closer than its coverage margin,
half-resolution depth boundaries and eye-dependent lighting remain phase 1 limits. The search's
extra work must be measured by its own GPU bracket; a queue gap is not shader execution.

The final d29445c5 captures measured the barrel at 283.8 centre pixels and 284.2/280.7 eye
pixels, and the Modern House target at 285.2 centre pixels and 285.7/282.9 eye pixels. The few
remaining pixels are within the documented depth/colour-edge and disocclusion limits. On the
RTX 5090, the final 310 s gm_construct and 120 s modern_house runs measured mean warp brackets of
0.56 ms and 0.64 ms, with 0%/1% GPU utilization before launch. Earlier loaded 2cbf7f0d runs measured
1.98/2.65 ms for the same search. The original 0.11 ms belongs to the older algorithm and a separate
run; these are not an isolated A/B ratio. The report retains all run identities, crops and coordinates.

## Alternatives considered

- Starting from infinity and accepting the first fixed point chooses a valid far surface even
  when a nearer observed one exists. Keeping the farther sample only repairs genuine disocclusions.
- Refining a near candidate without bounding its depth can jump to a farther layer and repeat
  the same mistake. The layered-surface regression rejects it.
- True stereo would supply each eye's hidden surfaces and history, but remains the separate V7
  design. This correction preserves the user's phase 1 architecture.
