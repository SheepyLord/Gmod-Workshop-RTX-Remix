# cl_core.lua: Client session and play space

New(native,onError,units) returns the core, exposed as NLVR only by Start(modules), removed by Stop(). Preserves V1 camera ownership, predicted feet, proxy Think/NoDraw restoration, once-per-FrameNumber pose sampling, once-per-sequence camera push, last valid camera and bounded native error handling. ToWorld/ToTracking transform Source-basis metres with yaw and scale; seated height translates both head and hands. Space.Turn(degrees) rotates about the tracked head. Space.Shift(delta) takes world game units: L moves the player feet by delta, then calls Shift once, which compensates the anchor and advances the cached floor without moving the head. Space.yaw remains nil until the first view/user command establishes orientation. Pose has physical left/right plus main/off aliases; linear velocity is game units/s, angular velocity remains radians/s. Ray uses the native controller -Z-to-Source +X conversion, i.e. Angle:Forward(). ctx.resolver(priority,fn(hand,state)) mutates shown/blocked/held/grip_curls, never target. Client movers run in ascending priority; equal priorities retain registration order. Aim(angles,owner) applies to this engine tick, first owner wins. On/Emit own listeners by calling module context; Debug must contain plain probe-safe values. Reads all 19 settings at Start; removes every change callback at Stop. No setting writes, files, idle hooks or timers.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

Mover/resolver iteration uses a snapshot so a failing module can remove its entries without skipping the next module in the same pass. Equal-priority registration order uses a monotonic ordinal.

CreateMove stops its current callback immediately if BeginFrame ended the session; it cannot send a fresh sync after STOP.

Follow-up 2026-11-11: `feet()` alone now permits an optional `C.ViewFeet(base)` render-only resolver.
The original `C.Feet` / player position remains the fallback. L owns/removes the resolver, predicts
unprocessed room input for the same rendered pose, and preserves Source's floor height. This applies
equally to ToWorld/ToTracking, camera and hands, without editing CreateMove or moving the player.
Only L may install the resolver; its prediction path does not call Space.Shift.
Locomotion follow-up: the resolver now interpolates non-room XYZ on a buffered monotonic render
clock and adds same-frame room displacement separately; it no longer substitutes tick-stepped
horizontal FOLLOW origins or delegates flight to the engine's older interpolation path.

V4 adds physical_reload/foregrip/ammo_counter (1, 0..1) and gun_angle (0, -45..45), for 19 core settings. CreateMove copies head pitch/yaw with zero roll; CalcView retains tracking roll. After movers, an active Aim rebases forward/right movement by the difference between their final command yaw and the aim yaw, preserving the world direction/speed and up movement. Feet/interpolation code is unchanged.


## V4 controller frames

C composes controller frames with one call to the session-owned `cl_frames.lua` service in Refresh. Ray uses the tip origin and forward. This leaves Q ownership of refresh scheduling intact.

Review correction: repeated Refresh calls share a cached resolver pass when frame, raw poses, play space, base feet, dominant hand and authoritative HandRevision are unchanged. Input changes invalidate the pass. Controller-frame composition belongs inside that pass when C lands.


Render-time coherence: Refresh(true) at CalcView detects advanced motor feet even without a new engine frame. It snapshots one transform for the head and both hands; CalcView uses that head pose. Ordinary duplicate calls remain cached. FOLLOW changes increment MoveRevision. The same-frame regression advances interpolation by 8 ms without a new pose/base and requires camera and drawn hands to agree.


Camera ownership delegates to cl_view_hooks.lua: stock capability probe, real ULib priority tables, protected recursive dispatch and safe refusal for unknown detached hook libraries. Runtime library/authoritative registry replacement still stops the session safely. Other view registrations/removals are deferred and restored.

Movement rule: ground locomotion uses its chosen yaw basis. Water and ladders follow
head pitch/yaw regardless of weapon aim; ladder-only8-way direction buttons are stamped
by the movement mover before tool controls. Gun aim re-expresses that same world motion.
Noclip takes precedence over water and retains full hand-directed throttle flight on
land and underwater. SetupMove never flattens or rebases noclip. Core does not rewrite
movement/tool buttons after module movers.

V6: `quality` joins the settings (0 Auto, up to 16; [cl_perf.lua](../modules/cl_perf.lua.md) clamps it to the ladder).
