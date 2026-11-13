# Armed noclip flight observer

Private Lua appended by `vr_q4_flight.py`. Four trials fly horizontally with the
off hand while the pistol aims +/-45 degrees, under both dominant-hand settings.
It observes final commands after the production core's rebase and records actual
player travel, rather than assigning results. It captures each trial and exercises
the shared hook fixture's Add/Remove during both Starts and after both Exits.

Changes four VR test preferences temporarily, restored after Exit; registers private
test hooks and a movement-clearing pre-mover. The server selects a stock pistol and
noclip in the isolated PoC only. Ordinary driver locks and rollback apply. Outputs
`Q4-flight-*` and `Q4-hook-lifecycle` receipts; Lua assertions fail the session.

The fixture records original preferences before the flat baseline and changes them only after VR starts. It restores them after each Exit. A retained regression rejects any preference write while the initial fixture is loading.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
