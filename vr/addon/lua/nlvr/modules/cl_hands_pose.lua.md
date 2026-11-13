# cl_hands_pose.lua

Resource-free helper table included by [cl_hands.lua](cl_hands.lua.md), also run under LuaJIT.

- `Bones(entity, side)` discovers named ValveBiped/Bip01 wrists, forearms and fifteen finger joints,
  keeping forearm descendants (hand descendants if no forearm). Case/spaces/punctuation do not
  affect lookup. Missing joints are skipped; `__INVALIDBONE__` is excluded before matrix writes.
- `Smooth(previous, priorSplay, input, grip, dt)` clamps scalar input and smooths with a 35 ms
  exponential time constant. Grip overrides all five curls and closes splay; initial input is direct.
- `Angles`/`Apply` map curls to three joint angles and proximal spread with ValveBiped thumb/finger
  axes. Finger yaw is shared; thumb pitch and spread mirror by physical hand. Missing joints are harmless.
- `Resolve(core, side, state)` sweeps a 3.5 cm brush-only palm hull from the head to a shoulder
  (18 cm down/side). The shoulder-controller cast extends 14.5 cm forward to cover open fingers,
  a conservative world-aligned envelope with 5 mm contact skin. A start in that extended shape
  tries a clear point 25 cm back; an unresolved solid start holds at the head.
  Only shown position and blocked change. Priority 10 precedes P's physical-hand resolver.
  Shown vectors are independent copies, including unblocked and solid-start fallbacks, so a
  later resolver can edit shown in place without changing the target or head.
- `Outline(side,w,h)` paints an original static open-hand contour inside an existing 2D canvas;
  it owns no target/render scope and draws no model.

No files, hooks, timers, net or settings on include; no command/exit code. Engine errors propagate.
Tests: [the harness](../../../../../companion/tests/vr_hands_harness.lua.md).

Integration: unresolved solid-start shoulder/hand casts clear shown.valid and set blocked, preserving the target and ray; no hand is placed at the eye.
