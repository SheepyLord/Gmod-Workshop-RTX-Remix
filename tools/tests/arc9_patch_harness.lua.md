# arc9_patch_harness.lua

Runs the RTX fixes' ARC9 patch (`packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/patcher/addons/cl_arc9.lua`,
R24, [ADR 0135](../../docs/decisions/0135-view-model-materials-and-arc9.md)) under LuaJIT with a mocked patcher
(`RTXPatcher.RegisterPatch`, `InterceptFunction`), convars, `Material`, `render.MaterialOverrideByIndex` (each draw
records the overrides in force), an ARC9 weapon and a stand-in for ARC9's `DrawCustomModel` with its early returns,
its model lists and the parts its loop leaves out (`weapons/arc9_base/cl_drawmodel.lua`).

Usage: `luajit arc9_patch_harness.lua <cl_arc9.lua> <scenario>`; prints `PASS <scenario>` or fails with a Lua error
(exit 1). Scenarios: `view` (a sticker and a gun screen skipped by ARC9 and drawn afterwards with their materials,
ARC9's results passed on, NoDraw and every override put back, a hidden part left out), `world-model-skipped` (nothing
while an RT scope renders, the base model alone at LOD 2), `view-model-skipped` (an NPC's, a distant player's, an
ownerless weapon's), `preset` (a preset icon draws the preset's models), `left-to-arc9` (animation proxies, charm
models and translucent parts), `error` (ARC9's error goes on with its own message, after NoDraw is put back), `off`
(`rtx_patcher_arc9_parts 0`), `screens-first` (the provider waits in the table the companion keeps when the patch
applies first; one screen function and one texture function for every frame) and `screens-after` (registered through
the companion; the DirectX check answers "fine"). Reads only the patch. Run by
[`test_arc9_patch.py`](test_arc9_patch.py.md).
