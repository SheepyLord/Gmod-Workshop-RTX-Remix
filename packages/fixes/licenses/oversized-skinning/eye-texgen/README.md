# Source eyes keep their iris TexGen to the draw

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[eye-texgen.patch](eye-texgen.patch) is the thirteenth native patch, after
[player-categories](../player-categories/README.md); [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds
the module with it last and records the patched native tree the thirteen give (`fixes.patched_tree.source`
`daa6870d...`; `public` and `premake5.lua` unchanged). The complete changed files are
[HardwareSkinningHooks.cpp](source/HardwareSkinningHooks.cpp), the new [eye_texgen_state.h](source/eye_texgen_state.h)
and the SDK-free regression [eye_texgen_state_test.cpp](tests/eye_texgen_state_test.cpp), as the work tree has them
(CRLF). The build applies only the patch's `source/` part. Made in a scratch checkout of the public base with the twelve
earlier patches applied; nothing was committed to the fork or pushed.

## The fault

Under RTX the fixes' fixed-function eye shaders (`Eyes_dx9`, `EyeRefract_ff` in their `stdshader_dx6.dll`) draw every
Source eye: the sclera on stage 0, the iris on stage 1 with its projection in stage 1's texture transform (tagged for the
runtime), and at the end of their dynamic state `RTX_SetEyeTexGenState(1)`, which writes camera-space TexGen for stage 1
on the device. The runtime recognizes an eye only if stage 1 still has that TexGen at the draw. Source's shader API
commits its own cached texture stage state between the shader's dynamic state and the draw; the helper writes the device
behind that cache, so where the cache differed from what the API wanted (the first eye drawn after other draws, every
frame) the commit replaced stage 1's TexGen and Remix drew that eye as a plain sclera. On GTA 5 Improved Models'
Franklin (Workshop 3567271959, `EyeRefract`, the eyes are meshes 0 and 1) only the second eye ever reached the runtime as
an eye: 32 of 32 `[GMod Eye] Handoff` lines at its origin, whichever material either mesh had.

## The change

- **`EyeTexGen::Request` ([eye_texgen_state.h](source/eye_texgen_state.h), standard C++)** holds the shaders' request:
  `RTX_SetEyeTexGenState(enable)` sets it (before its device check) and the shaders' own reset after their draw, or the
  hooks' safety-net resets, end it. `ApplyBeforeDraw` writes stage 1's camera-space TexGen, two transformed coordinates
  and clamped addressing, the values the helper writes; the header's D3D9 numbers are checked against the SDK where the
  module includes it.
- **The `DrawIndexedPrimitive` hook** writes the request at its top, before its per-strip bone work and the device's
  draw, while the request stands. The request is `thread_local`: with queued rendering the eye's dynamic state and its
  draw run on the material system's render thread, so another thread's draws never see it.
- Nothing else changes: stage 0 keeps the sclera's UV0, and a draw after the reset is left alone.

## Tests

[eye_texgen_state_test.cpp](tests/eye_texgen_state_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX`; it includes `d3d9.h` only for the numbers):
no write without a request, the four writes and their values with one, the fault's sequence (the helper's write, the
shader API's overwrite, the draw) restored for the first and the second eye, the draw after the reset untouched, and one
request per object. The loader's Release gate compiles and runs it and checks the folder's files against the patch
([test_eye_texgen.py](../../../../../tools/tests/test_eye_texgen.py.md)).

Validated build: 5,598,208 bytes, SHA-256 `172e0dd69956603fc548e16db8aa1cf3f8255bc9237402e2f8530219926ba34c`
(`build_modules.ps1 -Only fixes`, garrysmod_common `a854f23`, premake 5.0.0-beta2; the patched tree matched). In the PoC
with the package built from it: both of Franklin's eyes reach the runtime (two origins in the handoff log) and show their
irises, as HL2's characters do. See the loader's [ADR 0220](../../../../../docs/decisions/0220-source-eyes-show-their-irises.md).
