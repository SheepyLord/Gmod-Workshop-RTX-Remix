# vr_fixture_typing.lua

Private combined fixture helper, embedded by `vr_combined_session.py`; no code ships. It taps
the controller once for each letter of barrel and Enter. It waits for the fallback keyboard and
two frames over the intended cell, then keeps the ray on that cell through three press and three
release frames. It advances only after the real field contains the expected prefix. Missing/wrong
text stays failed: no retries, edits or direct SetText. Inputs are frame, actual text, keyboard
readiness and observed laser hover; outputs are key/down/state. No files or external side effects.
The offline `vr_fixture_typing_cases.lua` checks release ordering and fail-closed missing text.
