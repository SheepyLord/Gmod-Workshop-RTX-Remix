// The target check (ADR 0261): the queued functor classes it judges (by RTTI name and the shape of their call, on the
// shapes materialsystem.dll has and on ones it must refuse), the layout found in an installed game's
// materialsystem.dll and refused when a slot's code is not the expected getter, the class cache, and the judge on fake
// material variables and materials built in test memory (live; the variable's first word wrong; its material's first
// word wrong; no parameter array; not in it; unreadable; no material).
#include "nl_test.h"
#include "queue_check.h"
#include "target_check.h"

#include <windows.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace qc = nl::engine_guard::queue_check;
namespace tc = nl::engine_guard::target_check;

namespace {
std::uintptr_t address(const void* pointer) { return reinterpret_cast<std::uintptr_t>(pointer); }

constexpr const char* kIntSetter =
    ".?AV?$CMemberFunctor1@PEAVCMaterialVar@@P81@EAAXH@ZHV?$CRefCounted1@VCFunctor@@VCRefCountServiceNull@@@@";
constexpr const char* kTextureSetter =
    ".?AV?$CMemberFunctor1@PEAVCMaterialVar@@P81@EAAXPEAVITexture@@@ZPEAV2@V?$CRefCounted1@VCFunctor@@";
constexpr const char* kStringSetter =
    ".?AV?$CMemberFunctor1@PEAVCMaterialVar@@P81@EAAXPEBD@ZV?$CUtlEnvelope@PEBD@@V?$CRefCounted1@VCFunctor@@";
constexpr const char* kNoArgument = ".?AV?$CMemberFunctor0@PEAVCMaterialVar@@P81@EAAXXZV?$CRefCounted1@VCFunctor@@";

int classify(const char* name, std::initializer_list<std::uint8_t> code) {
  const std::vector<std::uint8_t> bytes(code);
  return tc::classify(name, bytes.data(), bytes.size());
}

// The game's file at `relative` in an installed game (the variable's path, else the PoC's or the game's in Steam's
// default library folders); "" when there is none (CI). The queue check's tests find it the same way.
std::wstring installed_materialsystem() {
  wchar_t path[MAX_PATH]{};
  if (GetEnvironmentVariableW(L"NL_MATERIALSYSTEM_DLL", path, MAX_PATH)) return path;
  wchar_t steam[MAX_PATH]{};
  DWORD size = sizeof(steam);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath", RRF_RT_REG_SZ, nullptr, steam, &size) !=
      ERROR_SUCCESS)
    return {};
  std::ifstream file(std::wstring(steam) + L"\\steamapps\\libraryfolders.vdf");
  std::string line;
  while (std::getline(file, line)) {
    const auto key = line.find("\"path\"");
    if (key == std::string::npos) continue;
    const auto open = line.find('"', key + 6);
    const auto close = open == std::string::npos ? open : line.find('"', open + 1);
    if (close == std::string::npos) continue;
    std::string folder;
    for (std::size_t i = open + 1; i < close; ++i) {
      if (line[i] == '\\' && i + 1 < close && line[i + 1] == '\\') ++i;
      folder += line[i];
    }
    const int length = MultiByteToWideChar(CP_UTF8, 0, folder.c_str(), -1, nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(length > 0 ? length : 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, folder.c_str(), -1, wide.data(), length);
    wide.resize(std::wcslen(wide.c_str()));
    for (const wchar_t* game : {L"GarrysMod_PoC", L"GarrysMod"}) {
      const std::wstring candidate = wide + L"\\steamapps\\common\\" + game + L"\\bin\\win64\\materialsystem.dll";
      if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) return candidate;
    }
  }
  return {};
}

// An installed materialsystem.dll mapped as an image (not relocated: its slots hold preferred-base addresses).
struct Mapped {
  HMODULE module = nullptr;
  const std::uint8_t* base = nullptr;
  std::uintptr_t preferred = 0;
  std::size_t size = 0;
  explicit Mapped(const std::wstring& path) {
    module = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE);
    if (!module) return;
    base = reinterpret_cast<const std::uint8_t*>(address(module) & ~std::uintptr_t{3});
    const auto* nt =
        reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + reinterpret_cast<const IMAGE_DOS_HEADER*>(base)->e_lfanew);
    preferred = nt->OptionalHeader.ImageBase;
    size = nt->OptionalHeader.SizeOfImage;
  }
  ~Mapped() {
    if (module) FreeLibrary(module);
  }
};
}  // namespace

