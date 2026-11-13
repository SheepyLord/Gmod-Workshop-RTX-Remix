# VR task C: controller frames (the real hand, the pointing ray and the gun in the hand)

Branch `v4c` in `out\worktrees\v4c`, cut from `vr2` after task W's merge. Read [VR-V4-plan.md](VR-V4-plan.md)
for the V4 rules (they add to [VR-V2V3-plan.md](VR-V2V3-plan.md)'s rules for every task, for PoC and VR tests)
and [VR-plan.md](VR-plan.md) for the design. Your report: `docs/handover/VR-V4-C-report.md`. Your decision
records: **0186-0187**, with their lines in `docs/decisions/README.md`.

## What Claude found

Every VR module treats the controller's raw device pose as the hand:

- `C.Pose[hand]` is the raw pose (`GetDeviceToAbsoluteTrackingPose`, `vr/native/session.cpp`, converted by
  `pose_math.cpp`); `C.Ray(hand)` points along its forward (`cl_core.lua`, `C.Ray`), with a comment saying raw
  -Z is the pointing direction "for Index, Touch and Vive". The laser, the teleport arc, gravity-glove targeting,
  the weapons' aim and convergence and the tools all point along it.
- H puts the c_arms wrist bone at the raw origin, rotated by the raw angle and a -90 degree roll for both hands
  (`cl_hands.lua`, `build_bones`).
- W orients the gun along the raw angle plus `nl_vr_gun_angle` (`cl_weapons.lua`, the `angle` before the
  foregrip) and gives the armed hand that angle (`poseGrip`).

SteamVR defines, for each controller, where the user's hand is and where it points, relative to the raw pose:
the render model's components (`component_local`: origin in metres, `rotate_xyz` in degrees). From the files in
SteamVR's install (`drivers/indexcontroller/resources/rendermodels/valve_controller_knu_1_0_left|right/*.json`,
`resources/rendermodels/vr_controller_vive_1_5`, `oculus_cv1_controller_right`, `oculus_rifts_controller_right`,
`oculus_quest2_controller_right`):

| Controller | `tip` (where the user points) | `openxr_handmodel` |
|---|---|---|
| Index right | origin (-0.006, -0.015, 0.02), rotate (-40, 5, 0) | origin (0.015, -0.015, 0.13), rotate (-40, 5, 0) |
| Index left | origin (0.006, -0.015, 0.02), rotate (-40, -5, 0) | origin (-0.015, -0.015, 0.13), rotate (-40, -5, 0) |
| Touch (Quest 2 right) | origin (-0.0167, -0.0252, 0.0247), rotate (-37.4, 0, 0) | origin (0.0113, -0.0018, 0.1019), rotate (-39.4, 0, 0) |
| Touch (Rift S, CV1 right) | origin (-0.0063, -0.0252, 0.0347), rotate (-39.4, 0, 0) | as Quest 2 |
| Vive wand 1.5 | origin (0, -0.01, -0.007), rotate (1.282, 0, 0) | origin (-0.02, -0.0285, 0.097), rotate (1.282, 0, 0) |

The Index's body extends from 0.02 to 0.20 m behind the raw origin (+Z in OpenVR), and its strap side is +X
for the right controller: the right palm faces -X (Source +Y, left) around the handle.

So with an Index or Touch controller held naturally (the tip level), the raw forward points about 40 degrees up:
the laser, the arc, the guns, the physgun beam and the toolgun ray aim about 40 degrees above where the player
points; the drawn wrist sits at the controller's top front, some 15-20 cm ahead of the real wrist; both palms
face up at the raw identity and towards the player when the tip is level, never inward around the handle; an
armed hand is open beside the gun (Claude's crops of W's Index run, `out/vr/v2/review/W-pistol-hand.jpg` and
`W-smg1-hand.jpg` in the main checkout). Every test so far used scripted identity poses, which hid it.

## What to build

