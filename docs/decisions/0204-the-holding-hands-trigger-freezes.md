# 0204: The holding hand's trigger freezes what it holds

- Status: Accepted 2026-11-13 for V8 on the branch `vr8`; reaching `main` needs the user's approval. The user approved V8 on 2026-11-13 and it was merged to `main`.
- Decided by: Claude, at the user's request of 2026-11-13 ("Add a key when grabbing to freeze that object").

## Context

The physgun freezes bodies; VR hands could not, and could not take a frozen body at all (a hold needs a moving one).
The key must be free while a hand holds something. A holding hand's grip is the hold itself; its stick moves or turns
the player; A and B already jump, eject, open the wrist menu or reload. The trigger of a holding hand does nothing:
use by hand is off while it holds, and the weapons module claims the main hand's grip and trigger whenever a gun is out,
so a gun hand never holds anything.

## Decision

- **Freeze**: pulling the trigger of a hand that holds a body stops that body where it is (`EnableMotion(false)`) and
  every hand lets go of it. It follows the physgun's convention: a ragdoll's held bone stops, the rest of the ragdoll
  does not; a prop stops whole. It is refused for `GetUnFreezable()` entities and when `CPPICanPhysgun` says no, and the
  body stays in the hand. The body is added to the player's frozen list (`AddFrozenPhysicsObject`), so the physgun's
  "unfreeze all" frees it too.
- **Free**: gripping near a frozen body (the grab's 16 cm reach) and pulling the trigger frees it into the hand. It
  obeys the grab's pickup permissions, `CPPICanPhysgun` and the sandbox's `CanPlayerUnfreeze` hook. A grip alone never
  takes a frozen body, so brushing a frozen build does not loosen it.
- After a freeze or a free, the same grip takes nothing else until it is let go.
- Haptics: pulse kinds 6 (freeze) and 7 (free), 50 ms, after the release pulse in the same tick.

## Consequences

- A player can pose ragdolls bone by bone in the headset, and build with frozen props, as with the physgun.
- A claimed trigger (the UI laser over a panel, a tool) never freezes: the interact module only sees triggers it owns.
