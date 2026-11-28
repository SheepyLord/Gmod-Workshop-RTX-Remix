# workshop_update_probe.lua

The [WU session](workshop_update_session.py.md) passes this client probe to `poc_session.py run --lua` in both launches. It reads the fixture's inner package ID, phase and run token from the isolated PoC's `data/nl_wu/run.json`.

On `gm_flatgrass`, v1 uses the Hotloader library's spawn request for a Citizen and for the host player. It saves through Sandbox's `gm_save` and records the new filename, digest, player selector and carrier keys in `data/nl_wu/baseline.json`. V2 observes the automatic migration before making any spawn request. It then spawns the registered Citizen with Sandbox's NPC-tab command and loads the recorded v1 save with `gm_load`. A persisted marker can resume the saved-actor phase after a Lua realm restart.

The side camera waits for the submitted render palette in the current frame of the Citizen's `Reference` sequence. The measurement is the distance from `ValveBiped.Bip01_Head1` to the midpoint of `Eye_L` and `Eye_R` in Source units. Each `NL_SHOT` view stays in place until the session tool sends the matching `nl_shot_taken` ordinal.

Each observation is one `NL_WU` JSON line under 500 bytes. The final `result` reports `ok`, the last stage and any failure, then the probe prints `NL_SHOT_DONE`. The driver verifies the measurements, registrations, digests, save, screenshots and game exit. [Commands and acceptance values](../../docs/handover/workshop-updates-report.md#claudes-two-launch-poc-check)
