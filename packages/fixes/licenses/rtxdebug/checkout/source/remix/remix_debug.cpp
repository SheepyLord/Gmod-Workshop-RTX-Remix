#include "remix_debug.h"

#include "../debug_context.h"
#include "../lua_util.h"
#include "../render_policy.h"

#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/Types.h>
#include <remix/remix_c.h>
#include <tier0/dbg.h>
#include <Windows.h>

#include <cctype>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <string>
#include <vector>

static_assert(REMIXAPI_VERSION_MAJOR == 0 && REMIXAPI_VERSION_MINOR == 1000
    && REMIXAPI_VERSION_PATCH == 1,
    "RTXDebug must be built against the Remix Plus 0.1000.1 headers");

using GarrysMod::Lua::ILuaBase;

namespace RTXDebug::Remix {

namespace {

struct ConfigOverride {
    std::string key;
    std::string currentValue;
    std::string restoreValue;
    // Written through the Remix API at least once: restored through it (Policy::RestoreThroughApi).
    bool throughApi = false;
};

constexpr const char* kDebugViewKey = "rtx.debugView.debugViewIdx";
constexpr const char* kGameThreadError = "RTXDebug Remix calls require the game thread";
// RTXFixesBinary owns RemixConfig, RemixResource and RemixMaterial.
constexpr const char* kRemixModule = "gmcl_RTXFixesBinary_win64.dll";
std::vector<ConfigOverride> g_configOverrides;

// Behind the developer gate the module writes through the Remix API itself (render_policy.h,
// RouteConfig): RemixConfig.SetConfigVariable takes only the options the RTX package's own Lua
// sets. The runtime's d3d9.dll exports remixapi_InitializeLibrary, which fills an interface of
// function pointers; the module asks for it once, at its first such write. It never calls
// Startup or Shutdown: the game owns the device, RTXFixesBinary the API's use. The runtime keeps
// the most recent initialize's version for the whole process; this module is built with the
// headers RTXFixesBinary and RTX Water are built with (the patched fixes checkout's
// public/include, 0.1000.1: the static_assert above), so that version stays what they asked for.
remixapi_Interface g_api{};
bool g_apiReady = false;

bool RemixApi(std::string& error) {
    if (g_apiReady) return true;
    const HMODULE runtime = GetModuleHandleW(L"d3d9.dll");
    const auto initialize = runtime
        ? reinterpret_cast<PFN_remixapi_InitializeLibrary>(GetProcAddress(runtime, "remixapi_InitializeLibrary"))
        : nullptr;
    if (!initialize) {
        error = "the Remix runtime is not loaded (d3d9.dll has no remixapi_InitializeLibrary)";
        return false;
    }
    remixapi_InitializeLibraryInfo info{};
    info.sType = REMIXAPI_STRUCT_TYPE_INITIALIZE_LIBRARY_INFO;
    info.version = REMIXAPI_VERSION_MAKE(REMIXAPI_VERSION_MAJOR, REMIXAPI_VERSION_MINOR, REMIXAPI_VERSION_PATCH);
    remixapi_Interface api{};
    const remixapi_ErrorCode code = initialize(&info, &api);
    if (code != REMIXAPI_ERROR_CODE_SUCCESS || !api.SetConfigVariable) {
        error = "remixapi_InitializeLibrary failed (" + std::to_string(static_cast<int>(code)) + ")";
        return false;
    }
    g_api = api;
    g_apiReady = true;
    return true;
}

bool ApplyThroughApi(const std::string& key, const std::string& value, std::string& error) {
    if (!RemixApi(error)) return false;
    const remixapi_ErrorCode code = g_api.SetConfigVariable(key.c_str(), value.c_str());
    if (code != REMIXAPI_ERROR_CODE_SUCCESS) {
        error = "the Remix runtime refused the value (remixapi error " + std::to_string(static_cast<int>(code))
            + "): an unknown option or a value it cannot read";
        return false;
    }
    return true;
}

bool PushRemixFunction(ILuaBase* lua, const char* table, const char* function) {
    lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    lua->GetField(-1, table);
    lua->Remove(-2);
    if (!lua->IsType(-1, GarrysMod::Lua::Type::Table)) {
        lua->Pop();
        return false;
    }

    lua->GetField(-1, function);
    lua->Remove(-2);
    if (!lua->IsType(-1, GarrysMod::Lua::Type::Function)) {
        lua->Pop();
        return false;
    }
    return true;
}

// Calls table.function(arguments...). On success its results are on the stack.
bool CallRemix(ILuaBase* lua, const char* table, const char* function,
    std::initializer_list<const char*> arguments, int results, std::string& error) {
    if (!PushRemixFunction(lua, table, function)) {
        error = std::string(table) + "." + function + " is unavailable (is RTXFixesBinary loaded?)";
        return false;
    }
    for (const char* argument : arguments) lua->PushString(argument);
    if (lua->PCall(static_cast<int>(arguments.size()), results, 0) != 0) {
        const char* luaError = lua->GetString(-1);
        error = luaError ? luaError : "Remix call failed";
        lua->Pop();
        return false;
    }
    return true;
}

int Forward(ILuaBase* lua, const char* table, const char* function,
    std::initializer_list<const char*> arguments = {}) {
    if (!IsMainThread()) return PushError(lua, kGameThreadError);
    std::string error;
    if (!CallRemix(lua, table, function, arguments, 1, error)) return PushError(lua, error);
    return 1;
}

bool ApplyConfig(ILuaBase* lua, const std::string& key, const std::string& value, std::string& error) {
    if (!lua) {
        error = "Lua is unavailable";
        return false;
    }
    if (!CallRemix(lua, "RemixConfig", "SetConfigVariable", {key.c_str(), value.c_str()}, 1, error))
        return false;
    const bool success = lua->IsType(-1, GarrysMod::Lua::Type::Bool) && lua->GetBool(-1);
    lua->Pop();
    if (!success) {
        error = "RemixConfig refused the option or its value (the console says why); options outside its list "
            "need the developer gate: local single-player, sv_cheats 1 and -insecure";
    }
    return success;
}

// Writes or restores one value the way the ledger says it goes.
bool Apply(ILuaBase* lua, const std::string& key, const std::string& value, bool throughApi, std::string& error) {
    return throughApi ? ApplyThroughApi(key, value, error) : ApplyConfig(lua, key, value, error);
}

const char* RouteName(bool throughApi) {
    return throughApi ? "remix_api" : "remixconfig";
}

int SetSessionConfig(ILuaBase* lua, const std::string& key,
    const std::string& value, const std::string& restoreValue) {
    if (!IsMainThread()) return PushError(lua, kGameThreadError);
    if (key.empty()) return PushError(lua, "Remix option key cannot be empty");
    const Policy::ConfigRoute route =
        Policy::RouteConfig(CanMutate(), lua == Lua() && CanConfigureRendering(), key);
    if (route == Policy::ConfigRoute::Refused) {
        return PushError(lua,
            "Remix writes take an rtx.* option, in the client rendering context (RemixConfig's options) "
            "or behind the developer gate (local single-player, sv_cheats 1 and -insecure)");
    }
    const bool throughApi = route == Policy::ConfigRoute::RemixApi;

    ConfigOverride* existing = nullptr;
    for (auto& entry : g_configOverrides) {
        if (entry.key == key) {
            existing = &entry;
            break;
        }
    }
    if (existing && existing->restoreValue != restoreValue)
        return PushError(lua, "Restore value differs from the session baseline");

    std::string error;
    if (!Apply(lua, key, value, throughApi, error)) return PushError(lua, error);
    if (existing) {
        existing->currentValue = value;
        existing->throughApi = Policy::RestoreThroughApi(existing->throughApi, route);
    } else {
        g_configOverrides.push_back({key, value, restoreValue, throughApi});
    }
    Msg("[RTXDebug] Remix config %s set for this session%s\n", key.c_str(),
        throughApi ? " (through the Remix API: developer gate)" : "");
    lua->PushBool(true);
    return 1;
}

bool IsHexHash(const std::string& text) {
    size_t start = text.rfind("0x", 0) == 0 || text.rfind("0X", 0) == 0 ? 2 : 0;
    if (text.size() <= start || text.size() - start > 16) return false;
    for (size_t i = start; i < text.size(); ++i)
        if (!std::isxdigit(static_cast<unsigned char>(text[i]))) return false;
    return true;
}

LUA_FUNCTION_STATIC(RemixVram) {
    return Forward(LUA, "RemixResource", "GetVramStats");
}

LUA_FUNCTION_STATIC(RemixConfigFile) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String))
        return PushError(LUA, "ConfigFile expects an option key string");
    const std::string key = LUA->GetString(1);
    return Forward(LUA, "RemixConfig", "GetConfigVariable", {key.c_str()});
}

