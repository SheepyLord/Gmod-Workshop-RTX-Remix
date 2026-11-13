# Reload production session wrapper

Uses tools/vr_session.py unchanged, its real lock/snapshot/install/launcher/capture/
rollback path. `py -3 companion/tests/vr_reload_poc.py --package <gma> --evidence
out/vr/v4k/calibrate --simulate --calibrate --seconds 15` calibrates seven ports
through W's actual models. Then `--calibration <calibrate/reload.json> --seconds
150 --simulate` runs per-class 20-second fire/eject/wait/shoulder/insert/fire timelines.
`--classes` selects comma-separated classes. `--button` tests flat-style B reload
with physical reload off; it also accepts nlvr_k_swep, gmod_tool and weapon_physgun.
Omit --simulate only for final Index overlay/compositor acceptance (both locks).
`--empty` sets empty clips/reserves for the no-pickup / held-empty path.
`--counter-motion` adds a 30-degree yaw and 0.18/0.07/0.10 m hand translation,
with captures after moving/returning. Allow fifteen seconds after the selected
weapon phases (35 s for one feature weapon), or 15 s for a calibration-only run.

Sessions must stay below 180 seconds. Records save to reload.json, stock muzzle
attachments and actual model port tracking poses included. The wrapper lets the
shared final Stop check settle for one second without weakening selector checks.
Field game console quit uses only the user-authorised main-checkout helper when
needed and records it. Never quits/reconfigures SteamVR. No upload. Exit codes
are the shared driver's; standalone analysis must also pass for feature acceptance.
The wrapper omits the shared wrist-HUD test's deliberate mid-run clip edit/restore:
only native fire and production reload code may change this fixture's ammo.
`reload-receipt.json` rejects isolated managed-module errors and missing requested
captures, identifies the ammo source by its exact native handle, requires nonblank
387 x 129 pixels and actual visible/bound/error-free native counter state, and
verifies the fixture's restored option strings. Feature arithmetic additionally
requires vr_reload_analyse.py; renderer progress alone is insufficient.

Physical capture poses bring the taken item forward at 8.6 s, with the head looking at the off hand; the well approach looks at the calibrated loading port. The shoulder squeeze still occurs with level, zero-yaw head tracking. These scripted camera poses make the held/well evidence visible rather than photographing ammunition behind the head. Raw poses and angles remain in timeline.json.

The K-labelled shared locks retain atomic create and inherited exact-token release, with a 250-ms poll and two-hour wait. This avoids missing short vacancies among the concurrent review queues; it never evicts or edits a foreign lock.

`--holster --classes weapon_smg1,weapon_pistol --seconds 35` selects the private before/after regression: fire/eject, Hands for 4.5 s, return and attempt reload/fire. Use the existing calibration, simulation and a fresh evidence folder.

The physical RPG phase first takes/inserts a rocket through production code before its initial shot; a new entity is never assumed chambered. This changes the fixture inventory preparation, not its later hold/insert/fire requirements.

`--button --deploy-lock` injects a native one-second player attack lock at phase+2.5 s, before B at3 s. The analyzer requires the later single reload command to wait for actual native readiness. This private fixture does not ship or change convars.

Field-game preflight now uses only the normal console-quit API, records sent/remaining PIDs and forced=false, and fails safely without a reachable console. It never calls the external scratch helper or taskkill. This follows an observed forced fallback in that external helper; the actual event is retained in the review report.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
