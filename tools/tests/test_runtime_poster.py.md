# test_runtime_poster.py

Checks runtime patch 0095 ([ADR 0226](../../docs/decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md),
GitHub issue 3): GMod's `poster` command under RTX, rendered by the runtime in tiles of the window's size.

```powershell
cd tools; python -m unittest discover -s tests -p test_runtime_poster.py
```

| Test | Checks |
|---|---|
| the poster's unit test from the patch | writes `rtx_poster_math.h` and `tests/rtx/unit/test_poster_math.cpp` as the patch creates them into a folder under `out\tmp`, compiles them with MSVC (`/std:c++17 /W4 /WX`, in the Build Tools' environment from `tools\lib\VsDevEnv.psm1`) and runs the test: the tile layout and its limits, the narrowed projections and direction bases, and the composer (`PASS poster math: N checks`). Skipped without the Build Tools |
| the engine guard calls the API the patch exports | `engine_guard/rtxposter_api.h` is the patch's `rtx_poster_api.h` (line endings aside), the four `rtxposter_*` functions are in `d3d9.def` and defined in `rtx_remix_api.cpp`, and they reach the poster through its own instance (`rtx_poster_instance.h`, set in its constructor and cleared at teardown and in its destructor), never the Remix API's `s_dxvkDevice`, which GMod never registers |
| the cameras look through the tile's window | the camera manager narrows the main, view model and sky cameras' projections before the camera's update, which keeps the game's field of view and aspect |
| each tile starts afresh and keeps its picture before its UI | injection resets the history at a tile's first frame and hands the traced picture to the poster after `traceView`; exposure adaptation, the lens effects and motion blur hold; textures are sampled for the poster's pixel; the sky matte's viewport is stretched to the tile's window with its jitter shrunk to a pixel (both the shader and the fixed-function path) |
| the sky and the clock hold for the tiles | the physical sky's cloud layer and aerial perspective follow the tile's window, the sky's pixel angle the poster's pixel; the runtime's clock stands still and goes on afterwards; the PNG is written as `.part` and renamed by a thread that holds the job; WIC is reached through `ole32.dll` at run time; the new files are in `meson.build` and the unit test in `tests/rtx/unit/meson.build` |

Reads the patch and the header; writes only the scratch folder. Exit 0 when every test passes.
