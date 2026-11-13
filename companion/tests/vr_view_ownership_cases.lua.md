# vr_view_ownership_cases.lua

Offline client-core view takeover cases loaded by vr_framework_cases.lua. Emulates ULib's independent
priority registry and compatible GetTable copy, tests competing early/late views and restoration,
unknown detached registries and recursive camera submission. No SDK/game/files. Python test_vr.py
launches the standard harness; assertions exit nonzero, PASS is printed by that harness.

The ULib stand-in now removes before adding, creates BackwardsHooks only alongside Hooks, indexes BackwardsHooks unguarded in Remove, and ignores monitor-priority returns. Regressions cover Start/Exit/second Start and Add/Remove after Exit under stock/ULib; removed private dispatch; detached ULib-shaped dispatch; gamemode leakage; and deferred registrations/monitor behavior.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
