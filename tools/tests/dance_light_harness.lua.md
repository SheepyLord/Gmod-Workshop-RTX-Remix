# dance_light_harness.lua

Loads the character motion importer's dance light (`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_flashlight.lua`,
the camera-following light of the MMD VMD NPC add-on) under a fake GMod API and checks it
([ADR 0209](../../docs/decisions/0209-the-dance-lights-uniform-lighting-and-options.md)).

```powershell
luajit tools\tests\dance_light_harness.lua <add-on lua\mmd_vmd_npc folder> <scenario>
```

The fake game has Source's vectors and angles (`Angle:Forward/Right/Up`, `Vector:Angle`), dancers with a pelvis and a
head bone (`ValveBiped.Bip01_Pelvis`, `ValveBiped.Bip01_Head1`) that dance through this client's
`MMDVMDNPC.LocalPlaybacks` or the server's `MMDVMDNPCDancing` flag, the camera path's state (`CameraAnimActive`,
`CameraAnimEntIndex`, `CameraAnimViewOrigin/Angles`), the third-person self view, `ents.FindInCone`, traces against a wall
across +x and a car's hull that only the trace's filter can skip, and the Remix API and projected textures, both
recording what they were given. The light is driven through its `Think` hook, sixty frames a second. Most scenarios use
the classic RTX install's values (Brightness 0.28, FOV 100, radius 30, 45 units behind the camera), which the companion
applies as first-run defaults. Expected values are worked out independently: where the light's axis passes the body by a
fine search along it, not the file's algebra.

| Scenario | What it checks |
|---|---|
| `defaults` | With the new options off, the light is as it was: 45 units behind the eyes, along the view, radiance 255 x 0.28 / 4, cone 50, softness, radius and haze as set; no traces and no looks for dancers; it follows the camera path; no view, no light; a Lua refresh reclaims the old light; without Remix one projected texture with the settings as before, updated only when something changes |
| `uniform` | On the camera path's dancer (another dancer nearer on the axis is not the subject), a cut to 60, 150, 400 and 1200 units gives that distance's light in the same frame; radiance / d^2 is constant within the clamps; Max boost 16 far away; Brightness applies at the normal distance; the haze stays at its set level under a boost; a smooth dolly-in stays within 15 % of its target and settles; a face close-up measures to the face; strength 0.5, the normal distance and Max boost; off is the set brightness exactly; on again starts at its target |
| `subject` | In first person, the dancing character whose body passes nearest the light's axis, not a nearer one off the axis, one behind the light or one that is not dancing; looks into the beam four times a second; then the one off the axis, found by that look; no dancer: the wall's distance from seven traces (a quarter of the cone, at most 15 degrees, the axis counting twice), the car the player sits in left out; nothing hit: the gain holds; the third-person self view's dancer |
| `aim` | Aim at the character: the light points at the body where the view's axis passes it, at most down to the pelvis; no traces; no character: along the view; the projected texture turns the same way |
| `temperature` | 0 K is the RGB colour; 3200 K is warm at the luminance of white; the RGB colour tints it; 6600 K is white; a projected texture keeps its strongest channel at 255 and carries the rest in its brightness |
| `rim` | The rim light: 80 units behind the chest as the camera sees it and 40 above, aimed at the head, 0.8 of the main light at the normal distance, cone 35, softness 0.5, no haze; straight above, behind the character's own back; rim 0, no character, a refresh and switching off remove it; without Remix a second projected texture without shadows |
| `presets` | Each of the four presets (camera, uniform, spot, stage, in that order) sets five or more existing settings and never brightness, colour or offsets; the stage is uniform, aimed, with a rim light; the camera light is as it was; an unknown preset does nothing |
| `vanilla_uniform` | Without Remix, uniform lighting makes up the projected texture's 100 / d fade beyond 100 units |

Writes nothing, sends nothing, renders nothing. Prints `PASS dance light <scenario>` and exits 0, or fails with
`FAIL <scenario>: <what>` (non-zero exit). Run by [test_lights.py](test_lights.py.md).
