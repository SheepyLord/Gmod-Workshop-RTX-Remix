# test_leftovers_lua.py

Tests for [ADR 0206](../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md): the companion's clean-up
of RTX a removed loader left, and the gates that keep the package's Lua out of starts without RTX.

```powershell
python -I tools\tests\test_leftovers_lua.py
```

- **Sources:** every companion autorun but the four that decide for themselves (`!!!!nativeloader_engine_guard.lua`,
  `_nativeloader_guard.lua`, `_nativeloader_effect_categories.lua`, `server/nativeloader_leftovers.lua`) starts with
  `if NativeLoaderRTXStart and not NativeLoaderRTXStart() then return end`; every autorun of the RTX fixes'
  `remixbinary` add-on with the strict form that also accepts the verified multiplayer initializer. So does the fixes' debug add-on (`source/debug/addon/.../rtx_debug.lua`). The load accelerator, which sorts first,
  carries the same decision before its convars and its module. The engine guard
  publishes the answer before it stops, and sorts first. The clean-up is never sent to clients and checks the RTX start
  and `bin/win64/winmm.dll` before it loads a module.
- **Runs** (LuaJIT, [`leftovers_harness.lua`](leftovers_harness.lua.md); skipped without LuaJIT): each gated file
  with and without RTX, and the clean-up's ten scenarios.

Reads only. Exit: unittest's.
