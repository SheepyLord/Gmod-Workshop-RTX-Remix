# 0147: A camera ring identifies each frame's pose and the render side paces submission

- Status: Accepted 2026-11-10 after Q's pacing comparison; supersedes the serial wait in the
  [V1 work plan](../handover/VR-V1-plan.md). V1's module has only render-side pacing.
- Amended at startup by [ADR 0158](0158-the-first-headset-frame-must-match-its-camera.md): the first eye
  output must match a camera before the later counted fallback can be used.
- Context: spikes S3 and S4 and the [review follow-up](../handover/VR-V1-Q-review-report.md).
  Source queues rendering ahead of the game thread; the pose acquired now need not belong to
  the camera being rendered now.

## Decision

The add-on acquires tracking once per engine frame at the first CalcView or PreRender callback,
sets the camera and pushes its pose with a sequence number. The runtime matches the rendered
Source camera's position and orientation against a ring of 16 poses, excludes already consumed
sequences and submits the matrix belonging to that camera. Invalid head tracking uses the
compositor's own pose and the last valid game camera. A frame without a fresh result repeats
the last pushed camera.

S4 tried the material system's call queue in `mat_queue_mode 2`. Over 120 game frames the
guarded PoC module made 360 attempts, with no accepted callback and no callback executed. This
build returns a private arena, not the public SDK's virtual `ICallQueue`; its first word is not a
vtable. Calling it as one is unsafe. The camera ring avoids that undocumented ABI and preserves
the game's threaded mode. The ring's consumed-sequence test also prevents a nearly identical
older camera from hiding a fresh pose.

In S3, letting the game thread call WaitGetPoses while queued render work still submitted the
previous frame produced 139 failed eye submissions in 6436 frames, OpenVR error 108,
AlreadySubmitted. Locking the Vulkan queue alone does not order the compositor's frame epochs.
A serial completion wait fixed that ordering, but made the game and renderer take turns.
On gm_construct at the Index's recommended size and 90 Hz, C measured 4.541 ms of game work,
9.071 ms waiting for render completion and 8.615 ms in WaitGetPoses, for 44.91 frames a second.
Without submission and pacing the same-sized pipeline reached 101.62 frames a second.

The runtime now calls WaitGetPoses on its render-side command-stream thread immediately after
both eye submissions and PostPresentHandoff; it primes the first epoch there too. Submission
and the wait therefore alternate on the same thread. Neither the request mutex nor the Vulkan
queue lock is held during the wait. Stop sets cancellation, then outwaits the SDK-call mutex
before revoking pointers (`src/dxvk/rtx_render/rtx_vr.cpp:87`, `:615` in the fork at `9d22eef6`).
OpenVR supplies no cancellation for a stuck WaitGetPoses, so Stop has no independent hard deadline.
The largest waits observed in the final 310 s runs were
19.518 ms on gm_construct and 36.912 ms on modern_house.

BeginFrame calls GetDeviceToAbsoluteTrackingPose without a render-completion wait. Its horizon
is the time to the next vsync plus vsync-to-photons and the measured pipeline lead in refresh
intervals. It starts uncalibrated and updates the lead from submitted pose timestamps and
Compositor_FrameTiming, not a guessed constant. The C ABI version 2 Start flag selects this wire
behaviour. Both header copies remain identical. The module no longer offers the serial mode;
the comparison package and source remain in the evidence.

## Consequences

On the RTX 5090 with 2468 x 2740 pixel eyes at 90 Hz, each corrected comparison ran for 310 s.
gm_construct went from 45 frames a second with serial pacing to 89 with render pacing;
modern_house went from 33 to 33. All four runs had zero failed submissions, unmatched
poses or frozen-frame failures. Render pacing recorded zero dropped frames on both maps;
gm_construct's SDK reprojected/present ratio fell from 50.123% to 1.907%.

On gm_construct, BeginFrame took 0.073 ms and actual game-thread CPU work 4.082 ms within an
11.270 ms wall frame. The render thread used 3.018 ms of CPU and waited 8.093 ms in OpenVR.
The engine and DXVK queues pace the game without a module wait or busy loop. modern_house's
14.448 ms of covered GPU/SDK work and 12.795 ms of game-thread CPU each exceed the 11.111 ms
budget at 90 Hz; it reprojects instead of failing or stalling. Less scene work is needed there.

Compositor scheduling estimates put gm_construct's render-paced pose age at 36.076 ms and
prediction timing error at +0.321 ms on average; they do not measure optical motion latency.
At 80 Hz the derived budgets are 12.5 ms for a native frame and 25 ms at half rate. No 80 Hz
throughput was measured, and the heavier map still exceeds the native budget at unchanged size.

## Alternatives considered

- The serial wait is correct in ordering but halves throughput on the reference scene. Its
  timeout tickets and first-render readiness rules disappear with the mechanism.
- A second pacing wait in the module would serialize work again; render pacing already makes
  gm_construct run within 1.4% of the headset's 90 Hz rate.
- Sending the latest pose regardless of the rendered camera would mislabel queued frames.
- Calling the material queue through private offsets would depend on this game build's arena
  layout, even though the safe experiment found no public enqueue path.
