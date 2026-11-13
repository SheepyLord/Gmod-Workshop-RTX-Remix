# All-class natural-hold geometry captures

Run with `python companion/tests/vr_v4_geometry.py --package <gma> --evidence
<fresh out folder> --seconds 115 --simulate --skeleton-reference
companion/tests/fixtures/vr_index_skeletons.json`. Add `--left-hand` for the other
holding hand. Without `--simulate`, add `--recorded-controllers` while the physical
controllers are off. This is scripted recorded-frame evidence on the real compositor,
not live controller or finger acceptance.

Uses C's existing controller-model decoration, pose and rendered-hand observers,
capturing all 16 W classes. Muzzle attachment positions are compared independently
with W's exported muzzle; every exposed attachment must be within 1 cm. Missing
attachments are reported separately rather than counted as zero error. Standard
driver locks, immutable Steam files, captured images and rollback apply. Outputs
`frames*.json`, `muzzle-checks.json`, captures and driver receipts. Exit 0 means both
the driver and geometry checks pass; failures return nonzero and keep all evidence.

Q4: the geometry matrix includes all W classes and independently checks the physgun first attachment. `--export-meshes` exports ten further posed model meshes via the private observer to `models.json`; no acceptance is claimed by an export.

C observer receives the original six grip references plus ten independent Q mesh references. The strict physical grip/closed grasp checks remain; authored mount distance is reported separately. Stock Fists has no world model and retains its avatar-hand checks.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Physgun acceptance requires both asset-named core and observed beam to agree with the product muzzle within1cm; matching wrong W/T positions cannot pass.


Physgun witness labels distinguish the add-on beam from the sole independent named-core asset reference. Raw export now requires all16 models.

Natural-hold capture matrix explicitly includes Annabelle as nlvr_frames_annabelle in each holding hand, in addition to W's16 class cases. Its named muzzle witness is mandatory. The full recipe allocates130seconds for the17 phases.
