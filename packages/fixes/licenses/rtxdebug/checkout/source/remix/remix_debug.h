#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace GarrysMod::Lua {
class ILuaBase;
}

namespace RTXDebug::Remix {

// The RTXDebug table must be at the top of the Lua stack.
bool Register(GarrysMod::Lua::ILuaBase* lua);

// Session overrides that still have to be restored.
size_t ActiveOverrides();

// Restores every session override the way it was written: through RemixConfig
// (call it while RTXFixesBinary is still loaded) or, for a value written behind
// the developer gate, through the Remix API. Returns how many were restored and
// appends a message for each one that could not be.
int RestoreAll(GarrysMod::Lua::ILuaBase* lua, std::vector<std::string>& failures);

// Module close: restores what is left; RemixConfig's values only if
// RTXFixesBinary is still usable, the Remix API's in any case.
void Shutdown(GarrysMod::Lua::ILuaBase* lua);

} // namespace RTXDebug::Remix
