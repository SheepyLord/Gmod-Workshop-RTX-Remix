// GPL-2.0. The native loader's review of 2026-11-16 (finding 24): regression for source/model_reload_policy.h,
// when RTX_ReloadModelsAfterHardwareSkinningSettings may discard studiorender's hardware meshes. Compiles alone
// (no SDK): cl /EHsc /std:c++17 /W4 /WX /UNDEBUG tests/model_reload_policy_test.cpp
#include <cassert>
#include <iostream>
#include <string>
#include "../source/model_reload_policy.h"

int main() {
    ModelReloadPolicy::Allowance reloads;
    std::string why;
    // Queued rendering (the material system's own thread may be drawing the meshes): never, and not counted.
    for (int i = 0; i < 5; ++i) {
        why.clear();
        assert(!reloads.Take(false, &why) && !why.empty() && reloads.Used() == 0 && "no flush under queued rendering");
    }
    // Single-threaded: cl_rtx.lua's two calls in one client Lua state (after the hardware-skinning setting is
    // restored, and once the map has loaded with mat_queue_mode 0), then no more.
    assert(reloads.Take(true) && reloads.Used() == 1);
    assert(!reloads.Take(false) && reloads.Used() == 1);
    assert(reloads.Take(true) && reloads.Used() == 2);
    why.clear();
    assert(!reloads.Take(true, &why) && !why.empty() && reloads.Used() == 2 && "at most two in one Lua state");
    assert(!reloads.Take(true) && !reloads.Take(true));
    // The next map opens the module again: two more.
    reloads.Reset();
    assert(reloads.Used() == 0 && !reloads.Take(false) && reloads.Take(true) && reloads.Take(true) && !reloads.Take(true));
    std::cout << "PASS model reload policy: none under queued rendering (not counted), at most "
              << ModelReloadPolicy::ReloadsPerLuaState << " single-threaded reloads in one client Lua state, again after "
                 "the module opens for the next map\n";
    return 0;
}
