# vr_perf_test.py

unittest wrapper that runs each scenario of [`vr_perf_harness.lua`](vr_perf_harness.lua.md) under LuaJIT: VR V6's
quality ladder and Auto controller. Skips when LuaJIT is not installed (`test_mmd_alpha.LUAJIT`).

```
python -m unittest discover -s companion/tests -t companion/tests -p vr_perf_test.py
```

Each test passes when the scenario exits 0 and prints `PASS <scenario>`. No files are written.

V8: adds the `frame_generation_rates` scenario.
