#pragma once
// The engine guard (R23, ADR 0130). Under RTX the game runs Source's fixed-function shader paths, so a
// material's "<dx90" block applies, and a $fallbackmaterial there that leads back into its own chain
// (ARC9 Gunsmith Reloaded's particle/warp5_explosion names itself) makes CMaterial::InitializeShader in
// materialsystem.dll reload the same VMT forever: the game stops at "Starting Lua". The guard detours
// the one call in that loop that reads "$fallbackmaterial" and answers "" for a fallback that names the
// material itself or that would be the fifth hop for one material in two seconds; the engine then
// finishes the shader's own fallback chain as for a material without that key.
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace nl::engine_guard {

// The call site in CMaterial::InitializeShader (materialsystem.dll of GMod build 26439081, rva 0xfb42):
//   lea r8,[rip+""]; mov rcx,r13; lea rdx,[rip+"$fallbackmaterial"]; call KeyValues::GetString;
//   mov edi,[rsp+40h]; mov r12d,[rsp+44h]; cmp byte ptr [rax],0; je <the loop's start>
// -1 is any byte. r14 holds the material across the loop: its warnings call r14's first virtual,
// GetName (`mov rax,[r14]; mov rcx,r14; call [rax]`, required within kGetNameReach bytes after the call).
// The pattern must occur exactly once, or nothing is changed.
const std::vector<int>& call_site_pattern();
const std::vector<int>& get_name_call_pattern();
inline constexpr std::size_t kGetNameReach = 0x100;
inline constexpr std::size_t kKeyLeaOffset = 10;  // lea rdx,[rip+key] inside the pattern
inline constexpr std::size_t kCallOffset = 17;    // the call (E8 rel32) inside the pattern
inline constexpr std::string_view kKey = "$fallbackmaterial";

// Offsets of the first `limit` matches of `pattern` in [data, data + size).
std::vector<std::size_t> find(const std::uint8_t* data, std::size_t size, const std::vector<int>& pattern,
                              std::size_t limit = 2);

// Material names compare as the engine finds them: without case, either slash, without a leading
// "materials/" or a trailing ".vmt".
std::string normalize(std::string_view name);
bool same_material(std::string_view a, std::string_view b);

// One thread's view of the loop: the material whose fallbacks it follows, how many in a row.
struct Tracker {
  const void* material = nullptr;
  unsigned hops = 0;
  std::uint64_t tick = 0;
};
// A cycle through other materials is cut at the seventeenth fallback followed for one material while
// they come less than kWindowMs apart (a stuck loop makes them in milliseconds, a slow disk in seconds);
// an empty fallback read for the material ends its chain, so separate initializations never add up.
inline constexpr unsigned kMaxHops = 16;
inline constexpr std::uint64_t kWindowMs = 2000;
enum class Verdict { follow, self, too_many };
Verdict decide(Tracker& tracker, const void* material, std::string_view own_name, std::string_view fallback,
               std::uint64_t now_ms);

// What the call site calls instead of KeyValues::GetString: the material's name comes from its first
// virtual function. Only "$fallbackmaterial" is ever filtered. Separate from the detour so tests can drive
// it with fakes.
using GetString = const char* (*)(void* key_values, const char* key, const char* default_value);
const char* filter(GetString get, void* key_values, const char* key, const char* default_value, void* material,
                   Tracker& tracker, std::uint64_t now_ms);

// The bytes the call site's new target holds: mov r9, r14; mov rax, <hook>; jmp rax.
std::vector<std::uint8_t> stub(std::uintptr_t hook);
bool is_stub(const std::uint8_t* code);

struct Status {
  bool installed = false;
  std::string reason;            // installed, installed by the other copy, or why not
  std::uintptr_t site_rva = 0;   // the call site, relative to materialsystem.dll
  unsigned cut = 0;              // fallback materials not followed
  std::string last_material;     // the last material whose fallback was not followed
  std::string last_fallback;
};

// Detours the call site of the loaded materialsystem.dll. Idempotent, also across the client and the
// server copy of the module (the second sees the first one's stub). Pins this module first: the
// detour stays for the process's lifetime. Never throws.
Status install() noexcept;
Status status() noexcept;

}  // namespace nl::engine_guard
