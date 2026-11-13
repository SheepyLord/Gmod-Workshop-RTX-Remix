# test_mod_texture_cache.py

The regression test of the mod texture cache (runtime patch 0086,
[ADR 0195](../../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md)): a later start of the
game reads no unchanged texture file of a USD mod again, and any change is read. Part of `tools\test.ps1` (the
`tools` folder's Python tests).

- `StoreTests.test_store_unit_test_from_the_patch`: takes `rtx_mod_texture_store.h` and
  `tests/rtx/unit/test_mod_texture_store.cpp` whole from the committed patch, compiles them with MSVC
  (`/std:c++17 /W4 /WX`, as the runtime builds) under `out\tmp` and runs the test. It checks, with real files: a first
  load reads every file and writes the cache; a second reads none and gives the same records and bytes and writes
  nothing; new content of the same size with the old write time put back, a file replaced by an identical one (another
  file id), and a file with two hard links are read again (the last never kept); unused entries are dropped; a tail too
  large is used but not kept; a damaged, shortened, other-version or other-magic cache file is ignored and rewritten; an
  unwritable cache folder fails the save only. Skipped without the MSVC Build Tools.
- `StoreTests.test_the_mod_loader_uses_the_store`: the patch routes every texture of a mod's first load through the
  cache (`m_textureCache->find`), writes it at the end of the load, makes cached assets with `restoreDdsAsset`, keeps the
  option on by default, builds the new source, and the store compares all four stamp fields and refuses hard-linked
  files.
- `CheckerTests`: [check_mod_texture_cache.py](../qa/check_mod_texture_cache.py.md) passes a right entry for a
  synthetic DDS, finds a wrong tail and a wrong header, leaves a changed file's entry alone and reports a damaged file.
- `LogTests`: [mod_load_session.py](../qa/mod_load_session.py.md) reads the runtime's `[RTX Mod Load]` and
  `[RTX Mod Texture Cache]` lines.

```powershell
cd tools; python -m unittest tests.test_mod_texture_cache -v
```

Exit code: unittest's (0 when every test passes or is skipped).
