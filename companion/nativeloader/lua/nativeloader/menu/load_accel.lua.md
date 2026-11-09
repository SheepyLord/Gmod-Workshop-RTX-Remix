# load_accel.lua

The load accelerator at menu start (R26, [ADR 0140](../../../../../docs/decisions/0140-the-load-accelerator.md)). The RTX
client module runs this companion menu script once in the menu realm of an RTX start
([ADR 0133](../../../../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)), before
[`loading_status.lua`](loading_status.lua.md) (name order). It requires the `nlfsaccel` module's `gmsv_` copy and calls
`Install()`, so the file lookup hooks (part A of [`fs_accel`](../../../../../fs_accel/README.md)) are in place before
the first map of the start loads; the load accelerator's add-on adopts them in the server and the client realm. Starts
without RTX run neither (the RTX client module is not loaded, and the loader leaves the package's add-on folders out:
[ADR 0013](../../../../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)).

- Off: `nativeloader_load_accel 0` is the add-on's client convar, which the menu realm cannot see; the client keeps
  `data/nativeloader/load_accel_off.txt` while it is 0, and with that file present this script loads nothing. It
  creates no convar of its own.
- The crash-loop guard is the module's own (the menu realm cannot write files): it writes
  `data/nativeloader/load_accel_pending.txt` before the hooks go in and removes it once a map has loaded with them and
  at least 20 s have passed; a start that finds the marker of a process that is gone leaves the hooks out once, and
  `Install()` returns why. This script's `Think` hook tells the module (`Settled()`) 10 s after the first map load ends
  (`IsInLoading()` true, then false), on any server; the add-on does too, where its client Lua runs.
- Sets `NativeLoaderLoadAccel` to the module's table, which `loading_status.lua` reads for the load overlay's status
  line ("N file lookups answered from memory", counted from the load's start) and the end-of-load console summary.

Prints one line: `[nativeloader] load accelerator (menu): F loose add-on folders cached`, or why it did not install,
or that it is off. Writes no files. Tested by [`test_load_accel.py`](../../../../../tools/tests/test_load_accel.py.md).
