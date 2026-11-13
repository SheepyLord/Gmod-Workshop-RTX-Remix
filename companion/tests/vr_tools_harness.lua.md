# vr_tools_harness.lua

Hook-library cases implement independent ordinary and ULib priority tables; ULib Call
dispatches only from the latter. Empty/existing events test Start, exact table restoration,
Stop and second Start. A detached-GetTable library must retain the ordinary fallback.
Moving hand/cache cases include 1 mm accumulation and wrapped angles; server limit stubs
use the actual physgun_DampingFactor name. Hands inherits weapon_base's generic draw method
and WepSelectIcon texture in the stand-in, so both default paths are exercised rather than assumed.
A labelled independent toy plant reproduces the native measured 90-to-75 degree damping
residual and tests feedback convergence/reset without changing server parameters. A second
case bounds trim and disables it with zero angular force. Actual Source settling must pass PoC.

Client review cases dispatch peer beam hooks through both Call/Run, assert one material/
debug object over repeated draws, stable tool/debug/inventory/native overlay work while
inputs are unchanged, custom SWEP selection drawing, one refused switch plus visible
feedback, excluded Use-chord hints, and IN_SPEED snap/release.

The native API probe found both drop functions release a physgun immediately on this
build, and either can reacquire while attack stays held. The fixture models that immediate
drop and separately requires the supported Entity:ForcePlayerDrop path. Failed creation, invalid pose, hand change,
controller failure and Stop must release it and send clear state. Separate cases enforce
server angular/arrival limits and origin-point velocity, including a nonzero COM-velocity
difference. Native tests are required; this stand-in is not evidence of engine behavior.
Server rearm rejects held attack until a valid physical release sync and an attack-free
command; this protects the gap before/coalescing of the client's empty receipt.

Review regressions assert owners after a pushed-stick drop, transient tracking loss,
hand swap, and wheel close/cancel with a held trigger. They verify release/neutral
rearming and absence of native distance commands while a stick is only latched.

W/K claim contracts cover physgun/toolgun attack, A and B reload passthrough; clip-gun
K A ownership through wheel open/close; a pending K B tap delaying a new wheel hold;
and cancellation if another module claims B while the wheel is open. These use real
Input claims with W/K boundary command bits; the game feature run uses actual W/K.

The rotation failure case injects a refused solver call and requires one logged failure,
no destruction inside PhysicsSimulate, and deferred Tick cleanup without removing the prop.
Repeated pickup without an intervening drop must replace/detach the old helper, and retained
physics callback references must do no work after Stop.

Custom icon tests require the icon-area clip during the SWEP callback and its cleanup,
including a callback that deliberately throws.
Selection cases include prediction command zero, single attempt before engine acknowledgement,
exactly stopping at acknowledgement and a bounded expiry without an inventory change.

Changed-only hold state is tested at ten seconds without another packet; tracking loss,
entity removal and a server Stop's explicit clear receipt remain separate release tests.

Offline cases for T, run with root/scenario by vr_tools_test.py. Uses S's independent
Euler, inventory and command fixtures, real input and T's modules. Own NLVR.Weapon stand-in
implements V4 section 3 without loading W. Owned-context fixtures record hooks/movers/events
and invalidations. Server fixtures observe pickup/drop/stale state, never simulate native
physgun physics. Geometry: 200 rigid round trips, 90-degree axes, wrapped/singular-adjacent
angles, 30/66/90/120 Hz stick integration, inventories to 155 and all pages/sector picks.
Behavior: translated stage/operation/text changes, tap/hold, claims, queued selection,
death/loss/mirroring/inventory changes, convergence clearing, beam and idempotent cleanup.
Mirrored cases select with left B/left trigger, place tool help on the opposite side and
derive the server hold from the left pose; changing the main hand drops the old native hold.
The beam respects physgun_drawbeams 0 while still suppressing the old local effects.
The complete client mover, not only its pure helper, integrates a one-second stick at
30/66/90/120 rendered commands per second with native Use/forward/back flags. Partial-stick
duty integrates over game time. The angular helper contributes zero linear force/damping;
controller attachment/target/cleanup are observed through explicit engine stand-ins. The
stand-in does not simulate competing native controllers; motion-01 supplies that measurement.

Contracts: [DrawPhysgunBeam](https://wiki.facepunch.com/gmod/GM:DrawPhysgunBeam) has a physics-bone-local
hit point; [OnPhysgunPickup](https://wiki.facepunch.com/gmod/GM:OnPhysgunPickup) observes success without
approval; [CUserCmd:SelectWeapon](https://wiki.facepunch.com/gmod/CUserCmd:SelectWeapon) queues selection.
Stock sandbox gmod_tool/cl_init.lua owns tool information filtering. Native physics, font
appearance and compositor delivery require PoC proof. No file/network/SDK side effects.
Prints PASS or raises (LuaJIT nonzero exit).

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.

q5_ladder_distance asserts neutral-main-stick off-hand climbing has no Use, and main-stick push/pull keeps native distance buttons.