LUA_FUNCTION_STATIC(RemixDebugViewFile) {
    return Forward(LUA, "RemixConfig", "GetConfigVariable", {kDebugViewKey});
}

LUA_FUNCTION_STATIC(RemixSetConfig) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String)
        || !LUA->IsType(2, GarrysMod::Lua::Type::String)
        || !LUA->IsType(3, GarrysMod::Lua::Type::String)) {
        return PushError(LUA,
            "SetConfig expects key, value, and explicit restore value strings");
    }
    const std::string key = LUA->GetString(1);
    const std::string value = LUA->GetString(2);
    const std::string restoreValue = LUA->GetString(3);
    return SetSessionConfig(LUA, key, value, restoreValue);
}

LUA_FUNCTION_STATIC(RemixSetDebugView) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::Number)
        || !LUA->IsType(2, GarrysMod::Lua::Type::Number)) {
        return PushError(LUA, "SetDebugView expects index and restoreIndex integers");
    }
    const double index = LUA->GetNumber(1);
    const double restoreIndex = LUA->GetNumber(2);
    const double minimum = static_cast<double>((std::numeric_limits<int32_t>::min)());
    const double maximum = static_cast<double>((std::numeric_limits<int32_t>::max)());
    if (!std::isfinite(index) || !std::isfinite(restoreIndex)
        || std::trunc(index) != index || std::trunc(restoreIndex) != restoreIndex
        || index < minimum || index > maximum
        || restoreIndex < minimum || restoreIndex > maximum) {
        return PushError(LUA, "SetDebugView indexes must be 32-bit integers");
    }
    return SetSessionConfig(LUA, kDebugViewKey,
        std::to_string(static_cast<int32_t>(index)),
        std::to_string(static_cast<int32_t>(restoreIndex)));
}

