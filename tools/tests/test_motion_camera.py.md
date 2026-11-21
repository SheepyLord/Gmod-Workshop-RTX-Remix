# test_motion_camera.py

Runs [motion_camera_harness.lua](motion_camera_harness.lua.md) under LuaJIT, once per scenario, without starting
Garry's Mod: the Character Motion Importer's camera (`cl_camera.lua`) leaving you out of the shot while its camera
motion plays ("Hide yourself during camera motion", the user's request of 2026-11-21,
[ADR 0250](../../docs/decisions/0250-hide-yourself-during-camera-motion.md)). One more test reads the tool and the
catalog as text.

```powershell
python -m unittest discover -s tools/tests -p test_motion_camera.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_hidden_while_the_camera_plays_and_back_after_a_stop_or_toggle` | Scenario `play`: on by default; your body, weapon, worn models and the RTX fixes' body and weapon copies hidden only while a camera frame draws, your flashlight dark, nobody else touched; back the frame the server stops the camera or the toggle leaves it; a shutdown mid-frame leaves nothing hidden |
| `test_unticked_mid_motion_shows_you` | Scenario `untick` |
| `test_a_preview_of_yourself_keeps_you` | Scenario `subject`: the debug window's camera preview orbiting you keeps you, orbiting an NPC hides you |
| `test_a_camera_that_fails_shows_you` | Scenario `ends`: the dancer removed under the camera |
| `test_a_frame_without_postrender_leaves_nothing_hidden` | Scenario `skipped` |
| `test_what_is_hidden_and_what_is_not` | Scenario `parts`: parts someone else hid stay hidden, a death ragdoll is hidden, the dancer never, copies made later too |
| `test_the_option_is_in_the_camera_section_with_its_texts` | The tool's Camera tab has the checkbox for `mmd_vmd_npc_cam_hide_player` with its label and help; the catalog block of 2026-11-21 has both texts in all nine languages (en, zh, zh-tw, ja, ko, fr, ru, ar, es) and the help says other players still see you |

LuaJIT is optional: without it the harness tests are skipped (the text test runs). Writes nothing. Exit code 0 on
success.
