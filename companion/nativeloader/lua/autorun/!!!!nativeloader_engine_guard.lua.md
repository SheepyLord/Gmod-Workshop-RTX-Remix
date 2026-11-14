# !!!!nativeloader_engine_guard.lua

R23 ([ADR 0130](../../../../docs/decisions/0130-an-engine-guard-for-lua-start-up.md)): loads the
engine guard, the `nlengineguard` binary module
([engine_guard/](../../../../engine_guard/README.md): `gmcl_` and `gmsv_nlengineguard_win64.dll`,
shipped in the fixes part), before the add-ons' autoruns: `!!!!` sorts before every autorun name that does
not itself start with four `!`.

- **When.** Shared, so in a local game the server realm, which starts Lua first, has it before an
  add-on's shared autorun runs there. Only in a start where this machine's loader activated RTX, decided
  as [`_nativeloader_guard.lua`](_nativeloader_guard.lua.md) decides it (`native-loader/status.json`
  active and, from loader 0.14.0, the held `native-loader/rtx-session.txt`): the material loop the guard
  cuts happens only under RTX's shader paths, and a start through an off switch loads no native code.
  On a remote server the client realm runs none of our autoruns; the early view
  (`_nativeloader_guard.lua` in `includes/init.lua`) loads the module there. A module already loaded
  by it is used as it is.
- **The answer for the rest of the package** ([ADR 0206](../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md)). Before it stops in a start without RTX, it publishes that decision, worked out once, as `NativeLoaderRTXStart()`. Every other autorun of the companion, and of the RTX fixes' `remixbinary` add-on, returns at its first line of code when the answer is no; `server/nativeloader_leftovers.lua` uses it to stay out of RTX starts. This file sorts before all of them.
- **The message.** The watchdog's native message (title, and a body with `%s` for the stuck file) comes from
  [`nativeloader/engine_guard_words.lua`](../nativeloader/engine_guard_words.lua.md), in the player's
  language from the companion's own catalog. The module takes only the first `SetMessage` call, and the
  function is removed from the table after it, so no other Lua, a server's included, sets the text of a
  native message. In the client realm the early view has already made that call.
- **The end of the watch.** `Initialize` ends it (`nlengineguard.StartupDone()`), and so does the first
  tick, in case an earlier `Initialize` hook failed. `OnGamemodeLoaded` and `PostGamemodeLoaded` bound it:
  `StartupDone(150)` ends it at the latest 150 s later, so it never stretches over a long map load, while a
  stall in an `Initialize` hook (90 s) is still reported. When the module says the start was reported and
  went on after all, the report `data/native-loader/startup-stall.json` is deleted.
- **The next start.** Client realm, eight seconds after `InitPostEntity`: a report left by a start that
  never got past Lua is shown once (its `utc` and `process_id` are kept in
  `data/nativeloader_companion/startup_stall_shown.txt`) as a 30-second notice
  ([`nativeloader/notice.lua`](../nativeloader/notice.lua.md)) that names the file nearest the top of the
  last sample's stack and the add-on that has it: a mounted Workshop add-on's title (`file.Exists` with
  the title as the search path) or a legacy `garrysmod/addons` folder. The console line stays English.

Tested by [`tools/tests/test_engine_guard_lua.py`](../../../../tools/tests/test_engine_guard_lua.py.md).