TEST_CASE("target check: the functor classes on a material variable are classified by name and call") {
  // The shapes in materialsystem.dll (int, texture, float, two arguments, a reference, no argument).
  CHECK(classify(kIntSetter, {0x8B, 0x51, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) ==
        0x18);
  CHECK(classify(kTextureSetter,
                 {0x48, 0x8B, 0x51, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) == 0x18);
  CHECK(classify(kIntSetter,
                 {0xF3, 0x0F, 0x10, 0x49, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) ==
        0x18);
  CHECK(classify(kIntSetter, {0x4C, 0x8B, 0x41, 0x28, 0x48, 0x8B, 0xC1, 0x8B, 0x51, 0x20, 0x48, 0x8B, 0x49, 0x18, 0x48,
                              0xFF, 0x60, 0x10}) == 0x18);
  CHECK(classify(kIntSetter, {0x44, 0x8B, 0x41, 0x24, 0x48, 0x8B, 0xC1, 0xF3, 0x0F, 0x10, 0x49, 0x20, 0x48, 0x8B, 0x49,
                              0x18, 0x48, 0xFF, 0x60, 0x10}) == 0x18);
  CHECK(classify(kIntSetter,
                 {0x48, 0x8B, 0xC1, 0x48, 0x8D, 0x51, 0x20, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) == 0x18);
  CHECK(classify(kNoArgument, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) == 0x18);
  CHECK(classify(kNoArgument, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x20, 0xFF, 0x60, 0x10}) == 0x20);  // jmp w/o REX
  // Not judged: another class, another object type, a call of another shape.
  const std::initializer_list<std::uint8_t> shape = {0x8B, 0x51, 0x20, 0x48, 0x8B, 0xC1, 0x48,
                                                     0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10};
  CHECK(classify(".?AV?$CMemberFunctor0@PEAVIMaterialInternal@@P8IMaterial@@EAAXXZ", shape) == -1);
  CHECK(classify(".?AV?$CFunctor1@PEAVCMaterialVar@@", shape) == -1);
  CHECK(classify(".?AV?$CMemberFunctorX@PEAVCMaterialVar@@", shape) == -1);
  CHECK(classify("", shape) == -1);
  // The string setter, as materialsystem.dll has it (+0x26470 in the build of 2026-11): its object at [rbx+18h].
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x4B, 0x18, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE0}) == 0x18);
  // Its near misses: cut short; jmp rcx; the object from [rcx+18h]; another frame; another register for the
  // conversion's result; a negative offset; another class.
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00}) == -1);
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x4B, 0x18, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE1}) == -1);
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x49, 0x18, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE0}) == -1);
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x30, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x4B, 0x18, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x30, 0x5B, 0x48, 0xFF, 0xE0}) == -1);
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x4B, 0x18, 0x48, 0x8B, 0xD1, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE0}) == -1);
  CHECK(classify(kStringSetter, {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8,
                                 0x5E, 0x9D, 0x04, 0x00, 0x48, 0x8B, 0x4B, 0xE8, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10,
                                 0x48, 0x83, 0xC4, 0x20, 0x5B, 0x48, 0xFF, 0xE0}) == -1);
  CHECK(classify(".?AV?$CMemberFunctor1@PEAVCMaterialSystem@@",
                 {0x40, 0x53, 0x48, 0x83, 0xEC, 0x20, 0x48, 0x8B, 0xD9, 0x48, 0x83, 0xC1, 0x20, 0xE8, 0x5E, 0x9D, 0x04,
                  0x00, 0x48, 0x8B, 0x4B, 0x18, 0x48, 0x8B, 0xD0, 0x48, 0x8B, 0x43, 0x10, 0x48, 0x83, 0xC4, 0x20, 0x5B,
                  0x48, 0xFF, 0xE0}) == -1);
  // The object read before rcx is kept in rax; a load from another base; into rcx; into xmm0; no jump; an unaligned
  // or negative offset; a load after the object's.
  CHECK(classify(kIntSetter, {0x48, 0x8B, 0x49, 0x18, 0x48, 0x8B, 0xC1, 0x48, 0xFF, 0x60, 0x10}) == -1);
  CHECK(classify(kIntSetter, {0x8B, 0x50, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) ==
        -1);
  CHECK(classify(kIntSetter, {0x41, 0x8B, 0x51, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60,
                              0x10}) == -1);
  CHECK(classify(kIntSetter, {0x8B, 0x49, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60, 0x10}) ==
        -1);
  CHECK(classify(kIntSetter, {0xF3, 0x0F, 0x10, 0x41, 0x20, 0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0x48, 0xFF, 0x60,
                              0x10}) == -1);
  CHECK(classify(kIntSetter, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x18, 0xC3}) == -1);
  CHECK(classify(kIntSetter, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0x1C, 0x48, 0xFF, 0x60, 0x10}) == -1);
  CHECK(classify(kIntSetter, {0x48, 0x8B, 0xC1, 0x48, 0x8B, 0x49, 0xF8, 0x48, 0xFF, 0x60, 0x10}) == -1);
  CHECK(classify(kIntSetter, {0x48, 0x8B, 0xC1}) == -1);  // cut short
  CHECK(tc::classify(kIntSetter, nullptr, 0) == -1);
}

