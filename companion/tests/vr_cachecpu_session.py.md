# vr_cachecpu_session.py

Run `python companion/tests/vr_cachecpu_session.py --package out/dist/candidate.gma --evidence
out/vr/v2q-review/cachecpu-sim-01 --inspect-dll out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll`.
Simulation only: 35 active seconds, no SDK initialization, normal production driver, PoC lock,
native counters/captures, two Start/Exit cycles and verified rollback. Uses a fixed stationary pose,
all modules and valid physical hands. Four balanced cached/forced-uncached blocks exclude their
edges from whole game-thread CPU/cycle intervals; requires >=200 frames per mode and measured
resolver behavior. Private server commands select Hands/noclip and observe health; nothing ships.
HUD change/capture follows the measured blocks. Outputs standard driver evidence, CPU/network
accounting and cachecpu-acceptance.json. User-authorized field quit only when needed, recorded.
No package writes, downloads, SteamVR changes or SDK run. Exit 0 only for all checks; errors/nonpass
are nonzero. Existing/failed evidence is never overwritten. Requires Pillow for unattended captures.

Stationary state is sent only on change, so zero server state sends after observer attachment is
valid in this control. It requires both realms' callbacks, client sync and absent off-state registry;
the combined acceptance separately requires actual dynamic server-state sends. All raw accounting
checks are retained, including the stationary false dynamic-state witness.
