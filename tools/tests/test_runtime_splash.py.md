# test_runtime_splash.py

Checks runtime patches `0102-The-splash-the-welcome-message-shown-as-text-once-fo.patch` and
`0103-The-startup-text-from-rtx-remix-mods-nativeloader_ui.patch` ([runtime/README.md](../../runtime/README.md)),
the fixes of findings 10 and 17 of the repository review of 2026-11-16: the Remix splash shows once, as the process
starts, for at most a minute, and its editable text comes from `rtx-remix/mods/nativeloader_ui`, never from
`garrysmod/data`, where any server's client Lua writes `.txt` files.

```powershell
cd tools; python -m unittest discover -s tests -p test_runtime_splash.py
```

| Test | Checks |
|---|---|
| the startup text's unit test from the patches | rebuilds `src/util/util_startup_message.h` and `tests/rtx/unit/test_splash_message.cpp` from the patches that create and change them (0012, 0034, 0103), compiles them with MSVC (`/std:c++17 /W3 /WX`) and runs them on a scratch folder: `Startup text policy tests passed` (the folder, the language choice, the 8192-byte bound, BOM and CRLF, invalid files falling back). Skipped without the VS 2022 Build Tools |
| the text comes from a folder Lua cannot write | `StartupMessage::folder` is `rtx-remix/mods/nativeloader_ui`; the splash and the font atlas load from it instead of `garrysmod/data/nativeloader_ui`; no code the series keeps names the old folder |
| the packager deploys the text where the runtime reads it | [package_fixes.py](../package_fixes.py.md)'s `STARTUP_TEXT` is the runtime's folder, create-only |
| the splash shows once for at most a minute | the display time's maximum (60 s, in the option and where it is read; `RtxOptions.md`), the two-minute start window, no timing from the epoch, the splash done once its time has passed, a steady clock |

Writes only a scratch folder under `out\tmp`, removed afterwards. Exit 0 when every test passes.
