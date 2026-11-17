# arc9_icons.lua

The load accelerator's third round, item F ([ADR 0240](../../../../docs/decisions/0240-arc9s-attachment-icons-decoded-when-first-drawn.md)):
ARC9's attachment icons decoded the first time they are drawn, not while a map loads. Included by the add-on's autorun
([`!!!!!nlloadaccel.lua`](../autorun/!!!!!nlloadaccel.lua.md)) in the server and the client realm (sent to clients
with `AddCSLuaFile`), before ARC9's own autorun runs.

**Why.** ARC9 (`lua/arc9/shared/sh_atts.lua`, `ARC9.LoadAtts`) runs every attachment file when it loads, and each asks
`Material("<icon>.png", "mips smooth")` for its icon: in the user's game 1,722 calls in the attachment files, 1,481 of
them PNGs (853 distinct), about 2.3 s of the server's Lua start. GMod's material system caches a PNG material by its
flags and path for the whole process (`0001010icon16/zoom_out`), so in a game this computer hosts the server realm
decodes each icon and the client realm finds it decoded.

**What it does.** It replaces `Material`. While a map loads (until the realm's `InitPostEntity`), a `.png` asked for by
a function whose source (up to nine frames up the stack: the render guard's wrapper may sit between) is an ARC9
attachment file (`arc9/common/attachments...`) gets a stand-in:

- **Server realm:** one shared material (`vgui/white`) for every icon: the server never draws one.
- **Client realm:** one material per icon (by flags and path, as GMod's own cache), made with `CreateMaterial` as an
  `UnlitGeneric` with `$vertexcolor` and `$vertexalpha` (GMod's PNG materials have `$flags` 48 and that shader), named
  `nlloadaccel/arc9icon_<CRC of flags and path>` (a later map's Lua state gets the same material back). The icon is
  decoded the first time anything draws the stand-in (`surface.SetMaterial`, `render.SetMaterial`,
  `render.MaterialOverride`, `ModelMaterialOverride`, `BrushMaterialOverride`, `WorldMaterialOverride`,
  `MaterialOverrideByIndex`) or reads it (`GetTexture`, `GetString`, `GetInt`, `GetFloat`, the vector and matrix
  getters, `GetKeyValues`, `Width`, `Height`, `GetColor`, `IsError`): GMod's own `Material` decodes it, and its texture
  (with its flags) goes into the stand-in. A missing icon answers `IsError()` true once decoded. `GetName` and
  `GetShader` stay the stand-in's.

Not deferred: flags other than `mips`, `smooth` and `noclamp` (they change the material, not the texture), any call
while ARC9's `arc9_atts_generate_entities` is on (ARC9 then reads every icon's texture name while it loads), any call
from another file, and any call after `InitPostEntity` (a reload of ARC9's attachments decodes as ARC9 does). `Material`
then passes the call on unchanged (two values: the material and its time).

- **Switch:** `nativeloader_load_accel_arc9` (archived, 1): 0 leaves `Material` alone from the next map. The load
  accelerator's `nativeloader_load_accel 0` leaves this file out too.
- **State:** `NLLOADACCEL_ICONS` = `{server, standIns, decoded, broken, fill}` (counts; `fill` decodes a stand-in now).
- **Output:** at `InitPostEntity`, `[nativeloader] load accelerator (<realm>): N ARC9 attachment icons not decoded (the
  server never draws them)` / `... left to be decoded when first drawn`.
- **Side effects:** `Material` replaced for the session; the draw functions above and the IMaterial getters wrapped
  (a table lookup while stand-ins wait). Nothing written to disk.
- **Tests:** [`test_arc9_icons.py`](../../../../tools/tests/test_arc9_icons.py.md) with
  [`arc9_icons_harness.lua`](../../../../tools/tests/arc9_icons_harness.lua.md).
