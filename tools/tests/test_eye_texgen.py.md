# test_eye_texgen.py

Checks how Source eyes reach Remix ([ADR 0220](../../docs/decisions/0220-source-eyes-show-their-irises.md), GitHub
issue 1): the RTX fixes' thirteenth native patch, [eye-texgen](../../packages/fixes/licenses/oversized-skinning/eye-texgen/README.md),
and the package's Remix defaults.

```powershell
cd tools; python -m unittest discover -s tests -p test_eye_texgen.py -v
```

- `test_complete_files_are_the_patch_applied`: `eye-texgen.patch` touches exactly `source/HardwareSkinningHooks.cpp`,
  the new `source/eye_texgen_state.h` and `tests/eye_texgen_state_test.cpp`. `HardwareSkinningHooks.cpp` is the patch
  applied to queued-draws' copy (no later patch changes the file); the new files are its added lines.
  `tools/ci/pins.json` builds the module with the patch right after player-categories (topbr-scope, the fourteenth,
  follows it since 2026-11-16).
- `test_the_draw_writes_the_eye_request_again`: the request is a `thread_local EyeTexGen::Request`;
  `RTX_SetEyeTexGenState` records it before its device check; the `DrawIndexedPrimitive` hook writes it again before
  its per-strip work and before calling the device's draw; the header writes camera-space TexGen on the iris stage and
  includes no SDK.
- `test_the_package_turns_remix_eye_shading_on`: the shipped layer `packages/runtime/layers/classic_remix_defaults.conf`
  has `rtx.eye.enable = True`.
- `test_the_regression_passes` (Windows with the VS 2022 Build Tools): compiles the folder's
  `tests/eye_texgen_state_test.cpp` with `cl /EHsc /std:c++17 /W4 /WX /UNDEBUG` under `out\tmp` and runs it, which
  prints `PASS eye texgen:`.

Reads only this repository; the C++ check writes and removes a scratch folder under `out\tmp`. Exit codes: unittest's.
