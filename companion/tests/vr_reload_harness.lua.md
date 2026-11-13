# Reload LuaJIT fixtures

Used by vr_reload_test.py with repository root and scenario arguments. Reuses S's
independent vector/weapon/inventory stand-ins, F's real module registry/input,
and loads K's actual client/server/shared reload modules. K's local W stand-in
exposes Active and a stock-attachment muzzle only. It is never packaged.

Engine save values, clock/ticks, commands, poses, network reads, overlay paint and
stock model creation are explicit observable fixtures. The review cases include a small explicit reload/switch/holster oracle. It can
refill or switch when the production hold/timer is absent, but is not a native
engine simulator: PoC sessions must establish actual engine behavior. The 30 transform trials compare both model
and authoritative muzzle paths. Arithmetic checks all reserves 0..60 and legal
clip sizes. One process per case prevents singleton state leakage. Prints PASS
or raises assertion (nonzero LuaJIT exit). No persistent side effects.

The client fixture can advance render/input frames without a user command. The B regression releases between commands, verifies one later reload, and checks cancellation on physical-mode, hand and weapon changes.

The B preview regression inserts three zero-number/zero-tick command samples between release and the real command. They must not consume the one networked reload.

The first-grant resolver case observes occupied-hand/curl state before any local ammo model has been created, and verifies cleanup of that temporary marker. This exercises K/W ordering rather than waiting an extra frame.

First-grant cleanup is also checked after the marker predates creation of the first visual, preventing a stale occupied hand when the entity pointer changes.

Review cases use independently advanced wall/game clocks, a real pickup cap (GiveAmmo versus SetAmmo), typed packet range assertions, no invented pistol soonest field, both secondary/primary cooldowns, P occupancy/climb, inventory lifecycle, deploy waits, ACK loss and counter faults. Exact arithmetic and a zero-transfer mutant replace bounds-only evidence.

The test runner may pass an optional third harness argument via NLVR_RELOAD_BASELINE to load only the three reload modules from an old source snapshot under out. Current core/fixtures remain shared. This compares the same regressions to the reviewed source without changing installed game files.

RPG fixtures use native max clip -1 and cold readiness; initial live RPG shots are armed by a real shoulder insertion in the feature driver.

Player attack readiness uses realm-specific m_flNextAttack save values (client absolute, server relative), not an invented convenience method. A missing client field exercises the acknowledged server-ready fallback.

Client fixtures expose absolute attack time and server fixtures expose relative attack time, matching the native realm-specific observations. A past positive client deadline must permit B.

Server Net.Send now uses the real protocol packet encoder, identical-signature suppression, per-player/type pending replacement and one delivered packet per engine tick, with explicit flush/delivery hooks for coupled tests. Client sends remain immediate as in cl_net. Slow-frame/tick control is explicit.

Q4 integration: uses the shared `companion/tests/vr_hook_fixture.lua` contract for hook-library compatibility; retained regression cases run without SteamVR.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
