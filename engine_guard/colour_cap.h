// Material colours above 1 capped for Remix (ADR 0190).
//
// Under RTX the game draws with Source's fixed-function shaders, and a material's tint ($color2 on a model,
// $color elsewhere, a render colour) reaches the GPU as D3DRS_TEXTUREFACTOR, one byte per component.
// shaderapidx9.dll's Color3f, Color3fv, Color4f and Color4fv make that byte with cvttss2si of value * 255 and
// keep its low byte: nothing clamps it, so 1.5 becomes 126 (0.49), 1.3 becomes 75 (0.29) and 2 becomes 254.
// The Remix runtime multiplies the albedo by that colour (multi-stage texture factor blending), so a tint meant
// to brighten darkens or discolours instead: gm_construct's tree cards ($color2 [1.3 1.4 1.5]) come out dark
// blue-grey. A byte cannot say "more than 1", so the fix is before the conversion: these four functions get each
// component clamped to [0, 1] first. Values within it reach the engine unchanged.
//
// The four are found by their machine code, not by address, and only where it is sure: four consecutive vtable
// slots of the loaded shaderapidx9.dll, in that order, each pointing at its own code that loads 255.0f, converts
// with cvttss2si and calls SetRenderState(D3DRS_TEXTUREFACTOR) through the device's vtable; the 3-component ones
// set alpha to 0xFF themselves, the vector ones read through their pointer, Color4f reads alpha from the stack.
// Anything else (another game build, another module's hook) leaves the game as it was and says why. Only where
// the Remix runtime is the d3d9.dll in the process: flat starts never change.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace nl::engine_guard::colour_cap {

inline constexpr std::uint32_t kTextureFactor = 60;          // D3DRS_TEXTUREFACTOR
inline constexpr std::uint32_t kSetRenderStateOffset = 0x1C8;  // IDirect3DDevice9::SetRenderState, slot 57
inline constexpr std::size_t kSlots = 4;                       // Color3f, Color3fv, Color4f, Color4fv
inline constexpr std::size_t kReach = 0x100;  // a function's code is read up to its `ret; int3`, at most this far

// One component as Remix gets it: within [0, 1]. NaN gives 0, as the engine's own conversion does.
inline float cap(float value) noexcept { return value > 1.0f ? 1.0f : (value >= 0.0f ? value : 0.0f); }

// The byte shaderapidx9.dll makes of a component: the low byte of (int)(value * 255). For tests and the record.
std::uint8_t engine_byte(float value) noexcept;

// What one of the four functions is, by its code.
enum class Kind { none, colour3f, colour3fv, colour4f, colour4fv };

// The kind of the function whose code starts at `code`, `size` readable bytes (at most kReach are read).
// `constant` answers a rip-relative movss's target: the float at that address, or false when it lies outside the
// image. The tests drive it with plain buffers.
using ReadFloat = bool (*)(const void* context, std::uintptr_t address, float* value);
Kind classify(const std::uint8_t* code, std::size_t size, std::uintptr_t address, ReadFloat constant,
              const void* context) noexcept;

// Where the four slots are in a mapped image: the offset of the first slot from `image`, or SIZE_MAX when there is
// not exactly one run of four. `image` is mapped as loaded (sections at their virtual addresses); `loaded_base` is
// the address the slots' pointers are relative to (the image itself when it is loaded, its preferred base when it
// is only mapped as a file image and not relocated).
std::size_t find_slots(const std::uint8_t* image, std::uintptr_t loaded_base) noexcept;

struct Status {
  bool installed = false;
  std::string reason;            // "installed", "installed by the other copy of this module", or why not
  std::uintptr_t slots_rva = 0;  // the first slot, relative to shaderapidx9.dll
  bool enabled = false;          // capping now (ColourCap(false) turns it off for a comparison)
  std::uint64_t capped = 0;      // calls that had a component outside [0, 1]
};

// Wraps the four slots of the loaded shaderapidx9.dll. Idempotent, also across the client and the server copy of
// this module; pins this module first (the slots point into it for the process's lifetime). Does nothing without
// the Remix runtime as d3d9.dll. Never throws.
Status install() noexcept;
Status status() noexcept;
// Turns capping on or off for the process (both copies share the owner's switch); returns the status after it.
Status set_enabled(bool enabled) noexcept;

}  // namespace nl::engine_guard::colour_cap
