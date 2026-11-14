# W's client PoC fixture

Appended by vr_weapons_poc.py to its generated test probe. Reads native timeline phases,
requests acknowledged server fixture changes, saves eye/centre/depth/overlay/mirror PNGs
and prints plain model/wrist/muzzle/aim/hand/punch receipts as NLVR_W JSON (large records
are base64 chunks to avoid Source's line limit). Tracks switch frames and owned models;
switch timing begins only when the player is alive with a valid shown hand. A respawn's
new weapon can replicate before the client's alive flag; no gun should draw while dead.
records the actual pushed camera under a nonzero view punch.
An owned test mover clears desktop keyboard/buttons before L/W process scripted controls;
the ordinary flat baseline hook is removed while the VR core owns command aim. On Exit removes
its own probe hook and asks the server fixture to clean up. This file never enters the
RTX package. No process exit code.

Owned review observers record the final attack bit during foregrip bursts, muzzle effect
origin/angles/scale, and request firing/melee captures from weapon_fired after effects
are created. A temporary util.Effect wrapper forwards arguments and restores only its
own writer at teardown; it adds no rendering or effect to the shipped weapon path.
Effect captures wait one Source frame after effect creation, so the requested image
contains the effect rather than the last pre-effect scene. First networked projectile
positions and the effective model-decal setting are also recorded.
Melee phases also retain before-contact and hand-withdrawn decal captures, so persistent
marks can be distinguished from existing texture detail and the weapon's occlusion.
An owned test mover supplies 200 units/s lateral command movement during melee-walk,
after L's input setup and before W's convergence. Normal client prediction and the host
CMoveData path apply it; no hand/world-position translation fakes walking.

V8: the melee-walk step goes toward the gun hand's side (`NLVR.Input.mainHand`), which carries the held crowbar into
the plate; a left-hand run mirrors the hands and the targets, so it now mirrors the step too (it walked the crowbar
away from the plate before). The rocket phase runs with `nl_vr_physical_reload` 0: it measures W's launch, and physical
reload (on by default) holds an RPG until a rocket is put in by hand, which this fixture never does. The setting goes
back to its saved value at the next phase and at the end, and `fixture-settings` checks it with the dominance and gun
angle.
