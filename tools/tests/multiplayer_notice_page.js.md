# multiplayer_notice_page.js

Runs the page's half of the companion's multiplayer notice (the `PAGE` string of
`companion/nativeloader/lua/nativeloader/menu/multiplayer_notice.lua`, R24) under Node against a mocked Angular
menu page: `$rootScope.$on('$locationChangeStart')`, `$location`, the menu's `lua.Run` bridge and the loader's
`NativeLoaderReceiveMenuState` with its session token.

Usage: `node multiplayer_notice_page.js <path to multiplayer_notice.lua>`. Checks that a route to the server browser
waits and asks the menu Lua, that `go()` lets one navigation through, that other routes are untouched, that a second
install keeps one listener and follows the off switch, that the loader's notice is told the choice with its own
token and the update reminder's fields, and that no click is swallowed (a failing `lua.Run` lets the browser open; an
overlong target is not held). Prints `PASS page`, `PASS without-loader-notice`, `PASS update-seen`,
`PASS never-swallowed`; exits 1 on the first failure. Reads only the Lua file. Run by [`test_multiplayer_notice.py`](test_multiplayer_notice.py.md).
