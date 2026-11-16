# mmd_player_probe.lua

Client half of [mmd_player_session.py](mmd_player_session.py.md): sent as console Lua by
[poc_session.py](../poc_session.py.md) `--lua` once the map runs. Never install it as an autorun.

It clicks through the Advanced MMD Animation Player as a player does and measures every step:

| Step | Action |
|---|---|
| `idle_baseline` | nothing (5 s) |
| `open_spawnmenu_tool` | opens the spawn menu (`GAMEMODE:OnSpawnMenuOpen`) and picks the tool (`spawnmenu.ActivateTool`), which builds its panel |
| `open_motion_manager` | with `NLMP_SETTINGS.manager`: `mmdvmd_menu` |
| `select_motion_A`, `select_motion_B` | a click on the motion's row in the tool's list (`DListView:OnClickLine`) |
| `close_spawnmenu` | closes the spawn menu |
| `select_self_reload` | R with the tool gun (`+reload`) |
| `assign_npc1`, `assign_npc2` | aims at the NPC and clicks (`+attack`): the selected motion is assigned |
| `unassign_npc2`, `assign_npc2_again` | clicks the same NPC again: off, then on |
| `idle_two_assigned` | nothing, two NPCs assigned (5 s) |
| `open_spawnmenu_again`, `select_motion_A_with_npcs`, `close_spawnmenu_again` | a motion picked while NPCs are assigned |
| `clear_selection` | the tool's Clear selection button (`RequestClearAssignedActors("all")`) |

For each step it tells the server half to start timing, records the time of every frame (a `Think` hook)
and times, with their own time apart from what they call: the add-on's `MMDVMDNPC` functions, its
`mmdvmd_*` net receivers, its hooks and every panel-keyed hook, timers created during the step (named by
their source line: the coalesced list rebuilds and details walks run from timers), `vgui.Create`, the
list and combo box methods, `file.*`, `util.JSONToTable`/`TableToJSON`/`CRC`, `chat.AddText` and
`RunConsoleCommand`. Then it reads the server half's report and writes
`data\nlmp_probe\step_NN_<step>.json`, and at the end `summary.json`.

With `tab`, `open_motion_tab` comes after `open_spawnmenu_tool`: the spawn menu's creation menu switches to the
RTX package's Motion importer tab, which builds its Motion Manager. It also counts the add-on's net messages by
name (each step records the ones it sent) and wraps GUI Scaler's `GUIScaler_Update`, `vgui.GetAll` and the
companion's hooks, for attribution.

With `features`, after the steps (or alone, with `steps = false`): the server half builds a test dance for the
imported character; the probe sets the tool's settings through their console variables
(`mmd_vmd_npc_ragdoll_collision` 1 then 0, `mmd_vmd_npc_keep_flexes` 1 then 0) around the server half's
`followers`, `collision` and `flexes` checks; then it selects the first NPC, opens the debug window on the test
dance and works its timeline: one position (frame 60), then the knob held (its `IsEditing` replaced, and put back
afterwards: GMod copies a class's methods into each panel, so assigning nil would delete the method) over 51
positions in about one and a half seconds, counting the debug requests; after the knob is let go, the frame shown
and the bone and flex lists. All of it goes to `data\nlmp_probe\features.json` and `NLMP_FEATURES` is printed.

With `qol` (the user's requests of 2026-11-16; alone or after `features`): the server half builds the test dance,
plays it once with ragdoll collision on (where the held-out hands are), then `push_old` (the bodies as they were
before) and `push` at `mmd_vmd_npc_ragdoll_push` 100 (the ragdoll's weight, the default), 25 and 0, then `endhold`. Then ToPBR's range: three props spawned in
view (`gm_spawn`: an oil drum, a crate, a chair; their own first materials recorded), `rtx_topbr_debug` and
`rtx_topbr_enabled` on, and `rtx_topbr_scope` 0, 1, 2 and 0 again for 25 s each between
`NLTP_PHASE <name> begin|end` console lines (the console's `Processed material '...'` lines between them are what each
range converted). Each phase records the native converter's `GetScope()` (restricted, names held, the player's
setting), its processed count and whether `InScope` takes the map's first material, each prop's material and the
view model's (`"none"` when there is no such material). Results go to `features.json` (`push_old`, `push_100`,
`push_25`, `push_0`, `endhold`, `topbr_range`).

Settings (a line the driver puts in front): `NLMP_SETTINGS = {window = 4, settle = 8, manager = false,
tab = false, features = false, steps = true, qol = false, motions = {}}`.

Console output: `NLMP_CLIENT_READY`, `NLMP_SETUP <json>`, `NLMP_MOTIONS`, one `NLMP_STEP <step> max <n> ms`
line per step, `NLMP_ERROR <message>` on a failure, then `NLMP_DONE` and `NL_SHOT_DONE`, which ends the
run. Side effects: the spawn menu and tool gun are used, motions are assigned and the selection cleared,
the `data\nlmp_probe` files; the wrappers stay in place until the game quits.
