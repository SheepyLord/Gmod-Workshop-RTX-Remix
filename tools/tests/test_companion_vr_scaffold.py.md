# test_companion_vr_scaffold.py

Gate bridge for `companion/tests/vr_v4_test.py`. Run through `tools/test.ps1 -Config Release` or `python -m unittest discover -s tools/tests -p test_companion_vr_scaffold.py -q`. The shared loader prints S scaffold's count and runs every case. No game/network or file writes. Unittest returns 0 on success and nonzero on failure.
