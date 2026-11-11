# SteamVR Input defaults

`nlvr_actions.json` declares `/actions/main` and twenty actions. Deploy it and the three binding
files in `garrysmod/addons/nlvr/input/`. Keep `openvr_api.dll` beside the native module in
`garrysmod/lua/bin/`; that directory permits only DLL root files. The module derives the input
folder from its own path and selects the manifest only at Start VR, before
polling events or updating input. SteamVR's binding UI remains the player's remapping authority.
The structure follows Valve's [action manifest](https://github.com/ValveSoftware/openvr/wiki/Action-manifest)
and [skeletal input](https://github.com/ValveSoftware/openvr/wiki/SteamVR-Skeletal-Input) interfaces.
These are original project bindings; no gVRMod code or data was copied.

| Names (left/right prefix) | Type | Default purpose from the control plan |
|---|---|---|
| `grip` | boolean | Grab, gravity gloves |
| `grip_force` | vector1 | Index grip force; Touch grip pull |
| `trigger`, `trigger_value` | boolean, vector1 | Use/panel click, fire, tool primary |
| `stick`, `stick_click` | vector2, boolean | Move/sprint; turn/teleport/crouch/flashlight |
| `a` | boolean | Jump; eject/tool secondary/physgun freeze |
| `b` | boolean | Wrist menu; reload/weapon wheel |
| `skeleton` | skeleton | Left/right hand finger curls |
| `haptic` | vibration (out) | Controller feedback |

`nlvr_bindings_index.json`: knuckles grip grab + force, triggers, sticks, A/B, skeletons, haptics.
`nlvr_bindings_touch.json`: Touch joysticks, triggers/grip, left X/Y mapped to the logical A/B,
right A/B, skeletons and haptics. Physical source names follow Valve's `touch_profile.json`.
`nlvr_bindings_vive.json`: trackpads substitute for sticks, application-menu for B, grip button,
triggers and haptics. Vive has no independent A; that optional action is left to player remapping.
The future gameplay add-on interprets tap/hold and stick directions; V1 uses none of the actions.
The module exposes the same names as action-table keys, without the `/actions/main/in/` prefix.
