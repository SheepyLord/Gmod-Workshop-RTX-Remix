# sv_weapons.lua

Session-only server weapon module, order 44. `NLVR_SV.Weapon(ply)` returns nil without a
live VR player/valid hand/active weapon, otherwise `{class,kind,muzzle={pos,ang}}` in world
game units/degrees, using P's stopped physical hand when available. K/T can rely on this
interface; client muzzle geometry is validated and transformed from that server pose.
Start publishes the function; owned cleanup removes it. No files/settings are written.
Message 64 validates model-local muzzle/foregrip data against the current class, bounds
and finite values. Offsets use three explicit floats per vector in metres, avoiding the
engine vector codec's 1/32-unit quantisation. Message 66 acknowledges accepted class/token
pairs. Uses the core's one-second pose validity bound, reachable server hands and a checked
eye-to-muzzle trace. The projectile being relocated is excluded from its own safety trace.
Message 65 reports actual bullet callback hits and projectile launches, keeping the
original callback/spread. EntityFireBullets applies only to the player/active weapon and
disables native tracers only for initial shots within five units of GetShootPos. Follow-up
penetration/ricochet/projectile-impact starts remain untouched even without VR geometry;
an unsafe initial VR shot alone is suppressed. Owned turrets keep normal behavior.
The owned EntityFireBullets event table prepares before ordinary hooks, including when
the engine retains its original dispatcher. The held table is dispatched once without a
gamemode; the outer dispatcher then calls its gamemode once if no hook returned a value.
An owned gamemode wrapper makes changed bullets apply when that method returns nil,
while false still vetoes them. Stock live roots and ULib's priority/plain tables are both
supported; other libraries retain an ordinary hook.Add fallback. A private probe checks
root-table replacement capability. ULib's original priorities and monitor semantics run
through its original dispatcher. Cleanup retains new hooks, removals, captured references
and later table/gamemode writers; global hook.Call is unchanged.
The server broadcasts explicit-start tracers to everyone;
message 65 no longer asks the host to draw another tracer.
OnEntityCreated queues HL2 projectiles. The launch sound/animation callbacks relocate
initialized launches in their creation tick; PlayerPostThink and bounded Tick handle
late ownership. EntityEmitSound has the same owned event-table preparation, so a sound
filter cannot skip it. Native grenade initialization continues after its spawn sound:
W places/freezes its VPhysics body at the hand, then reapplies the saved physical throw
and spin at the next pre-physics Tick, or at Stop, before releasing its owned freeze.
Bugbait has no VPhysics object and uses its native entity velocity path. Its uninitialized
owner interval is hidden until its first ready Tick relocates it and sets EF_NOINTERP.
Existing hidden states stay theirs; a foreign owner, timeout or Stop releases W's hold.
An owned EF_NOINTERP bit survives the relocation snapshots, then clears; existing bits
remain theirs. Grenade angles are set before world spin is converted into the physics
object's local frame. Tick reuses P's melee Hit/Damage and Throw maths,
including release-event exclusions. Physics launches use instantaneous velocity once.
Grenade grace lasts 200 ms only against the owner/proxies, with temporary native no-collide
pairs (reverse on removal) and exact custom-flag restoration. Every pair is owned and
removed at expiry/Exit. World collisions remain active.
Grenades also pass through P's public Grab/Release(false) when allowed, registering
its own swept-hand release exclusion without recalculating delayed throw velocity.
Owned per-target melee cooldowns protect the launch even if pickup permission refuses;
this prevents P's separate force impulse after a damage veto. Old cooldowns restore only
when W still owns their last value. EntityTakeDamage
suppresses only the armed main proxy's unarmed punches. Start/spawn gives nlvr_hands;
Stop strips it, reselecting the pre-VR class only if Hands was active (best owned weapon
if that class is gone). Another active weapon stays selected. Plain diagnostics record shots/projectiles.
No process exit code; include/start errors propagate through the module registry.
Without the engine weapon registry Start stays dormant and installs no resource.
P's passive touch use does not check its claim mask. W holds/restores only the armed
main hand's existing use cooldown while that feature is active, keeping off-hand use;
Hands/death/Stop restore W's last owned value. Q can move that check into P at integration.

Melee speed is tracked wrist velocity plus world angular velocity cross wrist-to-tip.
Artificial displacement is player-origin change minus L's applied_total room-follow
change; tracked physical walking/lunging is not subtracted twice. The residual guard
accepts the synchronized body frame or a proxy one movement sample behind, while still
rejecting unexplained jumps over five centimetres. Damage velocity remains tracked only,
but the sweep starts at the previous world tip so body movement cannot skip a thin door.
Start-solid/zero-length contacts are rejected. Proxy/epoch changes and half-metre
artificial body jumps still reset. Slow tracking never calls P's Hit. Off-hand grip/climb/blocked state and
P's public Holding result disallow server foregrip engagement. Impact data
includes the trace start/entity/surface/hitbox and club damage type. No process/filesystem
side effects were added; see decision 0193 for these review corrections.
The hull centre may sit outside the hit surface. A precise contact ray plus inward skin
gives native Impact a real surface to retrace for its decal, rather than ending short.

Dispatch refuses recursive replay. If another writer copied/rebuilt the event table,
it prepares the bullet then leaves iteration to that caller instead of replaying the
copy; other callbacks run once. Both server and client copies are tested.

Q4 integration centralises armed-hand ownership and released-projectile grace in P; passive touch honours the claim mask. W no longer edits P cooldowns or vetoes proxy damage. Camera override users share a lease and restore on module failure/Exit, preserving other config writers.

Independent review removes the unreachable grenade Grab/Release path and releaseGrace diagnostic. Grenades keep RegisterReleased collision grace and explicitly request P projectile feedback; death and dead-player tick ownership cleanup have rejecting mutation tests.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
