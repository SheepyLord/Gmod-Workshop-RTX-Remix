# vr_tools_check.py

Verification correction: beam origin acceptance is image-derived rather than comparing
T's draw-start with the same model attachment it uses. The image-fitted beam centreline
must align within 2 internal render pixels of the projected attachment; actual first
visible pixels must agree within 12 output pixels of the depth-derived gun boundary.
Both are independent captured-pixel measurements (vr_tools_capture.py, Pillow).
Distance and gun-line error derive from recorded body/contact/muzzle transforms and scale.
No capture means failure, even with identical debug/muzzle values. Review mode adds
native fault/rearm/limits/control tests and permits exactly the two declared injected
rotation errors, never an unrelated module failure. Historical receipts remain historical.

Run python companion/tests/vr_tools_check.py out/vr/v4t/run [--native-only]. Reads the run's
retained tools-records.json, summary.json and capture files; writes tools-acceptance.json
beside them. Native-only omits tool menu/application and the second weapon-selection stage.
Requires driver exit zero and verified clean restoration of all originals. Caught framework
module/cleanup failures in this session's console remain fatal even if rendering continues.
The physics callback's one-time tools-rotation error also fails acceptance after deferred cleanup.
Checks successful native pickup, settled independent matrix-angle errors within 5 degrees
and orientation range within 0.5 degrees, measured push/pull distance deltas, engine freeze/
unfreeze; settling also requires actual native spin at most 1 degree/second, so a repeatedly
clamped angle cannot pass while the native controller keeps spinning against it. Native linear
speed is retained as a separate number. Checks also cover
command selection, tap behavior, beam source, tool callbacks, captures and teardown.
The tap interval must stay closed with an unchanged wheel paint count, rather than relying
on a single late snapshot after a potentially brief open/close.
The beam requires two actual captured draw calls at the exact captured native pose id,
with independent model-attachment, world/pixel origin and visible colour/depth evidence.
The feature run also requires post-action removed/coloured target eye captures for visual QA.
Tool secondary must sample the target RGB; B reload must reset the actual prop to white.
The chosen tools must also be confirmed by authoritative target creation with the active
toolgun/mode. Remover requires that identified target's non-fixture removal in the action
interval, and colour/reload require that target's before/after server colour changes.
An empty scene, fixture cleanup or a missing target cannot certify a tool callback.
All tool settings edited by the test must compare equal as raw strings before Exit.
Wheel/tool receipts must have visible error-free OverlayInfo sources at their exact reserved
sizes and a PNG named by the recorded handle; file existence alone cannot certify the SDK state.
The source simulation flag must match the actual session, so a simulated receipt cannot pass
an Index check. All five native pickup/drop/freeze/reload hook kinds must be observed too.
Renderer success remains a separate required condition. Uses standard-library vector/angle
parsing and independent Source Euler bases, not production's reported difference alone.
Rotation goals are independently composed from the native pickup body/hand and the current
server hand: current_hand * transpose(pickup_hand) * pickup_body. Production debug/target
angles are not used. Earlier runs fall back to the last complete pre-pickup target sample.
Each measured hand delta must also match its declared 90-degree yaw/pitch/roll within 1 degree.
Incomplete or nonfinite components fail explicitly, never decode as a zero-length spin.
Missing samples/images are failures. No game/network/SDK activity or external writes. Exit
0 means every condition passed, 1 failed checks, 2 invalid CLI; malformed evidence raises.
