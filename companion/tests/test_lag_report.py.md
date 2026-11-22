# test_lag_report.py

Runs the six scenarios of [`lag_report_harness.lua`](lag_report_harness.lua.md) (client, server, ulib, ulib_guard,
copy, failure) against the companion's `nativeloader_lag_report.lua` (R28; `ulib_guard`, ULib's records holding the
render guard's wrappers, from ADR 0257).

Usage from the repository root: `python -I -m unittest discover -s companion/tests -p test_lag_report.py`. Needs
LuaJIT (found as in `test_mmd_alpha.py`); skipped when it is not installed. Each run has a thirty-second timeout.
Changes no files, game or network. unittest exits zero on success, nonzero on a failure; the repository's companion
checks discover it with the other tests there.
