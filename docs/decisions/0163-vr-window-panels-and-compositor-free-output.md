# 0163: VR can copy the window's 2D and render without a compositor

- Status: Implemented on `v2r` for VR V2, 2026-11-11; awaiting integration review. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.
- Context: V2 needs a flat-screen panel for the game's own menus, and repeatable tests without
  a headset. Neither requires a second OpenVR session or a different rendering pipeline.
- Extends: [ADR 0148](0148-vr-ui-through-exact-sized-overlay-targets.md). The module still owns OpenVR and
  overlay handles, and the runtime still owns copying their pictures.

## Decision

Add `rtxvr_SetOverlayWindow(handle, flags)` and two flag constants to both identical headers.
API version 3 and every structure remain unchanged. `RTXVR_WINDOW_SHOW` copies the game window
after its 2D has been drawn. Preserve its aspect ratio and cap the copy at 1920 pixels wide.
`RTXVR_WINDOW_NO_MIRROR` also clears the window to opaque black before the game's 2D, including
frames with no traced world. Flags zero end the binding. A render-target source and window source
are mutually exclusive for a handle. Reject unknown flags and suppression without a visible source.

Keep the new source on the existing request/render boundary. API calls change requests under the
request mutex; the render thread allocates, copies and retires images. Before replacing an image
given to SteamVR, clear its texture binding and outwait its GPU use. The window preparation enters
the command queue at BeginScene (`d3d9_device.cpp:1574` in runtime commit `d8df7e54`); the final copy
is at present, after the game's menus. Captures use the same overlay image that would be submitted.

With `RTXVR_START_NO_SUBMIT`, allow a null `getGenericInterface`. Run the ordinary centre output,
eye warp, mirror, overlay copies and captures, but make no OpenVR call, including pacing, timings,
texture submission and shutdown. Clear borrowed interfaces between generations. A completed copy
increments the overlay-update count without inventing a compositor submission. Submitted-frame,
present, dropped and reprojected counters remain zero; simulated tests judge rendered frames instead.

## Consequences

The simulated window proof on gm_construct renders 2619 matched frames with zero Submit errors
or unmatched poses, no OpenVR DLL, normal quit and restored settings. Its 1280 x 720 pixel overlay
and window capture are equal as decoded RGB, with a mean absolute difference of 0.0/255. They show
the escape menu and console over black. The same source is bounded to 1920 x 1080 pixels for a
3840 x 2160 pixel window; a CPU regression checks that extent. The report retains physical and
4K tests separately from this proof. The final 30 s Index run uses the engine's default queue
mode and accepts 1346 matched pairs with zero Submit errors or unmatched poses. SteamVR reports
the visible panel at 1920 x 1080 pixels with no texture error. Its mean difference from the
downsampled 3840 x 2160 pixel window is 0.048/255 per RGB channel, maximum 0.5/255. The earlier
simulated proof uses queued rendering; both restore their settings and PoC snapshot.

With VR off, the new paths add dormant CPU state and an atomic predicate in BeginScene. They do
not load OpenVR, allocate a coverage/window image, or enqueue a clear. V2 adds no Vulkan extension
requirement beyond [ADR 0157](0157-steamvr-requirements-do-not-depend-on-fsr.md). Alternating flat
controls check the practical cost. No saved window size or SteamVR setting is changed.

## Alternatives considered

- Reimplementing GMod's menus in a render target would omit engine and other add-ons' UI.
- Capturing before the game's 2D would copy only the mirror and miss the menu.
- Suppressing the mirror only on traced frames would leave stale 3D under a paused menu.
- A fake compositor would add SDK dependencies to tests and would not prove that the no-compositor
  path can keep working when SteamVR is absent.
