# vr_move_latency_probe.lua

Test-only probe appended by `vr_move_session.py --case latency`. Wraps the owned `nlvr.core`
CalcView callback and records its actual returned camera position once per rendered engine frame,
the same frame's raw pose/sequence, feet, tick, ideal unconsumed world position and rolls. The
reference is the first camera plus tracking displacement at the session's fixed yaw/scale; no
stick movement occurs. Collects 0.5/1.5 m/s side translations and a 2 Hz, 5 cm sway. Rows leave
through the existing bounded console JSON transport in 32-frame batches. Owned cleanup flushes
remaining rows and restores the exact wrapper when present. Clears physical keyboard/mouse in a
private test mover. After Exit it records the real player angles and the flat CalcView result's roll.
No game-file writes, new native path, SDK init or settings changes.
Exceptions remain real driver failures. Use only through the locked PoC driver.
For the combined follow-up session, optional local FROM/OFFSET values attach after the movement
sequence and normalize the later motion times to the identical analysis windows.

Temporal observation now records the engine RenderScene origin/angles once per frame, after camera ownership, rather than rawset-wrapping a retired public CalcView key. It never returns a view or mutates dispatch; cleanup removes the observer. This works with stock/ULib owned camera registries. Native timeline and all latency/roll bounds remain unchanged.
