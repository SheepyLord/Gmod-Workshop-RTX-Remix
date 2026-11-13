# Shared W/K/T fixture adapters

Private test support for the full V4 acceptance sequence. `input_data` converts
canonical palm trajectories to C's natural raw poses. The left-hand variant swaps
actions and reflects hand locations/head look while retaining the test's declared
world hand rotations (yaw/pitch/roll assertions remain unchanged). Calibration
positions are canonicalized before this layout transform; model-local rotations
remain their measured world orientation.

`configure` stores explicit recorded-component references and the exact input steps.
`prepare` adapts only the canonical observer suffix, never the native probe's eye
fields, inserts a Source-time functional input clock while retaining native time,
and aims GUI inputs from the SDK tip. Performance/temporal benchmarks stay separate.
Missing textual contracts fail rather than silently skipping transformations.

`stage` uses the shared driver's private plain-file add-on and ULib fixture. A late
client autorun declares test preferences before the probe baseline; the full snapshot
restores original PoC files after each game. This never changes Steam settings or
Remix user.conf. Exact generated sources/preferences/adapter hashes are kept in
`handed-fixture.json`. No SDK calls or game launch occur in this module itself.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
