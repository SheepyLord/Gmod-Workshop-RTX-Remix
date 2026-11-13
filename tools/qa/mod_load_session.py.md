# mod_load_session.py

Times the Remix runtime's load of the `rtx-remix\mods` USD mods (the "Loading enhancements" notice) at each start of
the PoC, for one or more packages in turn, with the user's subscribed content packages deployed as the field has them
(`--subscribed-content on`, the default). Written for the mod texture cache
([ADR 0195](../../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md),
[report](../../docs/handover/mod-load-cache-report.md)).

```powershell
py -3 -I tools\qa\mod_load_session.py --evidence out\mlc\ab1 --package I=out\mlc\pkg-instr.gma --package F=out\mlc\pkg-fix2.gma --starts 3 --cold I-3 --cold F-1 --cold F-3
py -3 -I tools\qa\mod_load_session.py --evidence out\mlc\ab1 --rollback        # after an interrupted series
py -3 -I tools\qa\mod_load_session.py --evidence out\mlc\x --parse <remix-dxvk.log>   # only read a log
```

## What it does

1. Takes `out\r10\poc.lock` (waits up to `--lock-timeout`, default 6 h; never removes another task's lock).
2. Snapshots the PoC with `field_snapshot.py` and moves its mutable trees aside (`vr_session.preserve`).
3. For each `--package LABEL=GMA` in order: `poc_session.py install` (the first) or `config` with
   `--allow-local GMA --remix on --subscribed-content on|off`, then `--starts` sessions named `LABEL-1`, `LABEL-2`, ...
   Each session is `poc_session.py run` to `--map` (gm_construct) at 1600x900 with `fps_max 60`, `-noaddons
   -noworkshop`, the camera pinned at the queued-draws lab's view, `--settle` seconds (90) in the map, then
   `--screenshots` captures (1) and a normal quit. The first session after a package's install or config also
   deploys it (a fresh install unpacks the content packages, about 25 GB in the PoC).
4. `--cold RUN` (repeatable): before that session, empties Windows' file cache of every file below the PoC's
   `rtx-remix\mods` and `rtx-remix\cache` with [purge_file_cache.py](purge_file_cache.py.md), as a first start after a
   reboot finds them. Reads nothing; needs no administrator rights.
5. After each session, reads its `remix-dxvk.log` (`poc\<run>\remix-dxvk.log`) and records in `results.json`:
   - the patched runtime's lines (patch 0086): `[RTX Mod Load] mod=... ms=... stage_ms materials materials_ms textures
     usd_ms find_ms preload_ms meshes meshes_ms lights lights_ms` per mod, `[RTX Mod Load] all mods=N ms=T` for the
     whole load, and `[RTX Mod Texture Cache] mod=... lookups repeats hits misses unkept unlisted folders list_ms read_ms
     save_ms loaded ignored saved save_failed` per mod, summed in `cache_sum`;
   - for any runtime, `markers`: the span from the first mod's `Adding asset search path` line to the last mod's
     `[SecretReplacement]` warnings (the end of its walk);
   - the size of the PoC's `rtx-remix\cache` after the session (`cache_bytes`).
6. Restores the PoC (`vr_session.restore`, the snapshot's rollback, `user.conf` hashes compared before and after) and,
   without `--keep-copies`, removes its own bulk copies (`vr_session.cleanup`).

## Inputs and outputs

- Inputs: the packages (`.gma`), the PoC, the built loader (`tools\install-loader.ps1` through `poc_session.py`).
- Outputs below `--evidence` (a new folder under the main checkout's `out`): `plan.json`, `results.json`, each step's
  log (`<run>.log`, `<run>-install.log`), `poc\` (poc_session's evidence: `session.json`, each run's logs and
  screenshots), the snapshot, `restoration.json`, `protected-before.json`/`protected-after.json`.

## Side effects

Installs the loader and the packages into the PoC and starts the game there; everything is rolled back at the end
(also after an error). The session writes GMod's settings back as `poc_session.py` does (Steam Cloud).

## Exit codes

0 when the series ran and the PoC was restored; an exception (non-zero) when a step failed, the lock timed out or the
rollback did not verify clean (the snapshot and generated files are then kept: `--rollback` recovers).
