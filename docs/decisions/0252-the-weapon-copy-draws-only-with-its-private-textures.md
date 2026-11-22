# 0252: The weapon copy draws only with its private textures

- Status: Accepted 2026-11-21 (the user's go-ahead to do the follow-up in the main session: "Weapon copy shows both
  copies in first person"); follows [ADR 0251](0251-the-weapon-copy-draws-nothing-before-the-frame.md) and applies
  [ADR 0043](0043-player-body-viewmodel-and-shadows.md)'s rule for the body copy to the weapon copy
- Package only: one file of the RTX fixes part (`lua/entities/rtx_pseudoweapon.lua`).

## Context

With the RTX fixes' weapon copy on and the tool gun in hand, both copies showed in the player's own first-person view:
the body copy's glasses, teeth and arms, and the weapon copy in its hands. The body copy alone stays out of view, with
the tool gun and the gravity gun. Measured in the PoC ([`shadow_copies_session.py`](../../tools/qa/shadow_copies_session.py.md)
`--order diagnose`, the tool gun, first person; [RESEARCH](../RESEARCH.md)):

- Leaving out the weapon copy entity's own draw changed nothing; leaving out its client-side model's draw as well gave
  a clean view. The tool gun screen add-on off changed nothing; the camera SWEP in hand showed nothing.
- With the copy's private textures (`rtx_pseudoweapon_unique_hashes 1`: the weapon's textures copied with one pixel
  changed, categorized as the player model's) both copies stayed out of view.

The copy's model drew the real weapon's textures under the classic `rtx_pseudoweapon_unique_hashes 0`, which the
companion applies. No category can hide those without hiding every weapon that shares them, and with that uncategorized
model at the body's hands the body copy showed too (the runtime's reason was not traced: it releases player-model
instances it finds far from the body, `filterPlayerModelInstances`). ADR 0043 settled the same question for the body
copy: its private textures are made whatever the legacy setting says. The weapon copy also made its textures in
`Think`, before the frame, which ADR 0251 removed for its draw.

## Decision

1. **The weapon copy draws only with its private textures**, whatever `rtx_pseudoweapon_unique_hashes` says, and draws
   nothing until they exist.
2. **They are made at the copy's first draw after a weapon change**, inside the frame (as the body copy makes its own),
   not in `Think`.
3. **The copy puts the material overrides back after its draw** (`render.MaterialOverrideByIndex()`), and registers its
   materials as the player model's at draw time once their hashes are known, as the body copy does; the RTX fixes'
   once-a-second scan stays.
4. A copy model made again in `Think` gets the same draw.

## Consequences

- Both copies stay out of the player's own first-person view with the tool gun and the gravity gun, and still give the
  weapon's shadow and reflection.
- The first draw after a weapon change makes one small texture per weapon material (a render target capture written to
  `data`, as before when the setting was on), and the copy may show for the frames before its hashes are registered.
- `rtx_pseudoweapon_unique_hashes` no longer changes anything; `rtx_pseudoweapon_unique_hashes_downscale` still sizes
  the textures.

## Rejected

- **Not drawing the weapon copy in first person.** It exists for the first-person shadow and reflection.
- **Changing the classic setting the companion applies.** The fixes' own default, the classic install's value and any
  saved value would all still reach the old draw; the rule belongs to the copy, as for the body copy.
- **Finding the runtime's reason for releasing the body copy.** Not needed once nothing uncategorized is drawn at the
  body's hands; the runtime keeps its player-model rules.
