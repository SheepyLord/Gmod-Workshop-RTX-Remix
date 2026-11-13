# sv_tools.lua

Creation failure inside the successful-pickup hook can precede the native held flag.
T retains that failed hold and drops on Tick after attachment, rather than losing its
only reference after an ineffective immediate drop. The release rearm guard remains active.

Forced release uses the held Entity:ForcePlayerDrop, including failed controller creation;
Player:DropObject is not used for a physgun hold. A failed creation briefly publishes the
hold, then sends an empty receipt when Tick drops it. The client keeps physical control
rearm guards after that receipt. Native review covers invalid sync, hand change,
controller error and creation failure, including sustained non-reacquisition.
A nil-returning StartCommand hook under T's own id additionally blocks held attack until
a valid release sync and attack-free command, preventing native reacquisition before the
receipt arrives. K's separate reload hook is left intact; no pickup permission is granted.

A repeated confirmed pickup first detaches the previous helper without dropping the native
hold. A delayed/missing old drop notification cannot orphan a controller across Exit.

Module Stop also sends the changed empty hold receipt (including isolated module failure),
so the client does not retain a server hold that has been dropped during cleanup.

Local-host server module, order 48, included by the dormant VR switch. Observes confirmed
pickups only with W's server Weapon service present; without it Start stays resource-free.
OnPhysgunPickup after native/prop-protection approval; all hooks return nil. Stores physics
bone/local contact, distance and hand-relative rotation. Tick sends changed/coalesced message
96 and plain measurements. Message 97 is the dominant-hand boolean, never a client-selected
entity or transform. Uses W's server Weapon API and the core's expiring validated poses.

sv_tools_rotation.lua follows pickup-relative hand angles on the same native-held body;
ADR 0181 records the measured choice. Drop, death, invalid tracking, controller failure,
holster and Stop remove the angle controller and clear state. Stop drops native holds
through Entity:ForcePlayerDrop. No mass/gravity/collision flags, files, settings or engine files change.
Framework cleanup owns hooks/receivers.
No process exit code; errors follow framework cleanup. Tests: vr_tools_test.py.
