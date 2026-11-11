# 0157: SteamVR's Vulkan requirements do not depend on the optional FSR library

- Status: Accepted 2026-11-10 for the second V1 review on `vr`.
- Context: the review found that `VK_KHR_get_memory_requirements2`, present in SteamVR's S1 list,
  was enabled only while `amd_fidelityfx_vk.dll` loaded. The tested package carried that library,
  so the original comparison did not exercise its absence.
- Amends: [ADR 0149](0149-steamvr-vulkan-extensions-at-device-creation.md). Its five missing names
  describe the measured S1 installation; they are not a complete independent startup guarantee.

## Decision

At Vulkan creation, request these supported names independently of optional upscalers:

| Scope | Names |
|---|---|
| Instance | `VK_KHR_external_fence_capabilities`, `VK_NV_external_memory_capabilities` |
| Device | `VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation`, `VK_KHR_win32_keyed_mutex`, `VK_KHR_get_memory_requirements2` |

The VR-specific creation list contains six names; the other required names were already requested
by the renderer. S1 found six instance and seven device requirements in total. The last device name is added beside the other
VR prerequisites (`src/dxvk/dxvk_adapter.cpp:496` in the fork at `8d348e14`), even when FSR is
absent. On the original tested installation it was already enabled through FSR; the five-name
difference measured in S1 remains correct for that run. Start still checks SteamVR's complete
live lists against the actual enabled names. Vulkan 1.2 already enabled the timeline feature;
no new feature boolean is needed.

With VR off, the runtime constructs its device-owned CPU state and container bookkeeping, keeps
copies of the enabled-name sets, exports the eight `rtxvr` entry points, and executes dormant
predicates and camera-FOV bookkeeping in the existing pipeline. It does not load OpenVR or the
VR module, initialize a scene, start a VR worker, allocate VR GPU images/queries, apply the VR
preset or prewarm the warp. The diagnostic tap override is read only at VR initialization.
These facts describe work, not a mathematical zero-cost claim; alternating flat controls measure
the combined change, including startup and frame-time variation.

## Consequences

A missing optional upscaler no longer causes an otherwise supported VR session to fail for a
Vulkan requirement. Unsupported live requirements still produce an actionable Start error. The
new flat comparison must identify its final DLL and retain all three alternating pairs, loaded
modules and screenshots. Earlier flat timings belong to the earlier runtime, not this correction.

## Alternatives considered

- Depending on FSR to request the name makes VR availability depend on an unrelated DLL loading.
- Treating core promotion as proof that a literal extension name was enabled would not satisfy
  SteamVR's reported requirement; the enabled-name comparison must remain.
- Starting OpenVR at device creation would violate explicit Start VR and is unnecessary for the
  pinned, measured requirements.
