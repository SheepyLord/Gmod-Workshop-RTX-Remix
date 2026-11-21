# motion_camera_harness.lua

LuaJIT harness for [test_motion_camera.py](test_motion_camera.py.md): the Character Motion Importer's camera
(`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_camera.lua`) under a fake GMod API, for
"Hide yourself during camera motion" ([ADR 0250](../../docs/decisions/0250-hide-yourself-during-camera-motion.md)).

```powershell
luajit tools\tests\motion_camera_harness.lua <scenario> <cl_camera.lua>
```

Each frame runs in GMod's order: `Think`, `CalcView` (the camera's view), the RTX fixes' flashlight question
(`RTXFlashlightHidden`, asked in `PreRender`, for you and for another player), `RenderScene` (every listener's answer
must be nothing: a value would replace the scene), the scene (each entity's no-draw flag is recorded), `PostRender`.
Hooks run in the order they were added and `hook.Run` returns the first answer, as GMod's `hook.Call` does. The camera
path arrives through the add-on's own net handlers (`mmdvmd_camera_begin`, `mmdvmd_camera_keys`, `mmdvmd_camera_stop`)
with the values the server sends; entities are tables with a no-draw flag, children, a class and an index; vectors,
angles, `LocalToWorld` and the traces are just enough for the camera's path, collision and transform.

The scene: you (index 1) carrying a tool gun, a holstered crowbar the server keeps hidden and a worn model (all
parented to you, as carried weapons are); the RTX fixes' body copy (`rtx_pseudoplayer`) and weapon copy
(`rtx_pseudoweapon`, parented to you, with its own clientside model); two NPCs, the first dancing with a still camera
beside it; another player.

| Scenario | Checks |
|---|---|
| `play` | The option exists and is on by default; first person hides nothing; in each camera frame your body, tool gun, worn model and both copies (and the copy's model) are hidden while the scene draws and shown after it, the holstered weapon stays hidden as the server keeps it, the NPCs and the other player are never hidden, your flashlight is kept dark and the other player's is not, and the view keeps `drawviewer`; between frames nothing is hidden; the server's `mmdvmd_camera_stop` and the camera toggle bring you back the next frame; entering again hides you again; a shutdown in the middle of a frame shows everything |
| `untick` | Unticking `mmd_vmd_npc_cam_hide_player` mid-motion shows you while the camera motion goes on; ticking it again hides you |
| `subject` | The debug window's camera preview orbiting you (nothing selected) keeps you; orbiting a selected NPC hides you; the window closing ends it |
| `ends` | The dancer removed under the camera: the camera motion fails and you are back that frame |
| `skipped` | A frame whose `PostRender` never comes: the next `Think`, before the next `CalcView`, shows everything |
| `parts` | A part someone else hid stays hidden after the frame; a death ragdoll is hidden for the frame; the camera's dancer is never hidden, even parented to you; a body copy made later is found within a second |

Writes nothing, sends nothing, renders nothing. Prints `PASS <scenario>` and exits 0, or fails an assertion with a
message (non-zero exit).
