# 0151: V1 uses a fixed VR preset at SteamVR's recommended density

- Status: Accepted 2026-11-10 for V1; automatic tuning remains V6.
- Context: the user's [performance decision](../handover/VR-plan.md), spike S7, Q's scale
  comparison and the final [pacing comparison](../handover/VR-V1-Q-review-report.md).

## Decision

Start VR defaults to render scale 1, DLSS Performance with Ray Reconstruction, and one to four
path bounces. A temporary, fileless runtime option layer above the quality presets disables
DLSS and FSR frame generation, motion blur, chromatic aberration, vignette, the runtime's
present throttle, its free camera and camera shake. The VR desktop present interval is zero;
the game variable `mat_vsync` is not changed. Exit removes the layer and restores the flat
settings, including frame generation if it was enabled before Start. No setting is written to
Remix `user.conf`. The option layer is constructed at `src/dxvk/rtx_render/rtx_vr.cpp:250`
in the fork at `9d22eef6`.

On the Index at 90 Hz, scale 1 gives 2468 x 2740 pixel eyes, a 3072 x 2752 pixel centre and
1536 x 1376 traced pixels. Q's initial serial-paced gm_construct runs on the RTX 5090 compared
scale 1, 0.85 and 0.7: 45, 48 and 49 frames a second, with 9.404, 7.345 and
6.016 ms of covered GPU/SDK work. The lower scales saved work but gained only about 7% and 9%
in frame rate while the serial handover remained the limit. The default preserves the density
SteamVR asked for rather than sacrificing detail to that scheduling problem. The manual scale
control remains available.

After render-side pacing replaced that handover, the corrected 310 s scale-1 run on
gm_construct reached 89 frames a second at 90 Hz, with 9.238 ms of covered work, zero
failed submissions or dropped frames and a 1.907% SDK reprojected/present ratio in the steady
window. The matching modern_house run reached 33 frames a second with 14.448 ms of
covered work and 12.795 ms of game-thread CPU per accepted pair. Both exceed the 11.111 ms
native budget there; the fixed preset is not a promise that every map sustains the headset rate.

## Consequences

V1 has a reproducible preset and a truthful warning rather than automatic quality changes.
The page warns about a low performance tier or less than 12 GiB of VRAM and caps the selected scale
at 0.5 on that warning tier. It also warns about a game frame cap below the headset rate;
these warnings do not block Start. Controller movement and turning remain V2. V6 must tune its
automatic ladder at 80, 90 and 120 Hz.

Every acceptance run was measured at 90 Hz. At the same dimensions, 80 Hz gives a derived
12.5 ms native budget and 25 ms half-rate budget (40 frames a second). gm_construct's final
9.238 ms work leaves about 3.26 ms of GPU budget at 80 Hz; modern_house's 14.448 ms already
exceeds it. No refresh setting was changed and no 80 Hz frame rate is claimed as measured.

The live upscaling reader, not file configuration, proves restoration: Q observed frame
generation enabled before Start, disabled in VR and enabled again after Exit, with the same
upscaler and support flags. Tests also compare the real Source variables before and after.

## Alternatives considered

- Keeping frame generation would count synthetic desktop frames as VR progress without giving
  the compositor a newly rendered head pose.
- Lowering the default scale to hide the serial wait would reduce detail while leaving the
  ordering cost. Render-side pacing resolves that cost directly.
- Calling the fixed preset Auto would promise adaptation that V1 has not implemented or tested.
- Changing persistent graphics settings or `fps_max` from Lua would disturb the flat session;
  the frame cap is reported to the player, and only test launch options choose it for a test.
