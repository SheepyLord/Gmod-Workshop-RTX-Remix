# runtime_patch_text.py

Helpers for the gate tests that check the runtime fork's patches (`runtime/patches/*.patch`,
[runtime/README.md](../../runtime/README.md)) as text, without the fork's 3.6 GB tree. Imported by
[test_runtime_mod_option_layers.py](test_runtime_mod_option_layers.py.md),
[test_runtime_imgui_formats.py](test_runtime_imgui_formats.py.md) and [test_runtime_splash.py](test_runtime_splash.py.md);
it runs nothing on its own and is not a test module (`unittest discover` loads only `test*.py`).

| Function | Gives |
|---|---|
| `patch_paths()` | every runtime patch, in name (apply) order |
| `one_patch(number)` | the one patch numbered so (`0101-*.patch`), or an assertion error |
| `file_blocks(patch)`, `file_block(patch, path)` | each file's diff block of a patch |
| `hunks(block)` | a block's hunks as (old start, marked lines), each as long as its `@@` header says (an empty context line whose space an editor dropped counts as context) |
| `added_lines(patch, path)`, `removed_lines(patch, path)` | the lines a patch adds to or removes from a file |
| `postimage(patch, path)` | a file the patch creates, whole |
| `apply(text, block, path)` | `text` with a block's hunks applied, each found by its context |
| `rebuilt(path)` | a file the fork's base commit lacks, as every patch that creates and changes it leaves it |
| `live_added_lines()` | per file, the lines the patches add that no later patch removes |

Reads only `runtime/patches`. No side effects.
