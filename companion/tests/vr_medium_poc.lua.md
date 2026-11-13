# vr_medium_poc.lua

Private client input/observation fixture for vr_medium_poc.py. Supplies scripted head
rotation and natural recorded-component hand frames, calibrates actual gun aim to+/-45,
and drives only the normal stick path. A low monitor records resulting commands/head
poses/class/model draws; it does not replace movement results. Registers owned temporary
hooks/native wrappers and restores them at Exit. No world target spawn/removal, disk,
SteamVR setting or direct process action; no independent exit code.

The approach uses the normal configured off-hand ground direction; the deliberate conflicting off-hand yaw begins only after real ladder attachment. No ladder state is forced.


Gun calibration now uses the actual post-dispatch command monitor; transient Debug tables are not a feedback source.


Angular calibration uses circular differences, so315degrees is correctly equivalent to-45. Ends one second after every case receipt, retaining the100second maximum.


Final angle witness is the rendered pistol barrel (-model forward), not the converged eye command. Physical controller inputs directly request+/-45; no model/result override. Near-wall eye convergence is recorded separately.


The final fixture uses ordinary tracked-hand poses with no convergence feedback or world-position override. Rendered barrel angle, converged eye command and physical movement remain separate observations.

Round5:33 cases retain the original15 and add6 five-degree ladder trials,6 underwater noclip idle/throttle trials and6 land noclip controls. Head and off-hand directions plus actual stick components are recorded. The same5mm hold,1degree barrel,3degree water-velocity, .2degree wish and .1unit lateral bounds are retained. No old261104 depot pins are passed; current PoC261112 verifies against field manifests. Both locks and normal driver-owned field quit remain mandatory.
