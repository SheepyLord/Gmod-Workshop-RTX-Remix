# cli_tests.py

CTest's offline CLI integration checks for `vrprobe`; runs installation discovery against
missing, valid, empty and malformed path files in a private `LOCALAPPDATA`, verifies UTF-8 JSON and
`--out`, and checks argument failure and help. Every discovered result must say OpenVR is
unloaded. No command initializes OpenVR or takes the VR lock; safe while another scene is running.

Usage: `python -I -B vr/native/probe/cli_tests.py --probe <vrprobe.exe> --scratch
<out/build/.../scratch>`. Inputs: the built probe and a scratch directory under `out/`. Creates
temporary fixtures there, launches the probe with only the child's environment changed, removes
its fixtures afterwards. Reads real process names (no process changes). Exit 0 on success;
nonzero on assertion, launch failure or timeout. Python standard library only; CTest runs it.