1. **One definition of each hand's frames, in the core, from SteamVR's data for the controller connected.**
   - `raw`: the device pose as now, kept (for example `C.Pose[hand].raw`).
   - `aim`: SteamVR's tip pose (raw composed with the `tip` component). `C.Ray(hand)` returns its origin and
     forward, so everything that points, points where the player points.
   - the hand frame: where the real hand is around the controller (the palm, oriented like the aim: forward
     where the hand points, up through the thumb). It becomes `C.Pose[hand].pos/ang`, which the modules, P's
     hand proxies and grabs and the server sync already use.

   The native module reads the components once per controller (re)connection through `IVRRenderModels` (the
   render model name from `Prop_RenderModelName_String`; the `tip` component and the hand's, or SteamVR's
   skeletal input with `VRSkeletalMotionRange_WithController` for the wrist and palm) and hands them to Lua with
   the frame data. Compose the constants with the predicted raw pose, so prediction stays as it is. A controller
   without them falls back to raw with one log line. Choose what defines the palm and record why.
2. **H:** place the c_arms wrist relative to the hand frame so that the hand wraps the controller's handle the way
   SteamVR shows a hand on it: palm inward (the right palm faces left), thumb up at the face buttons, fingers
   around the handle; mirrored for the left hand. Derive the offset from SteamVR's skeletal input (the wrist and
   metacarpal joints relative to the raw pose, read on the Index) or from the c_arms model's own geometry, and say
   which, with the numbers.
3. **W:** the gun's grip inside the closed main hand, the barrel along the aim (level when the player points
   level) and upright. `nl_vr_gun_angle` stays a user trim around that (0 means SteamVR's aim). The armed hand
   closes around the grip with the index finger at the trigger; the foregrip hand closes around the foregrip.
4. **Everything else keeps working through the core:** P's proxies, grabs, climbing, gloves and melee; L's
   hand-relative movement and the teleport arc; M's laser and the wrist panels; K and T through W. The wrist HUD
   and wrist menu stay where they were on the wrist: if they are placed from `C.Pose`, keep their placement
   relative to the controller.

## Tests

- **Offline:** the composition against the table above for the Index (both hands), Touch (all three) and the
  Vive wand. Copy the numbers into the test with their source named; tests never read SteamVR's install. A
  natural hold (raw pitched so the tip is level) gives a level `C.Ray` within 0.5 degrees; the hand frame's palm
  normal and finger direction are right for both hands; W's gun is level and upright in it.
- **Simulated captures with natural-hold scripted poses**, never identity poses: hands at chest height in front of
  the head, the tip level. For both hands empty, the pistol, the SMG with its foregrip, the crowbar and the
  physgun: the hand wraps the controller (draw SteamVR's own controller render model, its `_low_res.obj` read at
  test time from the SteamVR install by a test-only probe that the package never ships, at the raw pose, in a
  separate diagnostic capture); the gun level within 5 degrees, upright within 5 degrees, its grip inside the
  closed fingers; the laser level. Claude will look at these pictures, so make them clear (crops of the hands).
- **Index:** the components read live from the real controllers (log them), the skeleton's wrist against the
  drawn wrist (distance, palm-normal angle), and the same captures.
- Everything already accepted still passes: H's, W's, P's, L's and M's offline suites, and one simulated
  combined session (W's `vr_weapons_poc.py` timeline is a good base).

## Files

`vr/native` (the session, the Lua export, their tests), `vr/addon/lua/nlvr/core` (keep the change in
`cl_core.lua` small: one call from `C.Refresh` into a new core file such as `core/cl_frames.lua`, and `C.Ray`),
`cl_hands.lua`, W's `cl_weapons.lua`, `cl_weapons_model.lua` and `sh_weapons.lua`, and their tests. Leave P's, L's
and M's files alone unless one needs a change; then keep it minimal and say why. Task Q is changing `C.Refresh`
(once per frame) and P's files at the same time: Claude merges C into `vr2`, and Q merges `vr2`. The module changes,
so rebuild it, refresh its provenance (`tools/ci/repo_builds.py refresh`) and import it once, as R did.

## Done when

Offline, simulated and Index evidence as above; `tools\test.ps1 -Config Release` passes in your worktree; the
report gives the numbers and the pictures' paths, and says what Q must rerun.
