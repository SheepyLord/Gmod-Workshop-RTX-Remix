# 0276. Share repeated meshes that the renderer keeps rebuilding

Accepted 2026-11-27. The user approved the local Workshop update. The user asked to combine finding 1 from the Modern House frame-time study with [0274](0274-skip-covered-lower-cloud-tiles.md) and [0275](0275-pass-color-between-post-effects.md).

## Context

The field courtyard submitted 82 copies of the same 573-triangle geometry range in a 114,302-triangle merged bottom-level acceleration structure (BLAS) every rendered frame. A manual triangle cutoff admitted that mesh to the existing shared path, but also changed the handling of unrelated meshes. Clean merged buckets already cost no GPU build.

## Decision

At the default grouping settings, record how many distinct instances of each shortlisted mesh actually enter merged GPU builds or updates. A mesh needs at least 100 triangles, eight instances, and 8,000 duplicate triangles in each of three successive rendered frames at the stock 1,000-triangle cutoff. Each submission must independently meet the workload threshold. Two eyes in one frame count once. A frame served from the scene or bucket cache contributes no work.

Before promotion, count live, ray-visible instances of the same runtime geometry entry. Preserve the normal paths for point instancers, billboard splits, changing vertex geometry, skinned geometry, and incompatible geometry flags or micromaps. For unsplit geometry, compare the real micromap requests by source and format. The triangle count is common to the geometry entry. A matching group binds and pins the existing micromap through one instance. Mixed binding requests take the merged path. Each shared placement uses the existing instance transform, mask, surface index and material route. Vulkan permits multiple placements of the same BLAS. Opacity micromaps attach to its geometry. [Vulkan instances](https://docs.vulkan.org/refpages/latest/refpages/source/VkAccelerationStructureInstanceKHR.html) · [Vulkan micromap bindings](https://docs.vulkan.org/refpages/latest/refpages/source/VkAccelerationStructureTrianglesOpacityMicromapEXT.html)

Reclassify cached buckets containing a newly promoted mesh. A shared mesh retains its structure while its live copies account for at least half the admission workload and remain compatible. Otherwise the existing pool retires the shared structure while older top-level structures can reference it. A change to the manual grouping controls invalidates the cached routing. Selecting a nondefault minimum preserves the original per-mesh triangle cutoff.

The shared BLAS can persist across frames without a GPU size query or build. The cache records the live owner, geometry revision, position, index, bone and vertex-shader hashes, buffer addresses and layout, build range and flags, and the source, pinned object and descriptor for the micromap. Positions and indexed geometry require known content hashes. On a mismatch the adaptive path builds a new structure in full. Its old one goes into the existing pool so the previous frame can finish. Every placement still reaches the top-level structure each frame.

## Consequences

Promotion adds top-level instances and can lengthen a ray-tracing traversal. Counting actual rebuilds and requiring sustained duplicate work bounds that tradeoff. Scene measurements and limits are in the [handoff](../handover/repeated-mesh-frame-report.md).
