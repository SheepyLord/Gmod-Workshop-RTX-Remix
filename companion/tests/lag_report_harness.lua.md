# lag_report_harness.lua

A stand-in for the game's hook table, net receivers, timers, console commands, file and add-on calls, running the
companion's [`nativeloader_lag_report.lua`](../nativeloader/lua/autorun/nativeloader_lag_report.lua.md) under LuaJIT
(R28, [ADR 0143](../../docs/decisions/0143-read-backs-font-definitions-and-slow-render-hooks.md)). Invoked by
[`test_lag_report.py`](test_lag_report.py.md) with the script's path and a scenario:

- **client:** the client has only `nativeloader_lag_report`; a run times every hook, every function of the gamemode
  and every net receiver, starts the server's half in a local game, refuses a second run while measuring; the hooks
  are swapped in the hook table (`hook.Add` is called for the frame counter alone), a hook of an object that is gone
  is left to the hook library, and each timer is entered in the render guard's `timed` table; arguments, every
  return value (a `nil` in the middle too) and errors pass through the timers; after 100 simulated frames every hook
  and gamemode function is put back, except a hook its add-on replaced meanwhile; the report lists the slowest hook
  first with its cost per frame, file, line and add-on (a folder under `addons/`; a mounted Workshop item found once
  per file, also for its gamemode and for its file under `lua/postprocess`; "Garry's Mod" for the game's own file
  there, its modules and its base gamemode), the net receivers, the render guard's read-backs, fonts and slow
  callbacks, and writes the same lines to its data file; the time is clamped to 2-120 s and a word gives 10.
- **ulib:** a hook library with a function per priority (`hook.GetULibTable`): the timer goes in at the hook's own
  priority and into the plain table kept beside it (the render guard runs its events from that one), and comes out
  of both again.
- **copy:** a hook library whose `hook.GetTable` hands out a copy: no hook is touched, the gamemode's functions are
  timed all the same, and the report counts the hooks it could not time.
- **failure:** the report's file cannot be written: everything is put back, the failure is said, and the next
  report starts and is written.
- **server:** only `nativeloader_lag_report_server`; another player may not start it, the server's console may; the
  report is per tick, has its own file and none of the client's guard records.

Prints `PASS <scenario>`; exits nonzero on an assertion. Changes no files, game, settings or network.
