# test_remix_light_limits.py

Regression tests for review findings 13, 14 and 22 (2026-11-16) in the fixes part's `remixbinary` add-on:

- 13: Remix lights took networked values unchecked, so any player could feed infinite or NaN radiance and negative
  radii to every RTX client's light API. The stock-light and projected-texture wrappers now limit each value to what
  the entity's own controls give and leave out a light the player's own scaling makes non-finite; the RT light's
  settings have one table of limits (`RemixRTLight` in `entities/remix_rt_light/shared.lua`) that the tools, dupes,
  the editor's apply message and every client's light use.
- 14: the six RT light tools ignored `sbox_maxsents`, the owner and cleanup. They now spawn through
  `RemixRTLight.Spawn` (`entities/remix_rt_light/init.lua`): the limit first, then the count, the creator, the CPPI
  owner, cleanup and undo; the spawn message's fallback in `autorun/sv_rtx.lua` uses the same policy. The light's
  server `Think`, which only scheduled itself for every tick, is gone.
- 22: the sky editor was spawnable by anyone and its dupe modifier unclamped. It is `AdminOnly`, a paste by a player
  who is not an admin is removed, and dupes, the apply message and every client's sky share one table of limits
  (`RemixSkyEditor` in `entities/remix_sky_editor/shared.lua`).

The class converts the shipped files (GLua) into plain Lua with `glua_to_lua` from
[test_glass_map.py](test_glass_map.py.md) once, in a temporary folder under `out\tmp`, and runs
[remix_light_limits_harness.lua](remix_light_limits_harness.lua.md) with LuaJIT once per scenario (skipped without
LuaJIT):

- `test_light_tools_apply_the_spawn_policy_and_the_limits`: scenario `stools`.
- `test_dupes_the_editor_and_the_spawn_message_keep_the_limits`: scenario `apply`.
- `test_sky_editor_is_admin_only_and_clamped`: scenario `sky`.
- `test_clients_hand_the_remix_api_finite_values`: scenario `client`.
- `test_a_distant_light_mutes_the_sun_for_the_session_only`: scenario `distant_sun` (the follow-up of 2026-11-16: a
  distant RT light had written 0 into every RTX client's archived `rtx_api_map_lights_env_brightness_mult` and put it
  back afterwards, so a crash in between left the map's sun dark for good).
- `test_the_map_lights_read_the_sun_brightness_through_the_mute`: in `cl_remix_api_map_lights.lua` only
  `envBrightnessMult()` reads that setting (0 while `Light2RTX.SetEnvMuted` holds a mute), `SetEnvMuted` updates the
  sun lights when the first mute comes or the last goes and runs no command, and the RT light writes the setting
  nowhere.

Run from `tools\`: `python -m unittest tests.test_remix_light_limits -v` (or `tools\test.ps1`). No game, network,
Workshop upload or profile change; scratch in `out\tmp`. Exit follows unittest.
