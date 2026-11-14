# test_loading_status.py

R24 ([ADR 0134](../../docs/decisions/0134-what-a-map-load-is-doing.md)), with
[ADR 0214](../../docs/decisions/0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md) and
[ADR 0215](../../docs/decisions/0215-the-loads-estimate-learned-from-the-loads-before.md): unit tests of the companion's
menu script `companion/nativeloader/lua/nativeloader/menu/loading_status.lua`, which drives the engine guard's load
overlay from the menu's loading state, keeps it up after the engine's load until the game runs steadily, and learns
the load's estimate from the loads before.

- `LoadingStatusTests` runs [`loading_status_harness.lua`](loading_status_harness.lua.md) under LuaJIT, one scenario per
  test (two for the settling phase's interruptions, two for "no module" and "not the menu"; skipped without LuaJIT).
- `GModSyntaxTests` reads every companion menu script for `continue` used as a name (`x.continue`, `continue = ...`,
  `[continue]`): GMod's Lua makes it a keyword, so such a script compiles under LuaJIT but not in the game, as the R24
  notice's text table did before this check. A self-test proves the check finds that mistake and allows `continue` as
  a statement and in longer names.

Usage: `python -I -m unittest discover -s tools\tests -p test_loading_status.py` (or the whole suite through
`tools\test.ps1`). No side effects; exit status is unittest's.
