# 0149: Enable SteamVR's five missing Vulkan extension names at device creation

- Status: Accepted 2026-11-10 for late Start VR.
- Amended by: [ADR 0157](0157-steamvr-requirements-do-not-depend-on-fsr.md). The current startup
  guarantee is two instance and four device names, six in total. The five-name difference below
  was measured with FSR present, which already enabled the sixth name.
- Context: spike S1 ([A](../handover/VR-V1-A-report.md)) found that the RTX 5090 offers
  SteamVR's required extensions, but the published runtime had not enabled all their names.
  OpenVR starts after the game has created its Vulkan device; the names cannot be added then.

## Decision

At ordinary Vulkan instance creation, add `VK_KHR_external_fence_capabilities` and
`VK_NV_external_memory_capabilities` if supported. At device creation, add
`VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation` and `VK_KHR_win32_keyed_mutex` if
supported. The runtime already enables the timeline semaphore feature through Vulkan 1.2;
this adds no new feature boolean. These five literal names are the Vulkan setup change in a
flat session. No OpenVR DLL, session, worker, VR image, query pool or warp prewarm is needed
(`src/dxvk/dxvk_instance.cpp:762` and `src/dxvk/dxvk_adapter.cpp:496` in the fork at `9d22eef6`).

At Start VR, query SteamVR's complete instance and device lists and compare them against the
names actually enabled, including names added by providers. Fail with the missing name if
anything is absent; the machine having offered it is not enough. S1 requested six instance
and seven device names and found two and three respectively missing from the enabled lists.
The complete lists and source locations are in [RESEARCH](../RESEARCH.md).

## Consequences

Late activation works without recreating the game's device. An unsupported requirement is an
actionable Start failure, not a broken texture submission. Flat mode still has small dormant
runtime checks; absence of VR allocations does not prove zero instructions or zero startup cost.

Q compared three alternating published/VR-runtime pairs on gm_construct, clear noon,
1280 x 720 pixels, RTX 5090, with 30 s timed windows and no VR start. Mean median frame time
was 7.7627 ms for the published runtime and 7.7272 ms for the VR runtime, a change of -0.0355 ms
(-0.457%). Mean 99th-percentile frame time was 10.5634 and 10.5605 ms. Mean map-ready time was
24.100 and 24.567 s; the three paired changes were +1.3, -0.2 and +0.3 s. Neither OpenVR nor
the VR module loaded in those controls. This mixed startup result does not establish an exact
zero cost. It is the measured cost of the combined dormant VR changes, not an isolated timing
of each extension name.

## Alternatives considered

- Loading OpenVR at game startup just to discover its requirements would violate explicit
  activation. The pinned SDK and S1 provide the supported names; Start still checks the live list.
- Recreating the Vulkan device at Start would disturb every existing runtime image and resource.
- Treating a Vulkan core promotion as proof that its literal extension name was enabled would
  not satisfy SteamVR's reported contract on this device.
