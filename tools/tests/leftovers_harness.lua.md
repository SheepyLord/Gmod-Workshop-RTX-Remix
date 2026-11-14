# leftovers_harness.lua

LuaJIT harness for [ADR 0206](../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md), run by
[`test_leftovers_lua.py`](test_leftovers_lua.py.md). Two modes:

```
luajit leftovers_harness.lua <repo> trigger <scenario>
luajit leftovers_harness.lua <repo> gate <file> yes|no
```

- **trigger**: runs the companion's real `autorun/server/nativeloader_leftovers.lua` in a mocked server realm (hooks,
  `file.Exists`, `include` of the translations, convars, `require`, `RunConsoleCommand`, `MsgN`) with a mocked RTX
  client module whose `NativeLoaderLeftovers.Remove()` answers per scenario: `rtx-start`, `dedicated`,
  `loader-installed` (no hook, no module), `no-module`, `not-needed`, `module-error` (nothing visible), `refused`
  (a console line only), `removed` and `french` (the settings set back, console lines, the chat notice after the
  player's first own move, in French), `partly` (what stayed listed).
- **gate**: loads an autorun file in an environment that fails on any global other than `NativeLoaderRTXStart` and
  `NATIVELOADER_VERIFIED_MULTIPLAYER`. With `no` (a start without RTX) the file must return without touching
  anything; with `yes` it must go on past its gate (and then fail on the empty environment).

Prints `PASS ...` and exits 0, or fails with the reason. Reads only; writes nothing.
