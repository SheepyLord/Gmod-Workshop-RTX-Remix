# The About tab's secrets race: report (2026-11-15)

Found while investigating the field's crashes at a level change (exit 0xC0000409 at `engine.dll`+0x34b9dc, the
brief of 2026-11-15; that investigation continues on the branch `crash-34b9dc`). One of the field's seven crash dumps
of 2026-11-14/15 was not the level-change signature but a null read in the RTX runtime's About tab soon after a
start, and a PoC series built to reproduce the level-change crash hit the same race at a level change. Done by
Claude on the branch `secrets-race-0098`: runtime patch 0098 (fork branch `claude/secrets-race`); no loader
(`winmm.dll`) change, no ADR (a bug fix).

## Cause

`AssetReplacer::updateSecretReplacements` (`rtx_asset_replacer.cpp:222`) runs on DXVK's command thread whenever mods
finish loading, change on disk or reload. It cleared `m_secretReplacements`, refilled it from every loaded mod, and set
a plain `bool` when some mod declares secret replacements. `ImGuiAbout::Secrets::update` runs every frame, with the
RTX Remix menu open or closed, on the thread that presents (`ImGUI::render` in `D3D9SwapChainEx::PresentImage`): the
material system's render thread in queued mode, the main thread while a level loads. When the flag was set it walked
the same map by reference (`dxvk_imgui_about.cpp:233`). Nothing ordered the two, so the About tab could walk nodes
the command thread had just freed.

Both crashes came in starts that had just deployed a new build of an RTX map pack, so Remix loaded that mod cold and
finished while frames were being presented:

- **The field, 2026-11-15 00:06 local** (runtime 0094): a null read in `Secrets::update` three seconds after Remix
  loaded its mods, at start-up.
- **The PoC, 2026-11-15 12:33Z** (runtime 0096; the main checkout's `out/crash-34b9dc/lc-pack2`, the second start of
  a series with the field's subscribed content packs, its own local add-ons and the Country Estate pack's two builds
  alternating): at the level change, on the main thread (`Present` while the next map loaded), reading address -1.
  No PDB of the 0096 build was kept; the 0097 build's PDB names the code, which lies 0x80 lower from `LockImage` on
  (the functions match byte for byte at 96 to 100 %).

## Fix

Runtime patch `0098-The-About-tab-takes-the-secret-replacements-whole-no.patch` (commit `173bdc84` on 0097's
`678b28d1`):

- `rtx_secret_handoff.h` (new, self-contained): `SecretHandoff<Map>`, a map, a mutex and an atomic flag. `publish`
  replaces the map and sets the flag under the lock; `pending` reads the flag; `take` returns a copy of the map and
  clears the flag under the lock.
- `rtx_asset_replacer.h/.cpp`: `updateSecretReplacements` builds the new map in a local, checks the selected variants
  against it (as before) and publishes it; `hasNewSecretReplacementInfo` and `getSecretReplacementInfo` (now by
  value) go through the handoff. A load without secret replacements leaves the About tab's copy as it was, as before.
  `dxvk_imgui_about.cpp` is unchanged: its `const auto&` binds the returned copy.
- `tests/rtx/unit/test_secret_handoff.cpp` (22 checks, also built by the runtime's meson) covers the handoff,
  including a command thread publishing 3,000 maps while a present thread takes them, never a torn or older map.

Left as it was (upstream): `markVariantStatus` (a ticked secret's checkbox in the About tab) writes `m_variantInfos`
on the present thread while `getReplacementsForMesh` reads it on the command thread for every mesh.

## Verified

- **The gate** ([test_secret_handoff.py](../../tools/tests/test_secret_handoff.py.md)): the handoff's unit test
  compiled from the committed patch with MSVC (`/std:c++17 /W4 /WX`) and run, `PASS secret handoff: 22 checks`; the
  patch's wiring (the map built locally and published after the variants' check, the accessors through the handoff,
  the old member and flag gone, meson lists both files). `tools\test.ps1 -Config Release` (see below).
- **The build:** `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0098): `d3d9.dll` 478,662,144
  bytes, SHA-256 `7c7291b6852da7f77ca4fef2c8b3cb834f2491e0a29bbfd2968f3f22877e0122`.
- **The PoC** (the main checkout's `out/crash-34b9dc/lc-pack3`, a package built with 0098, the same conditions as the
  crash: the field's subscribed content packs and local add-ons, a new build of the Country Estate pack deployed at
  every start, gm_construct, 5 s, the estate map's item mounted, `map rp_countryestatev1`): six starts in a row, each
  deploying 1,781 to 13,509 files and changing level, none crashed and each quit normally. Without 0098 the second such
  start had crashed in `Secrets::update`. The race needs a load finishing while a frame is presented, so a clean series
  supports the fix without proving it; the unit test's threads prove the handoff.

## What is left

- Not checked in the field install; the field takes the Workshop item's update at its next start.
- The field's other crash at a level change (a freed functor in the material system's call list, run by
  `ForceSingleThreaded`) is a different fault, also in starts that had just deployed a pack; it is still being
  investigated on `crash-34b9dc`.
- Upstream's `markVariantStatus` race (above) is left as it was: only a ticked secret's checkbox reaches it.
