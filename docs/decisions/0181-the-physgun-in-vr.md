# 0181: The physgun in VR

Date: 2026-11-11. Status: implemented on v4t; packaged simulation/Index component proof recorded;
reviewed K's B/unfreeze integration passes simulation; final C/Index acceptance remains open.
Authority: [V4 plan](../handover/VR-V4-plan.md), physgun decision and task T's measured choice. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

The engine physgun remains the weapon and owns pickup, positional control, collision,
freeze and unfreeze. T observes successful OnPhysgunPickup, never returns a pickup/permission
decision, and returns nil from all server hooks. W owns trigger/A; K owns B reload. No console
attack command, replacement grab, native trust change or loader change is introduced.

The native baseline in out/vr/v4t/native-02 settles at yaw/pitch/roll errors
**0.8873 / 95.3241 / 90 degrees** for the declared 90-degree poses. Native Use/mouse/key
experiments in engine-01 measure mouse yaw/pitch and movement-key yaw, with no direct roll
tracking. Command mouse-wheel changes give **0 m** displacement. No held-angle save field is
exposed in the measured physgun SaveTable. Static strings alone were not treated as writable
fields; the failed Ghidra launch and bounded ordinary PE observations remain in the ledger.

Choose an angular shadow controller on the **existing native-held PhysObj**. An invisible,
non-solid/non-transmitting base_anim motion controller follows the initial prop orientation
relative to the validated server hand, composed rigidly each physics step. Its linear target
continues the body's current velocity for 50 ms; it does not replace native positional control.
No teleport, mass, gravity, drag, ownership or collision flag changes. The engine still holds
the body and emits its ordinary freeze/drop hooks. Drop/death/holster/stale pose/Exit removes
the controller. Callback failure schedules cleanup through the owned Tick, outside the solver.

The private motion-01 trial measures settled errors **0.0405 / 0.0407 / 0.0332 degrees**,
orientation ranges at most **0.0000013 degrees**, and **0 degrees/s native spin**. Thus the
two controllers settle together rather than visibly fighting. Native Use+forward/back moves
the held distance **2.35156 -> 7.47180 -> 2.26316 m**. T uses that native distance path, with
partial-stick time-weighted key pulses and a 0.2 dead zone. The main stick is claimed while
holding; raw mouse rotation deltas are consumed after locomotion reads them.

W's ConvergeAt receives the server-held distance, keeping the prop on the gun line instead
of tracing back onto the held prop. Reliable changed-only hold state has no silence timeout;
explicit native drop and lifecycle clears end it. Local tracking loss suspends controls while
retaining the last authoritative snapshot until the server clears it or tracking recovers.

DrawPhysgunBeam suppresses only local VR effects and draws from W's world muzzle. The existing
physgun_drawbeams preference remains authoritative. Tests temporarily enable it and restore
the exact string. Fresh settled draw origins match the independently sampled muzzle exactly.

Offline helper/lifecycle tests and the final simulation/Index/package/gate receipts are in
[T's report](../handover/VR-V4-T-report.md). Prototype success is not final packaged acceptance.

## Independent-review corrections, 2026-11-12

This review supersedes the original large angular constants: use live server
physgun_maxAngular/maxAngularDamping/timeToArrive (ragdoll variant where applicable).
T supplies zero linear force/damping; native positioning remains alone. The offset-mass
gravity barrel trial rejects a COM target and confirms zero linear contribution preserves
contact alignment. IN_SPEED snaps the angular goal using gm_snapangles, without consuming
L's sprint bit; release returns to continuous hand-relative orientation.

Use Entity:ForcePlayerDrop with server/client trigger rearm. Both native APIs release
immediately on this build, but either can reacquire with held attack. Failed creation
can precede native attachment; retain that failed hold and drop on Tick. Physical stick
ownership lasts until neutral after drop/tracking loss or a hand swap.

Visual beam origin is the rendered model muzzle attachment (W fallback). The measured
4.369-unit nominal-W/attachment difference is reported without changing W. Native effects
are suppressed after replay of existing stock/ULib handlers through the live registry,
not an early non-nil hook or replacement of public Call/Run fields alone. Independent
render-call/model/capture proof supersedes earlier self-comparing beam claims.

## Verification follow-up, 2026-11-12

The real damping convar is physgun_DampingFactor; native evidence now compares it as well
as angular limits and arrival time. Beam startup always installs an ordinary hook before
registry inspection, creating ULib's empty priority lists. Unsupported registries retain
that fallback without raising, while recognised registries preserve post-dispatch replay.
Empty/populated ULib lifecycle tests require exact restoration and a second Start.

The former draw-start/attachment equality is diagnostic identity, not independent origin
proof. Acceptance now fits actual beam pixels against the projected model attachment and
checks the visible beam boundary against captured opaque gun depth. Alignment is bounded
by 2 internal render pixels (before upscaling), visible-boundary error by 12 output pixels.
Opaque geometry prevents a claim to measure the hidden three-dimensional root directly.

Honouring the real factor 0.8 exposes a steady native pitch/roll error around 15 degrees
in verify2-features-01; that failure is retained. T therefore adds a bounded integral
world-axis orientation trim to the goal, keeping the exact server force/damping/arrival
parameters and zero linear forces. Trim is capped at 30 degrees and 2 degrees per physics
callback, reset on large desired-pose changes/disabled control, and ignores travel errors
over 30 degrees. Independent acceptance remains against the untrimmed hand goal. A toy
plant regression establishes the feedback contract; only a new native run proves settling.
