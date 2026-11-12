# 0190: Material colours above 1 capped for Remix

- Status: Accepted 2026-11-11
- Decided by: the user, on a report from their running game (`[507 | -1] npc_citizen`, "models whose materials set
  the `$color` parameter render incorrectly"): "in Remix, `$color` should be capped at 1 wherever it exists". Claude
  choosing where and how.
- Builds on: [0130](0130-an-engine-guard-for-lua-start-up.md) (the engine guard, its pattern-only patching and its two
  copies). Package only: no loader (`winmm.dll`) change, no runtime change.

## Context

Measured on the PoC on 2026-11-11 (evidence `out\worktrees\color\out\color\poc`, [RESEARCH.md](../RESEARCH.md),
"Material colours above 1 under RTX"):

- **Where the tint goes.** Under RTX every model draws with Source's fixed-function `VertexLitGeneric_DX7`. The
  shader's colour modulation (`$color2` on a model; `$color` elsewhere; on a model the engine replaces `$color` with
  the entity's render colour at each draw, so a VMT's `$color` there reads 1 in both modes) goes through
  `shaderapidx9.dll`'s `Color3f`, `Color3fv`, `Color4f` or `Color4fv` (rva `0x11b50`, `0x11bf0`, `0x11da0`,
  `0x11e50`, vtable slots at `0x7b568`; build 26229091, the PoC's and the field's file are the same). Each converts a
  component with `cvttss2si eax, value * 255.0` and keeps `al`, packs a `D3DCOLOR` and calls
  `IDirect3DDevice9::SetRenderState(D3DRS_TEXTUREFACTOR, colour)`. Nothing clamps: 1.2 becomes 50 (0.20), 1.3
  becomes 75, 1.5 becomes 126 (0.49), 2.0 becomes 254, -0.1 becomes 231.
- **What the runtime does with it.** The draw's second texture stage multiplies the result by that factor; the
  runtime keeps it as multi-stage texture factor blending (`src/d3d9/d3d9_rtx.cpp:1104-1113`,
  `rtx.enableMultiStageTextureFactorBlending`) and multiplies the albedo by it, weighted by the texture's opacity
  (`opaque_surface_material_interaction.slangh:770-778`). The factor is an 8-bit colour by then
  (`d3d9_rtx_utils.cpp:175`): the runtime cannot tell 1.5 from 0.49.
- **What it looked like.** gm_construct's tree cards (`models/props_foliage/tree_springers_cards_01`, `$color2
  [1.3 1.4 1.5]`) green and yellow in a flat start, dark blue-grey under RTX (factor 0.29, 0.40, 0.49); a citizen
  with `$color2 [1.5 1.5 1.5]` darker than the stock one (its albedo about a third); `$color` variants on a model the
  same as stock (replaced by the render colour). A flat start brightens them: the DX9 shaders take the colour as a
  float constant.

## Decision

1. **Cap before the conversion.** The engine guard wraps the four vtable slots of the loaded `shaderapidx9.dll`. A
   wrapper clamps each component, alpha included, to [0, 1] (NaN to 0, as the engine's conversion gives) and calls the
   engine's function; a colour within [0, 1] is passed on untouched, so its bytes are the same. The four slots carry
   every float colour the material system sends as the texture factor: `$color`, `$color2` and a render colour, on
   models, brushes, sprites and effects alike, which is "wherever it exists" for Remix. A runtime patch cannot do it:
   the byte has already wrapped.
2. **Only where sure.** The slots are found by their code, never by address: exactly one run of four consecutive
   pointers in `shaderapidx9.dll`'s read-only data, each to its own function that loads 255.0 rip-relative, converts
   with `cvttss2si` and calls `SetRenderState(D3DRS_TEXTUREFACTOR)` through the device's vtable, in the order
   `Color3f`, `Color3fv`, `Color4f`, `Color4fv` (told apart by alpha `FFh`, reads through `rdx`, alpha from the stack).
   No call in the image bypasses the vtable. Another game build or another module's hook leaves the game as it was,
   and `nlengineguard.colour_cap` says why.
3. **Only in Remix starts.** Nothing is wrapped unless the process's `d3d9.dll` exports `remixapi_InitializeLibrary`
   (and the loader hides the package, the engine guard with it, in a flat start).
4. **Every realm, once per process.** The menu realm's copy (`gmsv_`) installs at menu start, before any map; the
   other copy finds its export `nl_engine_guard_colour_cap_v1` and shares its switch and count. Each slot is changed
   with one aligned store; the module is pinned.
5. **A switch for comparisons.** `nlengineguard.ColourCap(false)` turns the cap off for the process,
   `ColourCap(true)` on; both return whether it caps and how many colour calls it changed. Not saved, no menu.

## Consequences

- Tints above 1 now leave the albedo as the texture is (a cap of 1), instead of darkening or discolouring it; tints at
  or below 1 tint as before. A tint meant to brighten does not brighten under RTX (it never did: the runtime's factor
  is a byte); a replacement material in a Remix mod remains the way to change a surface's look.
- An alpha above 1 (`$alpha`, a render colour's alpha) is capped too: it wrapped the same way.
- Costs a compare per component per colour call; no allocation, no lock.
- A GMod update that changes `shaderapidx9.dll` keeps working while the shape holds; otherwise the cap is off and says
  so, and the tests below fail on this machine's PoC until the shape is updated.
- Tested: `engine_guard/tests/test_colour_cap.cpp` (the wrap and the cap, the slots in an installed game's
  `shaderapidx9.dll`, nothing outside a Remix start, the module's contract) and `test_colour_cap_e2e.cpp` (a stand-in
  `shaderapidx9.dll` in assembly with the game's shape and a stand-in Remix `d3d9.dll`: wrapped before, capped after,
  unchanged within [0, 1], the switch, other shapes refused); on the PoC before and after
  ([report](../handover/colour-cap-report.md)).
