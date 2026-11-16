# remix_light_limits_harness.lua

LuaJIT harness for [test_remix_light_limits.py](test_remix_light_limits.py.md) (review findings 13, 14 and 22,
2026-11-16). It loads the RTX fixes' Remix light and sky editor Lua from the fixes part's `remixbinary` add-on, already
turned into plain Lua by the runner, with the engine stubbed: vectors and angles, convars, hooks, net messages, entities
whose networked-value setters refuse what the engine refuses (a table where a number goes raises), players with
sandbox's `CheckLimit` and `AddCount`, CPPI, cleanup and undo recorders, and recorders for the Remix light and
atmosphere APIs.

```powershell
luajit tools\tests\remix_light_limits_harness.lua <scenario> <folder>
```

The folder holds the converted files under short names (`rt_shared.lua`, `rt_init.lua`, `rt_cl_init.lua`,
`sky_shared.lua`, `sky_init.lua`, `sky_cl_init.lua`, `sv_rtx.lua`, `light_wrapper.lua`, `pt_wrapper.lua`,
`stool_<kind>.lua`); the runner's `FILES` table maps them to the shipped paths. One scenario per run:

- `stools` (finding 14 and the tools' part of 13): the light entity has no server `Think`; for each of the six
  `remix_rt_light_*` tools, a player at `sbox_maxsents` spawns nothing and nothing is counted; under the limit the
  light is counted (`AddCount("sents")`), names its creator and CPPI owner, is in the player's cleanup (`sents`) and
  undo (the tool's own undo name); crafted convars (`-1e39`, `1e39`, `nan`, `inf`) leave every setting within
  `RemixRTLight.LIMITS` (a NaN setting keeps its default); the tools' own ranges (radius and sizes to 2000, brightness
  to 10000, the bonemerge tool's type and offsets) are kept; a right click is limited the same way; without CPPI the
  rest of the policy holds.
- `apply` (findings 13 and 14): a crafted dupe (wrong kinds, NaN, infinities, a 1000-character texture name) raises
  nothing and ends within the limits; a genuine dupe comes back exactly; the editor's apply message does nothing for a
  player who is not an admin, clamps an admin's values, changes only the settings the editor always could
  (`RemixRTLight.EDITOR_KEYS`) and keeps the editor's slider range; the spawn message goes through `Spawn_SENT` in
  sandbox, and without it spawns only for an admin, asks the limit and counts, owns, cleans up and undoes the light.
- `sky` (finding 22): the sky editor is `AdminOnly`; a paste by a player who is not an admin removes it and applies
  nothing; an admin's paste and a server restore clamp 0, 1e30 and -1e30 and leave NaN and text as they were; the
  apply message clamps an admin's values and ignores other players; a client hands the atmosphere API finite values
  within the limits, sends no sun angle that is not a number, and passes a valid sky through unchanged.
- `client` (finding 13): the stock-light wrapper gives finite, non-negative radiance and radius for a `gmod_light`
  brightness or size of inf, NaN, 1e39 or below zero and a lamp cone within 5 to 85 degrees, keeps a normal light, a
  normal lamp and the light tool's brightness 20 as they were, and updates a wrapped light whose values turned bad
  with finite values; the projected-texture wrapper bounds brightness, field of view, reach and colour and keeps a
  normal projected texture as it was; the light entity's client creates and updates each light type with finite
  values within the limits from crafted networked values, keeps a bonemerged light at its bone when its offsets are
  not numbers, and passes a valid light through unchanged.
- `distant_sun` (the follow-up of 2026-11-16): a distant RT light asks a stand-in `Light2RTX.SetEnvMuted` to mute the
  map's sun once, not every frame; a second distant light keeps the mute until both are gone (one removed, the other
  switched to a sphere); the player's saved `rtx_api_map_lights_env_brightness_mult` (1.7 here) is never written, also
  without `Light2RTX`; the file registers no ShutDown hook that puts a setting back. Against the file before the fix it
  fails at that hook.

Prints `PASS <scenario>`; exit 1 with `FAIL: <reason>` on stderr otherwise. Against the files before the fix every
scenario fails (the client one with `gmod_light brightness inf size 256 base.radiance.y is nan`, the reviewer's
reproduction). No game, network or user files.
