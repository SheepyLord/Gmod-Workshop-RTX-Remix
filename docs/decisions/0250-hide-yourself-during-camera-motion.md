# 0250: Hide yourself during camera motion

- Status: Accepted 2026-11-21 (the user's request of 2026-11-21: "In the advanced mmd player, camera section, add a
  convenience function, default on, when in camera motion, hide the player in the world.")
- Package only: the character motion importer part (`cl_camera.lua`, the tool's Camera tab, `sh_core.lua`'s texts)
  and one file of the RTX fixes part (`cl_remix_flashlight.lua`); no loader, runtime or native change.

## Context

The Advanced MMD Animation Player plays a dance's imported camera animation (a VMD camera path) as the player's view:
its `CalcView` hook returns the path's view with `drawviewer = true` (`cl_camera.lua`), so the game draws the local
player in third person, wherever they stand. From the camera's side of the dance, the player stood in the shot with
the tool gun in hand.

What draws the local player in an RTX start (the add-on deploys only in RTX starts, `--requires-remix`):

- **The engine**: the player model while `ShouldDrawLocalPlayer()` is true (the camera's `drawviewer`), and the active
  weapon's world model with it. Under Remix the shadow and reflections come from that same geometry.
- **The Model Hotloader**, for an imported character as the player model: a clientside visual proxy
  (`mmdhl_native_visual`) draws the character; at each draw it asks `mmdhl.PresentationSuppressed(player)`, which is
  true while the player is no-draw. Its `PreRender` hook (`client.lua`, `UpdateClientInstances`) also reads the
  no-draw flag to decide whether to keep or release a character's world: a local hide that lasts five seconds releases
  it (`carrier.lua` `PresentationReleased`, `LocalHideRelease = 5`), and it is rebuilt when shown again.
- **The RTX fixes**: `rtx_pseudoplayer` and `rtx_pseudoweapon` (`cl_rtx_misc.lua` creates one of each) draw copies of
  the body and weapon for first-person shadows and reflections. Each hides itself while `ShouldDrawLocalPlayer()` is
  true, from its `Think`.
- **The RTX flashlight** (`cl_remix_flashlight.lua`): a Remix sphere light at the player's eyes, updated in
  `PreRender`. It shines from where the player stands whatever the view (its `PreRender` gets no arguments, so it
  always follows `EyePos()` and `EyeAngles()`). It is a light, not geometry: hiding the body leaves it lit.

GMod calls `CalcView` before `PreRender` ([RESEARCH](../RESEARCH.md), VR's S2 findings), then `RenderScene` and the
scene, then `PostRender`.

## Decision

1. **A checkbox in the tool's Camera tab, on by default and saved**: "Hide yourself during camera motion"
   (`mmd_vmd_npc_cam_hide_player`, a client setting created by `cl_camera.lua`). Its help says what is hidden and that
   it is on your screen only: in multiplayer other players still see you. Texts in the panel's nine languages.
2. **While the camera's view is the frame's view, the local player is left out of the shot**: their body, every
   entity parented to them (carried weapons, worn and attached models, the RTX fixes' weapon copy), the active weapon,
   a death ragdoll, and the RTX fixes' body and weapon copies (found once a second by class). The entity the camera
   follows is never hidden. The debug window's camera preview counts as camera motion (as for Hide HUD), except when
   it orbits the player themselves (nothing selected): then they are the shot's subject and stay.
3. **Hidden only while a frame draws, with the no-draw flag, restored every frame.** `CalcView` notes that the frame's
   view is the camera's; `RenderScene` sets no-draw on each of those entities that was drawn; `PostRender` clears it
   again. So the flag the game, the server's networking and the Model Hotloader's `PreRender` bookkeeping see between
   frames is never ours: nothing can stay hidden, the player is back the frame the camera motion ends, is stopped,
   cancelled with the toggle or fails, or the option is unticked, and a map change finds nothing to undo. A frame
   whose `PostRender` does not come (another add-on's `PreRender` skipped the drawing) is undone by the next `Think`,
   before the next `CalcView`; `ShutDown` undoes too. An entity someone else hid is left hidden and not shown after the
   frame.
4. **The camera view keeps `drawviewer`.** To the rest of the game the player is still drawn in third person, so
   nothing switches to its first-person body: the RTX fixes' copies stay hidden by their own rule, other add-ons' legs
   stay away, the Model Hotloader does not take the camera for a first-person view.
5. **The RTX flashlight gets a hook: `RTXFlashlightHidden(ply)`.** A listener answering true keeps that player's light
   on but dark: radiance and haze 0, no automatic-brightness traces; the light is not destroyed, and the frame no
   listener answers it is lit as it was. The motion importer answers for the local player while its camera hides
   them. Off and on again while hidden, the light comes on dark.

## Consequences

- Only this client's picture changes; nothing is sent to the server.
- Every frame of a camera motion sets and clears the no-draw flag of the player and a handful of entities: each change
  moves the entity out of and back into the client's leaf system, a few entities a frame. The copies' class lookup
  runs once a second.
- Not hidden: things another add-on draws for the player by its own hooks without parenting them (a PAC3 outfit drawn
  apart from the player, for example), and what is physics rather than drawing: the RTX water's ripples around a
  player standing in water, footsteps.
- The debug preview and the camera motion share the rule; a selected self-playback's real player is already hidden by
  the server, and its dancing proxy is the camera's subject.
- Other add-ons can keep the RTX flashlight dark through the same hook.

## Rejected

- **`drawviewer = false` in the camera's view** (the engine then draws the player as in first person: no body, no
  weapon). `ShouldDrawLocalPlayer()` turns false, so the RTX fixes' body and weapon copies come back (they would need
  hiding the way VR hides them, by pausing their `Think`), and other add-ons' first-person legs would be drawn at the
  player's feet in the shot.
- **Hiding in `CalcView` or `PreRender`.** `CalcView` comes before `PreRender`, where the Model Hotloader reads the
  flag: after five seconds of a camera motion it would release the player's imported character and rebuild it after.
  Hooks of one event run in no set order, so `PreRender` has the same problem.
- **`PrePlayerDraw` returning true.** It stops only the player's own draw: the active weapon and other attached
  entities draw on, the Model Hotloader's visual proxy draws the imported character anyway, and a hook of another
  add-on that answers first skips it.
- **Setting the flag for the whole camera motion and restoring it at the end.** No-draw is networked: a value the
  server sends meanwhile (the self playback's own hide, a weapon switch) would be overwritten by the restore, or the
  restore by it.
- **Switching the flashlight off.** That is the server's state, seen by other players, and it would not come back on by
  itself.
