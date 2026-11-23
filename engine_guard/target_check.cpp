// Queued calls on a material variable that is gone, skipped (ADR 0261). See target_check.h.
#include "target_check.h"

#include "queue_check.h"  // find_vtable, rtti_name_into

#include <windows.h>

#include <algorithm>
#include <cstring>

namespace nl::engine_guard::target_check {

const char* describe(Verdict verdict) noexcept {
  switch (verdict) {
    case Verdict::live:
      return "a variable of its material";
    case Verdict::not_judged:
      return "not a call on a material variable";
    case Verdict::no_owner:
      return "the variable names no material";
    case Verdict::other_owner:
      return "the variable belongs to another material class of materialsystem.dll";
    case Verdict::unproven:
      return "its material could not be confirmed, and the owner offset is not proven in this process yet";
    case Verdict::variable_unreadable:
      return "the material variable's memory cannot be read";
    case Verdict::not_a_variable:
      return "the material variable's first word is not CMaterialVar's vtable: it was destroyed";
    case Verdict::owner_unreadable:
      return "its material's memory cannot be read";
    case Verdict::owner_not_a_material:
      return "its material's first word is not CMaterial's vtable";
    case Verdict::no_parameters:
      return "its material lists no variable any more (uncached): the variable was destroyed";
    case Verdict::not_in_parameters:
      return "its material's variables do not include it any more: the variable was destroyed";
  }
  return "?";
}

bool gone(Verdict verdict) noexcept {
  return verdict != Verdict::live && verdict != Verdict::not_judged && verdict != Verdict::no_owner &&
         verdict != Verdict::other_owner && verdict != Verdict::unproven;
}

namespace {
struct Image {
  const IMAGE_SECTION_HEADER* first = nullptr;
  unsigned count = 0;
};

bool headers(const std::uint8_t* image, Image& out) noexcept {
  if (!image) return false;
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x10000) return false;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
  out.first = IMAGE_FIRST_SECTION(nt);
  out.count = nt->FileHeader.NumberOfSections;
  return true;
}

// The characteristics of the section holding [rva, rva + size), or 0.
DWORD section(const Image& s, std::uintptr_t rva, std::size_t size) noexcept {
  for (unsigned i = 0; i < s.count; ++i) {
    const auto& h = s.first[i];
    const std::uintptr_t begin = h.VirtualAddress, end = begin + h.Misc.VirtualSize;
    if (rva >= begin && rva < end && size <= end - rva) return h.Characteristics;
  }
  return 0;
}

// The `slot`th entry of a vtable in the mapping as an RVA, when the vtable holds that many entries in read-only data and
// the entry points into the image's code with `size` bytes of it; else SIZE_MAX.
std::uintptr_t slot_code(const std::uint8_t* image, std::uintptr_t loaded_base, const Image& s,
                         const std::uintptr_t* vtable, std::size_t slot, std::size_t size) noexcept {
  const auto table_rva = reinterpret_cast<std::uintptr_t>(vtable) - reinterpret_cast<std::uintptr_t>(image);
  const DWORD data = section(s, table_rva, 8 * (slot + 1));
  if (!data || (data & (IMAGE_SCN_MEM_WRITE | IMAGE_SCN_MEM_EXECUTE))) return SIZE_MAX;
  const std::uintptr_t address = vtable[slot];
  if (address < loaded_base) return SIZE_MAX;
  const std::uintptr_t rva = address - loaded_base;
  if (!(section(s, rva, size) & IMAGE_SCN_MEM_EXECUTE)) return SIZE_MAX;
  return rva;
}

// The displacement of `prefix d8 C3` at code (exactly five bytes, a positive disp8), or -1.
int getter(const std::uint8_t* code, std::uint8_t a, std::uint8_t b, std::uint8_t c) noexcept {
  if (code[0] != a || code[1] != b || code[2] != c || code[4] != 0xC3) return -1;
  const auto displacement = static_cast<std::int8_t>(code[3]);
  return displacement > 0 ? displacement : -1;
}

std::uintptr_t image_size(const std::uint8_t* image) noexcept {
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  return reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew)->OptionalHeader.SizeOfImage;
}

