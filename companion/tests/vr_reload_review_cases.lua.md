# Review regression cases

Loaded by vr_reload_harness.lua with K-owned fixtures. Cases exercise holstered
auto refill through a small explicit engine oracle, external fills, P's prop and
climb claims, server ACK/lease fallback, packet ranges, preserved per-gun state,
real-time rate/heartbeat, switches/removal, deploy waits, counter isolation and
steady-state call/allocation counts. A zero-transfer mutant tests the arithmetic
oracle itself. The engine model is a test double, not native proof; the separate
holster PoC verifies actual HL2 behavior. No standalone usage or file side effects.

The idle-cost case prints named-field reads and packets for100 unchanged commands; thresholds and stable debug identity are asserted. These are synthetic call counts, not a native CPU throughput benchmark.

Second verification adds2-second eject/carry hitches with a W input stand-in, glove lock/pull, actual table pruning through the production closure, holster return/insert/fire, saved-map holds, numeric-buffer identity and a serial retry with coalesced replies rather than injected ACKs.
