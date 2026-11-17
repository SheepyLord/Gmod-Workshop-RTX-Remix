# debug_view_probe.lua

Client Lua for `poc_session.py run --addons --camera <view> --hide-hud --lua tools\qa\debug_view_probe.lua
--lua-shots 180` ([ADR 0237](../../docs/decisions/0237-developers-set-remix-options-through-the-debug-modules-developer-gate.md)):
Remix's albedo debug view set and put back through the RTX debug module, seen from one pinned camera. With
`--extra -insecure` the debug module's developer gate is open (local single-player, `sv_cheats 1` and
`-insecure`) and the view must change; without it the gate is closed and nothing may change.

What it does, each step `NL_DBG_SETTLE` seconds (default 8) after the last change:

1. Prints `NL_DBG status` (`RTXDebug.Status()` as JSON: `can_mutate`, `insecure_launch`, `sv_cheats`,
   `single_player`, the version), calls `RemixConfig.SetConfigVariable("rtx.debugView.debugViewIdx", "23")`
   (`NL_DBG remixconfig`: `false`, ADR 0234 refuses it to every Lua) and takes `before`.
2. `RTXDebug.Remix.SetDebugView(23, 0)` (`NL_DBG set`: `true`, or `nil | <message>`), `NL_DBG overrides`
   (`RTXDebug.Remix.Overrides()`, with each override's `route`), then `view23`.
3. `RTXDebug.Remix.RestoreConfig("rtx.debugView.debugViewIdx")` (`NL_DBG restore`), `NL_DBG overrides`,
   then `restored`.

Each capture is a Source `jpeg` (`garrysmod/screenshots/<NL_DBG_PREFIX>_<label>.jpg`, default prefix
`nl_dbgview`, quality 95; `NL_DBG jpeg` names it) and, two seconds later, `NL_SHOT <label>`, which the
driver answers with a window capture and `nl_shot_taken`. After the last it prints `NL_SHOT_DONE`. The
globals `NL_DBG_VIEW` (another debug view index), `NL_DBG_SETTLE` and `NL_DBG_PREFIX` change the defaults.
Without the debug module it prints `NL_DBG error` and `NL_SHOT_DONE`.

Side effects: the session's debug view while the probe runs, put back by the module's restore (and by its
`ShutDown` hook at quit); three JPEGs in the install's `garrysmod/screenshots`. Exit codes: none (game Lua).
