# 0193: VR weapons after independent review

Status: accepted for task W on v4w, 2026-11-11; amended 2026-11-12 below.
Milestone integration/review remains separate. Renumbered from 0180 (K), then 0184 (Q), to 0191 at the coordinator's request, then to 0193 when main was merged into vr2 on 2026-11-12, where 0191 and 0192 were already taken. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

The independent W review exposed artificial movement counted as melee, follow-up bullets
rewritten as first shots, hook-order dependence, delayed projectile relocation and several
effect/lifecycle issues. This supersedes the affected behavior in decisions 0177 and 0178.
The public Weapon interface and C's controller-frame/grip work remain separate.

Melee uses tracked wrist velocity plus world angular velocity crossed with wrist-to-tip.
It starts a new sweep after proxy/physics/locomotion-generation changes or an unexplained
tip displacement over five centimetres. Walking, sprinting, snap turns and teleport paths
must not become weapon swings. Damage/cooldowns still belong to P.

Only a player's or active weapon's bullet starting within five units of GetShootPos is an
initial shot. Other starts retain their source/direction/callback, including tracking gaps.
Missing validated VR geometry vetoes only an unsafe initial VR shot. Server effects use
the actual trace start without an attachment and broadcast to everyone; the VR client's
initial predicted native tracer is suppressed.

An ordinary EntityFireBullets hook returning nil cannot guarantee preparation when an
earlier portal hook returns true. Replacing global hook.Call also fails the native path:
the engine retains its dispatcher reference (the native traces and cached-reference
harness case reproduce this). W therefore owns only this event's table while VR runs.
Its registry-guarded private event prepares the initial shot, then the original dispatcher
runs the held callback table once without a gamemode. Nil returns to the outer engine
dispatcher, which calls its own gamemode exactly once. Cancellation/results keep their
normal semantics. A forwarding table retains hook additions/removals; teardown restores
the held table, materializes callbacks for retained references, and preserves a later
table writer. Global hook.Call and other add-on callbacks/classes are unchanged.

The engine requires true to apply modified bullet data; the base gamemode supplies it
after nil-returning hooks. This is documented by [Facepunch's hook contract](https://wiki.facepunch.com/gmod/GM:EntityFireBullets)
and [base gamemode implementation](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/base/gamemode/shared.lua#L262).
[gamemode.Call](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/includes/modules/gamemode.lua#L73)
uses hook.Call. Offline tests force both short-circuit orders and cancellation/cleanup;
native PoC traces verify engine application and follow-up starts.

Native creation occurs after PlayerPostThink. Launch sound/animation callbacks provide
the early initialized boundary; the sound event table uses the same owned preparation
so a sound filter cannot bypass it. Ready launches relocate there with EF_NOINTERP.
Native VPhysics grenade setup continues after the spawn sound: W places/freezes that
body at the checked hand, then reapplies the captured throw and world-spin conversion
at the next pre-physics boundary (or Stop) and releases its owned freeze. The fuse is
not restarted, and owner/proxy grace remains bounded. Bugbait uses entity velocity, not
a nonexistent VPhysics object. It has no initialized launch callback: its unknown-owner
interval is hidden, then the first ready Tick sets its hand position/velocity and
EF_NOINTERP before releasing that owned visibility hold. Existing hidden states and
foreign owners are retained; timeout/Stop release only W's hold. Acceptance measures its
first visible client position explicitly. Launch alignment uses the ray recorded at firing, not
a later controller pose. Grenade angles precede conversion into physics-local degrees/s.
Foregrip permission/offset is sent as a profile once; the server decides actual
engagement from distance/buttons. Gun-angle updates retain an accepted profile while
awaiting their acknowledgement. Stop changes selection only when Hands is active, with
the best owned weapon as fallback if the prior class is gone.

Impact carries its complete trace fields. A hull hit point is its centre, short of the
surface; a precise contact trace and inward skin let the native effect actually retrace
the surface for a decal. Before/after captures verify the persistent mark with the hand
withdrawn. MuzzleEffect uses explicit origin/angles/scale
([engine effect fields](https://wiki.facepunch.com/gmod/Default_Effects)); image acceptance
must show the flash/impact itself. A nearby dynamic light alone is insufficient.
The package disables model decals by default. W enables them only during VR and restores
its last owned value; a later writer survives. Effect captures wait one Source frame
after creation, rather than reading the previous scene. The successful flash capture
contains the luminous plume itself; no diagnostic geometry or substituted bitmap is used.

## 2026-11-12: second independent review

This addendum supersedes the affected details above. User-requested corrections are:

- Stock dispatch uses the live event root; ULib dispatch owns both its live priority
  tables and plain compatibility table, preserving original priorities/monitor behavior.
  An ordinary hook.Add fallback remains for unknown libraries. A private probe tests
  whether replacing a GetTable event root really affects dispatch. No global hook.Call
  replacement or ULib code is shipped.
- An owned gamemode EntityFireBullets wrapper applies W's table changes if the original
  method returns nil; false still vetoes. Other hooks run before that final application.
  Cleanup preserves a later writer and inherited methods. Base returns true; Sandbox's
  metadata derives from Base. Tests explicitly cover a nil-returning stand-in.
- Melee residuals/sweep starts subtract player-origin movement. The tracked swing's
  damage is unchanged during walking, sprinting or platform motion; proxy/epoch changes,
  half-metre body jumps and five-centimetre relative tip discontinuities still reset.
- Server foregrips reject authoritative off-hand holds, climbing, blocks and P's Holding.
  C's client claim/pose regions remain untouched.
- The session-wide r_drawmodeldecals override is withdrawn. No V4 Done point here requires
  enabling model decals globally. Impact fields/particles remain; model marks obey the
  player's existing RTX setting. Cost/look of enabling that setting have not been measured
  and no proposal to enable it is made.

The earlier decal screenshots demonstrate the old override only, not current default
RTX behavior. Review-2 validation and the one simulated-session receipt are in the W report.

## 2026-11-12: verification-review follow-up

This addendum supersedes the preceding body-relative residual and contact-witness details.
Only artificial body movement is compensated: body-origin delta minus L's applied_total
delta. Physical room travel/lunges are already in tracked velocity. The residual guard
allows a physical proxy one movement sample behind without allowing unexplained jumps.
The actual world sweep starts at the prior tip, not a translated point that could skip
thin surfaces. Start-solid and zero-length contacts do not deal melee damage.

Acceptance now binds the spawned target index, phase serial, tick and measurement window
to an engine EntityTakeDamage witness and a nonzero Impact ray. W's lastHit/effect records
alone do not establish damage. Command-walking and room-follow motion are measured.

Both dispatchers guard re-entry. A copied/rebuilt event table is treated as the caller's
registry: preparation occurs once and normal iteration reaches its other callbacks once,
without recursively replaying the copied dispatcher. The old table is not forced back.

ADR 0193 is the coordinator-assigned final number (0191 until main took 0191 and 0192 on 2026-11-12); 0180 belongs to K and 0184 to Q.
