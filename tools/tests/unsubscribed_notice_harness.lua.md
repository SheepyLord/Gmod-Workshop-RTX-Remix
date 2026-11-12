# unsubscribed_notice_harness.lua

Runs the companion's real
[`nativeloader/menu/unsubscribed_notice.lua`](../../companion/nativeloader/lua/nativeloader/menu/unsubscribed_notice.lua.md)
([ADR 0188](../../docs/decisions/0188-unsubscribing-with-the-loader-already-installed.md)) under LuaJIT in a mocked menu
realm: the loader's start-up report (`file.Read` of `native-loader/status.json` and `util.JSONToTable`), the account's
subscriptions (`engine.GetAddons`, optionally `steamworks.IsSubscribed`), `hook.Add`, `timer.Create` and
`timer.Simple` (run by the harness's `tick`), menu cookies, convars, the module's read API (a small Japanese catalog)
and Derma panels whose `Paint` functions record the text they draw.

```text
luajit tools\tests\unsubscribed_notice_harness.lua <repo> <scenario>
```

Scenarios: `subscribed`, `not-subscribed`, `waits-for-the-list`, `growing-list`, `steam-says-subscribed`, `dismissed`,
`dismiss-button`, `resubscribed`, `local-source`, `no-status`, `translation`, `failure`, `not-menu`. Each prints
`PASS <scenario>` and exits 0, or raises an error (exit 1) naming what differed. It reads the script and writes nothing.
Run by [`test_unsubscribed_notice.py`](test_unsubscribed_notice.py.md).
