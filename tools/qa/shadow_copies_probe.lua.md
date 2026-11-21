# shadow_copies_probe.lua

The client half of [shadow_copies_session.py](shadow_copies_session.py.md): client Lua that the session sends into
the PoC game (`poc_session.py run --lua <file> --lua-shots`), with `NLSH = {...}` settings in front.

From a coroutine on `Think` it waits `settle` seconds (the RTX fixes reload models after a map starts), notes the
switches' values (`rtx_pseudoplayer`, `rtx_pseudoweapon`) and the sky's clock (`nativeloader_sky_time_passes`,
`nativeloader_sky_hour`), holds the time of day at `hour` when set, puts `weapon` in the player's hand when set
(`nlshadow_weapon`), runs `nlshadow_character` first when `character` is set,
then records `01_before` and each step of `steps`: the step's console commands (`set`: a switch and its value;
`run`: a command such as `nlshadow_player_model`), a wait (`wait`, 12 s), a state and a screenshot. A state is the
switches' values, the copies counted (`ents.FindByClass`), whether the player is drawn in third person, the held
weapon's class and the frame times over three seconds (`frames`, `median_ms`, `p90_ms`); it is printed as
`NLSH_STATE <json>`. A screenshot is `NL_SHOT <step>`, answered by the run with `nl_shot_taken <n>`; the RTX Remix
guide and the loader's update reminder are closed first.

At the end it puts the switches and the sky's clock back as it found them, asks the server half for its report
(`nlshadow_server_report`), writes `data\nlshadow\client.json` (`settings`, `original`, `steps`) and prints
`NL_SHOT_DONE`. An error prints `NLSH_ERROR <message>` and `NL_SHOT_DONE`.

**Prints:** `NLSH_PROBE_READY`, `NLSH_ORIGINAL`, `NLSH_STATE`, `NL_SHOT`, `NL_SHOT_DONE`. **Writes:**
`data\nlshadow\client.json` in the PoC's data folder (copied into the evidence before the PoC is restored).
