# hotloader_workshop_install_harness.lua

The LuaJIT side of [test_hotloader_workshop_install.py](test_hotloader_workshop_install.py.md)
([ADR 0255](../../docs/decisions/0255-workshop-models-install-several-at-once.md)). Loads the shipped `mmdhl/workshop.lua`
whole in the client realm (and `mmdhl/library.lua` for one scenario), with the native transfer and asset check, the
disk, timers, hooks and frames instrumented: a commit ends after a few polls (more for a larger file), an asset check
after a set number, and `SysTime` moves a little at each call so the install's per-frame budget holds.

```powershell
luajit tools\tests\hotloader_workshop_install_harness.lua packages\model-hotloader\mmd_hotloader\lua\mmdhl <scenario>
```

Scenarios:

- `parallel`: eight models sharing three textures. Every model installs with no error; every file moves exactly once;
  four asset checks run side by side (the instrumented computer has 24 threads), never more than four commits; no file
  is written before its model's install record; the state file is written a few times, not per model; installed models
  reach the library through `library.Add`, each once, in fewer updates than models, with one full rebuild (the scan's);
  the closing notice follows.
- `failures`: the first commit of a texture models 1 and 2 both list fails: whichever of the two moves it first fails,
  and the other moves the texture itself and installs, so exactly one of them installs. Which goes first follows the
  queue's order (`W.provided`'s `pairs` order, which LuaJIT 2.1 seeds per run), so the scenario accepts either. Model 3's
  check fails while others run and passes alone; model 4's check says it is no model: refused after its check alone,
  its manifest deleted. Two errors are reported; no check or transfer is left open.
- `replace`: an installed model one of whose files changed since it was last known good is verified, then that file
  alone is replaced (moved without being checked again) and the model installs again.
- `library_add`: `library.Add` lists new characters as a full rebuild lists them (a chosen name, the manifest's name),
  leaves out a deleted one, reads no other model's settings, and bumps the revision and runs `MMDHL.LibraryChanged`
  once for the batch and not at all when nothing is new; `library.Prime` decodes a new character's manifest at once
  without changing the library, and the update that lists it decodes nothing again.

## Pack updates

- `update_same_size` and `update_in_use` replace only a changed binary whose size and recorded time match. The latter checks the restart notice for a loaded copy.
- `unchanged` and `legacy_same_package` count zero hashes for intact files. `legacy_other_package` adopts hashes from a different build after checking its manifest. `legacy_other_stale` and `legacy_other_binary` repair mismatched manifests and binaries respectively.
- `resume` resumes a persisted pending update. `server_update` installs a same-size revision in a dedicated server's cache.
- `pack_owners` resolves a deployed directory and a directly mounted Workshop item, and refuses an ambiguous directory. `supersede_key` follows an author key through a source rename. `supersede_legacy` and `supersede_field` exercise previous records, including the reported case with both builds already installed.
- `supersede_save` checks every library change for a duplicate and retains the old saved carrier. `supersede_settings` checks the player's folder, favourite and custom name. Other successful cases remove the old bytes when there is no rig.
- `supersede_owned`, `supersede_private` and `supersede_shared` protect earlier imports, a local source record and a second provider. `supersede_ambiguous` and `supersede_legacy_collision` refuse ambiguous source names and pack titles. `supersede_failure` keeps the last usable entry through a failed check and retries the replacement.

The actor and save paths run in the [readiness harness](mmd_lazy_load_harness.lua.md).
`journal_owners` distinguishes two successive Workshop publishers using the same folder and
outer ID. `supersede_previous` uses the previous generation when there is no surviving sibling.
`supersede_demo` preserves an adopted character and `supersede_rollback` reinstates an earlier build.
Prints `PASS <scenario>` and exits 0. A failed assertion or Lua error exits nonzero. Writes nothing.
