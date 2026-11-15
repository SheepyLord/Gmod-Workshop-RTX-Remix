# 0224: The Animation Player answers a click with its built flags; keep expressions, ragdoll collision, the timeline

- Status: Accepted 2026-11-15 (the user's report and requests of 2026-11-14)
- Package only: the character motion importer part (`packages/character-motion-importer`) and one line of the
  Model Hotloader part (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua`); no loader,
  runtime or native change.

## Context

The user: "The experience of using the bundled Advanced MMD Animation Player is very laggy, and the selection,
assignment, action like assigning an animation to an NPC always result in a few seconds of hangs. Please optimize
the addon to make a smooth experience." And three options: keep the flexes a motion does not animate instead of
zeroing every flex when a dance starts; a long slider in the debug window to drag along the motion; and, for NPC
replays, collision through the NPC's ragdoll (its main 18 bodies) instead of its bounding box, on by default, with
the NPC's motion and the MMD collision unaffected.

Measured in the PoC with a copy of the field's motion library (255 motions with the Workshop packs) and two
imported characters as NPCs ([report](../handover/mmd-player-report.md), [RESEARCH](../RESEARCH.md) "The Advanced
MMD Animation Player's clicks"):

- Every target status, assignment status, finished build and cleared build made the client ask for the whole
  motion details. The server walked every motion: `HasMotionMetadataCached` and then `MotionMetadata` each tested
  the file in both places and read its time and size (about 2,000 file calls for 255 motions, in one tick), and a
  file test per motion for the selected actor's built flag; then it streamed all 255 entries. The client rebuilt the
  tool's motion list (3,570 panels) and the Motion Manager on each arrival. A click sent two such requests; the
  server deferred the second by half a second, so a click stalled the game twice. Each stall was 110 to 185 ms at
  1600x900 and up to 390 ms at 3840x2160 with the Motion importer tab open.
- In the field the user also has GUI Scaler, which walks the whole spawn menu again whenever the count of panels
  grows: every one of those rebuilds made it walk.
- The only part of the details a click changes is the built flag (which motions are built for the selected actor's
  model).

## Decision

1. **A click asks for the built flags alone.** New net messages `mmdvmd_built_flags_request` (the player's four
   build options) and `mmdvmd_built_flags` (the selected actor's model and the ids built for it, at most 60,000
   bytes; a longer list is flagged and the client asks for the full details instead). The server answers at most
   every quarter second per player, with the latest options; it lists the built folder once
   (`MMDVMDNPC.BuiltMotionIDs`, `sh_core.lua`, sharing `BuiltTail` with `BuiltPath`). A target status, a finished
   build and a cleared build ask for the flags; an assignment status asks for nothing (each row carries its own
   status); a change of the four build options asks for the flags. The details are asked for when a window opens,
   the Refresh button is pressed, or the motion list changes (an unchanged list response asks for nothing).
2. **The details walk tests no file twice.** `ListMotions` records where each motion lives
   (`MMDVMDNPC.MotionRealms`); `MMDVMDNPC.CachedMotionMetadata` serves the persisted metadata when the file's time
   and size are the indexed ones (two file calls), and only a miss derives it (the parse budget is unchanged). The
   built flags of the full details come from the same single listing.
3. **The lists keep their rows.** The tool's motion list fingerprints what it shows and rebuilds only when that
   changes (a changed selection re-highlights). The Motion Manager's fingerprint leaves out the Built column: when
   only built flags change it rewrites those cells in place and points its rows at the current details.
4. **Keep expressions the motion does not animate** (`mmd_vmd_npc_keep_flexes`, tool setting `keep_flexes`, **off by
   default**: the user asked for an option to disable the reset). On: a selection leaves the face; a dance records
   the weights of the flexes its built animation drives (`built.flexes`), touches only those, blends its start from
   them and gives them back at its stop; the debug window remembers what it previews and puts it back at its
   reference frame and close. Off: every flex is zeroed as before. `MMDVMDNPC.GetModelFlexWeight` (`sh_core.lua`)
   reads native flexes and the Model Hotloader's overflow morphs.
5. **Dancing NPCs collide with their ragdoll's body** (`mmd_vmd_npc_ragdoll_collision`, tool setting
   `ragdoll_collision`, **on by default** as the user asked). While an NPC dances (not the self-playback proxy), one
   collider per main body of its model's ragdoll follows its bone each tick: an imported character's carrier has
   exactly 18 bodies; a model with more keeps those on ValveBiped trunk and limb bones, at most 18. The shapes are
   read once per model from a ragdoll that exists for an instant (`GetMeshConvexes`, in each body's bone space); each
   collider is a server-only scripted entity (`mmd_vmd_npc_collider`, never transmitted, not duplicated, not grabbed,
   only this tool acts on it, damage forwarded to the NPC) whose physics object is a shadow moved by `UpdateShadow`,
   so nothing it touches moves the dance. The NPC's box stays for traces (the tool gun, bullets) but leaves physical
   contact: collision group debris (no players, no NPCs) and its hull's physics collisions off; both are restored at
   the stop. The colliders carry `MMDHLSceneExcluded`, and the Model Hotloader's scene capture
   (`secondary_collision.lua`) puts such entities' bodies in its excluded list, so the hair and clothing physics
   collides as before. The engine's own bone followers (`Entity:CreateBoneFollowers`) were the first choice; in the
   game they made none for the carrier, as Source creates them only for models that list `bone_followers` in their
   key values.
6. **The debug window's timeline**: a slider across the window above its buttons, from the motion's first frame to
   its last. A drag sends at most one request per 50 ms, the latest frame last; the server already answers ten a
   second and ends on the last frame asked for. While the knob is held the pose and summary follow and the bone and
   flex lists wait; they are rebuilt when it is let go. An answer moves the knob without asking again.

## Consequences

- A click costs one listing of the built folder and one small message; the measured stalls at 3840x2160 went from
  170-390 ms to the level of the frames around them (the report has the numbers). The details' full walk now runs
  when the list can have changed, and costs a quarter of its file calls.
- A client of the previous add-on version against a new server (or the reverse) still works: the old messages are
  unchanged; an old client simply keeps asking for the details.
- Ragdoll collision adds up to 18 server-only entities per dancing NPC and one shadow update each per tick. Players'
  movement prediction does not see the colliders (they are never sent), so walking into a dancing NPC is corrected
  by the server. A model without a ragdoll keeps its box.
- `sv_commands.lua` holds the new server code in one table (`MMDVMDNPC.Actor`): its main chunk stays below Lua's
  200-local limit.