TEST_CASE("target check: the layout is found in an installed game's materialsystem.dll and refused otherwise") {
  {  // this test executable has neither class
    const HMODULE self = GetModuleHandleW(nullptr);
    const tc::Layout layout = tc::find_layout(reinterpret_cast<const std::uint8_t*>(self), address(self));
    CHECK(!layout.found());
    CHECK(!tc::find_layout(nullptr, 0).found());
  }
  const std::wstring path = installed_materialsystem();
  if (path.empty()) return;  // no game on this machine (CI)
  const Mapped mapped(path);
  REQUIRE(mapped.base != nullptr);
  const tc::Layout layout = tc::find_layout(mapped.base, mapped.preferred);
  if (!layout.found()) std::printf("  target layout not found: %s\n", layout.reason.c_str());
  CHECK(layout.found());
  if (!layout.found()) return;
  std::printf("  CMaterialVar's vtable 0x%llx, CMaterial's 0x%llx; owner at +0x%x, count at +0x%x, parameters at +0x%x\n",
              static_cast<unsigned long long>(layout.variable_table - mapped.preferred),
              static_cast<unsigned long long>(layout.material_table - mapped.preferred), layout.owner, layout.count,
              layout.params);
  CHECK(layout.variable_table > mapped.preferred && layout.material_table > mapped.preferred);
  // The build of 2026-11: a game update that moves them is noticed here.
  CHECK(layout.owner == 0x31);
  CHECK(layout.count == 0x32);
  CHECK(layout.params == 0x38);
  CHECK(layout.image.begin == mapped.preferred && layout.image.end == mapped.preferred + mapped.size);
  CHECK(layout.constants_count >= 1);
  bool tables_in_constants = false;
  for (std::size_t i = 0; i < layout.constants_count; ++i)
    tables_in_constants |= layout.variable_table >= layout.constants[i].begin &&
                           layout.variable_table < layout.constants[i].end;
  CHECK(tables_in_constants);
  // A copy whose GetOwningMaterial (slot 24) does not end in ret: refused.
  std::vector<std::uint8_t> copy(mapped.base, mapped.base + mapped.size);
  const auto* variable = reinterpret_cast<const std::uintptr_t*>(copy.data() + (layout.variable_table - mapped.preferred));
  const std::uintptr_t getter = variable[tc::kOwnerSlot] - mapped.preferred;
  REQUIRE(getter + 5 <= copy.size());
  CHECK(copy[getter + 4] == 0xC3);
  copy[getter + 4] = 0x90;
  const tc::Layout refused = tc::find_layout(copy.data(), mapped.preferred);
  CHECK(!refused.found());
  CHECK(refused.reason.find("GetOwningMaterial") != std::string::npos);
  // And one whose ShaderParamCount reads a word, not a byte.
  copy[getter + 4] = 0xC3;
  CHECK(tc::find_layout(copy.data(), mapped.preferred).found());
  const auto* material = reinterpret_cast<const std::uintptr_t*>(copy.data() + (layout.material_table - mapped.preferred));
  const std::uintptr_t count = material[tc::kCountSlot] - mapped.preferred;
  CHECK(copy[count] == 0x0F && copy[count + 1] == 0xB6);
  copy[count + 1] = 0xB7;
  const tc::Layout word = tc::find_layout(copy.data(), mapped.preferred);
  CHECK(!word.found());
  CHECK(word.reason.find("ShaderParamCount") != std::string::npos);
  copy[count + 1] = 0xB6;
  // And one whose CleanUpShaderParams clears other offsets than the getters read: every such store pair changed.
  std::size_t pairs = 0;
  for (std::size_t at = 0; at + 12 <= copy.size(); ++at) {
    std::uint8_t* q = copy.data() + at;
    if (q[0] == 0x48 && q[1] == 0xC7 && (q[2] & 0xF8) == 0x40 && q[3] == layout.params && !q[4] && !q[5] && !q[6] &&
        !q[7] && q[8] == 0xC6 && q[9] == q[2] && q[10] == layout.count && !q[11]) {
      q[10] = 0x33;
      ++pairs;
    }
  }
  CHECK(pairs >= 1);
  const tc::Layout stores = tc::find_layout(copy.data(), mapped.preferred);
  CHECK(!stores.found());
  CHECK(stores.reason.find("CleanUpShaderParams") != std::string::npos);
}

