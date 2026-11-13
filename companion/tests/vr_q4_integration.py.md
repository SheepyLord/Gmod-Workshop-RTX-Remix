# Shared ULib all-module integration witness

`python companion/tests/vr_q4_integration.py --package <frozen gma> --evidence
<fresh out folder> --simulate` runs one production VR activation with P push/throw,
W pistol/foregrip/melee/grenade, K physical pistol reload, and T physgun/wheel/tool
features, followed by Exit, a second Start and Exit. The ordinary UI and locomotion
modules remain loaded. The shared ULib test add-on is installed before Start, with
stand-in add-on hook additions/removals during and after both activations.

The same script without `--simulate` uses the real compositor and both standard
locks, with scripted natural poses and explicit recorded components while the
physical controllers are off. Functional inputs run on Source time, with raw native
time retained separately. This is not a worn/live-finger claim or a timing benchmark.

Existing subsystem observer sources are scoped into sequential time windows; their
semantic checks remain necessary in addition to `integration-checks.json`. The K
off hand is guided through the actual model-local well, as its calibration fixture
does, through input poses, not direct reload calls. Ordinary driver protected-file
checks, snapshots, captures, native counters and rollback apply. Exit 0 requires
the renderer and integration checks; failed evidence is kept. Record presence by
itself is explicitly not full V4 acceptance.

All five semantic reducers (P, W, K, K assets/captures, T) are mandatory. Their normal record/provenance files are created from the actual generated client/server sources and native renderer return code; record presence cannot pass. T has its full 60-second features window, including preference restoration, and is moved to its documented clear-air arena. Mouse yaw uses T's original session-only save/restore. The script lasts 114 active seconds and keeps raw Source/native clocks.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
