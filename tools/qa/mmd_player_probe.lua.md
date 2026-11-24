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

With `camera` ("Hide yourself during camera motion", the user's request of 2026-11-21,
[ADR 0250](../../docs/decisions/0250-hide-yourself-during-camera-motion.md); alone or after the others): first the
order of `Think`, `CalcView`, `PreRender`, `RenderScene` and `PostRender` in a few first-person frames, each with
`FrameNumber()` (`hook_order`). Then the server half builds a test dance with a still camera beside the first NPC that
holds it, you and the second NPC in the shot; the probe closes the first-run RTX Remix guide (it opens eight seconds
after the spawn), holds the time of day at 15:00 (`nativeloader_sky_time_passes 0`, `nativeloader_sky_time 15`), with
`copies` turns on the RTX fixes' body and weapon copies (`rtx_pseudoplayer 1`, `rtx_pseudoweapon 1`: the companion's
"Local player shadow", off in the classic settings), turns on your RTX flashlight (`rtx_flashlight_on`, brightness 20000
so its light shows in daylight), all put back at the end, aims it at the dancer and samples, frame by frame (with
`hide = false` the option stays off for the whole run: a control in which the hide never runs): the no-draw flags of
your body, your active weapon, the copies and a Model Hotloader character's visual proxy right after the add-on's
`RenderScene` hook (`after_hide_*`), right before and after its `PostRender` hook (`before_restore_*`,
`after_restore_*`; both hooks wrapped) and between frames (`outside_*`, in `Think`); how often the camera motion was
active, the add-on said it hides you (`MMDVMDNPC.CameraHidesLocalPlayer`) and the game drew you as in third person
(`ShouldDrawLocalPlayer`); which of the scene's hooks ran, how often you were no-draw in them and one call's arguments
each (`events`, `events_hidden`, `event_args`); the radiance your flashlight's light was given
(`RemixLight.UpdateSphere` wrapped for the fixes' hash of your index; `flash_min`, `flash_max`); the copies' count and
your Model Hotloader instance. Phases: `first_person`; the looping dance's camera
motion with the option on (`hidden`, screenshot `camera_hidden`), unticked (`unticked`, `camera_unticked`) and
ticked again (`ticked_again`); after the server stops it (`after_stop`), and the camera's last view drawn by the
probe in third person with the camera's field of view (`after_stop_same_view`, screenshot `after_stop_same_view`); the
camera toggle
(`mmdvmd_camera_toggle`) during a dance (`before_toggle`, `after_toggle`); the dance played once to its end
(`once_playing`, `ended_after_seconds`, `after_end`); an imported character as your player model (the server half's
`player_model`), in first person, hidden (`mmd_hidden`, screenshot `mmd_camera_hidden`), still hidden six seconds
later, past the Hotloader's five-second release (`mmd_hidden_later`: the same instance), and unticked
(`mmd_unticked`, `mmd_camera_unticked`); the dancer removed under the camera (`before_remove`, `after_remove`). Each
screenshot is an `NL_SHOT <label>` line answered by the driver's `nl_shot_taken <n>`. Everything goes to
`data\nlmp_probe\camera.json`, then `NLMP_CAMERA` is printed; the option is set back on, the flashlight off and the
other settings above as they were.

With `carriers` (`"build"` or `"find"`, [ADR 0259](../../docs/decisions/0259-imported-characters-share-their-builds-across-carriers.md),
2026-11-22; alone or after the others): the server half's `carriers_build` or `carriers_find` (up to 300 s), its answer
in `data\nlmp_probe\carriers.json`, then `NLMP_CARRIERS` is printed.

With `debug_windows` ("hide the debug windows and stay in debug mode", the user's request of 2026-11-24,
[ADR 0264](../../docs/decisions/0264-hide-the-debug-windows-and-stay-in-debug-mode.md); after the others): the probe
closes the first-run RTX Remix guide, has the server half write and build the test dance on the first NPC (`build`, which
also selects it: the debug target), opens debug mode on the test dance at frame 60 through `MMDVMDNPC.ShowDebugMenu`
and ticks the camera debug panel. At each phase it records whether
the debug window and the camera panel are visible, whether the cursor is (`vgui.CursorVisible()`: whether the game
has the mouse), whether the keyboard focus is inside the debug window, `MMDVMDNPC.DebugWindowsHidden()` and the server
half's `debug_state` (the server's last debug frame and the first NPC's bones: debug mode and its pose): `shown`
(screenshot `debug_shown`), after the window's Hide windows button (`hidden`, `debug_hidden_notice` with the notice),
seven seconds later (`hidden_later`, `debug_hidden` once the notice has gone), with the context menu held
(`+menu_context`, `context_open`) and let go (`context_closed`, `debug_back`), after `mmdvmd_debug_panels 0` and `1`
(`command_hidden`, `command_shown`), hidden and opened again through `ShowDebugMenu` (`reopened`), and after the window
is closed (`closed`), then the server half's `cleanup` removes the test dance. Also the button's text, tooltip and width
(`button`). Everything goes to `data\nlmp_probe\debug_windows.json`, then `NLMP_DEBUG_WINDOWS` is printed.

Settings (a line the driver puts in front): `NLMP_SETTINGS = {window = 4, settle = 8, manager = false,
tab = false, features = false, steps = true, qol = false, camera = false, copies = false, hide = true,
debug_windows = false, carriers = "", motions = {}}`.

Console output: `NLMP_CLIENT_READY`, `NLMP_SETUP <json>`, `NLMP_MOTIONS`, one `NLMP_STEP <step> max <n> ms`
line per step, `NLMP_ERROR <message>` on a failure, `NL_SHOT <label>` per camera screenshot, then `NLMP_DONE` and
`NL_SHOT_DONE`, which ends the run. Side effects: the spawn menu and tool gun are used, motions are assigned and the
selection cleared, the `data\nlmp_probe` files; with `camera`, your flashlight, its brightness for the run and an
imported player model; the wrappers stay in place until the game quits.
