# check_input.py

Offline CTest check of the original SteamVR action manifest and three controller binding files.
Runs with `python vr/native/tests/check_input.py`. No arguments, writes, SDK load or SteamVR
access. Exit 0 when all three consistency tests pass, 1 on a mismatch, nonzero on an input error.

Reads `vr/input/*.json` and `vr/native/input_actions.h`: verifies every native action reader has a
declaration of the right type, every binding output exists with the right type, all supplied
controllers have their core controls, skeleton sides match, and action labels exist. It cannot
validate SteamVR's device-specific parsing; the explicit Index host checks that on real SteamVR.

Optional read-only source-profile verification:
`python vr/native/tests/check_input.py --profiles "C:/Program Files (x86)/Steam/steamapps/common/SteamVR"`.
This does not initialise OpenVR or change settings. It reads Valve's installed Index, Touch and
Vive input profiles and checks every physical source path, hand and mode against them; prints
JSON with profile hashes and checked counts. Redirect that output to evidence under out when
needed. CTest does not require SteamVR to be installed and therefore runs only the offline tests.
