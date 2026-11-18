#pragma once
// ADR 0246: the companion's client prelude. The engine starts each client realm's Lua with
// ILuaInterface::FindAndRunScript("includes/init.lua", ...) (client.dll), before any other Lua runs there; on a remote
// server even that file is the server's copy. Hooked once per process in the vtable every Lua state shares, that call
// first hands the realm to a runner (the module runs the companion's verified prelude scripts), then goes on as before.
// No Garry's Mod header is needed here: a state is the engine's ILuaInterface, passed through as it is.
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace nl::client::prelude {
// The companion's prelude scripts in the catalog: direct children of this folder, run in name order.
inline constexpr std::string_view kScripts = "nativeloader/nativeloader/prelude/";
// The first script the engine runs in a realm.
inline constexpr std::string_view kInit = "includes/init.lua";
// ILuaInterface's vtable slots in Garry's Mod x64, in the vendored header's order (third_party/gmod): IsClient,
// FindAndRunScript (client.dll calls [vtable+0x308] with "includes/init.lua") and RunStringEx. The tests check them
// against the header.
inline constexpr std::size_t kIsClientSlot = 76;
inline constexpr std::size_t kFindAndRunScriptSlot = 97;
inline constexpr std::size_t kRunStringExSlot = 111;
// The raw global set in the realm while its prelude runs, so a script knows the module ran it.
inline constexpr const char* kMarker = "__NATIVELOADER_CLIENT_PRELUDE";

// Called with the state whose includes/init.lua is about to run, any realm's; true when it ran the prelude there.
// It must not throw.
using Runner = bool (*)(void* state) noexcept;

// Whether a FindAndRunScript call starts a realm: the engine runs includes/init.lua.
bool starts_realm(const char* filename, bool run) noexcept;
// Whether a catalog key is a prelude script: a direct child of kScripts ending in .lua.
bool is_prelude_script(std::string_view key) noexcept;

// Whether `code`, mapped at `code_address`, loads `string_address` as the file name (`lea rdx, [rip+disp32]`) and then,
// within 64 bytes, calls the FindAndRunScript slot (`call qword ptr [reg+0x308]`): how client.dll starts a realm.
bool calls_through_slot(std::span<const unsigned char> code, std::uintptr_t code_address,
                        std::uintptr_t string_address) noexcept;
// Only where sure, for the engine's side: the loaded module `client` (client.dll) holds "includes/init.lua" in its data
// and calls the FindAndRunScript slot with it from its code (calls_through_slot), so the slot hooked is the one that
// starts a realm in this build. Returns an empty string, or why not.
std::string confirm_engine_call(const void* client) noexcept;

// Hooks FindAndRunScript in the vtable of `state` (any of the engine's Lua states: they share CLuaInterface's), once
// per process; later calls only replace the runner. Only where sure: the vtable must lie in `module`'s image outside
// its executable sections, and the IsClient, FindAndRunScript and RunStringEx slots must point into its executable
// sections. The caller confirms the engine's call first (confirm_engine_call). Returns an empty string, or why nothing
// was changed.
std::string install(const void* state, const void* module, Runner runner) noexcept;
// Whether the hook is in place, and how many times the runner ran a prelude.
bool installed() noexcept;
unsigned runs() noexcept;
}
