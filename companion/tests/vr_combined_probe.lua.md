# vr_combined_probe.lua

Private client fixture appended by vr_combined_session.py, never shipped. Inputs: the native
timeline and complete NLVR session. Acknowledges physical phases, records/captures each phase and
near-hand distance, then resets the test arena for movement and menu input. Clears physical
keyboard/mouse input through an owned pre-mover; production claims/resolvers/movers stay intact.
Outputs console records and runtime capture requests; Stop removes the fixture and requests
server cleanup. No permanent state, external files, arbitrary native paths or SteamVR changes.
Lua errors propagate to the standard driver's fatal acceptance checks.

The private P cleanup observation waits one second after NLVR is gone so it observes the server STOP message after it is processed, rather than sampling before the network stop can arrive.

Stage boundaries/slot length come from the recorded CONFIG.combined schedule. The current physical
slot is 4 seconds; near-hand poses match H exactly. No phase clock is inferred from image size.

The physical heavy-body capture includes client held/movement data for the simultaneous locomotion check.

The tracked-curls phase records all five actual manipulated root-joint bend angles per hand,
checks raw skeletal curls without grip override, and captures the world models.

The first installed recorded-pose fixture turns Space back to the requested zero yaw before measuring: desktop input during map/VR startup cannot offset both neutral and snap witnesses. It does not relax either angle bound.

Finger witness rereads engine bone caches from the draw observer and stores open/current local rotations with frame/model provenance. Legacy scalar bends remain diagnostics. Observer ownership restores the predecessor at cleanup.
