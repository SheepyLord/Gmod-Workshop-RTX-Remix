# vr_medium_server.lua

Private server setup and authoritative SetupMove/FinishMove observer for the limited
medium proof. Selects ordinary weapons and resets the test player between cases, then
requires real map-ladder attachment/water. Never sets MOVETYPE_LADDER or alters water,
gravity, lighting or target entities. Emits bounded JSON/chunks and last diagnostic
samples, with each failed case retained. Its private command/net channel exist only in
the snapshotted test add-on. No files, field/Steam settings or process action; exit comes
from the parent driver/reducer.


The ladder setup uses the accessible negative-Y side of the permanent world brush, matching its map ladder endpoints.


Ladder setup stays within real map endpoints and leaves measured travel clear of the ceiling. Water observes a fixed.8second post-input settling interval before its ten samples; speed/direction bounds are unchanged. Diagnostics also record frozen/handled state and actual player velocity.


Readiness freezes the player in NOCLIP only during setup/calibration, then restores WALK, exact initial position and zero velocity before input. Every accepted physical sample must be unfrozen and in the real ladder/water move type.


Final water sampling is a fixed1.5seconds after input begins, then ten Source samples. All bounds unchanged. Setup temporarily uses frozen NOCLIP, then restores WALK/exact position/zero velocity and unfreezes before input; accepted samples explicitly reject frozen physics.

Round5:33 cases retain the original15 and add6 five-degree ladder trials,6 underwater noclip idle/throttle trials and6 land noclip controls. Head and off-hand directions plus actual stick components are recorded. The same5mm hold,1degree barrel,3degree water-velocity, .2degree wish and .1unit lateral bounds are retained. No old261104 depot pins are passed; current PoC261112 verifies against field manifests. Both locks and normal driver-owned field quit remain mandatory.
