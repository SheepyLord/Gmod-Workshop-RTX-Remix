# test_vr_session.py

Follow-up 4 executes the real look branch without a screenshot function, checks its wall-time
limit and continued operation after SteamVR failure, refuses missing Pillow before any side
effect, and proves look skips that preflight. An exit-0 user-closed game has a truthful clean
completion result without needing a probe done record or pretending a live SDK query succeeded.

Manual-look acceptance rejects an unmatched initial camera, while an initial camera held until
a real pose match is a separate diagnostic rather than an unmatched submission.

Capture acceptance rejects a valid but blank wrist PNG even when every expected file exists.
The fixture uses the runtime's RGBA8/filter-zero format, without an external image dependency.

The camera-log check rejects a flat first-camera projection followed by VR projections. It
also retains separate stale/unknown diagnostics, without treating flat controls as VR sessions.

Capture completeness is checked too: a successful request is insufficient without both eyes,
centre/depth, mirror, overlay and timing files, including a capture deferred through an absent scene.

Offline tests for `tools/vr_session.py`: lock ownership/exclusion, out-only evidence, timeline
structure, console parsing, Lua literal escaping, protected user.conf refusal and guarded bulk
cleanup. Temporary fixtures stay under repository out/tmp; no game, OpenVR or SteamVR starts.
The steady-window arithmetic check keeps measured command work separate from the elapsed queue
gap and verifies pair throughput and reprojection percentages on an independent numeric fixture.
Long-packet tests verify exact reconstruction/order and rejection of incomplete/truncated records.
A regression rejects frozen successful counters in an active scene; zero Submit errors alone
does not prove the headset continues receiving frames.
Run `python -m unittest discover -s tools/tests -p test_vr_session.py -v` or the Release gate.
Exit 0 means all assertions passed; 1 means failure. Fixtures are removed after each test.
