// A stand-in shaderapidx9.dll for the colour cap's end-to-end test (ADR 0190). Its four colour functions are
// fake_shaderapi.asm; this file holds the API object whose read-only vtable names them in the game's order
// (among other slots), and a device whose SetRenderState (vtable slot 57) records the texture factor it is given.
#include <windows.h>

#include <cstdint>

extern "C" void nl_fake_colour3f();
extern "C" void nl_fake_colour3fv();
extern "C" void nl_fake_colour4f();
extern "C" void nl_fake_colour4fv();

namespace {
std::uint32_t g_state = 0, g_factor = 0, g_calls = 0;

HRESULT set_render_state(void*, std::uint32_t state, std::uint32_t value) {
  g_state = state;
  g_factor = value;
  ++g_calls;
  return S_OK;
}

void* g_device_vtable[58] = {};
struct Device {
  void** vtable;
} g_device{g_device_vtable};

void other_slot_a() { g_calls += 100; }
void other_slot_b() { g_calls += 200; }

// The API's vtable, in read-only data as the compiler puts vtables: two other slots, the four, two more.
void* const kVtable[8] = {reinterpret_cast<void*>(&other_slot_a), reinterpret_cast<void*>(&other_slot_b),
                          reinterpret_cast<void*>(&nl_fake_colour3f), reinterpret_cast<void*>(&nl_fake_colour3fv),
                          reinterpret_cast<void*>(&nl_fake_colour4f), reinterpret_cast<void*>(&nl_fake_colour4fv),
                          reinterpret_cast<void*>(&other_slot_b), reinterpret_cast<void*>(&other_slot_a)};
struct Api {
  void* const* vtable;
} g_api{kVtable};
}  // namespace

extern "C" {
void* nl_fake_device = nullptr;  // fake_shaderapi.asm calls through it
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_device_vtable[57] = reinterpret_cast<void*>(&set_render_state);
    nl_fake_device = &g_device;
  }
  return TRUE;
}

// The API object (its first field is the vtable, as a C++ object's is), the vtable, and what the device got last.
extern "C" __declspec(dllexport) void* nl_fake_api() { return &g_api; }
extern "C" __declspec(dllexport) void* const* nl_fake_vtable() { return kVtable; }
extern "C" __declspec(dllexport) std::uint32_t nl_fake_factor() { return g_factor; }
extern "C" __declspec(dllexport) std::uint32_t nl_fake_state() { return g_state; }
extern "C" __declspec(dllexport) std::uint32_t nl_fake_calls() { return g_calls; }
// What vtable slot `index` held at load (the colour cap changes four of them).
extern "C" __declspec(dllexport) const void* nl_fake_code(int index) {
  switch (index) {
    case 0: case 7: return reinterpret_cast<const void*>(&other_slot_a);
    case 1: case 6: return reinterpret_cast<const void*>(&other_slot_b);
    case 2: return reinterpret_cast<const void*>(&nl_fake_colour3f);
    case 3: return reinterpret_cast<const void*>(&nl_fake_colour3fv);
    case 4: return reinterpret_cast<const void*>(&nl_fake_colour4f);
    case 5: return reinterpret_cast<const void*>(&nl_fake_colour4fv);
    default: return nullptr;
  }
}
