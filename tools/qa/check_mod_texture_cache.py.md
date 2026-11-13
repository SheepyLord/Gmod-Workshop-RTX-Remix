# check_mod_texture_cache.py

Checks the Remix runtime's mod texture cache (`<game>\rtx-remix\cache\mod-textures\*.bin`, runtime patch 0086,
[ADR 0195](../../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md)) against the DDS files
it describes. For every entry whose file still has the size and write time the entry was made with (an entry of a
changed file is never used by the runtime and is not judged):

- the record holds the file's DDS header values (width, height, depth, mip levels, data offset, array layers), its size
  and write time, and its levels fit in the file;
- the kept smallest mips (the tail) equal, byte for byte, the file's bytes of those levels.

Each cache file's magic, version, size and FNV-1a checksum are checked first; a damaged one is reported.

```powershell
python -I tools\qa\check_mod_texture_cache.py H:\SteamLibrary\steamapps\common\GarrysMod_PoC\rtx-remix\cache\mod-textures
```

- Input: the cache folder. Reads the cache files and the DDS files they name.
- Output: JSON: `files`, `entries`, `checked`, `with_tail`, `problem_count`, `problems` (the first 50), `damaged`.
- Side effects: none.
- Exit codes: 0 when no entry has a problem and no cache file is damaged, else 1.

The file format is the one `rtx_mod_texture_store.h` writes (version 1): an 8-byte magic `NLMODTEX`, version, entry
count, payload size and FNV-1a 64 of the payload; per entry the lowercase path (UTF-16), the stamp (size, last write
time, change time, file id), the record (file size, data offset, data size, size of all levels, format, width, height,
depth, levels, layers, faces, last write time, each level's size) and the tail (first level or `0xFFFFFFFF`, its bytes).
