# The studio render hooks never read a queued draw's renderable

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[queued-draws.patch](queued-draws.patch) is the tenth native patch, after the public base and the nine patches
before it in [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`), which records the patched native tree
it gives (`fixes.patched_tree.source` `4843764b...`; `public` and `premake5.lua` unchanged). The complete changed
files are [prop_fixes.cpp](source/prop_fixes.cpp), [HardwareSkinningHooks.cpp](source/HardwareSkinningHooks.cpp), the
new [studio_draw_policy.h](source/studio_draw_policy.h) and its SDK-free regression
[studio_draw_policy_test.cpp](tests/studio_draw_policy_test.cpp), as the work tree has them (CRLF). The build applies
only the patch's `source/` part (`fixes.patch_paths`). The same change is commit `e6bc9e4` on the branch
`claude/queued-render-fix` of the local fork clone, after a commit (`aaf0174`) that applies the nine patches before it
to the base `f28bd5a`; that branch is not pushed.

## The crash

With queued rendering (`mat_queue_mode 2`, the default on a multi-core machine) studiorender draws every model on
the material system's render thread, a tier0 worker, from a copy of the main thread's `DrawModelInfo_t`. Its
`IClientRenderable*` is only that copy's pointer. When the main thread deletes the entity (a prop breaks, a gib fades
out, a script removes it) while the draw is still queued, the pointer refers to freed memory.

prop_fixes' `R_StudioSetupSkinAndLighting` hook counted the model's bones to choose its lighting: it read the
renderable's vtable and called slot 9 (`GetModel`). In a freed entity that first word is a heap free-list link, and
slot 9 of what it points to can still be an address in code, so `IsLikelyExecutablePtr` let the call through. The
function it ran either faulted at once (`client.dll+0x5744c`, reading -1) or overwrote the return address, and the
`ret` went to address 0: no frame handler, GMod's or Remix's crash handler can run on a stack like that, so only
Windows Error Reporting kept a dump. Four VR test crashes on 2026-11-11 and 2026-11-12 have that chain, return
address `gmcl_RTXFixesBinary_win64.dll+0x41605b` (`prop_fixes.cpp:357`, then `:265`), on the render thread, inside the
`R_StudioRenderFinal` hook's trampoline; the models being drawn were a PHX cube after a script removed scene
entities, two watermelon gibs and a crate swung as a bat ([RESEARCH.md](../../../../../docs/RESEARCH.md),
"The fixes' crash on the queued render thread"). It is not VR's: the published package has it, and any player who
removes entities in view can hit it.

## The change

- **The bone count is the drawn model's, from studiorender's own state.** `StudioDrawPolicy::BoneCount` reads
  `CStudioRender::m_pStudioHdr` (`+0x108` in GMod's x64 `studiorender.dll`, the field `HardwareSkinningHooks.cpp`
  already reads; at the crash it held the gib being drawn) and the header's `numbones` (`+0x9C`) after checking its
  `IDST` id, inside `__try`. The renderable is only compared with null: a draw without one keeps -1, as the old lookup
  gave it. The renderable lookup (`GetBoneCountForRenderable`) and its pointer checks are gone.
- **The lighting rule is unchanged**, now one function (`StudioDrawPolicy::ChooseLighting`): `r_forcehwlight`, or a
  model with at most one bone, gets `LIGHTING_HARDWARE`; a skinned model (or an unknown count) gets it with
  `r_forcehwskin` and keeps the engine's choice otherwise. For a live entity the count is the one `GetModel()` gave:
  the header `IVModelInfo::GetStudiomodel` returns for the entity's model is the one the draw carries. It can differ
  only where the lookup failed or the renderable draws another model than its own, and the drawn model is what the
  rule is about.
- **`HardwareSkinningHooks.cpp`'s model-to-world read.** `R_StudioRenderFinal` keeps the renderable for
  `ResolveModelToWorld`, which read the entity's coordinate frame through `ReadProcessMemory` (no fault, but freed
  memory can be anything). Only `r_hwskin_transform_chain` 1 and 2 use that matrix (`ComputeFinalBoneMatrix`); in the
  default 0 the pose-to-world bones go to the device unchanged, so the read is now skipped there and the renderable
  is never read. The two diagnostic modes keep reading it, as before. No other hook reads a renderable: the eyeball,
  mesh, flex and draw-group hooks use studiorender's state (`+0x08`, `+0xE8`, `+0x108`), and `model_draw_hook.cpp`
  runs on the main thread and never dereferences one.

The hook's code in the built module confirms it: the new `R_StudioSetupSkinAndLighting_detour` calls only the
trampoline, the convars, `StudioDrawPolicy::BoneCount` and `ChooseLighting`, and `BoneCount` compares the renderable
with zero and loads only from `CStudioRender+0x108` and the header; the old one's `GetBoneCountForRenderable` called
`[vtable+0x48]`.

## Tests

[studio_draw_policy_test.cpp](tests/studio_draw_policy_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG`): bone counts from a header behind a stand-in `CStudioRender` (0, 1, 57,
4096), every unknown case (no renderable, no or unreadable header, wrong id, out of range), a deleted entity whose
slot 9 points at code (never called) and a renderable in a guard page (never read: the guard would trip), the
lighting rule against the old one over a grid, and the transform-chain modes. A header that calls the renderable's
slot 9, as the old lookup did, fails it. The loader's Release gate compiles and runs it from this folder and checks
the folder's files against the patch ([test_queued_draws.py](../../../../../tools/tests/test_queued_draws.py.md)).

On the PoC, [queued_draws_session.py](../../../../../tools/qa/queued_draws_session.py.md) drives RTX sessions that
create and remove props, gibs, client models and doors in view, and a still scene for lighting captures, with the
published package and with this module ([the report](../../../../../docs/handover/queued-draws-report.md)).

Validated build (2026-11-12, this machine): **5,518,848 bytes**, SHA-256
`a2f091abdcf8528469b52fdd853abfcb8e1026f5301da26137ad7398805743ab` (the nine patches before it included), imported
once with `tools/inputs.py`. Built with [build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md) `-Only fixes`
through a temporary drive alias of this worktree's `out` (premake writes wrong paths under a folder with `!`). See the
loader's [ADR 0192](../../../../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md).
