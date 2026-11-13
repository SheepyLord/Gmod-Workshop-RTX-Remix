# test_vr_session.py

Q disk-space regressions refuse before locks/evidence mutation and preserve an unfinished
transaction until its own matching recovery. A different evidence path cannot clear its marker.

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

V2/F adds a regression for both-realm probe coverage, the moved hook namespace, and server lifecycle counters without a blocked client-to-server lua_run call.

Integration regressions reject missing/swapped roles and accept large panel and opaque black comfort canvases without classifying by size.

Q role regression checks the bounded move_arc_2..8 roles and rejects move_arc_9.

Capture deduplication regression proves mismatched copies retain the entire source, while verified
identical copies retain all raw bytes once and produce the size/SHA-256 removal receipt.

An isolated module failure rejects complete acceptance even with zero engine Lua errors and
a successful done record; this prevents continuous rendering from masking a stopped UI/hands module.

Role-selected extent regression rejects a source whose pixels disagree with its declared dimensions.

Atomic collection regression verifies unchanged raw bytes, source removal by rename, and
refusal to overwrite an existing destination.


The overlay-inventory regression permits an explicit empty inventory or a visible non-wrist role while requiring every declared source image. Unknown/unlabelled images and blank wrist glyphs remain failures.


Visible declared sources remain mandatory, while a hidden source may retire between request and asynchronous capture. The generated-source comparison expands the capture helper and still checks the complete template.


Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


A retained forced-simulation lock test fails the old needs_vr_lock rule and passes the explicit both-locks option.

Round5 exercises the unconditional two-lock policy for simulated, flat and native PoC modes.
