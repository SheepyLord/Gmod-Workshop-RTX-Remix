# 0158: The first headset frame must match the camera it was rendered from

- Status: Accepted 2026-11-10 for finding 5 of the second VR review.
- Context: the physical-tracking look in [Q's runtime review report](../handover/VR-V1-Q-runtime-review-report.md)
  found a queued flat camera after the VR projection had already been installed. The neutral scripted pose
  could not distinguish those two cameras because their positions coincided.
- Amends: [ADR 0147](0147-frame-poses-and-render-side-pacing.md), for the first output only.

## Decision

An eye frame needs the VR projection latched for its frame and generation. Before the first accepted
output it also needs an actual match in the camera ring. An unknown camera while no pose has been
consumed produces no eye output. After a first matched output, the counted newest-pose fallback for
genuinely unknown cameras remains as agreed; a known consumed camera is still skipped.

The physical run submitted one unmatched camera among 438 pairs, at consumed pose 0. Its camera was
the fixture's flat position, 823, -657, -40 GMod units, while the latest VR camera was at 764.846,
-659.314, -142.642 GMod units. Its FOV was already 1.90874 radians, about 109 degrees. Checking that
FOV alone therefore missed the bad first view (`rtx_vr.cpp:364` and `rtx_vr_policy.h:21` in the fork
at `d29445c5`, patch 0071).

The renderer logs initial cameras it holds back separately from unmatched submitted poses. The
manual-look driver checks its sample counters as well as normal shutdown, even though a manual run
has no scripted final-vr record. The CPU regression uses a VR camera offset from the flat fixture,
then checks first match and later fallback; the full reference has 249 assertions.

## Consequences

The headset keeps its loading or previous compositor image until the first correct camera arrives.
BeginFrame still predicts without waiting, and SDK readiness still installs the producer before the
renderer reports running. No ticket, game-thread wait, wire change or module rebuild is introduced.
Stop remains the existing SDK-call barrier. Field proof and final binary identities belong to Q's report.

## Alternatives considered

- Projection eligibility alone admits a queued flat camera under the new projection, as the physical
  run demonstrated. A neutral-only timeline is too weak a test for this sequence.
- Waiting for running before installing the producer recreates the startup dependency that the first
  review removed: the renderer needs a camera from that producer before it can run.
- Refusing every later unknown camera would change the agreed camera-ring fallback. This correction
  limits the exception to startup, where no valid VR image has yet established the session.
