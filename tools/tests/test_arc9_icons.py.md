# test_arc9_icons.py

Load speed-up round 3, item F ([ADR 0240](../../docs/decisions/0240-arc9s-attachment-icons-decoded-when-first-drawn.md)):
ARC9's attachment icons decoded when first drawn, not while a map loads.

- `Arc9IconTests` runs [`arc9_icons_harness.lua`](arc9_icons_harness.lua.md) with LuaJIT once per scenario (`client`,
  `guard`, `server`, `generate`, `off`); skipped without LuaJIT.
- `Arc9IconSourceTests` reads the add-on's autorun: it sends the file to clients (`AddCSLuaFile`) and includes it before
  it requires the native module (the file is Lua only).

```powershell
python -m unittest tests.test_arc9_icons      # from tools\
```

Touches no game; writes nothing. Exit 0 on pass.
