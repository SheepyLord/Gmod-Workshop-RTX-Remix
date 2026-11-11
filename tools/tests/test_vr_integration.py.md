# test_vr_integration.py

Replays only the shared VR C header's added/changed lines from the ordered runtime patches and
compares the result with `vr/native/include/rtxvr_api.h`, ignoring CRLF versus LF. This gate does
not need the runtime clone, OpenVR, a game or a headset. Invalid/missing hunks and unequal bytes fail.

Run `python -m unittest discover -s tools/tests -p test_vr_integration.py -v`, or the Release gate.
Inputs are the two source representations; there are no writes. Exit 0 means equality; 1 means failure.