TEST_CASE("target check: the material variable functors in an installed game's materialsystem.dll are classified") {
  const std::wstring path = installed_materialsystem();
  if (path.empty()) return;  // no game on this machine (CI)
  const Mapped mapped(path);
  REQUIRE(mapped.base != nullptr);
  // Every type descriptor name of a CMemberFunctorN on a CMaterialVar*.
  const std::string_view image(reinterpret_cast<const char*>(mapped.base), mapped.size);
  const std::string prefix = ".?AV?$CMemberFunctor";
  std::size_t classes = 0, judged = 0;
  for (std::size_t at = image.find(prefix); at != std::string_view::npos; at = image.find(prefix, at + 1)) {
    const std::size_t end = image.find('\0', at);
    if (end == std::string_view::npos) break;
    const std::string name(image.substr(at, end - at));
    if (name.find("@PEAVCMaterialVar@@") != prefix.size() + 1) continue;
    const std::uintptr_t* vtable = qc::find_vtable(mapped.base, mapped.preferred, name);
    if (!vtable) continue;
    ++classes;
    const std::uintptr_t call = vtable[tc::kCallSlot] - mapped.preferred;
    REQUIRE(call + tc::kCallReach <= mapped.size);
    const int offset = tc::classify(name, mapped.base + call, tc::kCallReach);
    if (offset >= 0) ++judged;
    std::printf("  %s: %d\n", name.substr(0, 72).c_str(), offset);
  }
  std::printf("  %zu classes on a CMaterialVar*, %zu judged\n", classes, judged);
  CHECK(classes >= 4);
  CHECK(judged == classes);  // the string setter too
}

