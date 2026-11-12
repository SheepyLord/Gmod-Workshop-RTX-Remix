# test_unsubscribed_notice.py

Python unit tests for the companion's notice for a Steam account that does not subscribe to the RTX package
([ADR 0188](../../docs/decisions/0188-unsubscribing-with-the-loader-already-installed.md)). Each test runs one scenario
of [`unsubscribed_notice_harness.lua`](unsubscribed_notice_harness.lua.md) under LuaJIT (on `PATH`, or
`%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`) and expects `PASS <scenario>`; without LuaJIT they are skipped.

What they hold: a subscribed account sees nothing; an account that does not subscribe sees the card once, naming the
item; nothing is decided while the menu's list of subscriptions is empty or still growing; `steamworks.IsSubscribed`
counts as a second opinion; "Don't show this again" and the console commands; subscribing again in the menu; nothing
for a local source or without the loader's report; the translated text with the item's id in it; a card that cannot be
built is only logged; nothing outside the menu realm.

```powershell
python tools\tests\test_unsubscribed_notice.py
```

Run by `tools\test.ps1` with the other Python tests. Writes nothing. Exit code 0 when every test passes or is skipped.
