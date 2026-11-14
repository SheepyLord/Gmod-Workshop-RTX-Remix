# rtx_settings_harness.lua

Loads the packaged RTX fixes' `remixlua/cl/cl_rtx_settings.lua` with stand-ins for the spawn menu and its form
panel, builds two of its Utilities > RTX Remix pages and checks their text
([ADR 0212](../../docs/decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md),
[ADR 0213](../../docs/decisions/0213-automatic-categorization-hardened.md)):

- **Map and prop PBR (ToPBR)**: its title; "Enable ToPBR for maps and props" bound to `rtx_topbr_enabled`; help that
  names Imported game PBR for imported characters, says a real PBR mod always wins and where the textures go; no
  control for `rtx_topbr_metallic` (it changes nothing since R11) and no "map reload" line; Debug Output and Clear Cache.
- **Auto-Categorization**: World Geometry bound to `rtx_auto_categorize_world` with help naming walls, floors,
  ceilings, displacements and static props, and the line about textures taken out of a category in `rtx.conf`.

Usage: `luajit tools/tests/rtx_settings_harness.lua <cl_rtx_settings.lua>`. Reads only its argument. Prints
`PASS RTX settings pages: ...` and exits 0, nonzero on a failed assertion. Run by
[test_topbr_publish.py](test_topbr_publish.py.md).
