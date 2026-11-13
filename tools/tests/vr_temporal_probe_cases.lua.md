# vr_temporal_probe_cases.lua

Offline regression for the actual-scene latency/motor observers. Run through test_vr_combined.py
or LuaJIT with repo root. With no public CalcView entry (as with owned/ULib dispatch), probes
must record RenderScene arguments once per frame, preserve the camera registry and remove their
observers. No game, filesystem changes or SDK; assertion failure exits nonzero.
