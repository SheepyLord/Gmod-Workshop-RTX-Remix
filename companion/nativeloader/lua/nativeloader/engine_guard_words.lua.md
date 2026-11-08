# engine_guard_words.lua

R23 ([ADR 0130](../../../../docs/decisions/0130-an-engine-guard-for-lua-start-up.md)): the start-up watchdog's
message for the engine guard's native message box, in the player's language. Shared; the server sends it
with the other shared rules ([`nativeloader_i18n.lua`](../autorun/nativeloader_i18n.lua.md)).

```lua
local words = include("nativeloader/engine_guard_words.lua")
local title, body = words()   -- body has one %s for the stuck file
```

- The English text is marked with `N("...")`, so [`tools/companion_i18n.py`](../../../../tools/companion_i18n.py.md)
  extracts it into the catalogs like any other companion text.
- The language: `nativeloader_language` when set, else `gmod_language` (`zh`, `zh-cn`, `zh-tw` mapped as the
  companion maps them). English returns the text as it is, without reading the catalog.
- Otherwise it includes the companion's catalog, `nativeloader/i18n_data.lua`, and takes the two strings
  (a translation without `%s` keeps the English body). This works where `nativeloader/i18n.lua` cannot: the
  server realm (no `CreateClientConVar`) and the early view of `includes/init.lua`. On a remote server the
  include fails (the server sent no such file) and the caller keeps the module's English.
- Never words from `garrysmod/data`: any server's client Lua can write there, and the message is a native,
  topmost dialog.

Callers: [`!!!!nativeloader_engine_guard.lua`](../autorun/!!!!nativeloader_engine_guard.lua.md) and the early
view in [`_nativeloader_guard.lua`](../autorun/_nativeloader_guard.lua.md). Tested by
[`tools/tests/test_engine_guard_lua.py`](../../../../tools/tests/test_engine_guard_lua.py.md).
