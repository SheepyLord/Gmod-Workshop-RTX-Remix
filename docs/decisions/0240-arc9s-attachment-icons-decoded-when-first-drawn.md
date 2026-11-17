# 0240: ARC9's attachment icons decoded when first drawn

- Status: Accepted 2026-11-17 (the user: "Let's also do the remaining 6 points in the plan. Every second matters"; item
  F of the second load speed-up plan)
- Decided by: the agents, from the field measurements; package only: the `load-accelerator` part's add-on
  (`fs_accel/addon/lua/nlloadaccel/arc9_icons.lua`). No native module, loader or runtime change.
- Report: [load-speedup-3-report.md](../handover/load-speedup-3-report.md).

## Context

ARC9 (`lua/arc9/shared/sh_atts.lua`, `ARC9.LoadAtts`, run when its autorun includes the file) runs every attachment
file in both realms, and each file asks `Material("<icon>.png", "mips smooth")` for its icon (`ATT.Icon = ...`). The
user's subscriptions hold 1,722 such calls in ARC9 attachment files, 1,481 of them PNGs, 853 distinct. In a modern_house
load of the user's game (after ADR 0238 and 0239) the server realm spent about 2.5 s there, `resources.dll` (GMod's PNG
decoder) 67 % of it, and the client about 1.5-2 s in ARC9's autorun.

Measured in the PoC (2026-11-17): GMod caches a PNG material by its flags and path in the material system, which both
realms of a game this computer hosts share (`Material("icon16/zoom_out.png", "mips smooth")` is
`0001010icon16/zoom_out`; a second call takes 0.002 ms; 30 PNGs the server realm decoded cost the client 0.10 ms
against 2.4 ms for ten fresh small ones). So the server decodes each icon and the client finds it decoded: skipping the
server's decodes alone would move them to the client.

## Decision

1. **While a map loads** (until the realm's `InitPostEntity`), `Material` for a `.png` asked by an ARC9 attachment file
   (a function whose source, up to nine frames up, is under `arc9/common/attachments`) returns a stand-in:
   - **server realm:** one shared material (`vgui/white`): the server never draws an icon;
   - **client realm:** one `UnlitGeneric` per icon (by flags and path, as GMod's cache), with `$vertexcolor` and
     `$vertexalpha` (GMod's PNG materials have `$flags` 48), made by `CreateMaterial` without decoding, named by the
     icon so a later map's Lua state gets it back.
2. **The icon is decoded the first time anything draws or reads its stand-in**: `surface.SetMaterial`,
   `render.SetMaterial` and the material overrides, and the IMaterial getters (texture, values, size, `IsError`). GMod's
   own `Material` decodes it and its texture goes into the stand-in. Icons nobody opens are never decoded.
3. **Left as GMod's own:** flags other than `mips`, `smooth`, `noclamp` (they change the material); the client while
   ARC9's `arc9_atts_generate_entities` is on (ARC9 then reads every icon's texture name while it loads); every other
   file; every call after `InitPostEntity` (a reload of ARC9's attachments decodes as before).
4. **Switch:** `nativeloader_load_accel_arc9` (archived, 1); the load accelerator's own off switch leaves it out too.

## Consequences

- The server's icon decoding leaves every load ("1012 ARC9 attachment icons not decoded"; 784 left to the client's
  first draw). Measured warm in the user's game: the server phase of modern_house 9.4 -> 8.4 s, of gm_construct after
  it 12.2 -> 10.7 s (the report). The client decodes an icon the first time ARC9's menus show it (about 1-3 ms an
  icon: the first opening of a menu with many icons costs a short hitch once).
- The icons' textures are no longer all held in memory: only those shown.
- A stand-in's `GetName()` is its own (`nlloadaccel/arc9icon_<CRC>`), not `0001010<path>`; its shader is the same.
- Other weapon bases' icons and ARC9's own UI materials are untouched.

## Alternatives considered

- **Skipping only the server's decodes:** nothing saved in a game this computer hosts (the shared cache moves the
  decodes to the client).
- **A Lua table standing in for the material:** `surface.SetMaterial` and the engine take only an IMaterial.
- **Decoding the icons in the background after the load:** a few seconds of frames with work in them and every icon's
  texture in memory, for icons most sessions never show.
