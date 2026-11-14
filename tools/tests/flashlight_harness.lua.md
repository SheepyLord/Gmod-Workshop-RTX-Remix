# flashlight_harness.lua

Loads the RTX fixes' flashlight Lua (GPL, `packages/fixes`) under a fake GMod API and checks the R19
fixes ([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md)) and the
flashlight's automatic brightness ([ADR 0208](../../docs/decisions/0208-the-rtx-flashlights-automatic-brightness.md)):

- `server <sv_remix_flashlight.lua>`: a burst of toggle messages costs one broadcast and the next
  one after the 0.3 s cooldown counts (F-04); a dead player, a spectator and a player whose
  `CanUseFlashlight()` is false cannot switch on, by message or by the flashlight key, while
  switching off is never refused (the review's miss); colour messages are coalesced: the first is
  broadcast at once, the newest when the 0.1 s interval ends, none while the flashlight is off.
- `client <cl_remix_flashlight.lua>`: a repeated "on" for one player (the join-time sync after a
  broadcast) replaces the Remix light instead of leaking it (F-03); "off" and `rtx_flashlight_reload`
  keep the count right.
- `auto <cl_remix_flashlight.lua>`: automatic brightness is on by default; the light comes on at the gain its beam
  wants, not at the fixed level; a wall up close is over 90 % dimmed within 0.2 s and settles on its gain; open space
  brightens gently (under a third of the way in 0.2 s) up to Max Boost and stays there; the haze stays at its set level
  under the boost (the volumetric scale divided by it); traces that start in a solid leave the gain; off is the fixed
  brightness exactly, with no traces; on again it is at its gain at once; the car the player sits in (and the seat's
  parent) is left out of the measurement; your own light is measured every frame (seven traces) and another player's
  ten times a second; strength 0, Max Boost and the normal distance are honoured; the menu has the switch and its three
  sliders, and Reset restores their defaults. Expected gains are worked out from the shared maths
  (`cl_remix_light_gain.lua`, which [light_gain_harness.lua](light_gain_harness.lua.md) checks) and the geometry the
  file describes: the light `rtx_flashlight_offset_forward` behind the eyes, a wall across the view.

The fake world is a wall across +x (or open space), traces that start in a solid, and a car's hull just ahead of any
trace that does not filter it; the fake Remix API records each light's radiance and volumetric scale. `include()` loads
the fixes' own Lua beside the given file's `lua/` folder.

Usage: `luajit tools/tests/flashlight_harness.lua server|client|auto <file>`. Reads only the given file and, for
`client` and `auto`, the shared gain beside it; no game, network or file writes. Exit 0 and a `PASS` line on success,
nonzero on a failed assertion. Run by [test_flashlight.py](test_flashlight.py.md).
