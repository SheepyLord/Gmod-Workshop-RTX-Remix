# vr_tools_test.py

Verification follow-up adds ULib-faithful lifecycle/unknown-library scenarios, moving-pose
cache/tolerance tests, real damping-name and native factor counterexamples, inherited Hands
icon rejection, and a capture with identical reported draw/attachment but a shifted beam.
The latter must fail acceptance using image-derived centreline alignment.

Evidence counterexamples reject a debug-only beam identity with no captured draw and a
debug distance increase when actual recorded positions do not move. Stick ownership now
asserts absent IN_USE/IN_FORWARD/IN_BACK; rate tests integrate actual partial-stick command
duty instead of summing their own time steps. Server drop rearm also needs a release sync.

Control handoff tests assert physical-hand owners, not only stripped IN_ATTACK.
Capture tests distinguish a muzzle hidden by independently measured model depth from an
unexplained gap in a fully visible beam; the latter still fails the 12-pixel limit.

Claim regressions exercise the reviewed W/K contract at T's boundary, including a pending
B reload owning the control while a new B hold reaches the wheel's time threshold.

Run python -m unittest discover -s companion/tests -p vr_tools_test.py -v, or the existing
tools/tests/test_companion_vr_tools.py gate bridge. Runs named scenarios via LuaJIT and
vr_tools_harness.lua with root and a 30-second case deadline. No game/OpenVR/network/file
mutations. LuaJIT absence is an explicit skip. Exit 0 on success, nonzero on failure.
Release discovery prints this suite's own count.
Also checks the independent evidence reader's angle/vector conventions and the native
timeline's complete 90-degree axes and push/pull actions. These cases require no LuaJIT.
Evidence checks reject a missing target or fixture cleanup as successful tool use. A solver
failure case verifies one error, deferred native drop/controller teardown outside the callback,
and survival of the held physics body.
An independent source check refuses a simulated overlay as an actual Index SDK receipt.
Lifecycle regressions cover repeated pickup before drop and an invoked callback after Stop.
Independent matrix cases preserve a compound pickup-relative rotation and select the exact
native pickup anchor ahead of the earlier pre-pickup sample.

Registers the ladder physgun distance/neutral climb case.
