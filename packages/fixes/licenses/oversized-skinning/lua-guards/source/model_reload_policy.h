// GPL-2.0, like the rest of the RTX fixes. The native loader's review of 2026-11-16 (finding 24): when
// RTX_ReloadModelsAfterHardwareSkinningSettings may discard studiorender's hardware meshes
// (MDLCACHE_FLUSH_STUDIOHWDATA). Under queued rendering the material system's own thread may be drawing
// those meshes at that moment: about half of the native loader's PoC starts crashed in studiorender until
// cl_rtx.lua switched mat_queue_mode to 0 for its last call (review R4). Any Lua can call the global, so the
// flush now runs only while the material system draws on the calling thread, and at most twice in one
// client Lua state (one map): the two calls cl_rtx.lua makes, after the hardware-skinning setting is
// restored and once the map has loaded. A refused call is not counted. No SDK and no Windows header:
// tests/model_reload_policy_test.cpp compiles this file alone.
#pragma once

#include <string>

namespace ModelReloadPolicy {

constexpr int ReloadsPerLuaState = 2;

class Allowance {
public:
    // A new client Lua state: the module opens again for each map.
    void Reset() { m_used = 0; }

    // Whether the flush may run now (singleThreaded: the material system's thread mode is
    // MATERIAL_SINGLE_THREADED); counts the flush when it may.
    bool Take(bool singleThreaded, std::string* reason = nullptr) {
        if (!singleThreaded) return Refuse(reason, "the material system renders on its own thread (queued rendering)");
        if (m_used >= ReloadsPerLuaState) return Refuse(reason, "this map's two model reloads have run");
        ++m_used;
        return true;
    }

    int Used() const { return m_used; }

private:
    static bool Refuse(std::string* reason, const char* why) {
        if (reason) *reason = why;
        return false;
    }
    int m_used = 0;
};

}  // namespace ModelReloadPolicy
