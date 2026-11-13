# 0161: Simulated VR sessions use a launcher-owned description and timeline

- Status: Implemented on v2n for review, 2026-11-11. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.
- Context: [V2/V3 plan, interface 8](../handover/VR-V2V3-plan.md) and
  [ADR 0150's Lua boundary](0150-vr-client-lua-boundary-and-native-quit.md).

## Decision

`nlvr.Start{simulate=true,timeline="NAME"}` is accepted only when the launcher set an absolute
`NLVR_TEST_ROOT`. Lua still supplies only a logical timeline name. The module reads the fixed
`simulated-index.json` under that root, with link refusal and bounded validation. The driver copies
the recorded V1 Index description there and records its source hash. There is no Lua device-path,
DLL-path, manifest-path or test-root override.

Simulation loads no OpenVR DLL, initialises no scene application and takes no shared VR lock.
The module paces scripted poses/actions at the recorded refresh with a timer and owns overlay
handles, placements, visibility, tint and sort order. The runtime receives NO_SUBMIT and a null
getGenericInterface; it owns rendered images, overlay copies and captures as usual. Info marks
simulation explicitly and reports no SDK readiness or compositor measurements. Window-source
support is an optional runtime export; an older runtime returns a clear unsupported result.

Timelines carry skeleton curls/splay and keyboard events in addition to the existing controls.
The native worker delivers timed events even if Lua frames pause; native quit and ordered cleanup
still apply. Live input, native quit acknowledgement and deferred IPD reads keep V1's behavior.

The PoC driver uses the same snapshot/restore and capture validation in simulation, with the PoC
lock alone. It checks rendered-frame progress and zero actual eye submissions, never substitutes
rendered frames for submitted pairs in live runs, and fails if OpenVR is observed in simulation.
Acceptance of compositor output and real tracking still requires the Index and both shared locks.

## Consequences

Feature tasks can exercise Lua without SteamVR or sleeping controllers. The simulation is an
explicit test environment, not a second player mode or a proxy for optical latency and VR comfort.
Until task R's runtime accepts the null interface, native fake-runtime tests prove this contract;
a clean real-runtime refusal is recorded as a refusal, not as successful rendering.
