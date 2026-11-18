# test_multiplayer_dxlevel.py

Unit tests for [ADR 0246](../../docs/decisions/0246-the-directx-level-servers-see.md), the DirectX level a server sees
from an RTX start: runs [`dxlevel_harness.lua`](dxlevel_harness.lua.md) under LuaJIT on the companion's
[`nativeloader/prelude/dxlevel.lua`](../../companion/nativeloader/lua/nativeloader/prelude/dxlevel.lua.md), one process per
scenario: multiplayer reports the level the game was started at, single-player and the switch keep the engine's, the
render guard's route, never lower than the engine and the same as the `mat_dxlevel` convar, unreadable or missing
settings, installed once, the server and menu realms and a realm without the engine's functions untouched,
metamethods a server set on `_G`.

```powershell
python -m unittest discover -s tools\tests -p test_multiplayer_dxlevel.py
```

Skipped without LuaJIT (`luajit` on `PATH`, or `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`), like the render
guard's tests. No game, file or network. Exit 0 when every test passes.
