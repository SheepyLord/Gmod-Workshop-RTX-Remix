# vr_v2_scene.py

This runs task R's controlled geometry through the current production tools/vr_session.py. It
imports that driver and supplies only the generated Lua fixture and optional depth-sweep timeline.
It does not keep a private driver snapshot. All production preflight checks, locks, snapshots,
screenshots, normal quit, restoration and cleanup remain in the driver.
Its ordinary lock class uses the R task label and a one-hour acquisition timeout, as H's fixture
does; polling and ownership checks remain the production implementation. This changes no game limit.

Use the same Python interpreter and unattended dependencies as the production driver:

```powershell
python runtime/vr_v2_scene.py --case ghost --package out/dist/test.gma --evidence out/vr/r-ghost --simulate --seconds 60
python runtime/vr_v2_scene.py --case sweep --package out/dist/test.gma --evidence out/vr/r-depths --seconds 85
```

Cases are barrel, ghost, near and sweep. Other arguments go to the production driver.
--steady-neutral adds a ghost capture at timeline time 8 seconds,
after temporal warmup and before the head turns; the original early neutral capture is retained.
This makes both early and steady image results available rather than replacing a failed receipt.
Sweep
replaces this run's generated timeline with fixed head poses and held-prop front depths of
0.15, 0.2, 0.3, 0.4 and 0.6 m, each held for 15 seconds. It captures each after ten seconds and
logs r-range records linking timeline time to camera sequence for per-distance GPU profiles.
Use 85 seconds for the sweep. A single near case accepts --distance, with its hand pose supplied
by --timeline. The centre projection always remains the runtime's chosen fixed extent.

For these isolated geometry tests only, the fixture masks the hands module's world-draw hook;
the module keeps its poses, input and lifecycle. This prevents an actual hand from occluding the
red measurement prop or determining the supposedly far scene's minimum depth. The saved draw
hook and the test hooks are cleaned up before the probe finishes. Static measurement entities
remain until the owned process quits, so their removal does not race queued Source draws.
Task H's unmodified
vr_hands_poc.py supplies the separate full-hands proof without this mask.

Inputs are the local package and optional timeline, under the usual production-driver rules.
Outputs and side effects are the same as that driver, plus generated fixture source, captures
and r-range console records. The script writes only this run's files below out. It starts no
field game, changes no Steam setting, and imports no package input. Simulated runs use only the
PoC lock; Index runs also use the VR lock and leave SteamVR running. Exit codes are the driver's
(0 accepted and restored, 1 failed, 2 argument/dependency refusal).
