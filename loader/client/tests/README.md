# loader/client/tests

`test_module.cpp` checks the `poll.h` throttle and attempt bound, and reads `module.cpp` (its path is
a compile definition) for the contracts a unit test cannot reach without a game: no field access
on the client realm, the temporary API raw-set inside the protected initializing step, Poll only
pushing and protect-calling that step, and the self-pin before the Think hook hands out callbacks. R24: the menu
scripts' read API answers only in the menu realm and only for the companion's catalog entries, only direct
children of `nativeloader/menu/` run, the API is removed after them, and they run once after the pin, never from Poll;
and the module takes the menu's part only in the engine's own menu state (`GetLuaInterface(State::MENU)`), checked
before `menu` is set (the R24 review: `MENU_DLL` alone can be set by any realm's Lua).

`test_former_rtx.cpp` (ADR 0188) checks which files count as the RTX package's former files; that originals' kept
copies move into `native-loader/backup/former-rtx/<stamp>/` with an `index.json` while the rest stays; that adopted
files move from the game only when unchanged, never mid-transaction and once; that nothing moves while
`native-loader/lock` is held; that no other game runs from a scratch folder; and, through the real deployer
(`nl::deploy::apply`, `nl::deploy::uninstall`), that after the archive the uninstall leaves the add-on and `lua/bin`
paths empty, puts a Remix mod's original back and keeps the archived files, and that an earlier copy which was partly
adopted, partly an original is gone after archive, release, a second deployment (the package's own copy, no longer
adopted) and the uninstall. `test_module.cpp` adds that the originals move only after the catalog is verified and
before the callbacks, and the adopted files only from `GMOD_MODULE_CLOSE`, without a client realm or another game.

`test_leftovers.cpp` (ADR 0206) checks, through the real deployer, that the loader counts as installed while `bin/win64/winmm.dll` is in the folder; that nothing happens without the loader's journal or without the RTX package in it (another package's journal stays); that with the loader gone `remove_leftovers` leaves no file of the package at its paths and removes the journal and the lock, puts the player's own Remix mod back, archives an earlier RTX installation's original and adopted files in `former-rtx`, moves the binary module the test holds mapped as an image (Windows refuses to delete it) to `native-loader/backup/in-use/<stamp>/` with an index and finishes the uninstall, returns the console setting the player had not changed since and marks the record; and that another deployment's lock leaves everything as it was, until it is free. It also checks `another_game`: a copy of Windows' `ping.exe` named the fixture's `gmod.exe` and started by the test
(as the game starts its Chromium helpers) is not another game; one started through a `cmd.exe` that ends at once, so
that it does not descend from the test, is. `test_module.cpp` adds that a server realm gets only `NativeLoaderLeftovers`, raw, acting for that state, the module's own folder and this process's `gmod.exe`, with no path from Lua.

`test_addon_list.cpp` (ADR 0189) checks the add-on list writer against GMod's own file byte for byte (and the
loader's reader of it), a missing list and one written on one line, refusals of other files, bad ids and links, and,
through the real deployer with a Workshop fixture, that the RTX item in the list removes the package at the next start
and that it comes back once the entry is out. `test_steam_switch.cpp` reads Steam's per-account list layout (enabled,
switched off, not listed, not Steam's list) and finds it per account below a Steam folder. `test_module.cpp` adds that
both menu functions act on the verified RTX item only, in the menu realm.

`test_catalog.cpp` exercises the actual `catalog::prepare` policy in synthetic game folders under
the test build's scratch directory. `CMakeLists.txt` builds `nl_client_catalog_tests` with the
existing `loader/tests/test_main.cpp` / `nl_test.h` harness. No game, network, real install, or user
configuration is opened.

Cases cover exact RTX package/source ownership, local/dev-folder/Workshop allowlists, unrelated
files and add-ons, disabled policy, module binding, byte/size/NUL limits, missing files, case
collisions, junctions and immutable snapshots. Committed-journal parsing is checked separately for
unsafe paths, preserving the loader's existing path and protected-folder rules. Junction creation
uses a generated directory and is skipped if the platform refuses it; the target is never followed
during cleanup.

The secure-render policy cases use independent copies of the seven shipped recipe specifications,
not accepted digest values. They require the exact owner/module/name/find/offset/replace fields,
and reject altered ordering, additional patches and every proper subset. The separate config
suite checks the opt-out's boolean type and that it does not alter native allowlists or the general
insecure patch gate. The render-recipe refusal cases (ADR 0056) require activation to fall back
exactly when the opt-out leaves the reviewed recipes skipped: no `-insecure` on the command line
(case-insensitive, quoted values excluded) or in the plan's own arguments, and the general gate
closed. Other owners, changed recipes or no patch sets never refuse.

Build with `cmake --build --preset win64-release --target nl_client_catalog_tests`, then
`ctest --test-dir out/build/win64-release -R ^nl_client_catalog_tests$ --output-on-failure`.

`test_prelude.cpp` (ADR 0246) checks the client prelude hook against a stand-in Lua state, an object whose vtable lies in
this test executable's data and whose 128 slots are distinct functions of its code: calls through the vendored
`ILuaInterface` header land in the slots `prelude.h` names (IsClient 76, FindAndRunScript 97 at `0x308`, RunStringEx
111); which calls start a realm and which catalog keys are prelude scripts; refusals (no state, module or runner, a
module that is not an image, a vtable on the heap, a slot that points at data) change nothing; once installed, the
runner gets the state before the engine's `includes/init.lua` and the engine's function then gets the same arguments and
gives its answer back, other files and calls that do not run reach the engine alone, a runner that ran nothing is not
counted, and a second install keeps one hook and only replaces the runner; `calls_through_slot` finds client.dll's call (`lea rdx` naming the file, then `call [reg+0x308]` within 64 bytes: rax, rcx, r9 with its REX byte) and refuses another slot, a call too far away, another string, another register and a SIB form; `confirm_engine_call` refuses a missing module and a buffer that is not an image, and, where `NL_CLIENT_DLL` names a real `client.dll`, finds the call in it (mapped as an image resource, never run). `test_module.cpp` adds that the prelude runs
only in a client realm of a verified start, only the catalog's prelude scripts, with the marker raw-set while they run,
and that the hook goes in from the engine's own menu state after verification and the pin, never from `Poll`.
