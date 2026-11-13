# Recorded Index description for simulated tests

`index-v1.json` holds OpenVR projection tangents, eye offsets, size and refresh from V1's actual
Index measurements. Its provenance names and hashes VR-C's V1 receipt; the zero recorded cant
uses a neutral eye rotation. The V2-N live receipt checks the full transforms separately, so
these test inputs do not silently change with a player's current IPD/resolution setting.

The driver copies the file to **`NLVR_TEST_ROOT/simulated-index.json`**. The module never reads
this repository path by itself, and Lua cannot choose a different device file or test root.
The bounded parser checks dimensions, refresh, projection signs, finite rigid transforms and IPD.
These are test data, not a packaged device preset and not a reason to initialise SteamVR.


## V4 controller frames

C records Index tip/openxr_handmodel matrices from the SteamVR render-model JSON files (2026-11-11). These optional local OpenVR-basis matrices feed the same frame composition as live SDK reads, with source recorded_components. They are test data only. Old device descriptions without controllers retain raw fallback.
