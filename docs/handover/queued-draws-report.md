# The RTX fixes' crash on the queued render thread: report (2026-11-12)

The VR work (milestone V4, branch `vr2/v2q`) had its combined acceptance runs end at instruction pointer 0, and its
Claude session traced that crash, and the earlier ones, to the RTX fixes module, not to VR code. This task fixed the
module. Done by Claude on the branch `claude/admiring-mayer-33a48a`; package only (the fixes part's
`gmcl_RTXFixesBinary_win64.dll` and its GPL source), no loader (`winmm.dll`) change, no runtime change. Merged into
`main` on the user's approval and published to Workshop item 3829070317 (see the end).
[ADR 0192](../decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md).

## Root cause (the triage, checked again here)

1. **The chain.** Four WER dumps (the main checkout's `out\vr\v2\crash`, 2026-11-11 07:40 to 2026-11-12 08:50) all
   have, on a tier0 worker thread (the material system's queued render thread): the fixes' `R_StudioRenderFinal` hook
   (`HardwareSkinningHooks.cpp:3764`), studiorender, the `R_StudioSetupSkinAndLighting` hook, the return address
   `gmcl_RTXFixesBinary_win64.dll+0x41605b` (`prop_fixes.cpp:357`, its call of `GetBoneCountForRenderable`) and, in the
   one that faulted inside the called function, `+0x415442` (`prop_fixes.cpp:265`, the call of the renderable's vtable
   slot 9, `GetModel`). Lines from the crashed build's PDB through dbghelp; the packaged module (SHA-256 `477c2266...`)
   is that build.
2. **The renderable was freed.** The hook spilled `pClientRenderable` into its caller's shadow space next to that return
   address, so all four dumps still hold it. In each, the entity's first two words (the renderable's "vtable") are heap
   links to another free chunk of the same size, whose stale data at slot 9 is an address in code: `tier0.dll+0x12a5a`
   (twice), `tier0.dll+0xad9d` and `client.dll+0x5744c`, return addresses inside functions. `IsLikelyExecutablePtr` accepts them; the call lands in the
   middle of a function, which either faults (`client.dll+0x5744c`, reading -1) or leaves through a corrupt stack to
   address 0, where no handler can run.
3. **Why a freed entity is drawn.** With queued rendering studiorender queues each model's whole draw for the render
   thread with a copy of its `DrawModelInfo_t`; the renderable in it is only a pointer. The main thread deletes a client
   entity at once when a prop breaks, a gib fades or a script removes it, possibly while the last frame's draw of it is
   still waiting on the render thread. The engine only passes the pointer on; the fixes were the code that called into
   it. Studiorender's own state for the draw names the model being drawn: `CStudioRender+0x108` (`m_pStudioHdr`) held
   the gib's header at the crash.

## The fix

The fixes' tenth native patch, [queued-draws](../../packages/fixes/licenses/oversized-skinning/queued-draws/README.md)
(GPL-2.0, with its complete files), also commit `e6bc9e4` on the branch `claude/queued-render-fix` of the local fork
clone `E:\Modding_Backup\garrys-mod-rtx-remixed` (after `aaf0174`, the nine earlier patches applied to the pinned base
`f28bd5a`; not pushed to GitHub):

- **`prop_fixes.cpp`:** the bone count comes from `StudioDrawPolicy::BoneCount(this, renderable)`, which reads
  `CStudioRender::m_pStudioHdr` and its `numbones` after checking the `IDST` id, inside `__try`; the renderable is only
  compared with null (no renderable keeps -1, as the lookup gave it). The rule is unchanged and is one function,
  `ChooseLighting`: `r_forcehwlight` or at most one bone gives `LIGHTING_HARDWARE`; a skinned model or an unknown
  count gets it with `r_forcehwskin` and keeps the engine's choice otherwise. The renderable lookup is gone.
- **`HardwareSkinningHooks.cpp`:** `ResolveModelToWorld` reads the renderable's coordinate frame only for
  `r_hwskin_transform_chain` 1 and 2, the only modes that use the matrix; in the default 0 it never reads it. No other
  hook reads a renderable (the rest use `CStudioRender`'s fields; `model_draw_hook.cpp` runs on the main thread).
- **`studio_draw_policy.h`:** the offsets, the read and the rule, with no SDK, and its regression
  `tests/studio_draw_policy_test.cpp`.
- **The package:** `tools/ci/pins.json` (the patch, the patched tree `source` `4843764b...`), the module rebuilt with
  `tools/ci/build_modules.ps1 -Only fixes` (5,518,848 bytes, SHA-256
  `a2f091abdcf8528469b52fdd853abfcb8e1026f5301da26137ad7398805743ab`) and imported with `tools/inputs.py`.

## Verified

- **Offline, in the gate** ([`test_queued_draws.py`](../../tools/tests/test_queued_draws.py.md)): the folder's files are
  the patch applied; the shipped hook passes the renderable only to the trampoline, a debug print and `BoneCount`, which
  compares it with null; `ResolveModelToWorld` checks the mode before its read; `studio_draw_policy_test.cpp` compiled
  with `/W4 /WX` and run: bone counts from a header behind a stand-in `CStudioRender`, every unknown case, a deleted
  entity whose slot 9 points at code (never called), a renderable in a guard page (never read), the rule against the
  old one over a grid. A copy of the header that calls the renderable's slot 9, as the old lookup did, fails it.
- **The built module:** the new `R_StudioSetupSkinAndLighting_detour` (dumpbin with its PDB) calls only the trampoline,
  `ConVar::GetBool`, `StudioDrawPolicy::BoneCount` and `ChooseLighting`; `BoneCount` compares the renderable with zero
  and loads only `[this+108h]`, `[header]` and `[header+9Ch]`. The old module's `GetBoneCountForRenderable` called
  `[rbp+70h]` (the slot-9 function).
- **The package:** built from this branch with `tools/build_package.py`, it differs from the published package
  (`0.0.0-dev.20261112034453+d568f6e1`, the item's current content) only in `gmcl_rtxfixesbinary_win64.dll`, the
  patch folder's GPL source under `remixbinary/src/hw/queued-draws` (the add-on carries `licenses/oversized-skinning`)
  and `native/manifest.json`.
- **PoC, prop lighting unchanged** (`out\queued-draws\run1`, gm_construct at the VR fixture's camera, 1600x900): a still
  scene of one-bone props (oil drum, crate, watermelon, PHX cube, chair), a door and a multi-bone citizen ragdoll, frozen,
  three captures each with the published package and with this module: `block_diff` 0.157-0.171 between the two
  packages, the same as between two captures of one session (0.170-0.171); within the props, 11 of 500,000 pixels
  differ by more than 16 (path-tracing noise at edges). `out\queued-draws\lighting-before-after.png` shows both and
  their difference.
- **PoC, the crash** ([`queued_draws_session.py`](../../tools/qa/queued_draws_session.py.md), the main checkout's
  `out\queued-draws\run1` to `run3`, each series under the PoC lock and the PoC restored clean after it). In view of
  the camera, twenty times a second: a watermelon and a crate broken into gibs, three solid props removed after
  0.1-0.4 s, now and then a door removed after 0.3-0.8 s (a 10-minute run: 62,000 props spawned, about 40,900
  removed, 24,798 broken, about 3,700 doors); run2 and run3 at 2560x1440 with console churn like the VR probe's
  packets:

  | Series | Package | Run | Result |
  |---|---|---|---|
  | run1 | published | 8 client models made and removed per frame, 1600x900 | ended after 237 s: `CUtlMultiList overflow!` (an engine limit, see below) |
  | run1 | this branch | the same | ended after 204 s the same way |
  | run2 | published | no render load | 609 s, normal quit, no crash (53,090 frames, 87 fps) |
  | run2 | published | 24 CPU-skinned ragdolls as render load | 609 s, normal quit, no crash (38,717 frames, 64 fps) |
  | run3 | this branch | 24 ragdolls (the final scripts, `+fps_max 0`) | 609 s, normal quit, no crash (64,135 frames, 105 fps) |
  | run3 | this branch | the same | 609 s, normal quit, no crash (61,815 frames, 101 fps) |

  The game's own `fps_max` was 300 in all of them (the field's `config.cfg`), so run2's probe asking for 0 from Lua and
  run3's `+fps_max 0` on the command line change nothing at these rates. Under the same render load the module with the
  fix ran at 101-105 fps against 64 for the published one. The likely reason: the old hook made a `VirtualQuery`
  system call (`IsLikelyExecutablePtr`) each time studiorender set up a material, on the render thread. The two
  packages' load runs differ only in how the frame cap and focus sleep were asked for (from Lua in run2, by the driver
  in run3); a run of the published package with exactly run3's scripts (`run4`) is queued behind the VR milestone's PoC
  work to confirm the comparison.

  **The old module's crash did not reproduce in a flat session** (about 24 minutes of removals in view). The dumps say
  why ([RESEARCH.md](../RESEARCH.md)): the freed entity's links point to an equal-size free chunk of a dlmalloc-style
  heap, and slot 9 is that chunk's stale data 0x38 bytes in, which in all four VR crashes was a code address. That
  depends on what else the process allocated and freed at that size, which the VR sessions did and these flat sessions
  evidently do not. So the "before" side rests on the four dumps; the new module cannot take that path at all (it never
  calls through the renderable, checked in its code and by the regression), and under the same stress it ran clean.
  The in-game confirmation is the VR acceptance itself: its V4 combined runs crashed 2 of 2 times with this signature,
  and they can run with this module.
  **An engine limit found on the way:** the first series' client-model churn (8 `ClientsideModel`s a frame, about
  120,000 in all) ended both packages' sessions in an engine `Error()`, `CUtlMultiList overflow! (exhausted index
  range)` (exit `0xC0000409`, a fail-fast in `engine.dll` from a Lua call; dumps in the series' `wer` folders), not in
  the fixes. The driver no longer churns client models by default.

## Side finding for the user: `r_forcehwlight 1` in the package's `autoexec.cfg`

`packages/fixes/garrysmod/garrysmod/cfg/autoexec.cfg` sets `r_forcehwlight 1` ("from launcher options"). It never
applies: only the fixes module defines that convar, and it creates it at map load (`[RTX Fixes 2] r_forcehwlight convar
ready`), after `autoexec.cfg` has run; its default is 0 and no `config.cfg` saves it. Every crash stack went past the
hook's `r_forcehwlight` check into the bone lookup, so it was 0 in those sessions too. It also contradicts a decision:
the companion's guard pins `r_forcehwlight` at 0 (`_nativeloader_guard.lua`, R3-016: with 1, GPU-skinned characters
give Remix no bones and draw in bind pose). Recommendation: drop the line from `autoexec.cfg` so the file says what the
game does. It is not part of the crash fix, which holds with either value.

## Published

- **2026-11-12 21:00 UTC.** `main` fast-forwarded to `9edb9ffa` on the user's approval, after `tools\test.ps1 -Config
  Release` passed at that commit in a short-path worktree (CTest 35 of 35, 903 Python tests, `NL_FIXES_CLONE` set so the
  ten patches' tree replay ran), and was pushed with one Git LFS object (the module, 1.1 MB). The merge's hook uploaded
  item 3829070317 as **0.0.0-dev.20261112210004+ee023f12** (2,085,715,198 bytes, SHA-256
  `d2b8947322c74d7ec5cd50a83a479d06d9f1f1424083b44f1145e683e81e3631`), content digest `b2d32d09be40afa3...`; Steam
  took it as a 10.7 MB update. It differs from the package the PoC runs `run1` and `run3` ran only in two documents
  (the patch folder's `README.md`, `Source.md`) and `native/manifest.json`: the module and every other file are the
  ones tested. The push's hook found the same inputs and uploaded nothing. A player's game gets it at a start after
  Steam has downloaded the item.

## Open

- **The fork's push** to GitHub (`claude/queued-render-fix`): the user's approval.
- The VR acceptance can drop its retry rule for this signature once its package carries this module (`main` has it).
- `run4` (the published package before this change with exactly run3's scripts) was still running at the merge; its
  frame rate (about 60 fps in its first minutes against the fixed module's 101-105) confirms the comparison once done.
