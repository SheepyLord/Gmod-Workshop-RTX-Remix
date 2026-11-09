# test_multiplayer_notice.py

R24 ([ADR 0133](../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)): unit tests of the
companion's multiplayer notice, `companion/nativeloader/lua/nativeloader/menu/multiplayer_notice.lua`.

- `MultiplayerNoticeMenuTests` runs [`multiplayer_notice_harness.lua`](multiplayer_notice_harness.lua.md) under
  LuaJIT, one scenario per test (skipped without LuaJIT).
- `MultiplayerNoticePageTests` runs [`multiplayer_notice_page.js`](multiplayer_notice_page.js.md) under Node
  (skipped without Node).

Usage: `python -I -m unittest discover -s tools\tests -p test_multiplayer_notice.py` (or the whole suite through
`tools\test.ps1`). No side effects; exit status is unittest's.
