# test_runtime_lockimage_resolve.py

Checks runtime patch `0097-*.patch` (GitHub issue 12: Radeon cards crashed with 0xC0000005 at the main menu and in
maps). `D3D9DeviceEx::LockImage` reads back an image the GPU wrote and resolves it first if it is multisampled. It chose
the image with `sampleCount != 1 ? pResource->GetResolveImage() : std::move(resourceImage)` and resolved while
`resourceImage` was still set. MSVC never moves there: the conditional binds the resolve image's const reference. So
every read-back of a single-sample image also resolved the image into itself, `vkCmdResolveImage` with one sample and
the same image on both sides, which AMD's driver crashes on. The patch chooses with an explicit branch.

```powershell
python -m unittest tools.tests.test_runtime_lockimage_resolve
```

| Test | Checks |
|---|---|
| the patch changes only LockImage's choice | one file (`src/d3d9/d3d9_device.cpp`); the three removed lines are the conditional; the added lines are marked `NV-DXVK` and their code is the explicit branch that moves `resourceImage` into `mappedImage` for a single-sample image; the resolve's own check (`if (resourceImage != nullptr)`, outside the hunk) is left as it is |
| only a multisampled image is resolved | builds the patch's removed lines and its added lines into two functions with stand-ins for DXVK's `Rc` (a copy takes a reference, a move takes the pointer), `DxvkImage` and `D3D9CommonTexture`, compiles them with MSVC as the runtime builds them (`/std:c++latest /W4 /WX`) and runs them: `PASS lockimage resolve: N checks` (the old lines resolve a single-sample image into itself, the bug under this compiler; the new lines read a single-sample image back from itself without a resolve, resolve a multisampled image into its resolve image, and keep and release every reference). Skipped without the VS 2022 Build Tools |

Writes only a scratch folder under `out\tmp`, removed afterwards. Exit 0 when every test passes.
