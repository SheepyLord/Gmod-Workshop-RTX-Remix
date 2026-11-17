# load_callbacks.lua

The load accelerator's third round, item D2 ([ADR 0241](../../../../docs/decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md)):
what held the main thread during a map load without leaving a file name on the stack. Included first by the add-on's
autorun ([`!!!!!nlloadaccel.lua`](../autorun/!!!!!nlloadaccel.lua.md)) in the server and the client realm, so that it
times the other add-ons' callbacks from their start.

**Why.** The load overlay names "the Lua files that ran longest" from the file names GMod keeps on the stack while a
file runs. A hook, a timer or a net receiver runs later, from a file that has finished, and was invisible there: the
second round's 54 s frame was one net receiver of the Model Hotloader, called 94 times.

**What it does.** From the autorun until 10 s after the realm's `InitPostEntity` (a timer: a frame still running then
counts whole; 900 s at the latest):

- `hook.Add`, `timer.Simple`, `timer.Create` and `net.Receive` wrap each function they register in a timing wrapper
  (`SysTime()` before and after; arguments and results pass through). Entries: a hook by `<event> <id>`, a net receiver
  by its name, `timer.Create` by its id, `timer.Simple` by where its function was defined. A time includes what the
  callback calls.
- Each wrapper is entered in the render guard's `NativeLoaderRenderGuard.timed` (client realm) with the function it
  times, as the lag report does, so that the guard's records keep naming that function; wrappers made before the guard
  loaded are entered once it has.
- A call of 0.25 s or more writes `data/nativeloader/load_callbacks_<realm>.txt` (at most every 0.5 s): a first line
  `load <os.time at the start> <realm>`, then up to eight entries `seconds <TAB> calls <TAB> worst <TAB> kind <TAB>
  name <TAB> source:line <TAB> add-on` (the add-on only in the final file). The load overlay
  ([`loading_status.lua`](../../../../companion/nativeloader/lua/nativeloader/menu/loading_status.lua.md)) reads both
  realms' files at the end of the load.

At the end the original functions go back where the wrappers still are (`hook.Add`, `timer.Simple`, `timer.Create`,
`net.Receive` if still this file's; each hook through the lag report's `swap`, ULib's table included; each net
receiver), the wrappers left in timers only pass the call on, the final file is written, and one line is printed:
`[nativeloader] load accelerator (<realm>): Lua callbacks that ran longest during the load: net mmdhl_catalog 51.2 s
(94 calls, lua/mmdhl/sharing.lua:385, Model Hotloader); ...` (five at most, 0.1 s or more), or `no Lua callback ran
0.1 s or longer during the load`. The add-on is the folder under `addons/`, else the mounted add-on that has the file.

- **Switch:** `nativeloader_load_accel_callbacks` (archived, 1): 0 times nothing from the next map.
- **State:** `NLLOADACCEL_CALLBACKS` = `{realm, began, entries, write, stop, restored}`.
- **Side effects:** the file above; the four registration functions replaced during the load.
- **Tests:** [`test_load_callbacks.py`](../../../../tools/tests/test_load_callbacks.py.md) with
  [`load_callbacks_harness.lua`](../../../../tools/tests/load_callbacks_harness.lua.md).
