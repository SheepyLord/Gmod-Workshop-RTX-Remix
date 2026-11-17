# arc9_icons_harness.lua

LuaJIT harness for the load accelerator's
[`nlloadaccel/arc9_icons.lua`](../../fs_accel/addon/lua/nlloadaccel/arc9_icons.lua.md) (ADR 0240), run by
[`test_arc9_icons.py`](test_arc9_icons.py.md).

```
luajit tools\tests\arc9_icons_harness.lua <repo> <scenario>
```

It mocks a realm: `Material` (each PNG it is asked for counts as a decode; a path with `missing` gives an error
material) and `CreateMaterial` (by name), the IMaterial metatable, `surface` and `render`, convars, `hook.Add`,
`util.CRC`. An "ARC9 attachment file" is a chunk named `@lua/arc9/common/attachments_bulk/test_bulk.lua` that does
`local m = Material(...) return m`, as ARC9's files assign (`ATT.Icon = Material(...)`); a `return Material(...)` would
be a tail call, which leaves no frame of the file on the stack.

| Scenario | Checks |
|---|---|
| `client` | an attachment's PNG is not decoded at load; one stand-in per flags and path, with a PNG material's flags; another file, a VMT and `vertexlitgeneric` are GMod's own; the first `surface.SetMaterial` decodes once into the stand-in; a read (`GetTexture`, `Width`) or `MaterialOverrideByIndex` decodes first; a missing icon's `IsError()`; after `InitPostEntity` Material is GMod's own; the line printed |
| `guard` | the same with one more wrapper between the file and this one (the render guard's) |
| `server` | one material stands in for all; no icon decoded, `vgui/white` once; the line printed |
| `generate` | ARC9's `arc9_atts_generate_entities` on: GMod's own Material |
| `off` | `nativeloader_load_accel_arc9 0`: Material untouched |

Writes nothing. Exit 0 and `PASS <scenario>`, or a Lua error naming the failed check.
