# vr_hands_poc.py

Short task-H PoC driver built on `tools/vr_session.py` with its snapshot, hash protection,
normal quit, shared PoC/VR locks, runtime captures and rollback unchanged. Adds its own timeline,
fixture and captures to the generated probe; no production file or shipped package is altered.
Lock receipts name task H; waits up to an hour without removing another task's lock.

Usage: `py -3 companion/tests/vr_hands_poc.py --package out/dist/<package>.gma --evidence out/vr/v2h/<new-run>`.
Use `--simulate` after task N is merged (PoC lock only); acceptance omits it for the Index (both).
`--legacy-input` is for the pre-N native module: the fixture supplies curls through scripted
Actions while native timeline poses still drive the scene. Final N acceptance omits that option.
Default active interval 85 s, `--seconds` overrides it; keep below 180 s. Requires Pillow like the
unattended standard driver. Never starts/quits SteamVR separately or changes its settings.

Inputs: local package, production driver, Lua fixture. Writes timeline beside the fresh evidence
folder under repository `out`, then the standard logs/receipts/PNG/counter/debug records in it.
`hands-acceptance.json` additionally rejects missing models/finger bones/draws/captures,
missing wall/ghost behavior or live hand models after Exit; renderer progress alone cannot pass H.
It also checks each individual curl, actual mirrored thumb-bone opposition, measured near distances,
mirrored mapping and a changed hand model.
The generated probe replaces V1's three turn captures with H's own plateau captures; at most
one new H capture is requested per frame so two requests cannot overwrite the native slot.
Game-side fixtures select a real world wall, position the test player, exercise individual
fingers, 0.2/0.3/0.5 m wrists, wall stop, ghost switch, dominant hand and player-model change.
Archived settings are restored before finishing and by the driver's snapshot. Temporary server
commands and client probes are confined to the disposable process. Exit follows the driver:
0 success, 1 checks/operation failed, 2 dependency/argument refusal. Rollback uses the standard
driver's `--evidence <run> --rollback` if preparation is interrupted.
