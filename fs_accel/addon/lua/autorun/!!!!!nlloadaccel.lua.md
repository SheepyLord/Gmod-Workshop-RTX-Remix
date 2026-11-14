# !!!!!nlloadaccel.lua

The load accelerator's add-on (R26, [ADR 0140](../../../../docs/decisions/0140-the-load-accelerator.md)), deployed by the
package's `load-accelerator` part as `garrysmod/addons/nlloadaccel`. Its five `!` make it the first autorun of every
realm (GMod runs `lua/autorun` in name order across the add-ons). It runs in RTX starts: in a start without RTX the
loader leaves every add-on folder of the RTX package out of GMod's searches
([ADR 0013](../../../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)), this one included.

From [ADR 0206](../../../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md) it also decides that
itself, first: unless this machine's loader activated RTX in this start (its `native-loader/status.json` says so and,
from loader 0.14.0, it holds `native-loader/rtx-session.txt` open; the companion's `_nativeloader_guard.lua` decides it
the same way), it returns before any convar or module. A start through an off switch (`-nonativeloader`), a game whose
loader was removed, or files a loader left behind still mount the folder, and loaded the module before (seen on the PoC,
2026-11-13).

In the server and the client realm it:

1. Creates `nativeloader_load_accel` (archived, default 1; 0 leaves the module out from the next start) and
   `nativeloader_load_accel_verify` (not archived; 1 turns the checks on). The menu realm cannot see a client realm's
   Lua convar (RESEARCH, R24), so the client keeps "off" for the companion's menu script as
   `data/nativeloader/load_accel_off.txt` (written while the convar is 0, removed when it is 1, at once on a change).
   Then, when on, it loads the `nlfsaccel` module ([`fs_accel`](../../../README.md)) when `util.IsBinaryModuleInstalled`
   finds it.
2. Calls `Install()` for the module's file lookup hooks (part A). They are hooked once per process: normally at menu
   start already, by the companion's [`load_accel.lua`](../../../../companion/nativeloader/lua/nativeloader/menu/load_accel.lua.md),
   which this only adopts (the other realm's copy of the module likewise). The module leaves them out once after a
   start that ended before a map had loaded with them (its marker `data/nativeloader/load_accel_pending.txt`); then one
   line says why. The checks' switch is passed on only when it is on, so a map change does not turn off checks turned
   on in the other realm.
3. Replaces `file.Find` with a function that, for a path that is not one of GMod's search paths (`GAME`, `LUA`,
   `DATA`, a mounted game's folder, ...) and the default or `namedesc` sorting, asks the module's index
   (`nlfsaccel.FindInAddon`, part B) and returns its answer when the path is an add-on's title; anything else (a
   wildcard in the folder part as well) and every date sorting goes to GMod's own `file.Find`. Before the first answer
   it compares GMod's and the index's answers for `*`, `lua/*` and `materials/*` in three mounted add-ons, spread over
   the list first: an add-on GMod's table does not hold (GMod finds nothing under it either) is skipped; any difference,
   or no mounted add-on to compare with, leaves every search to GMod for the session, with one console line saying
   which; while the index reports GMod's table changing, GMod answers and the next search tests again. With the checks
   on, every answer is also asked of GMod, a difference is printed (the first ten) and GMod's answer returned.
4. Invalidates the index on `GameContentChanged` (a subscription or a server's add-on mounted or unmounted).
5. 5 s after `InitPostEntity` tells the module a map has loaded (`Settled()`, so its start-up marker may come off) in
   the client realm and on a dedicated server (a listen server's own `InitPostEntity` comes before its client has
   loaded), and in the client realm prints the load's tally:
   `[nativeloader] load accelerator (client): N file lookups answered from memory in F folders; M add-on searches
   answered from the index` (and what the checks found, when they found anything).

`NLLOADACCEL` holds `{ find = <the replacement>, original = <GMod's file.Find> }` once it has run (false while it
gave up). Inputs: the module, GMod's file system. Outputs: console lines; in the client realm the off file. Tested by
[`test_load_accel.py`](../../../../tools/tests/test_load_accel.py.md).
