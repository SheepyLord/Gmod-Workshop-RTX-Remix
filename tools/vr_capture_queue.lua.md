# vr_capture_queue.lua

Private production-driver capture scheduler, embedded into the generated Lua probe by vr_session.py.
Queue.New takes injected Frame/Now/Running/Inventory/Describe/Forward/Error callbacks. Request accepts
the native capture arguments; Pump forwards at most one per subsequent frame, waiting until every
visible overlay is at least two frames old so a fresh render target can be painted before copying.
It takes the semantic inventory at dispatch. Source readiness times out after one second; native
refusals and undelivered captures at Stop are errors, never successful missing evidence. No standalone
hooks, files, SDK calls or exit code. Tests use injected clocks and callbacks, with no game/OpenVR.


Required logical sources without a handle/visible binding wait and then fail readiness, rather than disappearing from the expected inventory.
