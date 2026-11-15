# GitHub issue 12: Radeon cards crashed at the main menu and in maps: report (2026-11-15)

[Issue 12](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/12), "Code: 0xC0000005, crashed for an
undetermined reason": on an AMD Radeon RX 9060 XT (16 GB, Windows 10, 16 GB of RAM, loader 0.16.0) the game crashed
at the main menu after a while, about ten seconds into the RTX Poolrooms map, and at once in a map without RTX
content, with only the RTX item enabled. The user asked for an investigation and a fix if one was clear. Done by
Claude on the branch `issue12-lockimage`: runtime patch 0097 (fork branch `claude/lockimage-resolve`); no loader
(`winmm.dll`) change, no ADR (a bug fix).

## Evidence

The issue's log archive (the loader's session folder `2026-11-15T070223.219Z-11240-crash`, kept in `out\issue12`):
the Remix log, which ends without an error, and Remix's minidump. Symbols: the patch 0094 build's PDB and DLL that the
level-change crash investigation kept in `out\crash-34b9dc\sym0094` (the reporter ran package
`0.0.0-dev.20261115025852+1145e794`, runtime `remix-main+81b4d393`); GMod's own DLLs of 2026-11-12 from the field
install to unwind the game's frames; cdb from the installed WinDbg. Facts and offsets are in
[RESEARCH.md](../RESEARCH.md) ("Radeon crash: every single-sample read-back resolved into itself").

- **Where**: an access violation reading `0x318` in AMD's Vulkan driver (`amdvlk64+0x3f798a`) on DXVK's `dxvk-cs`
  thread, inside `vkCmdResolveImage`, called from `DxvkContext::resolveImageHw` for the CS command that
  `D3D9DeviceEx::LockImage` pushes to resolve a multisampled image before reading it back.
- **What the game did**: the main thread waited in that `LockImage` for a managed texture whose CPU copy the runtime
  had released to save memory. The lock came from GMod's main menu: `lua/menu/background.lua` changes the background
  picture every 30 seconds and, from the third picture on, reuses a freed material with `IMaterial:SetDynamicImage`,
  whose `ITexture::Download` write-locks the texture. The crash came 83 seconds after the menu appeared.

## Cause

`LockImage` chose the image to read back with
`mappedImage = sampleCount != 1 ? pResource->GetResolveImage() : std::move(resourceImage)` and resolved
`if (resourceImage != nullptr)`, counting on the move to empty `resourceImage` for a single-sample image. MSVC never
moves there: `GetResolveImage()` returns a const reference, and the conditional binds to it and copies (the shipped
binary AddRefs and has dropped the null test; a small program shows the same under `/std:c++17`, `c++20` and
`c++latest`). So every read-back of a GPU-written single-sample image also asked the card to resolve the image into
itself with one sample, which Vulkan does not allow: NVIDIA's driver ignores it, AMD's crashes. Since R13 (loader
0.13.0, 2026-11-03) the `minimum` memory profile, below 15 GB of video memory or 28 GB of RAM, releases idle managed
textures' CPU copies and marks them written by the GPU, so every later lock of one takes this read-back: the menu's
slideshow, fonts and other textures in a map.

## Fix

Runtime patch 0097 chooses with an explicit branch: a multisampled image is read back through its resolve image, a
single-sample one directly, and `resourceImage` is moved out for the latter, so the resolve runs only for a
multisampled image, as DXVK meant. Nothing else in the read-back changes.

## Checked

- [test_runtime_lockimage_resolve.py](../../tools/tests/test_runtime_lockimage_resolve.py.md) compiles the lines the
  patch removes and adds with MSVC as the runtime builds them (`/std:c++latest`), against stand-ins for DXVK's types:
  the old lines resolve a single-sample image into itself, the new ones only a multisampled image, and every
  reference is kept and released.
- The built code (patch 0097, `d3d9.dll` 478,660,096 bytes, SHA-256 `c60ef71c...b253`; its PDB in
  `out\issue12\sym0097`): the single-sample branch moves the image pointer (no AddRef) and the resolve's push sits
  behind a real `resourceImage != nullptr` test; in the reporter's 0094 build the branch AddRefs and the push is
  unconditional.
- The PoC (RTX 5090, the branch's package `0.0.0-dev.20261115123138+bc26e174` with `remix.memory_profile` minimum,
  `out\qa-poc\issue12`): `01-minimum`, gm_construct for 150 s, released 587 texture copies and quit normally, but
  nothing locked a released texture again. `02-readback` called `ITexture:Download()` on 16 of the world's textures
  after their release: no read-back either, since a file texture's `Download` makes a new D3D9 texture. `03-menu`
  went back to the main menu after the map, the reporter's case: the slideshow's `SetDynamicImage` locked released
  background textures six times in 150 s (six read-backs of 8,388,608 bytes each), the pictures were drawn, and the
  game quit normally; the Remix log has no error beyond the shader-model lines every start has. This shows the
  changed read-back working; it cannot show the crash gone, which needs a Radeon card.

## What is left

- No Radeon card here: the fix is not checked on the reporter's hardware. The issue's reply asks the reporter to
  confirm after the update.
- The conditional is DXVK's own and is also in NVIDIA's dxvk-remix (this fork took its `main` of 2026-11-14 with patch
  0093). Upstream releases no texture copies, so it reaches this read-back far less often. Reporting it there is the
  user's call.
