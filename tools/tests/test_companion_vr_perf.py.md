# test_companion_vr_perf.py

Discovery adapter only: `tools/test.ps1` searches tests below `tools`, so this imports VR V6's quality ladder and
Auto controller cases (`VRPerfTests`, LuaJIT, skipped without it), the V6 PoC analysis on synthetic records
(`VRQualityAnalysisTests`) from [vr_perf_test.py](../../companion/tests/vr_perf_test.py.md), and V7's true-stereo
PoC analysis on synthetic records and pictures (`VRStereoAnalysisTests`, Pillow) from
[vr_stereo_test.py](../../companion/tests/vr_stereo_test.py.md). Run the normal gate or
`python -m unittest discover -s tools/tests -p test_companion_vr_perf.py -v`. No game, network or native VR use;
the stereo cases write their pictures under `out\tmp` and remove them. Exit status is unittest's.
