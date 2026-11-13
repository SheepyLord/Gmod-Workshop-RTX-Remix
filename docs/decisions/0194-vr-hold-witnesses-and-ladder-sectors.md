# 0194: VR hold witnesses and ladder sectors

Status: Accepted 2026-11-12 after Claude's review; the user approved V2-V4 that day and they were merged to `main`.

Stock weapons use measured posed-mesh handle points. A third-person bonemerge hand
marker is a different landmark from the rendered anatomical wrist and cannot replace
that data. Tests retain full raw meshes, independently annotated semantic handle
regions/centrelines, actual finger circles, signed bone-relative envelopes and rendered
barrel/up directions. Wrong magazines, stocks, barrels, muzzles and orientations must
fail. Grasp distance is at most5mm; rig-landmark residuals are reported separately.
The fixture generator reads declared raw JSON only, derives shaft sections from mesh
gaps and radial support, and never imports production cap/grip constants.

Ladders quantize stick intent into8-way sectors with22.5degree boundaries. Direction
buttons are stamped in the movement mover before physgun distance controls; core never
overwrites them afterward. A neutral main stick adds no Use on a ladder, so climbing
does not push a held prop. Ground and vehicle buttons keep their ordinary semantics.
Water and ladders follow the head; underwater noclip retains hand-directed throttle
flight and takes precedence over swimming in client commands and both SetupMove paths.

After the reviewed fixes-module repair, any recurrence of its stack signature stops.
Only the known NVIDIA startup crash permits one restored retry in a fresh folder.
Normal field quits are driver-owned, after the helper's120second startup guard;
a helper-reported post-quit crash (exit5) stops preparation and keeps the evidence.

See [the V4 report](../handover/VR-V4-report.md) for retained failures and acceptance.
