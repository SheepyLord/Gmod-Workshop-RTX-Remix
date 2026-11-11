# run.py

Run `python vr/native/spike_s4/run.py` from the `vr-d` worktree after [build.ps1](build.ps1).
It acquires the main checkout's PoC and VR locks by exclusive creation, waiting up to 30 minutes
for their owners; checks the process inventory; snapshots the PoC with `field_snapshot.py` and
the field install's depot manifests; stages only the disposable module at a previously absent
`garrysmod/lua/bin/gmcl_nlvrs4_win64.dll`; stages the real Release `gmcl_nlvr_win64.dll` at a
previously absent neighboring path; and runs [probe.lua](probe.lua) and
[module_smoke.lua](module_smoke.lua) through `poc_session.py`.
No OpenVR is initialized by this spike (the production Start rejects the current runtime's missing
VR export first). It leaves SteamVR running and changes no Steam settings.
The first session records the actual RTX `mat_queue_mode`. If it is not 2, a second session sets 2
for that session only through the standard driver's console path and repeats the probe; the driver
restores the user's archived settings before quitting. Missing expected probe/smoke markers fail
the run instead of being mistaken for success.

Evidence is in the main checkout's `out/vr/d/s4`: process list, before/after hashes, build hash,
session logs and rollback result. Rollback runs even after a failed session. Only after a clean
rollback and matching watched hashes does it delete its snapshot copies, after checking the
resolved path stays inside the S4 evidence folder. It releases only locks it created. It refuses
existing module paths, running games, damaged snapshots and hash mismatches. It never edits depot
files or `user.conf`. The game writes its usual session files; the standard drivers restore its
settings. Exit 0 means session and rollback completed; exceptions exit nonzero and preserve evidence.
