# test_dlfg_hudless.py

Checks runtime patch `0094-DLSS-frame-generation-keeps-the-UI-in-place-a-HUD-le.patch`
([ADR 0223](../../docs/decisions/0223-frame-generation-gets-the-frame-before-its-ui.md)): DLSS Frame Generation is
given the frame before its UI (NGX's HUD-less colour), so the crosshair and the rest of the HUD stay in place in
the generated frames instead of moving with the scene.

```powershell
python -m unittest tools.tests.test_dlfg_hudless
```

| Test | Checks |
|---|---|
| the handoff's unit test from the patch | writes `rtx_dlfg_hudless.h` and `tests/rtx/unit/test_dlfg_hudless.cpp` as the committed patch creates them into `out\tmp`, compiles them with MSVC (`/std:c++17 /W4 /WX`, as the runtime's own unit test builds) and runs them: `PASS dlfg hudless: N checks` (no frame without a copy; a filled frame is passed, a later frame in its slot replaces it; a new copy forgets the old copy's frames and refuses a mark made for it; dropping another swapchain's copy changes nothing; the render and presenter threads). Skipped without the VS 2022 Build Tools |
| the handoff forgets a replaced copy | a mark counts only for the current copy's generation; `setSource` and `dropSource` advance it and forget every frame |
| injection fills the copy after the game target | with frame generation on and a copy of the target's size, format and one sample, `injectRTX` blits the final output into it with the game target's own blit, after that blit, and marks the frame |
| the present blits the copy beside the back buffer | the swapchain keeps the copy from the back buffer's create info and sampled view, blits it into the presenter's HUD-less image of the same slot with the back buffer's `presentImage` call (same rects and gamma), and drops it when it goes |
| frame generation gets it only for a filled frame | the present thread takes the slot's HUD-less image only for a marked frame, passes it to every interpolated frame, moves it from the present layout to shader read and back like the back buffer (a barrier set of five), and `NGXDLFGContext::evaluate` sets `pHudless`; meson lists the header and the unit test |

Writes only a scratch folder under `out\tmp`, removed afterwards. Exit 0 when every test passes.
