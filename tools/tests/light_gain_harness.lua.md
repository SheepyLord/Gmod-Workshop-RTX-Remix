# light_gain_harness.lua

LuaJIT checks of the distance gain the RTX flashlight's automatic brightness
([ADR 0208](../../docs/decisions/0208-the-rtx-flashlights-automatic-brightness.md)) and the dance light's uniform
lighting ([ADR 0209](../../docs/decisions/0209-the-dance-lights-uniform-lighting-and-options.md)) share. The maths
ships twice, once in each package part, so neither part depends on the other: the RTX fixes'
`remixlua/cl/remixapi/cl_remix_light_gain.lua` and the character motion importer's `mmd_vmd_npc/cl_light_gain.lua`.

```powershell
luajit tools\tests\light_gain_harness.lua <fixes cl_remix_light_gain.lua> <motion importer cl_light_gain.lua>
```

It first requires the two copies to be the same bytes, then runs every check on each:

| Function | What is checked |
|---|---|
| `Target` | The inverse square at strength 1 (twice as far, four times the light; the normal distance is 1), its square root at 0.5, nothing at 0, a 1/d light (Source's projected texture); the clamps; nothing closer than the light's own size gets brighter; a projected texture below 100 units does not fade; NaN or missing values give 1 within the clamps; strength is at most 1 |
| `EffectiveDistance` | Equal samples give their distance; the inverse-square mean (one near hit in five pulls it close); weights; the harmonic mean for a 1/d light; samples that are not numbers are skipped; samples are kept within near and far; nothing measured gives nil |
| `Smooth` | The first gain at once; no time leaves it; one time constant leaves 1/e of the way in log space, falling and rising; monotone and never past the target; dimming over 90 % done in 0.2 s, brightening under 30 % (0.08 s and 0.6 s, the flashlight's); a NaN target leaves the gain |
| `Jumped` | A few units and a degree is motion; 200 units in a frame at 150 is a cut, not at 1000; a turn of 26 degrees is a cut; an unknown move counts as a jump |
| `Ring` | The axis first, then unit directions at the given angle, evenly around |
| `Kelvin` | 6600 K is white; from 1000 to 40000 K the luminance of white (Rec. 709); warm below 6600 K, cool above; below 1000 K counts as 1000 K; NaN is white |

Reads only the two files; no game, network or file writes. Prints `PASS light gain: ...` and exits 0, or fails an
assertion (non-zero exit). Run by [test_lights.py](test_lights.py.md).
