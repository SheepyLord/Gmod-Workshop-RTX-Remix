# 0183: VR review resource and physics corrections

Accepted for Q's branch integration, 2026-11-11, by Claude's review instructions relayed by the user.
Supersedes the NPC ragdoll-setting and retained-overlay policies in
[0173](0173-vr-integration-review-fixes.md). Its other fixes remain in force.

VR never writes `ai_serverragdolls`, including at Exit. Server death ragdolls are grabbable when
the game creates them. The VR help directs the player to the game's Keep corpses option.
An explicit per-NPC server-ragdoll test fixture proves grabbing without changing that setting.

Logical overlays own their canvases throughout their lifetime, but native handles exist only
while shown or for two seconds after hiding. At the native bound, evict the least recently
hidden handle. An all-visible bound leaves a requested object hidden and logs once; it never
stops its module. Three reserved arc dots plus the target replace eight dots plus the target.
The native bound stays 32. The runtime's separate bound is **16 distinct pending source requests**,
including removal and window-source requests, drained by `applyOverlayRequests`; it is not a
bound on its live overlay images. The manager batches requests across frames. The 21 reserved
roles, including all V4 placeholders, fit both bounds without a runtime change or cap increase.

The server adds authoritative player velocity to tracking-relative hand velocity at validated
sync receipt, before history is stored. Proxy following feeds that world velocity forward;
hold damping and throws use the same world convention. Client hands predict the current tracked
pose with the server's obstruction correction, preserving the client's geometry stop, instead
of stepping between old proxy positions. Only actual obstruction produces a ghost outline.

Hold gains are mass-normalised and critically damped with backward-Euler discretisation. Heavy
objects have a slower transient response; light objects and bones cannot acquire an unstable
mass-dependent damper. Melee transfers bounded momentum from an eight-kilogram hand instead of
an unscaled impulse. New proxies sweep from the authoritative eye side before any interaction.
Teleport movers carry proxies and held bodies with each validated blink/shift displacement.

Oversized cumulative room steps rebaseline and discard displacement rather than rejecting all
future receipts. Paused single-player menu motion is discarded; tracking continues with the
anchor under the head. FOLLOW older than 0.3 seconds falls back to the engine position and a
fresh receipt resets the render buffer. Tracking and movement permissions remain unchanged.

Borrowed menus detach before protected close callbacks. UI frame work stops after a synchronous
wrist Exit. Identical refresh inputs share one resolver pass per frame; a changed pose, anchor,
setting, base position or authoritative hand correction invalidates it. C's future composition
call belongs inside that cached core pose pass. Gloves filter eligibility/mass/range before a
cached targeting mesh walk; exact grabs still revalidate the mesh and ownership.
