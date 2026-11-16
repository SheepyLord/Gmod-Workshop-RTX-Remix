# test_portal_limits.py

Regression test for review finding 5 (2026-11-16): a pasted Seamless Portals dupe with a huge side count hung the
host and every client. The portal now reads its side count and size through limits shared by every reader
(`SeamlessPortals.LimitSides` and `LimitSize`, `ENT:GetSides`, `ENT:GetSize` in `seamless_portal/sh_init.lua`) and
stores bounded values again when it is pasted (`ENT:PostEntityPaste`).

- `test_crafted_side_counts_and_sizes_stay_within_the_limits`: turns the portal entity's `sh_init.lua`, `init.lua`
  and `cl_init.lua` (GLua) into plain Lua with `glua_to_lua` from [test_glass_map.py](test_glass_map.py.md), in a
  temporary folder under `out\tmp`, and runs [portal_limits_harness.lua](portal_limits_harness.lua.md) on them with
  LuaJIT (skipped without LuaJIT): at most 200 hull points and 900 mesh vertices for side counts 2^31-1, 0, -5, NaN,
  inf and 1e300, a bounded `GetSize()` for (1e30, -1e30, NaN), the tools' and Hammer's sizes unchanged, and bounded
  stored values after a paste.

Run from `tools\`: `python -m unittest tests.test_portal_limits -v` (or `tools\test.ps1`). No game, network,
Workshop upload or profile change; scratch in `out\tmp`. Exit follows unittest.
