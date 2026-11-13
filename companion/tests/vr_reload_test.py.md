# Reload offline suite

Run `python companion/tests/vr_reload_test.py -v`, or the existing tools gate bridge
`test_companion_vr_reload.py`. LuaJIT runs one isolated scenario per unittest.
Tests hold/restoration (all seven classes, five seconds of setter observation),
eject/conservation, insertion limits/refusals, shotgun/crossbow/RPG state,
shoulder and port transforms, clip arithmetic, A/B taps/holds, claims and counter
repaint/visibility/teardown. No native firing, prediction, graphics or compositor
is simulated; production PoC evidence must establish those. No game/files/settings
are written. Exit 0 passes, nonzero fails; missing LuaJIT skips explicitly.

Seven Python receipt cases require no game or image library: accept a complete
synthetic role receipt, reject an isolated managed-module failure despite renderer
progress, reject a requested-but-missing eye image, and reject a wrong ammo canvas
extent. Generated fixtures stay under this worktree's out/tmp and are removed.
The remaining cases accept a known moving device transform and reject an incorrect
transform or repainting while the measured numbers remain unchanged.

The suite includes render-only gaps between B release and the next user command, plus pending-button context cancellation. These regressions reproduce the post-Q native missed-tap witness without changing the framework.

An eighth Python case observes a foreign lock unchanged through the 250-ms wait, releases that controlled fixture owner, and verifies atomic K acquisition and exact-token cleanup.

The preview-command case independently reproduces consuming a B tap on a zero-number/zero-tick sample, and requires delivery to the later real command exactly once.

The first-grant case requires the off hand to block W immediately after server acknowledgement, before the next K frame creates its visual item.

The review suite adds state/timing/ownership/range/fault/cost regressions from vr_reload_review_cases.lua and an explicit trust-boundary documentation check. Legacy hold assertions are supplemented by an oracle capable of actual refill/switch mutations; this still cannot substitute for PoC proof.

NLVR_RELOAD_BASELINE optionally selects a saved three-module source snapshot for regression comparison. Default tests always exercise the worktree production source.

Deploy tests expose native relative m_flNextAttack, not Player:GetNextAttack; missing client access uses the server-ready ACK bit.

Field-quit tests cover no-console refusal without launching any force helper, and normal completion.

Two counterexamples enforce full-phase B counting: a valid late RPG command, and a late second command that a short window would hide.

Receipt checks enforce readiness+0.3 s delivery, including late RPG/stale-ACK and duplicate cases. Mutation tests remove heartbeat advancement, both prune paths or timer guards and require the corresponding case to fail.

A receipt counterexample excludes the reload's own subsequent attack lock from prerequisite readiness.

Q4 retains a regression for an unclassified pre-chapter attack row: it cannot crash analysis or falsely pass a reload criterion.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
