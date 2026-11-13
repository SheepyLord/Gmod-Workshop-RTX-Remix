# sv_reload.lua

Server reload module, order46, only for the admitted VR host. Registry-owned
StartCommand, WeaponEquip, PlayerDroppedWeapon and EntityRemoved hooks maintain
stock-gun state; no standalone entry point, file writes or exit code.

## Authority and trust boundary

The server trusts **bounded client-synced hand/head poses** admitted by the core,
and W's bounded client-sent muzzle offset in **message 64** (up to1.5 m). W applies
that offset to the server's copy of the synced hand pose. This is **not independent tracking attestation**.
K does not accept a separate insertion point, ammo count, capacity or arbitrary
loading-port data in its gesture message. It checks active weapon ownership,
server-issued token, grip/free hand, reserve, pose age, distance/alignment and a
clear segment to its own stock-model loading port. This guards inventory authority;
it does not prove a remote controller is physically where the client claims.

## State and timing

80 configures the setting/main hand;81 requests eject/take/insert/drop;82 returns
state and a16-bit lease serial. Its physical flag means active **for this weapon
now**, including alive/vehicle/config checks. Changed fields publish immediately;
an otherwise unchanged state gets a new lease serial every.5 real seconds. Client
expiry is1.5 real seconds, matching the server config lease. Gestures use real
time (80 ms plus one per engine tick); carry lasts30 real seconds. Pose freshness
still uses the core's game-time sync timestamp, in the same clock as that producer.
Clip16/reserve24 wire values saturate; authoritative inventory/debug counts do not.

Every stock gun's exposed holster timer is refreshed at most every.5 game seconds,
including holstered guns. GMod's FIELD_TIME save interface reads/writes a relative
time: setting0 means now (the native probe records the round trip). Primary holds
are only rewritten when missing/reset/expiring; no secondary or player-wide attack
lock is changed. Native reload flags are checked on transitions or at10 Hz, not
resolved by name for every gun every command. Exposed-field membership is cached.
The pistol's unexposed soonest-primary field is not invented or written.

Per-gun state survives settings, hand changes, vehicles and config gaps. These
suspend holds/carry, not ejection/readiness. RPGs start unloaded, and only an
accepted insertion arms the next native reserve-fed shot; insertion does not
also remove a rocket. A positive clip supplied externally clears stale ejection
and releases the owned hold. Death/Stop discard state; removed weapons are pruned,
dropped weapons release their deadlines, and equipment hooks register new guns.

Inventory transfers use SetClip1/RemoveAmmo; eject uses SetAmmo to preserve rounds
above pickup caps. Shotgun adds one shell; crossbow/pump/delayed states are made
consistent. Debug tables and packet comparisons are reused; unchanged packets
are not serialized through the core. A failed server half explicitly disables
physical mode on Stop, with the client lease as the no-packet fallback.

Message82 appends an attack-ready boolean after the lease serial, based on the native relative m_flNextAttack field; this is a fallback for clients without that save field.


Second verification corrections: message 64 also supplies bounded pitch (+/-45
degrees), foregrip displacement (<=0.65 m) and the two-hand flag. W uses the synced
main/off hands and that foregrip to re-aim the gun, then its SafeMuzzle trace from
the player's eye clamps the muzzle against solid geometry. K transforms its own
model-local loading port from that resulting position/orientation. These bounded
client inputs, proxy constraints and trace are the trust chain, not independent
tracking attestation.

A persistent action reply (serial/kind/result) is included in every subsequent
state report until replaced by another action; routine state cannot erase a rate
refusal. Retries of a completed serial are idempotent. Carries survive up to five
real seconds of config lapse while the player lives, remains outside vehicles and
keeps the same active weapon/grip; insertion still requires fresh poses/config.
K-shaped far-future primary deadlines are never restored as an external prior
when a map restores a weapon. Native-ready B delivery remains independently bound
at0.3 s in the acceptance analyzer.
