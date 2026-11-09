# !!!!!nlloadaccel.lua

The load accelerator's add-on (R26, [ADR 0140](../../../../docs/decisions/0140-the-load-accelerator.md)), deployed by the
package's `load-accelerator` part as `garrysmod/addons/nlloadaccel`. Its five `!` make it the first autorun of every
realm (GMod runs `lua/autorun` in name order across the add-ons). It runs in RTX starts: in a start without RTX the
loader leaves every add-on folder of the RTX package out of GMod's searches
([ADR 0013](../../../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)), this one included.

In the server and the client realm it:

1. Creates `nativeloader_load_accel` (archived, default 1; 0 leaves the module out from the next start) and
   `nativeloader_load_accel_verify` (not archived; 1 turns the checks on), and loads the `nlfsaccel` module
   ([`fs_accel`](../../../README.md)) when `util.IsBinaryModuleInstalled` finds it.
2. Calls `Install()` for the module's file lookup hooks (part A). They are hooked once per process: normally at menu
   start already, by the companion's [`load_accel.lua`](../../../../companion/nativeloader/lua/nativeloader/menu/load_accel.lua.md),
   which this only adopts (the other realm's copy of the module likewise). The module leaves them out once after a
   start that ended within 20 s of installing them (its marker `data/nativeloader/load_accel_pending.txt`); then one
   line says why.
3. Replaces `file.Find` with a function that, for a path that is not one of GMod's search paths (`GAME`, `LUA`,
   `DATA`, a mounted game's folder, ...) and the default or `namedesc` sorting, asks the module's index
   (`nlfsaccel.FindInAddon`, part B) and returns its answer when the path is an add-on's title; anything else (a
   wildcard in the folder part as well) and every date sorting goes to GMod's own `file.Find`. Before the first answer
   it compares GMod's and the index's answers for `*`, `lua/*` and `materials/*` in up to three mounted add-ons spread
   over the list; any difference leaves every search to GMod for the session, with one console line saying which. With
   the checks on, every answer is also asked of GMod, a difference is printed (the first ten) and GMod's answer
   returned.
4. Invalidates the index on `GameContentChanged` (a subscription or a server's add-on mounted or unmounted).
5. In the client realm, 5 s after `InitPostEntity`, prints the load's tally:
   `[nativeloader] load accelerator (client): N file lookups answered from memory in F folders; M add-on searches
   answered from the index` (and what the checks found, when they found anything).

`NLLOADACCEL` holds `{ find = <the replacement>, original = <GMod's file.Find> }` once it has run (false while it
gave up). Inputs: the module, GMod's file system. Outputs: console lines; it writes no files. Tested by
[`test_load_accel.py`](../../../../tools/tests/test_load_accel.py.md).