LUA_FUNCTION_STATIC(RemixSessionConfig) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String))
        return PushError(LUA, "SessionConfig expects an option key string");
    const std::string key = LUA->GetString(1);
    for (const auto& entry : g_configOverrides) {
        if (entry.key != key) continue;
        LUA->CreateTable();
        SetString(LUA, "last_set_value", entry.currentValue);
        SetString(LUA, "restore_value", entry.restoreValue);
        SetString(LUA, "route", RouteName(entry.throughApi));
        return 1;
    }
    LUA->PushNil();
    return 1;
}

LUA_FUNCTION_STATIC(RemixOverrides) {
    LUA->CreateTable();
    int index = 1;
    for (const auto& entry : g_configOverrides) {
        LUA->CreateTable();
        SetString(LUA, "key", entry.key);
        SetString(LUA, "last_set_value", entry.currentValue);
        SetString(LUA, "restore_value", entry.restoreValue);
        SetString(LUA, "route", RouteName(entry.throughApi));
        SetArrayValue(LUA, index++);
    }
    return 1;
}

// Restoring only undoes this module's own change, so it needs no mutation gate. It goes back
// the way the value went in (render_policy.h, RestoreThroughApi).
LUA_FUNCTION_STATIC(RemixRestoreConfig) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String))
        return PushError(LUA, "RestoreConfig expects an option key string");
    if (!IsMainThread()) return PushError(LUA, kGameThreadError);
    const std::string key = LUA->GetString(1);
    for (auto it = g_configOverrides.begin(); it != g_configOverrides.end(); ++it) {
        if (it->key != key) continue;
        std::string error;
        if (!Apply(LUA, it->key, it->restoreValue, it->throughApi, error)) return PushError(LUA, error);
        Msg("[RTXDebug] Restored Remix config %s\n", it->key.c_str());
        g_configOverrides.erase(it);
        LUA->PushBool(true);
        return 1;
    }
    return PushError(LUA, "No session override exists for this key");
}

LUA_FUNCTION_STATIC(RemixMaterialHashes) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String))
        return PushError(LUA, "MaterialHashes expects a material name string");
    const std::string material = LUA->GetString(1);
    return Forward(LUA, "RemixMaterial", "GetAllTextureHashes", {material.c_str()});
}