// Whether the image's code holds mov qword ptr [r+params],0; mov byte ptr [r+count],0 (48 C7 4r pp 00 00 00 00
// C6 4r cc 00) at least once, r one of rax, rcx, rdx, rbx, rsi, rdi.
bool cleanup_stores(const std::uint8_t* image, const Image& s, std::uint8_t params, std::uint8_t count) noexcept {
  for (unsigned i = 0; i < s.count; ++i) {
    const auto& h = s.first[i];
    if (!(h.Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
    const std::size_t size = std::min<std::size_t>(h.Misc.VirtualSize, h.SizeOfRawData);
    const std::uint8_t* code = image + h.VirtualAddress;
    for (std::size_t at = 0; at + 12 <= size; ++at) {
      const std::uint8_t* p = code + at;
      if (p[0] != 0x48 || p[1] != 0xC7 || p[8] != 0xC6 || p[2] != p[9]) continue;
      const std::uint8_t r = p[2] & 0x07;
      if ((p[2] & 0xF8) != 0x40 || r == 4 || r == 5) continue;  // [r+disp8]; never rsp (SIB) or rbp
      if (p[3] != params || p[4] || p[5] || p[6] || p[7] || p[10] != count || p[11]) continue;
      return true;
    }
  }
  return false;
}

Layout refused(Layout layout, const char* why) {
  layout.reason = why;
  return layout;
}
}  // namespace

Layout find_layout(const std::uint8_t* image, std::uintptr_t loaded_base) noexcept {
  Layout out;
  try {
    Image s;
    if (!headers(image, s)) return refused(out, "materialsystem.dll's headers could not be read");
    const std::uintptr_t* variable = queue_check::find_vtable(image, loaded_base, ".?AVCMaterialVar@@");
    const std::uintptr_t* material = queue_check::find_vtable(image, loaded_base, ".?AVCMaterial@@");
    if (!variable || !material) return refused(out, "CMaterialVar's or CMaterial's vtable was not found once");
    const std::uintptr_t owner = slot_code(image, loaded_base, s, variable, kOwnerSlot, 5);
    const std::uintptr_t count = slot_code(image, loaded_base, s, material, kCountSlot, 5);
    const std::uintptr_t params = slot_code(image, loaded_base, s, material, kParamsSlot, 5);
    if (owner == SIZE_MAX || count == SIZE_MAX || params == SIZE_MAX)
      return refused(out, "the material variable's or the material's interface slots are not materialsystem.dll's code");
    const int owner_at = getter(image + owner, 0x48, 0x8B, 0x41);    // mov rax,[rcx+dd]; ret
    const int count_at = getter(image + count, 0x0F, 0xB6, 0x41);    // movzx eax,byte ptr [rcx+dd]; ret
    const int params_at = getter(image + params, 0x48, 0x8B, 0x41);  // mov rax,[rcx+dd]; ret
    if (owner_at < 0) return refused(out, "IMaterialVar::GetOwningMaterial is not mov rax,[rcx+dd]; ret");
    if (count_at < 0) return refused(out, "ShaderParamCount is not movzx eax,byte ptr [rcx+dd]; ret");
    if (params_at < 0) return refused(out, "GetShaderParams is not mov rax,[rcx+dd]; ret");
    // CMaterial::CleanUpShaderParams ends with mov qword ptr [r+params],0; mov byte ptr [r+count],0 (r one of rax,
    // rcx, rdx, rbx, rsi, rdi, the same in both): the offsets the getters gave must be the ones the cleanup clears.
    if (!cleanup_stores(image, s, static_cast<std::uint8_t>(params_at), static_cast<std::uint8_t>(count_at)))
      return refused(out, "CMaterial::CleanUpShaderParams' stores of 0 to the parameter array and count were not found");
    out.image = {loaded_base, loaded_base + image_size(image)};
    for (unsigned i = 0; i < s.count && out.constants_count < kMaxConstants; ++i) {
      const auto& h = s.first[i];
      if ((h.Characteristics & IMAGE_SCN_MEM_READ) && !(h.Characteristics & (IMAGE_SCN_MEM_WRITE | IMAGE_SCN_MEM_EXECUTE)))
        out.constants[out.constants_count++] = {loaded_base + h.VirtualAddress,
                                                loaded_base + h.VirtualAddress + h.Misc.VirtualSize};
    }
    out.variable_table = loaded_base + (reinterpret_cast<std::uintptr_t>(variable) - reinterpret_cast<std::uintptr_t>(image));
    out.material_table = loaded_base + (reinterpret_cast<std::uintptr_t>(material) - reinterpret_cast<std::uintptr_t>(image));
    out.owner = static_cast<std::uint32_t>(owner_at);
    out.count = static_cast<std::uint32_t>(count_at);
    out.params = static_cast<std::uint32_t>(params_at);
    return out;
  } catch (...) {
    return refused(out, "materialsystem.dll's code could not be read");
  }
}

namespace {
// One argument load from [rcx+d8] into an argument register (never rax, rcx or rsp; never xmm0): mov, lea, movzx,
// movsx, movsxd, or movss/movsd with their F3/F2 prefix. Its length, or 0.
std::size_t argument_load(const std::uint8_t* code, std::size_t size) noexcept {
  std::size_t at = 0;
  bool scalar = false;  // F3 or F2: movss, movsd
  if (at < size && (code[at] == 0xF3 || code[at] == 0xF2)) {
    scalar = true;
    ++at;
  }
  std::uint8_t rex = 0;
  if (at < size && (code[at] & 0xF0) == 0x40) {
    rex = code[at++];
    if (rex & 0x03) return 0;  // REX.X or REX.B: another base than rcx
  }
  if (at >= size) return 0;
  bool xmm = false;
  if (code[at] == 0x0F) {
    if (++at >= size) return 0;
    const std::uint8_t op = code[at];
    if (op == 0x10) {
      if (!scalar) return 0;
      xmm = true;
    } else if (op != 0xB6 && op != 0xB7 && op != 0xBE && op != 0xBF) {
      return 0;
    }
    if (scalar && !xmm) return 0;
  } else if (code[at] == 0x8B || code[at] == 0x8D || (code[at] == 0x63 && (rex & 0x08))) {
    if (scalar) return 0;
  } else {
    return 0;
  }
  if (++at + 2 > size) return 0;
  const std::uint8_t modrm = code[at];
  if ((modrm & 0xC0) != 0x40 || (modrm & 0x07) != 0x01) return 0;  // [rcx + disp8]
  const unsigned reg = ((modrm >> 3) & 7) | ((rex & 0x04) ? 8u : 0u);
  if (xmm ? reg == 0 : (reg == 0 || reg == 1 || reg == 4)) return 0;
  return at + 2;
}
}  // namespace

int classify(std::string_view name, const std::uint8_t* code, std::size_t size) noexcept {
  constexpr std::string_view kPrefix = ".?AV?$CMemberFunctor";
  constexpr std::string_view kObject = "@PEAVCMaterialVar@@";
  if (name.size() < kPrefix.size() + 1 + kObject.size() || name.substr(0, kPrefix.size()) != kPrefix) return -1;
  const char digit = name[kPrefix.size()];
  if (digit < '0' || digit > '9' || name.substr(kPrefix.size() + 1, kObject.size()) != kObject) return -1;
  if (!code) return -1;
  size = std::min(size, kCallReach);
  // The string setter: push rbx; sub rsp,20h; mov rbx,rcx; add rcx,d8; call rel32 (the argument's conversion);
  // mov rcx,[rbx+dd]; mov rdx,rax; mov rax,[rbx+pp]; add rsp,20h; pop rbx; jmp rax. -1: any byte; -2: dd.
  static const int kString[] = {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, -1,
                                0xE8, -1,   -1,   -1,   -1,   0x48, 0x8B, 0x4B, -2,   0x48, 0x8B, 0xD0, 0x48,
                                0x8B, 0x43, -1,   0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE0};
  constexpr std::size_t kStringSize = sizeof(kString) / sizeof(kString[0]);
  if (size >= 2 && code[0] == 0x40 && code[1] == 0x53) {
    if (size < kStringSize) return -1;
    int offset = -1;
    for (std::size_t i = 0; i < kStringSize; ++i) {
      if (kString[i] == -2)
        offset = static_cast<std::int8_t>(code[i]);
      else if (kString[i] >= 0 && code[i] != kString[i])
        return -1;
    }
    return offset > 0 && (offset & 7) == 0 ? offset : -1;
  }
  bool moved = false;  // mov rax,rcx seen
  for (std::size_t at = 0; at < size;) {
    const std::uint8_t* p = code + at;
    const std::size_t left = size - at;
    if (!moved && left >= 3 && p[0] == 0x48 && p[1] == 0x8B && p[2] == 0xC1) {
      moved = true;
      at += 3;
      continue;
    }
    if (moved && left >= 4 && p[0] == 0x48 && p[1] == 0x8B && p[2] == 0x49) {
      const auto offset = static_cast<std::int8_t>(p[3]);
      const std::uint8_t* jump = p + 4;
      const std::size_t rest = left - 4;
      const bool jumps = (rest >= 4 && jump[0] == 0x48 && jump[1] == 0xFF && jump[2] == 0x60) ||
                         (rest >= 3 && jump[0] == 0xFF && jump[1] == 0x60);
      return jumps && offset > 0 && (offset & 7) == 0 ? offset : -1;
    }
    const std::size_t length = argument_load(p, left);
    if (!length) return -1;
    at += length;
  }
  return -1;
}

void Classes::add(std::uintptr_t table, int offset) noexcept {
  if (count_ >= kClassCache) return;
  tables_[count_] = table;
  offsets_[count_] = offset;
  ++count_;
}

int Classes::lookup(std::uintptr_t table, Resolver resolver) noexcept {
  for (std::size_t i = 0; i < count_; ++i)
    if (tables_[i] == table) return offsets_[i];
  if (!resolver) return -1;
  const int offset = resolver(table);
  add(table, offset);  // a full cache resolves again next time
  return offset;
}

namespace {
bool read_word(std::uintptr_t address, std::uintptr_t& out) noexcept {
  __try {
    out = *reinterpret_cast<const volatile std::uintptr_t*>(address);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

bool read_byte(std::uintptr_t address, std::uint8_t& out) noexcept {
  __try {
    out = *reinterpret_cast<const volatile std::uint8_t*>(address);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// The call's code, up to kCallReach bytes, stopping at the first that cannot be read.
std::size_t read_code(std::uintptr_t address, std::uint8_t* out) noexcept {
  std::size_t read = 0;
  __try {
    for (; read < kCallReach; ++read) out[read] = reinterpret_cast<const volatile std::uint8_t*>(address)[read];
  } __except (EXCEPTION_EXECUTE_HANDLER) {
  }
  return read;
}
}  // namespace

int resolve_in_memory(std::uintptr_t table) noexcept {
  char name[256];
  if (!queue_check::rtti_name_into(table, name, sizeof(name))) return -1;
  std::uintptr_t call = 0;
  if (!read_word(table + 8 * kCallSlot, call) || !call) return -1;
  MEMORY_BASIC_INFORMATION m{};
  if (!VirtualQuery(reinterpret_cast<const void*>(call), &m, sizeof(m)) || m.Type != MEM_IMAGE ||
      !(m.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
    return -1;
  std::uint8_t code[kCallReach];
  const std::size_t size = read_code(call, code);
  return classify(name, code, size);
}

void Judge::use(const Layout& layout) noexcept {
  variable_table = layout.variable_table;
  material_table = layout.material_table;
  owner = layout.owner;
  count = layout.count;
  params = layout.params;
  image = layout.image;
  constants_count = std::min(layout.constants_count, kMaxConstants);
  for (std::size_t i = 0; i < constants_count; ++i) constants[i] = layout.constants[i];
}

Verdict judge(Judge& j, std::uintptr_t functor, Finding& f) noexcept {
  f = Finding{};
  if (!j.variable_table || !j.material_table) return f.verdict = Verdict::not_judged;
  std::uintptr_t table = 0;
  if (!functor || !read_word(functor, table)) return f.verdict = Verdict::not_judged;
  f.functor_table = table;
  const int offset = j.classes.lookup(table, j.resolver);
  if (offset < 0) return f.verdict = Verdict::not_judged;
  f.offset = static_cast<std::uint32_t>(offset);
  std::uintptr_t variable = 0;
  if (!read_word(functor + static_cast<std::uintptr_t>(offset), variable)) return f.verdict = Verdict::not_judged;
  f.variable = variable;
  if (!variable || !read_word(variable, f.variable_table)) return f.verdict = Verdict::variable_unreadable;
  if (f.variable_table != j.variable_table) return f.verdict = Verdict::not_a_variable;
  if (!read_word(variable + j.owner, f.owner)) return f.verdict = Verdict::variable_unreadable;
  if (!f.owner) return f.verdict = Verdict::no_owner;
  // The owner: a CMaterial proves the owner offset; another vtable in the image's read-only data is another material
  // class (not judged); anything else is gone only once the offset is proven in this process.
  if (!read_word(f.owner, f.owner_table))
    return f.verdict = j.owner_proven ? Verdict::owner_unreadable : Verdict::unproven;
  if (f.owner_table != j.material_table) {
    for (std::size_t i = 0; i < j.constants_count && i < kMaxConstants; ++i)
      if (f.owner_table >= j.constants[i].begin && f.owner_table < j.constants[i].end)
        return f.verdict = Verdict::other_owner;
    return f.verdict = j.owner_proven ? Verdict::owner_not_a_material : Verdict::unproven;
  }
  j.owner_proven = true;
  std::uint8_t count = 0;
  if (!read_byte(f.owner + j.count, count) || !read_word(f.owner + j.params, f.parameters))
    return f.verdict = Verdict::owner_unreadable;
  f.count = count;
  if (!f.parameters || !count) return f.verdict = Verdict::no_parameters;
  for (std::uint32_t i = 0; i < count; ++i) {
    std::uintptr_t entry = 0;
    if (!read_word(f.parameters + 8 * i, entry)) return f.verdict = Verdict::not_in_parameters;
    if (entry == variable) return f.verdict = Verdict::live;
  }
  return f.verdict = Verdict::not_in_parameters;
}

}  // namespace nl::engine_guard::target_check
