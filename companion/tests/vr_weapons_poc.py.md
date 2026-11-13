# W's PoC feature driver

Use installed Python with Pillow, e.g. `py -3 companion/tests/vr_weapons_poc.py --package
out/dist/<local>.gma --evidence out/vr/v4w/<new-run> --seconds 172 --simulate`.
`--weapons-phases` takes comma-separated phase names for shorter feature/calibration runs.
`--camera-debug` adds two declared probe-owned camera copies (original/debug-white)
and material/bone diagnostics; such a run is diagnostic, not ordinary image acceptance.
Omit simulate only for final Index acceptance. The driver owns the shared PoC lock and,
for the Index, both locks, waiting up to two hours. SteamVR stays running/unmodified.

Uses tools/vr_session.py's package install/snapshot/normal quit/rollback, native timeline,
image capture/counters, settings and protected/depot-file verification. Test-only Lua is
injected through ordinary admin console commands; never packaged. If a field game is
running, uses the user's explicitly authorised main-checkout normal-console quit helper,
recording its PIDs and result. No field files are written. No publishing or native imports.
Adds W JSON receipts and keeps all renderer acceptance checks. One-second flat settling
matches S's documented selector fix. Inventory fixture avoids the unrelated HUD ammo edit.
Exit 0 only when the production driver and vr_weapons_analyse's applicable feature
checks pass. It decodes chunked full console records without accepting truncation.
Analysis writes a separate weapons-checks.json, leaving original records unchanged.

Review phases bolt-eye and bullet-passes exercise a real eye-line obstacle, native
penetration/missing-geometry bullets and a short-circuiting second hook. Foregrip phases
now hold an automatic burst across grip/release. The selected review run uses 22 phases
and 98 seconds; a full 44-phase run may use 186 seconds. Never reuse evidence directories.
The second review adds melee-walk: a real predicted/host Source movement command at
200 units/s during the swing, with a wide stationary target. Its one selected session
uses pistol-5, fore-smg, bolt-eye, melee-walk and bullet-passes (30 active seconds).

Third-review melee-lunge scripts head/left-hand physical travel of 0.5 m and a 1 m main
hand stroke. The selected one-session validation uses pistol-5, melee-fast, melee-walk,
melee-lunge with 30 active seconds and a new evidence folder/package version.
The post-phase neutral hand settle retains physical HMD travel, so later generic HUD
witnesses do not put a wrist behind the head. Its regression is offline-verified; the
review's single session exposed the old tail and is retained as a capture rejection.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