namespace {
// Fake game memory: a material variable (CMaterialVar's 0x41 bytes, its owner the unaligned word at +0x31), a material
// (its parameter count a byte at +0x32, its array at +0x38) and a functor that keeps the variable at +0x18.
constexpr std::uint32_t kOwner = 0x31, kCount = 0x32, kParams = 0x38, kObject = 0x18;
const std::uintptr_t kVariableTable[4] = {};  // stand-ins for the two vtables
const std::uintptr_t kMaterialTable[4] = {};
const std::uintptr_t kFunctorTable[4] = {};
// A stand-in for materialsystem.dll's read-only data: another material class's vtable (CMaterialSubRect's) lies in it.
const std::uintptr_t kImageData[16] = {};
const std::uintptr_t* const kSubRectTable = kImageData + 8;

struct Fake {
  alignas(8) std::uint8_t variable[0x48] = {};
  alignas(8) std::uint8_t other[0x48] = {};
  alignas(8) std::uint8_t material[0x48] = {};
  std::uintptr_t params[3] = {};
  std::uintptr_t functor[5] = {};
  tc::Judge judge;
  Fake() {
    put(variable, 0, address(kVariableTable));
    put(variable, kOwner, address(material));
    put(other, 0, address(kVariableTable));
    put(other, kOwner, address(material));
    put(material, 0, address(kMaterialTable));
    material[kCount] = 3;
    put(material, kParams, address(params));
    params[0] = address(other);
    params[1] = address(variable);
    params[2] = 0;
    functor[0] = address(kFunctorTable);
    functor[kObject / 8] = address(variable);
    judge.variable_table = address(kVariableTable);
    judge.material_table = address(kMaterialTable);
    judge.owner = kOwner;
    judge.count = kCount;
    judge.params = kParams;
    judge.resolver = nullptr;
    judge.classes.add(address(kFunctorTable), kObject);
    judge.constants[0] = {address(kImageData), address(kImageData + 16)};
    judge.constants_count = 1;
  }
  static void put(std::uint8_t* at, std::uint32_t offset, std::uintptr_t value) {
    std::memcpy(at + offset, &value, sizeof(value));
  }
  tc::Verdict run(tc::Finding& finding) { return tc::judge(judge, address(functor), finding); }
  tc::Verdict run() {
    tc::Finding finding;
    return run(finding);
  }
};
}  // namespace

TEST_CASE("target check: the judge on fake material variables and materials") {
  {  // live, with what it found
    Fake fake;
    tc::Finding f;
    CHECK(fake.run(f) == tc::Verdict::live);
    CHECK(f.functor_table == address(kFunctorTable));
    CHECK(f.offset == kObject);
    CHECK(f.variable == address(fake.variable));
    CHECK(f.owner == address(fake.material));
    CHECK(f.count == 3);
    CHECK(f.parameters == address(fake.params));
    CHECK(!tc::gone(tc::Verdict::live));
  }
  {  // the variable destroyed and its memory reused: its first word is not CMaterialVar's vtable
    Fake fake;
    Fake::put(fake.variable, 0, address(&fake));
    tc::Finding f;
    CHECK(fake.run(f) == tc::Verdict::not_a_variable);
    CHECK(f.variable_table == address(&fake));
    CHECK(tc::gone(f.verdict));
  }
  {  // a live variable proves the owner offset
    Fake fake;
    CHECK(!fake.judge.owner_proven);
    CHECK(fake.run() == tc::Verdict::live);
    CHECK(fake.judge.owner_proven);
  }
  {  // its material is another material class of the image (CMaterialSubRect): not judged, proven or not
    Fake fake;
    Fake::put(fake.material, 0, address(kSubRectTable));
    tc::Finding f;
    CHECK(fake.run(f) == tc::Verdict::other_owner);
    CHECK(!tc::gone(f.verdict));
    CHECK(f.owner_table == address(kSubRectTable));
    fake.judge.owner_proven = true;
    CHECK(fake.run() == tc::Verdict::other_owner);
  }
  {  // its material's first word is no vtable of the image: gone only once the owner offset is proven
    Fake fake;
    Fake::put(fake.material, 0, address(&fake));
    tc::Finding f;
    CHECK(fake.run(f) == tc::Verdict::unproven);
    CHECK(!tc::gone(f.verdict));
    CHECK(!fake.judge.owner_proven);
    Fake::put(fake.material, 0, address(kMaterialTable));
    CHECK(fake.run() == tc::Verdict::live);  // proves it
    Fake::put(fake.material, 0, address(&fake));
    CHECK(fake.run(f) == tc::Verdict::owner_not_a_material);
    CHECK(tc::gone(f.verdict));
  }
  {  // the material uncached: no array, or no count (CleanUpShaderParams stores 0 for both)
    Fake fake;
    Fake::put(fake.material, kParams, 0);
    CHECK(fake.run() == tc::Verdict::no_parameters);
    Fake again;
    again.material[kCount] = 0;
    CHECK(again.run() == tc::Verdict::no_parameters);
  }
  {  // re-cached with new variables: not in the array
    Fake fake;
    fake.params[1] = address(fake.other);
    CHECK(fake.run() == tc::Verdict::not_in_parameters);
    Fake short_count;
    short_count.material[kCount] = 1;  // the array's first entry only
    CHECK(short_count.run() == tc::Verdict::not_in_parameters);
  }
  {  // unreadable: the variable, the material, the array
    void* reserved = VirtualAlloc(nullptr, 0x10000, MEM_RESERVE, PAGE_NOACCESS);
    REQUIRE(reserved != nullptr);
    Fake fake;
    fake.functor[kObject / 8] = address(reserved);
    CHECK(fake.run() == tc::Verdict::variable_unreadable);
    fake.functor[kObject / 8] = 0;
    CHECK(fake.run() == tc::Verdict::variable_unreadable);
    Fake owner;  // an unreadable material: not judged before the offset is proven, gone after
    Fake::put(owner.variable, kOwner, address(reserved));
    CHECK(owner.run() == tc::Verdict::unproven);
    owner.judge.owner_proven = true;
    CHECK(owner.run() == tc::Verdict::owner_unreadable);
    Fake array;  // the array unreadable (the material a CMaterial: proven)
    Fake::put(array.material, kParams, address(reserved));
    CHECK(array.run() == tc::Verdict::not_in_parameters);
    VirtualFree(reserved, 0, MEM_RELEASE);
  }
  {  // no material: not judged, the call runs
    Fake fake;
    Fake::put(fake.variable, kOwner, 0);
    tc::Finding f;
    CHECK(fake.run(f) == tc::Verdict::no_owner);
    CHECK(!tc::gone(f.verdict));
  }
  {  // a class the cache does not know and no resolver: not judged; nothing judged without a layout
    Fake fake;
    fake.functor[0] = address(kMaterialTable);
    CHECK(fake.run() == tc::Verdict::not_judged);
    Fake none;
    none.judge.variable_table = 0;
    CHECK(none.run() == tc::Verdict::not_judged);
    tc::Finding f;
    CHECK(tc::judge(fake.judge, 0, f) == tc::Verdict::not_judged);
  }
  for (int v = 0; v <= static_cast<int>(tc::Verdict::not_in_parameters); ++v)
    CHECK(std::strlen(tc::describe(static_cast<tc::Verdict>(v))) > 5);
}

