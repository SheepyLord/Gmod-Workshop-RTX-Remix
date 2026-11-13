# VR-V2-R: the runtime for V2

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it: its interface 9 is what you build, its rules are yours.
You know the runtime's VR mode from V1 (you wrote the second review's corrections: the nearest-surface warp, the
first-camera rule, the recoverable failures). Read the user's report at the top of the plan: it is the reason for
two of the five items.

Your branches: `vr2` in the fork's clone `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r17\out\runtime-src`
(create it from `vr` at `d29445c5`), and `v2r` in this repository, worktree
`H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2r`, for the exported patches (0072 onward, one at a time:
`git format-patch -1 --start-number N -o <absolute path>`), both copies of the header, `runtime/README.md` and your
documents. Build experiments with `runtime\build_runtime.ps1 -NoImport`. **No import into `packages\`**: task Q
imports the one runtime that ships, at the end.

## What to do, in this order

1. **The header first.** Add the declarations of interface 9 (`rtxvr_SetOverlayWindow` and its two flags) to the
   fork's `rtx_vr_api.h` and to `vr/native/include/rtxvr_api.h`, byte for byte the same, as additional exports; keep
   `RTXVR_API_VERSION` at 3 unless a structure must change (then say so at once in your report's first lines).
   Commit the repository's copy on `v2r` with the exported patch, so the gate's header comparison passes.
2. **The ghost lines.** Reproduce them in the PoC: a scene with thin near features (hair-like strands, rings, a
   chain-link fence, foliage, ropes: whatever stock content shows them) a metre or two from the head, in front of a
   far wall, with a scripted head that moves a little. Capture centre, depth and both eyes. Decide from the pictures
   where the lines come from: already in the centre image (temporal reconstruction, motion vectors) or made by the
   warp (thin surfaces in the half-resolution depth found at several steps of the search, or the colour/depth
   resolution mismatch at edges). Reduce them, measure the affected pixels before and after on the same frames, and
   keep ADR 0156's barrel widths (284 / 284 / 281 or better).
3. **Hands near the eyes.** The search starts at `kNearestEyeDepthMetres` = 0.5 m (`rtx_vr_math.h:43`). Bring the
   near limit to 0.2 m: the centre view must cover both eyes down to it and the warp must find surfaces from there.
   Prove it with a prop held by a scripted hand at 0.2, 0.3 and 0.5 m (whole in both eyes, the right size by the
   projections), and give the cost: centre pixels, warp time, total GPU time, at the Index's recommended size. If 0.2 m
   costs more than the plan allows, choose the nearest limit that fits and say why.
4. **Without a compositor** (interface 9): `RTXVR_START_NO_SUBMIT` with a null `getGenericInterface` renders,
   warps, mirrors, copies overlays and captures, and never calls OpenVR. Task N's simulated sessions depend on it:
   finish this early and say when it is on `v2r`.
5. **The window overlay source** (interface 9), with a test that shows an overlay's picture equal to the window's
   2D (the escape menu over black with `NO_MIRROR`).
6. **The desktop window's cost.** The same VR session with a 1280 x 720 and a 3840 x 2160 window (task N adds the
   driver's `--window WxH`; until it is on `vr2` use a local change you do not commit): frame rate, GPU time by pass,
   the compositor's figures. Find what scales with the window, remove or shrink what VR does not need, measure again.
7. **VR off unchanged**: flat controls, at least 5 + 5 alternating launches of the published and your runtime
   (a table like the one `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\claude_launch_table.py` prints:
   median frame time, start to map, the screenshots' mean difference), and the list of what the new runtime does
   differently at start-up with VR off.

## Files you may change

The fork's clone (your branch only), `runtime/**`, `vr/native/include/rtxvr_api.h`, decision records **0162** (the
near limit and the warp's thin features) and **0163** (the window overlay source and rendering without a
compositor) with their lines in `docs/decisions/README.md`, and your report. Nothing else in `vr/native`.

## Proof

The runtime's own unit tests for the warp's maths (extend V1's 249 assertions: near limit, thin features), the gate's
header comparison, and PoC sessions (the Index with both locks where SteamVR matters, simulated or `NO_SUBMIT` runs
otherwise) with saved pictures and timings. The field game may be running at 4K: note the GPU's use beside timings.

## Report

`docs/handover/VR-V2-R-report.md`: each item's result with numbers and pictures (paths), what the ghost lines were,
what you changed and what remains (what only V7's true stereo can fix), the window's cost before and after, the
runtime commits and patches, the tests, what is open, your text for the shared documents. `tools\test.ps1 -Config
Release` passing in your worktree.
