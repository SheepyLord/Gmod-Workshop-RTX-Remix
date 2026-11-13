# Crash-rule tests

`python -B -m unittest discover -s tools/tests -p test_vr_crash.py` generates tiny
AMD64 minidumps under `out/tmp`. Exception and thread-list contexts deliberately
have different RSPs. Tests cover the known fixes return address/build, wrong-thread
and wrong-build rejection, missing/truncated evidence, startup-only NVIDIA matching,
the one-retry limit, and verified copy without source mutation. No game, SteamVR,
WER source directory, external parser or native process is accessed. Exit 0 on pass.

Additional regressions cover repeated unused stream padding, signed Windows exit codes, read-only destination protection, durable single-use retry claims and full-caller re-execution (mocked; no subprocess or game is launched). Wrong exception/thread contexts cannot silently authorize retry.

Round5: after the reviewed queued-draw repair, any fixes stack marker (including an unreviewed build) stops; only the NVIDIA startup signature permits one restored fresh-folder retry. Old receipt flags cannot override current policy. The normal field-quit helper is driver-only; exit5 after a quit crash is fatal and its evidence is retained.
