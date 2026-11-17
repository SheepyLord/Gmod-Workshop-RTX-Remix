# load_callbacks_harness.lua

LuaJIT harness for the load accelerator's
[`nlloadaccel/load_callbacks.lua`](../../fs_accel/addon/lua/nlloadaccel/load_callbacks.lua.md) (ADR 0241), run by
[`test_load_callbacks.py`](test_load_callbacks.py.md).

```
luajit tools\tests\load_callbacks_harness.lua <repo> <scenario>
```

It mocks a realm: GMod's hook library as a plain table (`hook.GetTable`), `timer.Simple`/`timer.Create` (run by the
harness), `net.Receive`/`net.Receivers`, a clock the callbacks advance (`SysTime`), `file.Write`, `engine.GetAddons`
with `file.Exists` (the add-on of `lua/mmdhl/sharing.lua`), and the render guard's `timed` table. Callbacks are
defined in chunks named as other add-ons' files.

| Scenario | Checks |
|---|---|
| `client` | a hook added before the render guard loaded is entered in its `timed` table once it has; the hook table holds a timing wrapper that passes arguments and results through; a slow call writes the file at once (format, source); a net receiver's three calls, `timer.Simple` by where its function was defined, `timer.Create` by its id; 10 s after `InitPostEntity` `hook.Add`, the timers and `net.Receive` are GMod's again, each hook and receiver holds its own function; the line printed (order, calls, source, add-on; under 0.1 s left out) and the final file; nothing timed after the load |
| `server` | the same in the server realm (no render guard) |
| `off` | `nativeloader_load_accel_callbacks 0`: nothing replaced |

Writes nothing to disk. Exit 0 and `PASS <scenario>`, or a Lua error naming the failed check.
