# W's server PoC fixture

Injected only by vr_weapons_poc.py through ordinary admin console Lua. Gives/selects
the named weapons, prepares native frozen targets, melee props and a grab prop, scripts
death/respawn, logs server muzzle/projectile/hit/grab measurements. Frozen target faces
sit 5/20 m from the settled muzzle. A separately labelled zero-spread native FireBullets
diagnostic accompanies each weapon's actual trigger shots; spread stays untouched for
those trigger shots. Injects one known view punch to test the real pushed camera and
reads actual post-physics projectile velocities.

The review fixture also records explicit server effect data/broadcast, native initial,
penetration and missing-geometry pass starts/directions with a second hook returning true,
and an eye-line obstacle with a clear muzzle ray. Its util.Effect observer forwards the
original arguments and restores only its own wrapper at done. Exit expectations are
sampled before Stop: an ordinary selected weapon stays selected; Hands restores the prior
selection. This replaces the former unconditional pre-VR-selection expectation.
Bounded two-tick projectile event-order records distinguish creation, initialized launch
callbacks and the first physics boundary; finalized grenade receipts expose the owned
initialization hold. Melee targets now use a flat crate face for visible decal inspection.
For melee-walk a wide stationary plate accommodates lateral body movement; FinishMove
records actual speed/displacement alongside the native held-weapon hit and target health.
The fixture clears its own accepted projectiles between phases so their explosions do
not move the player during later measurements, and queues frag collision diagnostics.
Registers its own fixture hooks/console commands until the short session ends; done removes its hooks and
entities and restores the chosen weapon/dominance.
Before its own selection cleanup, prints the actual and expected pre-VR weapon so
production Stop's restoration is measured independently. Session settings are restored by the
production driver's transaction. No Steam/depot/user.conf write or process exit code.

Third-review receipts include the spawned target EntIndex, phase serial/start and tick,
plus EntityTakeDamage witnesses restricted to that target, player and melee inflictor.
Room-scale lunge uses actual L room follow in walk mode on a temporary static floor;
FinishMove records cumulative room movement. Done restores the prior move mode.
