# 0274. Skip covered lower-cloud tiles

- Status: Accepted 2026-11-27 (the user approved the local Workshop update)
- Requested by the user: "Please address #2 and #3 to a ready to commit state."
- Extends [ADR 0272](0272-the-enhanced-sky-below-the-horizon.md).

## Context

Enhanced No horizon renders clouds below the horizon with a second NUMOS camera. The composite reads its screen image only on a below-horizon camera miss. In the Modern House hallway trace, one of 2,073,600 primary depths carried the miss sentinel.

## Decision

Classify the current primary linear depth on the GPU in 32-pixel tiles. An exact miss with either camera direction below the horizon keeps its tile and its adjoining tiles. The compositor still checks PSR and sparse-pixel flags. The mask deliberately keeps their possible misses. The margin covers the shifted sampling grid and the spatial filter.

Apply the mask only to the lower renderer's screen-cloud passes at matching extents. A whole workgroup decides before any workgroup barrier. Hidden groups retire their raw colour, depth and history using the same pixel ownership as their current sampling schedule. A negative surface distance makes the old depth invalid when a sky pixel reappears. In the split schedules, hidden fresh samples are empty, rebuild groups clear their fallback flags, and the fallback pass leaves the rebuild result in place.

Compile the host entry guard with the pinned library's original variant definitions. Check the compiled binding layout, local size and push constants at build time. The main sky and the dome used for reflections use the library's original passes. A debug view or mismatched cloud extent uses the full lower pass.

## Consequences

The cost of the mask is paid only for Enhanced No horizon. Its storage follows the internal render size and is released with the lower renderer. The test covers solid geometry, odd screen edges, axis reversal, shifted sampling and history invalidation. The PoC comparisons are in the [handover](../handover/renderer-frame-output-report.md).
