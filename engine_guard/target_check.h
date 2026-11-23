// Queued calls on a material variable that is gone, skipped (ADR 0261), inside the run check (run_check.h, ADR 0254).
//
// In queued rendering a Lua IMaterial:SetTexture, SetInt, SetFloat... on the main thread does not write the material's
// variable: CMaterialVar::Set*Value queues a CMemberFunctorN<CMaterialVar*, ...> holding the raw variable pointer
// (nothing keeps the variable alive). IMaterialSystem::UncacheAllMaterials (the RTX fixes' map-exit cleanup calls it)
// destroys every file-based material's variables at once; a setter still queued then runs on freed memory when the
// engine leaves threaded rendering, and the game dies (exit 0xC0000409).
//
// So the run check asks, right before it runs a call: is the call a setter on a material variable, and is that variable
// still a variable of its material? It is alive exactly when its first word is CMaterialVar's vtable, its owner's first
// word is CMaterial's vtable, and the owner's parameter array lists it (CMaterial::CleanUpShaderParams frees the array
// and stores 0 for it and its count, and the variable's own destructor leaves its owner word as it was).
//
// What is needed is found in materialsystem.dll, only where sure: both vtables by their RTTI classes; the owner's offset
// from CMaterialVar's slot 24 (IMaterialVar::GetOwningMaterial: mov rax,[rcx+dd]; ret); the count's and the array's
// from CMaterial's slots 40 (ShaderParamCount: movzx eax,byte ptr [rcx+dd]; ret) and 41 (GetShaderParams:
// mov rax,[rcx+dd]; ret), cross-checked against CMaterial::CleanUpShaderParams, which stores 0 at both. A queued call
// is judged only when its class is a CMemberFunctorN on a CMaterialVar* (by RTTI) whose call (slot 3) has one of the
// engine's two shapes, which say where the functor keeps the variable. Everything else runs as before.
//
// Only where sure, also at run time: a variable whose owner is another material class of materialsystem.dll
// (CMaterialSubRect has variables of its own) is not judged. An owner that cannot be read, or whose first word is no
// vtable of the image, counts as gone only once some variable's owner has been a CMaterial in this process (which a
// wrong owner offset could not produce); before that the call runs.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace nl::engine_guard::target_check {

// The public interface slots the layout is read from, each verified by its exact code bytes.
inline constexpr std::size_t kOwnerSlot = 24;   // IMaterialVar::GetOwningMaterial
inline constexpr std::size_t kCountSlot = 40;   // IMaterialInternal::ShaderParamCount
inline constexpr std::size_t kParamsSlot = 41;  // IMaterialInternal::GetShaderParams
inline constexpr std::size_t kCallSlot = 3;     // a queued functor's call
inline constexpr std::size_t kClassCache = 48;  // functor classes remembered per process
inline constexpr std::size_t kCallReach = 48;   // a functor's call is read this far at most

struct Range {
  std::uintptr_t begin = 0, end = 0;  // [begin, end)
};
inline constexpr std::size_t kMaxConstants = 8;

struct Layout {
  std::uintptr_t variable_table = 0;  // CMaterialVar's vtable, as loaded
  std::uintptr_t material_table = 0;  // CMaterial's vtable, as loaded
  std::uint32_t owner = 0;            // the variable's owner (unaligned word)
  std::uint32_t count = 0;            // the material's parameter count (a byte)
  std::uint32_t params = 0;           // the material's parameter array
  Range image;                        // the image, as loaded
  Range constants[kMaxConstants];     // its read-only data sections, as loaded (where its vtables are)
  std::size_t constants_count = 0;
  std::string reason;                 // empty when every part was found exactly as expected
  bool found() const noexcept { return reason.empty(); }
};

// The layout in a mapped image of materialsystem.dll (sections at their virtual addresses); its vtables hold addresses
// relative to `loaded_base` (the image's own address when loaded, its preferred base when only mapped as a file).
Layout find_layout(const std::uint8_t* image, std::uintptr_t loaded_base) noexcept;

// Where a queued functor keeps its material variable (its byte offset), from its class's RTTI name and its call's
// code; -1 when the class is not one to judge. The call must be argument loads from [rcx+d8] into argument registers,
// mov rax,rcx, mov rcx,[rcx+dd] and jmp [rax+pp], in that order (the loads before or after mov rax,rcx); or the string
// setter's: push rbx; sub rsp,20h; mov rbx,rcx; add rcx,d8; call rel32; mov rcx,[rbx+dd]; mov rdx,rax;
// mov rax,[rbx+pp]; add rsp,20h; pop rbx; jmp rax.
int classify(std::string_view rtti_name, const std::uint8_t* code, std::size_t size) noexcept;

// What the judge found of one call.
enum class Verdict : std::uint8_t {
  live,                  // a variable of its material: the call runs
  not_judged,            // not a call on a material variable: it runs
  no_owner,              // the variable names no owner: it runs
  other_owner,           // its owner is another material class of the image (CMaterialSubRect): it runs
  unproven,              // its owner is no CMaterial and the owner offset is not proven in this process: it runs
  variable_unreadable,   // gone: the variable's memory cannot be read
  not_a_variable,        // gone: its first word is not CMaterialVar's vtable
  owner_unreadable,      // gone: the owner's memory cannot be read
  owner_not_a_material,  // gone: the owner's first word is not CMaterial's vtable
  no_parameters,         // gone: the owner lists no variable (uncached)
  not_in_parameters,     // gone: the owner's variables do not include it
};
const char* describe(Verdict verdict) noexcept;
bool gone(Verdict verdict) noexcept;

struct Finding {
  Verdict verdict = Verdict::not_judged;
  std::uintptr_t functor_table = 0;  // the call's class
  std::uint32_t offset = 0;          // where the functor keeps the variable
  std::uintptr_t variable = 0;
  std::uintptr_t variable_table = 0;
  std::uintptr_t owner = 0;
  std::uintptr_t owner_table = 0;
  std::uintptr_t parameters = 0;
  std::uint32_t count = 0;
};

// The functor classes seen, by vtable. Main thread only.
class Classes {
 public:
  // Says where a class keeps its variable (-1: not judged); the game's reads the RTTI name and the call's code.
  using Resolver = int (*)(std::uintptr_t table) noexcept;
  void add(std::uintptr_t table, int offset) noexcept;
  int lookup(std::uintptr_t table, Resolver resolver) noexcept;
  std::size_t size() const noexcept { return count_; }

 private:
  std::uintptr_t tables_[kClassCache] = {};
  int offsets_[kClassCache] = {};
  std::size_t count_ = 0;
};

// The game's resolver: the class's RTTI name and its call's code, read under SEH.
int resolve_in_memory(std::uintptr_t table) noexcept;

struct Judge {
  std::uintptr_t variable_table = 0;
  std::uintptr_t material_table = 0;
  std::uint32_t owner = 0, count = 0, params = 0;
  Range image;
  Range constants[kMaxConstants];
  std::size_t constants_count = 0;
  bool owner_proven = false;  // some variable's owner was a CMaterial: the owner offset is right
  Classes classes;
  Classes::Resolver resolver = &resolve_in_memory;
  void use(const Layout& layout) noexcept;
};

// Judges the call whose functor is at `functor` (the element's object). Every read under SEH. Never throws.
Verdict judge(Judge& judge, std::uintptr_t functor, Finding& finding) noexcept;

}  // namespace nl::engine_guard::target_check
