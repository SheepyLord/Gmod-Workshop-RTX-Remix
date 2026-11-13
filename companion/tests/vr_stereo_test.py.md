# vr_stereo_test.py

Offline tests of [`vr_stereo_poc.py`](vr_stereo_poc.py.md)'s analysis (VR V7): synthetic `V7-stereo` records and
synthetic eye pictures (a blocky pattern, each eye shifted twelve pixels the other way) written with Pillow under
`out\tmp` and removed afterwards. A good run passes every analysis check; swapped eyes, eyes without disparity, a
darker eye, stereo that never starts, a second eye that costs nothing, and missing pictures each fail the check
that guards against them. Skips without Pillow.

```
python -m unittest discover -s companion/tests -t companion/tests -p vr_stereo_test.py
```

The gate runs it through [`tools/tests/test_companion_vr_perf.py`](../../tools/tests/test_companion_vr_perf.py.md).
