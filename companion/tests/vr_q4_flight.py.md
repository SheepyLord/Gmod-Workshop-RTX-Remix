# Noclip rebase acceptance

`python companion/tests/vr_q4_flight.py --package <frozen gma> --evidence <fresh
out folder> --simulate` runs four real Source flight trials with the pistol aimed
45 degrees up/down, both dominant hands. Remove `--simulate` for the same scripted
recorded-component path on the real compositor while the controllers are off.

Uses standard shared locks, protected-file checks, plain private fixture staging,
ULib-compatible hook fixture, and rollback. No SteamVR settings are changed. The
controller references are explicit and raw live status remains available.

Writes normal driver captures and receipts plus `flight-checks.json`. Requires all
four actual horizontal flights (>20 units, <1 cm sideways/vertical), command cosine
>.99999 against the off-hand direction with the gun over 30 degrees pitched, and
hook Add/Remove checks during/after both Start/Exit cycles. Exit 0 only on success;
all failed evidence is retained.

flight-sim-01 had all four motion/command and two-cycle hook checks pass but failed the unchanged preference-restoration guard because the fixture changed the baseline vignette. The fixture-only correction is retained with a failing-before/passing-after test; all original renderer bounds remain.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