namespace {
int g_resolves = 0;
int resolve_odd(std::uintptr_t table) noexcept {
  ++g_resolves;
  return (table & 8) ? 0x18 : -1;
}

// A class of this executable: not a CMemberFunctor on a CMaterialVar*.
struct Plain {
  virtual ~Plain() = default;
  virtual void a() {}
  virtual void b() {}
  virtual void c() {}
};
}  // namespace

TEST_CASE("target check: the class cache resolves each class once, and the game's resolver on this executable") {
  tc::Classes classes;
  g_resolves = 0;
  CHECK(classes.lookup(0x1008, &resolve_odd) == 0x18);
  CHECK(classes.lookup(0x1010, &resolve_odd) == -1);
  CHECK(classes.lookup(0x1008, &resolve_odd) == 0x18);
  CHECK(classes.lookup(0x1010, &resolve_odd) == -1);
  CHECK(g_resolves == 2);
  CHECK(classes.size() == 2);
  for (std::uintptr_t t = 0; t < tc::kClassCache + 4; ++t) classes.lookup(0x2000 + 16 * t, &resolve_odd);
  CHECK(classes.size() == tc::kClassCache);
  CHECK(classes.lookup(0x1008, nullptr) == 0x18);  // still remembered
  CHECK(classes.lookup(0x9008, nullptr) == -1);    // unknown, nothing to resolve with
  Plain plain;
  CHECK(tc::resolve_in_memory(*reinterpret_cast<const std::uintptr_t*>(&plain)) == -1);
  CHECK(tc::resolve_in_memory(0) == -1);
  char name[64];
  CHECK(qc::rtti_name_into(*reinterpret_cast<const std::uintptr_t*>(&plain), name, sizeof(name)));
  CHECK(std::string(name).find("Plain@") != std::string::npos);
  CHECK(!qc::rtti_name_into(0, name, sizeof(name)));
}
