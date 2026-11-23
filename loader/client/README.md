# loader/client

Native client-payload support for this project's allowlisted RTX package. It does not change
sv_allowcslua, widen the native source allowlist, or create a general source-execution API.

| File | Purpose |
|---|---|
| `catalog.h`, `catalog.cpp` | Validate the enabled RTX owner/source, bind the bootstrap module to its journaled SHA-256, and snapshot only owned add-on Lua whose exact bytes match the committed generation |
| `module.cpp` | Menu-realm module entry, active-owned-runtime and committed-journal checks, the companion's menu scripts (R24), client-realm lifecycle polling, private catalog callbacks, completion/status and cleanup. From loader 0.10.1 every client-realm access is raw and runs inside one protected call on that realm, the temporary API is raw-set, and the module pins itself while its callbacks stay reachable ([ADR 0056](../../docs/decisions/0056-guard-and-startup-fallbacks.md)) |
| `former_rtx.h`, `former_rtx.cpp` | [ADR 0188](../../docs/decisions/0188-unsubscribing-with-the-loader-already-installed.md): the RTX package's former files below `garrysmod/addons/` and `garrysmod/lua/bin/` (an earlier RTX installation) into `native-loader/backup/former-rtx/<UTC stamp>/` with an `index.json`, under the deployer's lock: in a verified RTX start the originals from `native-loader/backup/originals` (`archive_former_rtx`), at the end of the session the adopted files from the game (`release_adopted`); `another_game_running` (`-multirun`) |
| `leftovers.h`, `leftovers.cpp` | [ADR 0206](../../docs/decisions/0206-rtx-a-removed-loader-left-removes-itself.md): RTX a removed loader left in the game. `loader_installed` (`bin/win64/winmm.dll` in the folder, or this process's `winmm.dll` loaded from there), `another_game` (another Garry's Mod of the folder, this game's own Chromium helpers left out), `leftovers_refusal` and `remove_leftovers`: an interrupted deployment undone, ADR 0188's two moves, `deploy::uninstall` with this process excluded from its game check, files the game holds open moved to `native-loader/backup/in-use/<UTC stamp>/` (`set_aside_in_use` in `former_rtx.cpp`) and a second uninstall, and the console settings to put back, planned as the loader plans them |
| `addon_list.h`, `addon_list.cpp` | [ADR 0189](../../docs/decisions/0189-steams-per-account-switch-turns-rtx-off.md): adds a Workshop item to GMod's list of disabled add-ons, `garrysmod/cfg/addonnomount.txt` (what the installed loaders read), or removes it, keeping every other byte; GMod's layout for a missing file; refuses a file that is not GMod's list, a link, an id that is not digits |
| `steam_switch.h`, `steam_switch.cpp` | ADR 0189: an item's state in the signed-in account's own Steam list, `<Steam>\userdata\<account>\ugc\4000_subscriptions.vdf` (enabled, `disabled_locally`, not listed), Steam's folder and the account from the registry with advapi32 loaded at run time |
| `disk_space.h`, `disk_space.cpp` | [ADR 0260](../../docs/decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md): `package_footprints` (per package of a generation, the bytes of its payload folder and of its other files, from the journal; sums saturate) and `drive_space` (the free and total bytes of the volume that holds the game folder, `GetDiskFreeSpaceExW` as the loader measures, and its drive letter), for the companion's menu notice about disk space |
| `poll.h` | The polling policy: a client-realm check at most every 250 ms, and at most 480 initializer runs (two minutes) for a realm whose local player never becomes valid |
| `prelude.h`, `prelude.cpp` | [ADR 0246](../../docs/decisions/0246-the-directx-level-servers-see.md): the client prelude hook. `install` puts it into `ILuaInterface::FindAndRunScript`'s slot (97) of the vtable the engine's Lua states share, once per process, only where sure (`confirm_engine_call`: `client.dll` names `includes/init.lua` and calls slot 97 with it, `lea rdx` then `call [reg+0x308]` within 64 bytes, so the slot is the one that starts a realm in this build; the vtable in `lua_shared.dll`'s data, the IsClient, FindAndRunScript and RunStringEx slots in its code); the hook hands a realm to the module's runner right before the engine runs its `includes/init.lua`, then calls the engine's function with the same arguments. `starts_realm`, `is_prelude_script`, `calls_through_slot`, `installed`, `runs` |
| `bootstrap.lua` | Private client initializer: scoped include/require/file helpers, shared/client autoruns, client entity registration and owned initialization-hook replay |
| `bootstrap.lua.md` | Initializer behavior and side effects |
| `bootstrap_data.h.in` | CMake embedding template for the initializer |
| `CMakeLists.txt` | Static catalog library, native module, script embedding and test targets |
| `tests/` | Synthetic catalog policy, polling-policy and module source-contract checks; see [tests/README.md](tests/README.md) |

R24 ([ADR 0133](../../docs/decisions/0133-the-multiplayer-notice-in-the-companion.md)): once verified, the module runs
the companion's menu scripts, the catalog's `nativeloader/nativeloader/menu/*.lua` (direct children only, in name
order), once in the menu realm, where Workshop add-ons' Lua never runs. While they run,
`__NATIVELOADER_MENU_API.read(name)` returns a verified file of the companion add-on (`nativeloader/...` keys only)
and `identity` the manifest digest, and `disk_space()` the game drive's free space and each deployed package's size
(ADR 0260); the global is removed afterwards, and `read` answers only in the menu realm. The
multiplayer notice is one such script, so its text and behaviour change with the package, not the loader. The status
line ends with `menu scripts <n>` (how many ran without an error). The module takes the menu's part only in the
engine's own menu Lua state (`lua_shared`'s `GetLuaInterface(MENU)`): any realm's Lua can set `MENU_DLL`, and a
listen server's realm that passed for the menu would have taken over the catalog and ended it when it closed (the R24
review).

