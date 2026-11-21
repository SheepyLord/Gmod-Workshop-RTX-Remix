# map_sky.lua

Which sky a map shows in RTX starts ([ADR 0249](../../../../docs/decisions/0249-which-sky-a-map-shows.md)): the RTX sky,
the map's own sky (its sky textures, and its 3D skybox where it has one), or the sky the map's RTX version brings, and
the words that say so. A module (`include("nativeloader/map_sky.lua")` returns it) with no Garry's Mod function in it,
so the tests run it under plain LuaJIT. [`nativeloader_sky.lua`](../autorun/nativeloader_sky.lua.md) reads the map, the
add-ons' sky files and the player's choices, and does what this decides. The guide for modders is
[docs/MAP_SKY.md](../../../../docs/MAP_SKY.md).

| Function | What |
|---|---|
| `validId(id)` | A sky file's id: lower-case letters, digits, `_` and `-`, at most 48, starting with a letter or digit; not `auto`, `rtx`, `map` or `addon` |
| `validMap(name)` | A map name the sky files' folder may be named after: letters, digits, `_`, `-`, `.`, at most 64, no `..` |
| `validSkyname(name)` | A sky name as `sv_skyname` takes it: letters, digits, `_`, `-` and `/` (subfolders), at most 64, no empty segment or trailing `/` |
| `validChoice(choice)` | `auto`, `rtx`, `map`, `addon` or a valid id |
| `title(text)` | A title for the chat and the panel: control characters made spaces, spaces collapsed, at most 64 bytes of whole UTF-8 characters; nil when nothing is left |
| `skyCamera(entities)` | The map's `sky_camera` among its parsed entities (`sky_model.parseEntities`): `{ scale = n }` (16 when the key is missing or not above 0), or nil without a 3D skybox |
| `skyTexinfos(lump, band)` | How many texinfos of a texinfo lump (72-byte records, the flags at byte 64) carry `SURF_SKY2D` or `SURF_SKY`; `band` is `bit.band` |
| `lzmaStream(lump)` | A lump Source compressed (`LZMA`, the size unpacked, the size packed, five property bytes) as the stream `util.Decompress` reads (the properties, the size unpacked as 8 bytes, the data); nil for anything else |
| `facts(info)` | What the map has of its own, from `{ texinfos, faces, camera, skyname }`: `open` (it shows sky somewhere, or that is unknown), `own` (sky faces and its sky name's materials: a sky of its own), `own3D`, `fits3D` (scale 16, `SCALE`), `scale`, `skyname` |
| `declaration(id, text, decode)` | A sky file checked (`decode` is `util.JSONToTable`): a table `{ id, kind, title, skyname, skybox3d, default, priority }`, or nil and the reason. Version 1; `sky` `map` or `skybox`; `skyname` with `skybox`; `skybox3d` and `default` true or false (default true); `priority` a whole number -100 to 100 (default 0); at most 16 KiB |
| `sorted(list)` | Sky files by priority, the higher first, then by id |
| `resolve(s)` | Which sky shows, before a setting changed in the session; `s`: `choice`, `global` (`nativeloader_sky`), `facts`, `files` (sorted), `addon` (`{ name, fixed }` of an add-on that sets the sky from Lua), `single` (a single-player game). The result: `sky` (`rtx`, `map`, `file`, `addon`), `reason` (`default`, `choice`, `global`, `package`, `missing`), `file`, `addon`, `threeD`, `blocked3D`, `skyname`, `package` (the title of the sky `auto` gives from the map's RTX version) |
| `choices(s)` | The panel's This map list: `{ value, label, argument }` for Automatic, RTX sky, The map's own sky (where it has one), the add-on's and each usable sky file's |
| `state(e, f)`, `advice(e, f)`, `limit(e, f)` | The chat line's sentences as `{ text, arguments... }` (text marked for the translations with `N`, translated by the caller): what shows (`e.shown`: `rtx`, `own`, `addon`, `taken`; `e.follows` for an add-on that sets the RTX sky itself), how to switch (or that the map has no sky of its own), and that a 3D skybox at another scale cannot be shown |

How `resolve` decides:

1. `rtx`: the RTX sky. `map`: the map's own sky where it has one, else the RTX sky (reason `missing`). `addon`: the
   add-on's sky where one answers. A sky file's id: that file's sky, if usable.
2. `auto` (and a choice that does not apply): the map's RTX version's sky, the user's choice of 2026-11-20: the add-on's
   that sets it from Lua first, then the first sky file with `default` true; a `skybox` file only in a single-player
   game (`sv_skyname` is every player's).
3. Then `global`: `0` shows the map's own sky where it has one; otherwise the RTX sky.

The map's own sky and a sky file's bring the 3D skybox (`threeD`) where the map has one at scale 16 and the file does
not say `skybox3d: false`; at another scale `blocked3D` is set and `limit` says so.

Tested by [`tools/tests/test_companion_sky.py`](../../../../tools/tests/test_companion_sky.py.md).
