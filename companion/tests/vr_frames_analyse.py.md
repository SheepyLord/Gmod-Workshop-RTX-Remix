# vr_frames_analyse.py

Imported by vr_frames_poc.py after production rollback. analyse(evidence,phases) reads bounded frame receipts and capture files; checks phase/hand identity, real native components, ray level (0.5 degrees), gun level/roll (5 degrees), actual gun/c_arms wrist agreement (5 mm), foregrip, UI panel and Exit. Reports wrist-versus-controller-skeleton distances as measured evidence. Writes reproducible centre-image hand crops under evidence/crops with Pillow. No game/SteamVR access. Returns a plain success/issues/metrics dict; caller controls exit code. Parsing helpers share W's public evidence-maths module.

Every curled non-thumb finger must have at least 5 mm inward proximal-to-distal displacement in the shown anatomical frame. This rejects the sideways claw pose that numeric wrist alignment alone missed.

Actual wrist-bone rotation plus measured anatomy determines the mesh's palm normal. It must face the controller grip hemisphere (within 60 degrees, allowing authored weapon grips); this rejects a right-hand wrist rotation copied onto the left hand. Live skeleton normals are compared in world space and reported beside wrist distance. Tight two-hand and individual-hand crops are retained.

For calibrated weapon grips, acceptance compares the actual rendered model anchor with the circumcentre of the drawn middle-finger joints (under 5 mm), rather than requiring a left wrist to coincide with a right-authored weapon bone.

The result states controller_sources and live_controller_skeleton explicitly, so a recorded-profile compositor witness cannot be mistaken for live controller validation.

Orthogonal captures compare the finite 6 cm grasp-cylinder axis with the independently fitted render-model handle, in raw controller coordinates before projection (maximum <15 mm). The cylinder uses all eight proximal/middle joints and the direction fitted through four finger-arc centres; surface PCA and arc-only fits remain separate audit fields. Five metacarpal/knuckle heads and five actual mesh fingertips are compared with untouched SDK model-space joints (<20 mm). Every capture/hand must have a valid source for joint_comparison_complete. Sources retain their recorded flag. Matching profiled/unprofiled SMG model poses must agree within 1 mm and 0.1 degrees in the same hand frame.

The raw SDK reference is also fitted with both arc-centre and eight-joint cylinder methods against the same handle, allowing the reference/model disagreement to be distinguished from the drawn hand's correction.

Scripted camera captures record that the owned command-input fixture ran; the final C settings receipt must confirm exact restoration. The original failed mouse-turn witness remains available separately.

## Review correction (2026-11-12)

Matching source follows the hand's actual read kind: WithController for unarmed articulation and GripLimit for an owned grasp. Open/straight fingers do not define a grip tube; the <15 mm axis check is only for GripLimit. Raw joint/tip comparisons remain consistency checks. Independent acceptance additionally requires <5 mm wrist/palm motion, <30 degree adjacent transported bone roll, >20 mm finger travel and >20 changed reads per sweep, own-palm gun anchor <10 cm, <=31 reads/second, <=1 grasp refit/phase and <=3 weapon measurements/phase. Actual model barrel/up, including generic models, must be level/forward.

## Placement review (2026-11-12)

Every gun capture/phase requires independent physical grip evidence within 20 mm of the drawn finger grasp. Mount-to-wrist error is always reported; the mount bone is not labelled a physical grip. The rendered palm midpoint must lie within 50 mm of the measured controller handle axis in calibrated Index views. This is a bone-centre placement envelope, not a skin-contact tolerance; the baseline independent palm distance was 42.2–43.3 mm. Raw/unknown controllers have no physical handle-axis claim. Stability/roll remain stability checks and do not accept a constant incorrect placement.

The obsolete 31 reads/second budget is replaced by no duplicate full-skeleton reads within a render frame, matching the raised production rate. Grasp refits and geometry measurement retain their separate per-phase bounds.

Mixed merge-check receipts choose calibrated/raw validation per phase label, including foregrip engagement and raw anatomical thumb-up checks in the same production transaction.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

Q4 separates authored bonemerge mount distance (reported, finite) from independent selected mesh-grip registration (<20 mm) and the drawn closed grasp (<5 mm). Right-02 retained a failure at 18.6 cm crowbar / 16.4 cm bugbait mount distance despite correct physical grip. That 12 cm universal mount criterion was semantically wrong across rigs; a deliberately misplaced/missing grip still fails. Stock Fists has empty WorldModel and is checked as drawn avatar hands, not an absent gun mesh.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Authored-bone witnesses compare against the observed Hand bone, never frame.grip. Shaft witnesses retain the posed geometry/finger oracle. The20mm placement bound remains.

Round5 requires independent handle-centreline distance below5mm and the signed bone-relative handle envelope. This supersedes the old20mm authored-bone coincidence certificate; old receipts are not rewritten.