LUA_FUNCTION_STATIC(RemixTrackedTextures) {
    return Forward(LUA, "RemixMaterial", "DumpAllTextureHashes");
}

// Reverse lookup: the materials that own a Remix texture hash.
LUA_FUNCTION_STATIC(RemixFindMaterialByHash) {
    if (!IsMainThread()) return PushError(LUA, kGameThreadError);
    if (!LUA->IsType(1, GarrysMod::Lua::Type::String) || !IsHexHash(LUA->GetString(1)))
        return PushError(LUA, "FindMaterialByHash expects a hex hash string such as 0x1A2B3C4D5E6F7788");
    const std::string hash = LUA->GetString(1);
    std::string error;
    if (!CallRemix(LUA, "RemixMaterial", "FindMaterialByHash", {hash.c_str()}, 2, error))
        return PushError(LUA, error);
    // [materials, revision] -> {materials = ..., revision = ...}
    LUA->CreateTable();
    LUA->Insert(-3);
    LUA->SetField(-3, "revision");
    LUA->SetField(-2, "materials");
    return 1;
}

LUA_FUNCTION_STATIC(RemixHashStats) {
    return Forward(LUA, "RemixMaterial", "GetMaterialHashStats");
}

LUA_FUNCTION_STATIC(RemixExpectedApiVersion) {
    LUA->PushString("0.1000.1");
    return 1;
}

} // namespace

bool Register(ILuaBase* lua) {
    if (!lua || !lua->IsType(-1, GarrysMod::Lua::Type::Table)) return false;

    lua->CreateTable();
    AddFunction(lua, "Vram", RemixVram);
    AddFunction(lua, "ConfigFile", RemixConfigFile);
    AddFunction(lua, "DebugViewFile", RemixDebugViewFile);
    AddFunction(lua, "SetConfig", RemixSetConfig);
    AddFunction(lua, "SetDebugView", RemixSetDebugView);
    AddFunction(lua, "SessionConfig", RemixSessionConfig);
    AddFunction(lua, "Overrides", RemixOverrides);
    AddFunction(lua, "RestoreConfig", RemixRestoreConfig);
    AddFunction(lua, "MaterialHashes", RemixMaterialHashes);
    AddFunction(lua, "TrackedTextures", RemixTrackedTextures);
    AddFunction(lua, "FindMaterialByHash", RemixFindMaterialByHash);
    AddFunction(lua, "HashStats", RemixHashStats);
    AddFunction(lua, "ExpectedApiVersion", RemixExpectedApiVersion);
    lua->SetField(-2, "Remix");
    return true;
}

size_t ActiveOverrides() {
    return g_configOverrides.size();
}

int RestoreAll(ILuaBase* lua, std::vector<std::string>& failures) {
    int restored = 0;
    for (auto it = g_configOverrides.rbegin(); it != g_configOverrides.rend(); ++it) {
        std::string error;
        if (Apply(lua, it->key, it->restoreValue, it->throughApi, error)) {
            Msg("[RTXDebug] Restored Remix config %s\n", it->key.c_str());
            ++restored;
        } else {
            failures.push_back("Remix config " + it->key + ": " + error);
        }
    }
    g_configOverrides.clear();
    return restored;
}

void Shutdown(ILuaBase* lua) {
    if (g_configOverrides.empty()) return;
    // The companion addon restores overrides from the ShutDown hook. If some
    // are left, RemixConfig can only be called while RTXFixesBinary is loaded:
    // after its own close it no longer has a config manager. A value written
    // through the Remix API goes back through it: the API is the runtime's.
    const bool remixConfig = lua && GetModuleHandleA(kRemixModule);
    for (auto it = g_configOverrides.rbegin(); it != g_configOverrides.rend(); ++it) {
        if (!it->throughApi && !remixConfig) {
            Warning("[RTXDebug] Remix config %s was not restored (RTXFixesBinary is gone); "
                "it stays at '%s' until the game restarts\n",
                it->key.c_str(), it->currentValue.c_str());
            continue;
        }
        std::string error;
        if (Apply(lua, it->key, it->restoreValue, it->throughApi, error))
            Msg("[RTXDebug] Restored Remix config %s\n", it->key.c_str());
        else
            Warning("[RTXDebug] Failed to restore Remix config %s: %s\n", it->key.c_str(), error.c_str());
    }
    g_configOverrides.clear();
}

} // namespace RTXDebug::Remix
