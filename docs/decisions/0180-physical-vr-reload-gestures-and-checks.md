# 0180: Physical VR reload gestures and checks

Date: 2026-11-11. Status: accepted for V4 implementation under
[the shared plan](../handover/VR-V4-plan.md). The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

Main A is a tap eject / 300 ms hold secondary for pistol, .357, SMG1 and AR2 while
physical reload is on. A released main-B tap below 300 ms adds IN_RELOAD once for
every other case, including the tools; the hold belongs to T's wheel. Off grip
is claimed in the shoulder zone or while carrying ammo so P cannot grab with it.

The shoulder zone is head-yaw local: 6–42 cm behind, 12–50 cm to either side,
28 cm below through 18 cm above the tracked head. Pitch does not move it. A
server-acknowledged squeeze there with reserve takes a stock visual ammo item.
It reserves no rounds; letting go drops only the visual item. Eject returns exact
remaining rounds to reserve, even above the engine's pickup cap. Ten-second
client physics drops and held models are registry-cleaned, original placements
of base-game assets, with no new binary art.

Points are K-owned data in the gun model's local frame, so W may change weapon
placement. Client insertion: wrist within 6 cm, forward direction within 55 degrees
of the port axis. Server: active entity and server-issued token, free/squeezed off
hand, available reserve, valid tracking no older than 250 ms, carry no older than
30 s, 16 cm and 75 degrees, and a clear segment to the port. The wider server
tolerance permits one pose-sync/physics/network delay, without accepting any
client-supplied position. The stock weapon's local muzzle converts our local port
to W's authoritative muzzle computed from its server hand pose. Gesture messages
are limited to one per tick and one per 80 ms. Inventory changes occur only there.

The 387 x 129 numeric ammo overlay is attached to the physical main-hand device,
beside the gun, facing the head. Clip/reserve and secondary reserve are the entire
paint signature; moving the gun/hiding/showing it does not repaint. Hidden for no
ammo, disabled option, invalid pose/model and a visible wheel. No world-space UI
quad or material is path traced. Insertion pulses the off hand after server ack.

Messages 80/81/82 carry config/action/state within S's assigned range. Debug data
contains server state, counts, hold time, zone/carry, insertion reason, paint/drop
counts. No core, W, H, P or loader source is changed. The report retains measurements,
captures, offline assertions and remaining integration work.
