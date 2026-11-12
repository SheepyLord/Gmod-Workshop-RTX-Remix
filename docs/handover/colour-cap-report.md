# Material colours above 1 under RTX: report (2026-11-11)

The user's report from their running game: `[507 | -1] npc_citizen`, "models whose materials set the `$color`
parameter render incorrectly under RTX Remix". The user's rule for the fix: "in Remix, `$color` should be capped at 1
wherever it exists". Done by Claude on the branch `color-cap`; package only (the engine guard's two modules in the
fixes part), no loader (`winmm.dll`) change, no runtime change.
[ADR 0190](../decisions/0190-material-colours-above-1-capped-for-remix.md).

## Root cause

1. **A model's tint reaches Remix as an 8-bit texture factor that wraps above 1.** Under RTX every model draws with
   Source's fixed-function `VertexLitGeneric_DX7`. Its colour modulation (`$color2`; on a model `$color` is replaced by
   the render colour at each draw; on other materials `$color`) goes to `shaderapidx9.dll`'s `Color3f`, `Color3fv`,
   `Color4f` or `Color4fv` (rva `0x11b50`, `0x11bf0`, `0x11da0`, `0x11e50`; vtable slots rva `0x7b568`-`0x7b580`;
   GMod build 26229091, the same file in the PoC and the field). Each component is converted with
   `cvttss2si eax, value * 255.0` and only `al` is kept, then
   `IDirect3DDevice9::SetRenderState(D3DRS_TEXTUREFACTOR, colour)`: 1.5 becomes 126 (0.49), 1.3 becomes 75 (0.29),
   1.2 becomes 50, 2.0 becomes 254. Nothing clamps.
2. **The runtime multiplies the albedo by it.** The draw's later stage multiplies the result by the factor; the
   runtime keeps that as multi-stage texture factor blending (`src/d3d9/d3d9_rtx.cpp:1104-1113` in the runtime fork,
   `rtx.enableMultiStageTextureFactorBlending`) and the shader multiplies the albedo by the factor, weighted by the
   texture's opacity (`src/dxvk/shaders/rtx/concept/surface_material/opaque_surface_material_interaction.slangh:770-778`).
   The factor is already a `D3DCOLOR` there (`src/d3d9/d3d9_rtx_utils.cpp:175`): a runtime patch cannot tell 1.5 from
   0.49, so the fix belongs before the conversion.

Which parameter: `$color2` on models (and `$color` on brushes, sprites and effects, and a render colour from
`Entity:SetColor` or `render.SetColorModulation`). A VMT's `$color` on a model reads `[1 1 1]` after a draw in both
modes, because studiorender writes the render colour into it; the user's NPC most likely had a `$color2` above 1 (no
stock citizen material has one).

## The fix

[`engine_guard/colour_cap.cpp`](../../engine_guard/colour_cap.cpp) (MIT, this repository), in
`gmcl_`/`gmsv_nlengineguard_win64.dll`, which the fixes part ships and the companion loads in RTX starts:

- Every realm's load (the menu realm's `gmsv_` copy first, at menu start) wraps the four vtable slots. A wrapper
  clamps each component, alpha included, to [0, 1] (NaN to 0, as the engine's conversion does) and calls the engine's
  function; a colour within [0, 1] passes untouched, so its bytes are the same as before.
- The slots are found by their code only: exactly one run of four consecutive pointers in `shaderapidx9.dll`'s
  read-only data to functions that load 255.0 rip-relative, convert with `cvttss2si` and call
  `SetRenderState(D3DRS_TEXTUREFACTOR)` through the device's vtable, in the order `Color3f`, `Color3fv`, `Color4f`,
  `Color4fv` (alpha `FFh`, reads through `rdx`, alpha from the stack tell them apart). No call in the image bypasses the
  vtable. Anything else leaves the game unchanged and `nlengineguard.colour_cap` says why.
- Only when the process's `d3d9.dll` exports `remixapi_InitializeLibrary`. A flat start does not load the module (the
  loader hides the package's add-ons), and a start that did would not install it.
- `nlengineguard.ColourCap(false|true)` switches it for the process (both copies share the owner's switch) and
  returns whether it caps and how many colour calls it changed; the before/after below are from one session with it.

## Verified

- **Offline, in the gate** (`tools\test.ps1`):
  - [`engine_guard/tests/test_colour_cap.cpp`](../../engine_guard/tests/test_colour_cap.cpp): the engine's wrap and the
    cap; the four slots found once in an installed game's `shaderapidx9.dll` (the PoC's; also run against the field's
    copy with `NL_SHADERAPI_DLL`); no change outside a Remix start; `module.cpp`'s contract.
  - [`test_colour_cap_e2e.cpp`](../../engine_guard/tests/test_colour_cap_e2e.cpp), its own process: a stand-in
    `shaderapidx9.dll` whose four functions are assembled with the game's shape (`tests/fake_shaderapi.asm`) and a
    stand-in Remix `d3d9.dll`. Through the vtable: wrapped before (1.5 gives 7Eh), unchanged without the Remix
    `d3d9.dll`, capped after (FFh), the same bytes within [0, 1], only out-of-range calls counted, the switch,
    idempotence, functions of another shape refused.
- **PoC** (gm_construct at noon, 1600x900, `ai_disabled`; a temporary add-on `nlct_color` with seven citizens wearing
  test VMTs (`$color` 0.8, 1, 1.2, 1.5, 2, `[1.5 0.5 0.5]`; `$color2` 1.5) beside a stock one, and the stock
  `wrecked_boxcar_gate_door` (`$color2` 1.8) and `tree_springers_card_01` (`[1.3 1.4 1.5]`)). Evidence
  `out\worktrees\color\out\color\poc` (in the main checkout's `out\worktrees\color`), sheet `out\color\compare.png`:

  | Run | Package | Result |
  |---|---|---|
  | `01-rtx-before` | published 0.0.0-dev.20261112014628+0c72c174 (the item as Steam had it installed; the item's newer +51376c12 differs only by the unsubscribe follow-up) | the bug: tree cards dark blue-grey; the `$color2` 1.5 citizen darker (torso 40/64/85 against 42/79/107; albedo about a third) |
  | `02-flat-before` | published, Remix off | the intended look: tree cards green and yellow, the `$color2` citizen brighter |
  | `03-rtx-after` | this branch (0.0.0-dev.20261112033514+613ccc50) | cap off: exactly the bug (tree patch 29/49/54, citizen 40/64/85, as `01`); cap on: tree patch 72/91/62, citizen 45/84/110 beside stock 44/81/107; citizens at or below 1 unchanged within 2; about 50,000 colour calls capped per 5 s, 476,735 in the session; the client copy "installed by the other copy of this module"; normal quit |
  | `04-flat-after` | this branch, Remix off | unchanged: no engine guard in the process (system `d3d9.dll`, dxlevel 95), the measured patches (tree 60/64/24, citizens) equal to `02` |

  The PoC's `config.json` was put back byte for byte (SHA-256 `1ed7ea10...6c16b`) after the runs.

## How it ships

In the RTX package on the Workshop (item 3829070317): the merge of `color-cap` into `main` publishes it through the
hooks. No runtime rebuild, no loader release.
