# 0185: VR motion contract, safe carry and camera ownership

Accepted for branch review, 2026-11-12, under Claude's verification instructions. Extends
[0183](0183-vr-review-resource-and-physics-corrections.md) and
[0184](0184-vr-capture-lifetimes-and-review-witnesses.md); supersedes their world-velocity mutation
and permissive capture/lag interpretations where inconsistent.

`pose.vel` remains the wire's tracking-relative velocity in world axes/game units per second.
The validated server sample separately adds authoritative player velocity into `pose.wvel`.
Only proxy feed-forward, hold damping and throws consume wvel. Melee, glove flicks, W's melee and
K's gestures continue using vel. Bare proxy collision velocity also excludes stick locomotion.

Teleport validates the swept world bounds of every held entity before translating it. Blocked
holds are released on the original side; constrained holds are released without moving or stretching
their contraption. The player can still teleport. Free body/proxy carry remains supported.

Window overlays are pending until their real runtime request succeeds and the overlay is visible.
Permanent refusal uses the ordinary painted update fallback and never opens/pauses GameUI for an
invisible window. Temporary resource pressure stays pending. Pending ghost/target overlays must be
hidden when no longer wanted, not only when already visible.

Targeting hints have a real per-hand 100 ms mesh-query limit even during movement. Native walking
queries are measured on actual server ticks; exact grabbing still revalidates geometry. Heavy holds
retain the original >3-unit lag acceptance and slower mass-scaled transient while preserving stable
critical gains. The three-dot arc plus target requires four painted roles and >=256 64-segment ring
draws, replacing the old >500 expectation of nine rings.

Capture expectations include wanted logical roles without handles and the configured wrist HUD.
Every expected role needs a native source/image; empty inventory is allowed only with explicit empty
expectations. Hidden non-required sources may retire. No missing expected HUD is accepted.

CalcView ownership uses stock dispatch capability probing or ULib's authoritative priority registry,
deferring other registrations/removals and restoring them at Exit. Recursive dispatch cannot resubmit
the camera or reach a competing view. Unknown detached dispatch refuses VR safely, rather than
silently allowing another view to override it. W's files remain unchanged.
