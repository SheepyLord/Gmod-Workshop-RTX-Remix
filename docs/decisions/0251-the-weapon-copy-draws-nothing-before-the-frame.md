# 0251: The weapon copy draws nothing before the frame

- Status: Accepted 2026-11-21 (the user's go-ahead to do the follow-up in the main session: "Local player shadow: lost
  path tracing, Hotloader error")
- Package only: one file of the RTX fixes part (`lua/entities/rtx_pseudoweapon.lua`). The same change fixes the Model
  Hotloader's scene capture for entities without a model scale (`secondary_collision.lua`), a plain bug fix that needs
  no decision.

## Context

The RTX fixes' weapon copy (`rtx_pseudoweapon`, "Pseudoweapon Enabled" in the fixes' own settings; off in the classic
settings the companion applies) is a client-side copy of the held weapon, bonemerged to the player's hand, that gives
the player a weapon shadow and reflection in first person. Its `Think` called the held weapon's `DrawWorldModel()` on
every call, wrapped in `pcall`, to keep the weapon's world model current in first person (and Customisable Weaponry
2.0's `WMEnt`, which the copy reads next). `Think` runs before the frame is rendered.

- An engine weapon (the physics gun, the gravity gun) has no `DrawWorldModel`: the `pcall` swallowed the error and
  nothing was drawn.
- A scripted weapon (the tool gun, most add-on weapons) drew its world model before the frame began: Remix received a
  draw that belongs to no camera of the frame.
- Measured in the PoC ([`shadow_copies_session.py`](../../tools/qa/shadow_copies_session.py.md), gm_construct,
  1600x900, the tool gun in hand; [RESEARCH](../RESEARCH.md), "Local player shadow's weapon copy and path tracing"):
  in a third-person view (a `CalcView` with `drawviewer`, as the motion importer's camera makes one) the frame's median
  time fell from 13 ms to 4 ms and the screenshot was the game's own raster picture (the map's sky, its baked light),
  until the view went back to first person. The weapon copy alone did it; the same view without the copies stayed
  path traced. The camera runs 3 and 4 of ADR 0250's work had both copies on and the tool gun in hand.

## Decision

1. **The weapon copy's `Think` draws nothing.** It sets up the player's and the held weapon's bones (`SetupBones`),
   which the copy bonemerged to the player's hand follows, where it called `DrawWorldModel()`.
2. **Nothing else of the copy changes**: its own client-side model still draws in the frame through its
   `RenderOverride` and hides in third person as before; the private textures of `rtx_pseudoweapon_unique_hashes 1`
   (`MaterialSet`) are as they were.

## Consequences

- Third-person views keep their path tracing with the weapon copy on: in the same PoC steps the median frame was
  15.2 ms with the weapon copy and 12.9 ms with both copies, the RTX sky in both shots.
- A weapon that places a world model of its own only in its `DrawWorldModel` (Customisable Weaponry 2.0's `WMEnt`) no
  longer gets that update from the copy in first person: the copy reads `WMEnt`'s render origin as before, which may
  lag; the copy is seen only in shadows and reflections.
- Not changed by this decision, found in the same runs (the handover report has the evidence): with the tool gun's
  weapon copy on, the body copy and the weapon copy show in the player's own first-person view, before and after this
  change; the body copy alone stays out of view, and the gravity gun's weapon copy does not do it. The cause was not
  found ([RESEARCH](../RESEARCH.md)); the weapon copy is off in the classic settings.

## Rejected

- **Skipping the draw in third person only.** The first-person draw happened outside the frame too, and a draw outside
  the frame can reach Remix with whatever camera the last pass left set.
- **Drawing the weapon in a render hook of the frame instead.** With the classic `rtx_pseudoweapon_unique_hashes 0`
  the copy has the real weapon's textures, so a second weapon would be drawn in the player's own view.
- **A runtime change that ignores draws outside the frame.** The add-on's draw is the cause; the runtime keeps reading
  draws as the game issues them.
