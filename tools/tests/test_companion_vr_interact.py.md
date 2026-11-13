# test_companion_vr_interact.py

Gate bridge for `companion/tests/vr_interact_tests.py`. Run through `tools/test.ps1 -Config Release` or `python -m unittest discover -s tools/tests -p test_companion_vr_interact.py -q`. The shared loader prints P interaction's count and runs every case. Until the task's suite is merged, absence is one explicit pending-suite skip; the task must add the exact named companion file and its sidecar. No game/network or file writes. Unittest returns 0 on success and nonzero on failure.
