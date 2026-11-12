# 0192: The fixes never read a queued draw's renderable

- Status: Accepted 2026-11-12
- Decided by: Claude, on a task from the VR work's crash triage (the crash is the RTX fixes', not VR's); the fork's
  push and the merge to `main` wait for the user.
- Builds on: the RTX fixes' patch series in `packages/fixes/licenses/oversized-skinning` (the tenth native patch,
  recorded in `tools/ci/pins.json` as R19 records the patched tree). Package only: no loader (`winmm.dll`) change, no
  runtime change.

## Context

Four `gmod.exe` crashes in VR test sessions on 2026-11-11 and 2026-11-12 ([RESEARCH.md](../RESEARCH.md), "The fixes'
crash on the queued render thread"; [report](../handover/queued-draws-report.md)):

- **The chain.** On the material system's render thread (a tier0 worker), the fixes' `R_StudioRenderFinal` hook calls
  studiorender, which calls the `R_StudioSetupSkinAndLighting` hook (`prop_fixes.cpp`). That hook counted the drawn
  model's bones to choose its lighting, through `GetBoneCountForRenderable(pClientRenderable, ...)`, which called the
  renderable's vtable slot 9 (`GetModel`). Return address `gmcl_RTXFixesBinary_win64.dll+0x41605b` in all four.
- **Why the renderable can be freed.** With queued rendering (`mat_queue_mode 2`, the default on a multi-core
  machine) studiorender queues each model's whole draw for the render thread with a copy of its `DrawModelInfo_t`,
  whose renderable is only a pointer. The main thread deletes a client entity at once when a prop breaks, a gib fades
  or a script removes it, possibly while the previous frame's draw is still queued. The freed entity's first word was
  a heap link, and slot 9 of what it pointed to was an address in `client.dll`'s code, so `IsLikelyExecutablePtr` let
  the call through: one crash faulted inside that function, three returned to address 0, where no handler can run
  (only Windows Error Reporting's LocalDumps kept a dump).
- **Who else reads it.** Only `HardwareSkinningHooks.cpp`'s `R_StudioRenderFinal` hook keeps the renderable, for
  `ResolveModelToWorld` (the entity's coordinate frame through `ReadProcessMemory`, which cannot fault but reads
  whatever the freed memory holds); that matrix is used only by `r_hwskin_transform_chain` 1 and 2. The other studio
  hooks use `CStudioRender`'s own fields.
- **What the lighting rule needs.** Only the drawn model's bone count, which studiorender holds for the draw:
  `CStudioRender::m_pStudioHdr` (`+0x108` in GMod's x64 `studiorender.dll`, already read by the skinning hooks), set
  from the draw's own info before any mesh is drawn, and the header the engine itself draws from.

## Decision

1. **The bone count comes from studiorender's state, never from the renderable.** `StudioDrawPolicy::BoneCount(this,
   renderable)` reads `m_pStudioHdr` and its `numbones` after checking the header's `IDST` id, inside `__try` (a changed
   layout gives -1, the old "unknown"). The renderable is compared with null only, so a draw without one keeps -1 as
   before. The renderable lookup and its pointer heuristics are removed.
2. **The lighting rule stays as it was.** `r_forcehwlight`, or a model with at most one bone, gets
   `LIGHTING_HARDWARE`; a skinned model or an unknown count gets it with `r_forcehwskin` and keeps the engine's choice
   otherwise (`StudioDrawPolicy::ChooseLighting`, the one function the hook uses).
3. **The model-to-world read only where it is used.** `ResolveModelToWorld` reads the renderable only when
   `r_hwskin_transform_chain` is 1 or 2; the default 0, which uploads studiorender's pose-to-world bones unchanged,
   never reads it.
4. **In the fork.** The change is a commit on a branch of the local fork clone on top of the nine patches before it,
   and the RTX package builds it as the tenth patch from `packages/fixes`; pushing the fork is the user's call.

## Consequences

- A prop, gib or door removed while its draw is queued no longer crashes the game through the fixes: on the render
  thread the fixes call nothing through a renderable. The engine still passes the pointer on as proxy data, as it
  always did.
- For a live entity the bone count is the one `GetModel()` gave (the header `GetStudiomodel` returns for its model is
  the one the draw carries), so lighting, and with it which meshes Remix sees, is unchanged. Where the old lookup
  failed (a transient renderable with no readable `GetModel`) or the renderable draws a model other than its own, the
  drawn model's count now decides, which is what the rule is about.
- `r_hwskin_transform_chain` 1 and 2, diagnostic modes the package never sets, still read the entity's coordinate frame
  and can get a stale matrix for one draw of a deleted entity; they cannot crash on it.
- `CStudioRender+0x108` is a layout fact of the current x64 build, which the skinning hooks already depend on. If a
  GMod update moves it, the field no longer holds a studio header, the count is -1 and every model keeps the engine's
  lighting (or `r_forcehwskin`'s) until the offset is updated: props lose their forced hardware lighting, nothing
  crashes.
- The package's `autoexec.cfg` line `r_forcehwlight 1` never applies (the convar is created later, at map load) and
  contradicts the companion guard's pin at 0 (R3-016). Dropping it is left to the user.
- Tested: `tests/studio_draw_policy_test.cpp` in the patch folder (bone counts, every unknown case, a deleted entity's
  renderable neither read, it sits in a guard page, nor called, the rule over a grid), compiled and run by
  `tools/tests/test_queued_draws.py` in the Release gate with checks that the folder's files are the patch applied;
  the built module's code (no call through the renderable); RTX sessions on the PoC with the published package and
  with this module ([report](../handover/queued-draws-report.md)).
