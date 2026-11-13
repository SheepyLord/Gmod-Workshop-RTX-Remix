# purge_file_cache.py

Drops files from Windows' file cache without administrator rights, so that the next read of each comes from the disk,
as at a game's first start after a reboot. It opens each file once for reading with `FILE_FLAG_NO_BUFFERING` and
closes it: NTFS then flushes and purges the file's cached pages (while no process has the file mapped). Used by
[mod_load_session.py](mod_load_session.py.md) `--cold` for the mod texture cache's cold starts
([ADR 0195](../../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md)).

```powershell
python -I tools\qa\purge_file_cache.py <folder> [<folder> ...]
python -I tools\qa\purge_file_cache.py out\tmp\purgetest --check   # also time a tail read before and after
```

- Input: folders; every file below them is purged.
- Output: one JSON line: `files`, `purged`, `purge_s`, `failed` (at most 20 paths) and `failed_count`; with `--check`
  also `warm_s` and `after_purge_s`, the time to open each file and read its last 4 KB before and after the purge.
- Side effects: none on the files (opened for reading only, nothing read or written). `--check` reads the files.
- Measured on H: (Samsung 980 PRO, 2026-11-12): 3,000 files of 64 KB, a tail read of each took 0.072 s warm and
  0.39 s after the purge.
- Exit codes: 0, or 1 when a file could not be opened (a file another process holds without read sharing).
