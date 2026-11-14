# 0220: Source eyes show their irises: Remix's eye shading on, and the eye's TexGen kept to its draw

- Status: Accepted 2026-11-14 (the user: "Fix issue #1"); package only, no loader change, no runtime change.
- Context: [GitHub issue 1](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/1) ("VMT shaders such as
  $Iris, $color are ignored in render time"): no model's `$iris` showed under RTX; `$color` and `$selfillum` looked
  ignored; a skin change did not apply. The owner had answered that this was intentional for now.

## What was found

- **The eye pipeline works up to the runtime.** Under RTX the game runs at DirectX level 7 (`d3d9.shaderModel = 0`),
  so the material system loads only `stdshader_dbg`, the RTX fixes' fixed-function `stdshader_dx6.dll` and
  `stdshader_dx7`; every `Eyes` and `EyeRefract` material draws with the fixes' `Eyes_dx9` or `EyeRefract_ff` port.
  Each eye draw binds the sclera on stage 0 and the iris on stage 1, loads the iris projection into stage 1's texture
  transform with a tag (`[3].z` = 54321 or 54322), and asks the fixes' module (`RTX_SetEyeTexGenState(1)`) for
  camera-space TexGen on stage 1. The runtime (`d3d9_rtx.cpp`) recognizes that as an eye and passes both textures and
  the projection on: with `rtx.gmod.enableInstrumentation` it logs `[GMod Eye] Handoff` for every NPC eye.
- **The runtime's eye shading was off.** `rtx.eye.enable` defaults to `False` in the runtime, the classic install's
  `rtx.conf` never set it, and so neither did the package's layer: every eye drew as a plain sclera.
- **The first EyeRefract eye of a model lost its TexGen.** With the shading on, HL2's characters showed both irises,
  but a model whose eyes are its first meshes (GTA 5 Improved Models' Franklin, Workshop 3567271959, `EyeRefract`) kept
  one white eye: only the second eye drawn ever reached the runtime as an eye (32 of 32 handoffs at one origin), the
  same mesh whatever material it had. Source's shader API commits its cached texture stage state between the shader's
  request and the draw, and the module writes the device behind that cache, so where the cache differed (the first eye
  after other draws, every frame) the commit replaced stage 1's TexGen.
- **The rest of the issue.** `$color2` and a render colour tint models under RTX (since [ADR 0190](0190-material-colours-above-1-capped-for-remix.md)
  also above 1); a model VMT's `$color` does nothing without RTX either, because studiorender writes the render colour
  into it. Skins change under RTX (a pop can's and a Combine soldier's, stock models). `$selfillum` glows only with the
  RTX fixes' Legacy Emissive categorization, which the classic defaults leave off.

## Decision

1. **The package turns Remix's eye shading on.** `rtx.eye.enable = True` is pinned in the package's Remix defaults
   (`tools/remix_defaults.py`, `EYES`), like the path bounces of [ADR 0051](0051-path-bounce-defaults.md): the
   player's own `rtx.conf` and `user.conf` still decide over it.
2. **The eye's TexGen is asserted at its draw.** The RTX fixes' thirteenth native patch,
   [eye-texgen](../../packages/fixes/licenses/oversized-skinning/eye-texgen/README.md) (GPL-2.0, like the module), keeps
   the eye shaders' request per thread (`EyeTexGen::Request`) and writes stage 1's camera-space TexGen again at the top
   of the module's `DrawIndexedPrimitive` hook while the request stands; the shader's own reset after its draw ends it,
   so no other draw changes.
3. **Legacy Emissive stays as the classic defaults have it (off).** Switching it on makes `$selfillum` parts glow, but
   also every unlit material of every map; that is the user's call, not part of this fix.

## Consequences

- Every Source eye shows its iris under RTX: HL2's characters (Eyes) and Workshop models with `EyeRefract` eyes, both
  eyes; models with painted (anime) eyes look as before. The eye shading adds Remix's eyeball normals and its iris
  depth and limbal ring (`rtx.eye.*`), so eyes no longer look flat.
- A changed native module in the fixes part (5,598,208 bytes); `tools/ci/pins.json` builds it with thirteen patches.
- Checked offline by `tools/tests/test_eye_texgen.py` (the patch, its SDK-free regression, the shipped layer) and
  `test_remix_defaults.py`; in the PoC with the built package (`out/qa-poc/issue1-final`).
