# test_motion_tab.py

Runs [motion_tab_harness.lua](motion_tab_harness.lua.md) under LuaJIT, once per scenario, without
starting Garry's Mod. It loads the companion's Motion importer tab and the shipped Character Motion
Importer files from `packages/character-motion-importer` (catalog code from `sh_core.lua`, then
`cl_menu.lua`, `cl_import_data.lua`, `cl_import_bake.lua`, `cl_importer.lua`, and for one test the tool,
`lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua`) with mocked Derma and net messages.

```powershell
python -m unittest discover -s tools/tests -p test_motion_tab.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_tab_fills_in_when_the_addon_arrives` | The tab waits for the add-on, then builds: section buttons and Open in window; the importer's inputs in the desktop importer's order on the left, the bake, options, progress and log on the right; a file chosen through Model Hotloader's picker; the library with its columns and actions; Open in window opening both windows |
| `test_without_file_access_the_importer_explains` | The notice, Resolve and File Access Settings, disabled controls, and everything enabled once file access comes |
| `test_floating_windows_and_console_commands` | `mmdvmd_menu` and `mmdvmd_import` build the windows in Derma's look with their old layout; closing releases the hooks; losing file access closes the importer window and opens Resolve |
| `test_tab_and_window_share_the_inputs` | A file and an option chosen in the window show in the tab |
| `test_addon_without_builders_gets_window_buttons` | An add-on copy without the builders: buttons that open its windows |
| `test_the_importer_scales_with_the_screen_like_external_models` | `MMDVMDNPC.MenuScale()`: 1 at 1080p and below, 2 at 2160p, 4/3 at 1440p, times the player's `mmd_vmd_npc_menu_scale` |
| `test_with_gui_scaler_the_tab_opts_out_of_its_second_scaling` | With GUI Scaler's convar present, the tab, its buttons and each section (one built later too) carry `gScF`, as Model Hotloader's panels do; without it nothing is marked |
| `test_a_failing_builder_is_reported_once_and_offers_the_windows` | A builder that throws: one report, no half-built page left, the window buttons instead, and no second attempt on the next frame |
| `test_title_and_tooltip_follow_the_language` | The tab's title and tooltip through the companion's translations |
| `test_a_selection_asks_for_the_built_flags_not_the_details` | The user's report of 2026-11-14: a target status, an assignment status and a finished build send no details request (the selection and the build ask for the built flags); the flags set the details' `built` and the Motion Manager changes its Built cells without rebuilding its rows; a cut-off flag list and a changed motion list ask for the details, an unchanged list does not |
| `test_the_tools_motion_list_is_rebuilt_only_when_it_changes` | The tool's panel (`TOOL.BuildCPanel`): its motion list keeps its rows through built flags and unchanged details and is rebuilt for a new motion; the two new settings' defaults (keep expressions off, ragdoll collision on) |
| `test_a_dances_music_ends_with_its_dancer` | The user's report of 2026-11-16: the music stops when its dancer becomes invalid, also without the server's stop; an NPC spawned later at the dancer's index does not bring it back; a start that arrives before its dancer is networked waits for it and then follows it |
| `test_the_debug_windows_timeline` | The debug window's timeline: the strip above the buttons, a short label and a long bar; a drag sends one request a burst with the latest frame; an answer while the knob is held moves the pose and summary but not the lists, which catch up when it is let go; an answer moves the knob without asking again |
| `test_the_debug_windows_hide_and_come_back_in_debug_mode` | The user's request of 2026-11-24 (ADR 0264): the debug window's Hide windows button hides it and the camera debug panel without closing them or telling the server (debug mode stays on), with a notice naming the key that shows them again (the context menu's, or the player's own); a preview step leaves them hidden; the context menu's key shows both and gives the debug window the mouse again; `mmdvmd_debug_panels` (0 hides, 1 shows, nothing toggles); the player's own key (`mmd_vmd_npc_debug_panels_key`) toggles once per press, not while a text field has the keyboard, not at all when unset; opening debug mode again shows them; with no window nothing counts as hidden; the five new texts in all nine catalogs, each `_fmt` text taking one key name |

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
