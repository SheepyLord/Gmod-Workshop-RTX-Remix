# test_lights.py

The distance gain the RTX flashlight's automatic brightness and the dance light's uniform lighting share, and the
character motion importer's dance light itself ([ADR 0208](../../docs/decisions/0208-the-rtx-flashlights-automatic-brightness.md),
[ADR 0209](../../docs/decisions/0209-the-dance-lights-uniform-lighting-and-options.md)). The flashlight's own checks
are in [test_flashlight.py](test_flashlight.py.md).

```powershell
python -I -m pytest tools\tests\test_lights.py -q
```

| Test | What |
|---|---|
| `SharedGainTests` | The fixes' `cl_remix_light_gain.lua` and the motion importer's `cl_light_gain.lua` are the same bytes; the motion importer's autorun sends its copy to clients; [light_gain_harness.lua](light_gain_harness.lua.md) on both copies |
| `DanceLightTests` | One test per scenario of [dance_light_harness.lua](dance_light_harness.lua.md): the defaults keep the light as it was, uniform lighting, the subject, aim, colour temperature, the rim light, presets, the vanilla projected texture |
| `DanceLightMenuTests` | Every `mmd_vmd_npc.lighting.*` key the tool's Lighting tab shows, and every preset's label, is in the add-on's English catalog (`sh_core.lua`; a missing one shows as its raw name); every `mmd_vmd_npc_flashlight_*` setting the light creates has a control in that tab |

Reads only repository files; no game or network. A missing LuaJIT skips the LuaJIT tests (reported); the byte and
catalog checks run without it. A failed harness assertion fails its test with the harness's message.
