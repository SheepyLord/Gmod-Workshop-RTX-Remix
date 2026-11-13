# sv_tools_rotation.lua

Review update: cached server convar handles supply timeToArrive (ragdoll variant where
applicable), maxAngular/maxAngularDamping and the real physgun_DampingFactor on every
step, so live server changes apply. Zero angular limits remain zero; arrival time has a
0.001-second numerical floor because ComputeShadowControl rejects zero. The existing
position frame is continued using GetVelocityAtPoint at the origin, not COM velocity.
The parameter table is reused. The review PoC measures off-centre/gravity behavior and
compares the actual damping factor with that server convar, alongside the other limits.
Honouring the real 0.8 damping factor exposed a native steady 15-degree pitch/roll
residual. A bounded integral orientation trim adjusts only the requested goal: integrate
the actual-to-desired world axis-angle error at 8/s, at most 2 degrees per callback and
30 degrees total. Do not integrate errors over 30 degrees; reset on target jumps over
5 degrees or disabled angular force/damping factor. Server force/damping/arrival values,
zero linear contribution and native holding remain unchanged. Debug/acceptance still
compare against the desired hand orientation, never the trimmed goal. The toy residual
plant regression is not a substitute for the unchanged native <5-degree acceptance.
While the native IN_SPEED key is down, the target follows gm_snapangles; releasing it
returns to continuous hand-relative orientation. IN_SPEED remains in the command for L's
sprint, and the angular controller follows the same snap intent instead of opposing it.

Included by sv_tools only at VR server Start. New(ctx,player,hold,hand) attaches an invisible,
non-solid/non-transmitting base_anim motion controller to the existing native-held PhysObj.
Its angular shadow target is the pickup-relative orientation composed with the validated
server hand. The linear shadow goal continues the body's existing velocity for 50 ms,
preserving native positional control; teleport is zero. No mass, gravity, drag, ownership or
collision flag is changed. No native pickup/permission/freeze/reload action is replaced.

The helper owns its controller, not the held body. Stop removes it idempotently. Callback
work is inert after Stop, including an already retained callback reference.
Errors are caught/logged once; the outer owned Tick drops and removes outside the physics
solver. Parameters is also exercised offline. No files/settings/network or process exit code.
The measured selection/limits are recorded in ADR 0181 and T's report.

Native linear trial: zero maxspeed/maxspeeddamp preserved alignment, while a COM target
introduced a 0.568 m error. T now supplies zero linear force/damping; its harmless position
frame uses origin-point velocity and the engine alone controls positioning/gravity. Full
review motion proof is still required on this revision.
