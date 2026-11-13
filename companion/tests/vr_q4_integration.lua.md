# Integration lifecycle observer and physical reload input

Private Lua used only by `vr_q4_integration.py`. Scopes existing observers into
four Source-time chapters, inventories every production module at each transition,
and exercises ULib hook Add/Remove while active and after both Exits.

During physical pistol insertion it transforms the actual model-local well back
to tracking space and guides the scripted off hand through it. No ammo, clip or
reload result is assigned. It adds only private test hooks and an input-clearing
pre-mover; standard snapshot/rollback removes the add-on. Console evidence is under
`Q4-integration-*`. No filesystem/SteamVR-setting changes or process exit codes.

The guided-input frame wrapper captures its predecessor and restores only while it owns the native slot. A later writer can safely restore its cached predecessor after Exit; a reverted-predecessor mutation fails the regression.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
