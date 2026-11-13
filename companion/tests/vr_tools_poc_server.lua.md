# vr_tools_poc_server.lua

Long T JSON is chunked with bounded per-realm ids and validated on collection. No partial
record is accepted as complete evidence.

Review fixture now uses a real HL2 oildrum001 with gravity enabled, mass centre measured,
and motion initially frozen only to allow deterministic pickup. Native physgun pickup
enables motion. The origin is placed so COM lies on the gun line. Pickup independently
records contact in physics-local coordinates; samples retain actual body transform,
server muzzle and scale for distance/ray calculations. Scoped Entity-metatable ForcePlayerDrop
observer records immediate/0.15 s native held state. No production drop is faked.
The older gravity-free cube description below is historical, not this review fixture.

The motion-only prototype attaches an invisible base_anim motion controller after native
pickup. Its angular shadow target comes from validated server hand poses; its linear target
continues the body's current velocity, with no teleport or changes to mass/gravity/collisions.
Calls/errors are recorded. Native drop and fixture cleanup stop/remove the controller.

Target placement retries authoritative W geometry at 100 ms for at most 30 attempts and
records waiting/failure. A one-shot timer could run before the geometry-token handshake;
that rejected first run is retained and is not a native physgun measurement.
Tool targets require the actual active toolgun and requested authoritative tool mode before
replacing a target. Creation/removal receipts identify its purpose/entity and whether removal
was fixture cleanup; missing geometry leaves the existing target and records a failure.
This prevents an empty scene after failed setup from passing the remover check.
Removal markers belong to each target's captured receipt, because Entity:Remove defers its
callback until after the calling Lua function returns; a temporary shared boolean is invalid.
Tool target readiness also requires W's authoritative gun ray within 8.11 degrees of the
declared neutral forward (dot >=0.99), after the menu closes. This ensures a picture target
is placed from fresh level geometry; it never changes that geometry or selects the weapon.

Setup retains the actual phys_spinspeed and player rotation/wheel sensitivity strings for
interpreting native input experiments; no sensitivity setting is overwritten by the fixture.

Private local-host fixture injected through ordinary admin console Lua by vr_tools_poc.py.
Setup gives physgun/toolgun/crowbar and spawns the real gravity-enabled barrel 100 units
along W's server muzzle. Only its initial pre-pickup placement is frozen; subsequent
grabs/rotation/freezes stay native and T production owns its declared angular controller.
Observational hooks return nil so gamemode/protection still decide. Records actual transforms,
native angular velocity/shadow target, hold/motion state, active class, tool and hook counts.
The native successful-pickup observer separately records body/hand angles for an independent
expected-rotation calculation; it reads no production target/relative-orientation field.
Native linear velocity is retained beside spin, before any evidence summarization.
One initial SaveTable inventory supports the native-controller investigation. Outputs NLVR_T
console records; no arbitrary file IO, user data or Steam settings. Done removes owned fixture,
hooks/commands and restores its saved test-player transform/move type. Runs only inside the
snapshot/lock-owning PoC process; no SDK initialized. No process exit code; errors fail acceptance.
The private StartCommand observer never changes commands or returns a value: sampled native
view angles, mouse deltas, wheel and buttons witness what actually reaches the engine. Successful
pickup also records rotation/attachment save fields, including any exposed embedded fields.