ADR 0246: the client prelude. On a remote server a client realm runs the server's copy of `includes/init.lua`, then the
server's autoruns, so the loader's early view (a local file's view) never reaches it, and the verified client bootstrap
above runs only once that realm has a gamemode and a valid local player, after the server's checks at `InitPostEntity`.
Once verified, after its menu scripts, the module hooks `ILuaInterface::FindAndRunScript` (client.dll starts each
realm with `call [vtable+0x308]` and `"includes/init.lua"`) through the menu state's vtable, which every Lua state
shares, only once it has found that very call in the loaded `client.dll` (a game update that moves the slot leaves the
prelude off, and the render guard's fallback takes over). When the engine is about to run a client realm's `includes/init.lua` (`IsClient()`, in any game of this
verified start, local or remote), the companion's verified `lua/nativeloader/prelude/*.lua` (catalog keys
`nativeloader/nativeloader/prelude/<name>.lua`, direct children, name order) run there first through `RunStringEx`,
chunk `@lua/nativeloader/prelude/<name>.lua`, with the raw global `__NATIVELOADER_CLIENT_PRELUDE` true while they run;
then the engine's call goes on unchanged. Other realms and other files pass straight through. No new Lua API, and no
source but those verified files. The status line ends with `client prelude hooked` (or `not hooked:` and why), and
`NativeLoaderRTXClient.Status()` has `prelude` and `prelude_runs`. The one prelude script is the DirectX level a
server sees ([`dxlevel.lua`](../../companion/nativeloader/lua/nativeloader/prelude/dxlevel.lua.md)).

ADR 0188: the module also takes the RTX package's former files out of the game. When the package was first deployed
over files already at its add-on and `garrysmod/lua/bin` paths (an earlier RTX deployment whose journal was lost, a
classic install), the loader kept the ones that differed as originals to put back when the package goes (ADR 0035) and
adopted the identical ones, which it never deletes; without the runtime their Lua fails (`remixbinary` requiring
`RTXFixesBinary`, the field on 2026-11-11). Once verified, before its menu scripts, the module moves the originals'
kept copies into `native-loader/backup/former-rtx/<UTC stamp>/`; the status line says how many and where. When the
menu state closes with the game, and only if no client realm is left and no other gmod.exe of the folder runs, it
moves the adopted ones into `.../<UTC stamp>-adopted/`; the next start installs the package's copies as the loader's
own. Both hold `native-loader/lock` (nothing moves while a deployer holds it), never copy or delete, and never write
the journal: at the uninstall the loader notes that an original is gone, drops the records of adopted files that are
gone, and leaves the paths empty. Files of other packages, and Remix mods or data, stay as the loader keeps them.

ADR 0189: two more functions of the menu API, for the companion's `unsubscribed_notice.lua`, act only on the RTX
package's own Workshop item from the verified journal (never an id or path from Lua) and only in the engine's menu
state: `rtx_steam_state()` reads the signed-in account's switch in Steam ("disabled", "enabled", "not listed"), and
`rtx_addon_list(off)` writes the item into GMod's `garrysmod/cfg/addonnomount.txt` (true) or takes out the entry
this session wrote (false), so a switched-off RTX is removed at the next start by the installed loaders.

ADR 0206: in the engine's server state (a local game; `GetLuaInterface(State::SERVER)`), the module takes no menu part. It only publishes `NativeLoaderLeftovers`, raw: `Check()` (true, or false and why) and `Remove()` (a table: `outcome`, the counts, the archive folders, `notes`, `error`, and `restore`, the console settings `{name, value}` for the caller to set). Both act only for that state, only when the module sits at its deployed path in a folder whose `bin/win64/gmod.exe` is this process, and take nothing from Lua. The companion's `autorun/server/nativeloader_leftovers.lua` calls them when the loader is gone: the loader's own uninstall then runs from inside the game, so a player who deleted `winmm.dll` before the unsubscribe took effect gets a plain game after one local game and a restart.

The module consumes the existing protected native-loader journal and config through nl_core.
Catalog preparation expects a validated committed generation; normal use refuses absent/pending
journals, disabled policy and an active renderer that is not the package's deployed runtime.
Only package gmod-rtx-remix is accepted. Local and development sources must match their own
allowlist entries; Workshop loading is limited to distribution item 3829070317.

R20-A exposes the same `allowed_runtime_source` check to the loader release-record reader, so menu
announcements cannot obtain a broader native source policy than the client bootstrap.

Catalog keys identify an add-on and virtual Lua path. Callback reads are exact map lookups into an
immutable verified snapshot, not arbitrary filesystem reads. Source is limited to 2 MiB per file
and 64 MiB total, with NUL text and case-colliding keys refused. Generic developer automation
rtx_agent and mmdhl/debug.lua is excluded from this multiplayer path. Other community files and
server code remain subject to the original engine APIs.

`secure_render_patch_set` recognizes only the exact SHA-256 fingerprints of the seven reviewed
rendering fixes emitted by tools/package_fixes.py and only for gmod-rtx-remix. Changing a recipe,
adding/removing a patch or using another owner cannot inherit the secure-render exception.
Other memory patches retain their general insecure gate, and config can disable this exception.

The Garry's Mod interface headers are vendored separately under third_party/gmod with their
BSD-3-Clause notice. Build with the normal tools/build.ps1 flow. Development/build/test scratch
belongs under the repository's out directory; no build step installs into a real game.
