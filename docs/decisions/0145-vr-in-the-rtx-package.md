# 0145: VR belongs to the RTX package and starts only when the player asks

- Status: Accepted 2026-11-10 for V1 on `vr`; reaching `main` requires the user's approval. The user approved V1
  on 2026-11-10 and it was merged that day.
- Context: the user's [VR design](../handover/VR-plan.md) and its table of decisions. The vanilla
  64-bit game must gain VR through the existing package, without a second game install or work in
  the loader. A flat start must not start SteamVR or prepare VR rendering.

## Decision

The runtime owns a VR output mode: the centre image, its projection, the two eye images, their
submission, the desktop mirror and copies of overlay textures. It accepts OpenVR interfaces from
the module; it never loads the SDK or initializes a session itself. The MIT module
`gmcl_nlvr_win64.dll` owns the SDK, the OpenVR scene session, tracking, input, haptics, events and
its overlays. The add-on owns the game's camera and wrist HUD. The companion's VR page owns
Start VR, Exit VR, status, warnings and the checks for a local game and another VR add-on.

Only the page is loaded automatically. Start VR loads the native module and starts its worker;
when the SDK is ready the page includes the add-on and installs its frame hooks. A status check
may explicitly load the module and probe installation facts, but does not load OpenVR or start a
session. Before Start there is no active VR worker, per-frame add-on hook, VR image allocation or
warp shader prewarm. The supported Vulkan extension names have to be enabled at device creation
([ADR 0149](0149-steamvr-vulkan-extensions-at-device-creation.md)). Exit ends the SDK session,
removes the hooks and retires runtime resources at the render boundary. GMod caches the loaded
module and its Source render target until game exit.

The page installs the producer at SDK readiness
(`companion/nativeloader/lua/autorun/client/nativeloader_vr.lua:159`), before the first traced
frame, so the renderer does not wait on a camera whose producer is still waiting for the renderer.

gVRMod and vrmod-x64 are references for behaviour only. None of their code, comments or data is
copied into this repository's MIT implementation. OpenVR is pinned to Valve's v2.15.6, commit
`0924064316de3effbcd1acf1e309182a2deb1c05`. Its header and BSD-3-Clause licence are vendored
unchanged in `third_party/openvr`; its 64-bit DLL is a SHA-256-checked download, dynamically loaded
only at Start, without an OpenVR import library.

The fifteenth package part, `vr`, carries the module and SDK DLL beside each other in
`garrysmod/lua/bin`. The packager reads the add-on from `vr/addon` and the action manifest and
bindings from `vr/input`, deploying the latter as real files in `garrysmod/addons/nlvr/input`.
SteamVR reads those files by their native path. The existing native allowlist and off switches
apply; no loader change is needed.

A pinned download may be recorded before its package part exists with `staged: true` in
`tools/ci/pins.json`. Default fetching skips it; an explicit `--only openvr` fetch verifies it for
the spike. An unknown requested name fails. Integration removes `staged` when the indexed part
exists. This was how task A supplied a reproducible SDK to C and D before Q assembled the part;
it does not let an unindexed binary enter a normal package build.

## Consequences

The package can be tested and reviewed on `vr` without changing the field install or publishing
it. Source ownership follows the four components, and their C interface is checked against the
runtime patch series. Loading the page is enough to explain an unavailable runtime or SteamVR
installation without opening a scene session. An already loaded module remains inert after Exit.
The separate probe is a development executable and does not ship.

## Alternatives considered

- Extending the loader would make a game feature part of startup and would not own the game's
  render callbacks. The existing package deployment already supplies every required file.
- Loading OpenVR on module load, or prewarming the warp during flat startup, would charge players
  who never start VR and could start SteamVR without their request.
- Shipping gVRMod would couple the implementation and licence to another complete VR add-on.
  The user chose a new implementation inside this package.
- Leaving the SDK download unpinned until integration would make the parallel tasks depend on
  a developer's local DLL. Staging keeps its version, licence and bytes reviewable from task A.
