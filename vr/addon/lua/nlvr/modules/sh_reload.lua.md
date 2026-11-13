# Shared physical reload data and geometry

Included only by the reload modules at VR Start. Returns original HL2 class data,
model-local magazine/loading/ejection points, stock ammo models and reload sounds;
messages 80 (configuration), 81 (action), 82 (state); shoulder, alignment,
port transform and conservative clip-transfer helpers. No side effects on include.

Distances use session game units per metre. The shoulder zone is head-yaw local:
6–42 cm behind, 12–50 cm to either side, 28 cm below through 18 cm above the head.
Client insertion is 6 cm / 55 degrees, server validation 16 cm / 75 degrees, with
250 ms tracking freshness imposed by the server. Server ports transform our local
point through the stock model's local muzzle and W's authoritative muzzle pose.
Each gun records its own loading point and insertion axis: grip-bottom magazines,
the revolver cylinder, shotgun underside, crossbow rail and RPG rear tube. Muzzle
and aim-frame data come from stock-model measurements; K's native calibration
must verify the reviewed W placement before these become acceptance evidence.

`Transfer` caps clip/reserve/max-size arithmetic and adds one shotgun shell.
RPG uses a ready latch because the native weapon consumes reserve directly.
No helper mutates ammo. Errors propagate to the owning registry.

An optional trusted per-class `frame` stores the measured model rotation relative
to W's aim frame. This avoids treating aim angles as the model attachment's own
axes. Its muzzle-relative displacement scales with session units per metre.

ACK_LEASE is1.5 real seconds for server config and client acknowledged physical state. Message82 appends a16-bit changing lease serial so a healthy idle server is distinguishable from a stopped one. Model-local port data is K-owned, while its hand/world transform ultimately trusts the core/W bounded client inputs; see sv_reload.lua.md.

ACK_READY identifies the trailing attack-ready bit in82; both K halves ship together.

ACK_POLICY, ACTION_SERIAL, SHORT_LAPSE and HOLD_MARK support safe gesture ownership, persistent action acknowledgements, bounded lapse recovery and recognition of saved K holds. State82 adds policy/serial/result; action81 adds a16-bit serial.
