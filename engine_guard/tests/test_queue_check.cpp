// The queue check (ADR 0247): the material system's layout found once in an installed game's materialsystem.dll,
// stale calls dropped and live ones kept (in order, head and tail following), broken lists left as they are, the
// engine's way of appending, the judge on real memory, RTTI names, nothing installed outside a Remix start, and the
// module's contract (every realm installs it and publishes how it went).
#include "nl_test.h"
#include "queue_check.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace qc = nl::engine_guard::queue_check;

namespace {
// A queued call laid out as the engine's: IRefCounted's two, a virtual destructor, operator() in slot 3.
struct Call {
  virtual int AddRef() { return 1; }
  virtual int Release() { return 1; }
  virtual ~Call() = default;
  virtual void operator()() { ++runs; }
  int runs = 0;
};

std::uintptr_t address(const void* pointer) { return reinterpret_cast<std::uintptr_t>(pointer); }
std::uintptr_t vtable_of(const void* object) { return *reinterpret_cast<const std::uintptr_t*>(object); }

// A queued context's call list and its arena as the engine lays them out: {head, tail, next free byte}, then the arena.
struct Arena {
  std::vector<std::uintptr_t> words;
  qc::List list;
  explicit Arena(std::size_t elements) : words(3 + 2 * elements) {
    list.header = words.data();
    list.arena_begin = address(words.data() + 3);
    list.arena_end = list.arena_begin + elements * qc::kElement;
    words[2] = list.arena_begin;
  }
  // Appends a call and returns its element.
  std::uintptr_t push(std::uintptr_t object) {
    REQUIRE(qc::append(list, object));
    return words[1];
  }
  // The objects of the calls still linked, in order.
  std::vector<std::uintptr_t> objects() const {
    std::vector<std::uintptr_t> out;
    for (std::uintptr_t e = words[0]; e; e = reinterpret_cast<const std::uintptr_t*>(e)[0])
      out.push_back(reinterpret_cast<const std::uintptr_t*>(e)[1]);
    return out;
  }
};

qc::Why judge(void*, std::uintptr_t object) { return qc::judge_memory(object); }

// Objects of each kind the check must tell apart, on real memory.
// A vtable in writable data, as no engine functor's is.
std::uintptr_t g_writable_table[4] = {};
// A vtable in read-only data whose call slot points at data, not code.
const char kNotCode[] = "not code";
const void* const kDataTable[4] = {nullptr, nullptr, nullptr, kNotCode};

struct Objects {
  Call live[3];
  std::uintptr_t* freed = nullptr;  // a heap block whose first word is another heap address: memory reused
  std::uintptr_t writable[1] = {address(g_writable_table)};
  std::uintptr_t data_table[1] = {address(kDataTable)};
  void* reserved = nullptr;  // reserved, never committed: unreadable
  Objects() {
    freed = static_cast<std::uintptr_t*>(std::calloc(8, sizeof(std::uintptr_t)));
    freed[0] = address(std::calloc(8, sizeof(std::uintptr_t)));
    reserved = VirtualAlloc(nullptr, 0x10000, MEM_RESERVE, PAGE_NOACCESS);
  }
  ~Objects() {
    std::free(reinterpret_cast<void*>(freed[0]));
    std::free(freed);
    VirtualFree(reserved, 0, MEM_RELEASE);
  }
};

// The game's file at `relative` in its install: the variable's path, else the PoC's or the game's install found in
// Steam's libraries (its registry key and libraryfolders.vdf). "" when there is none (CI).
std::vector<std::wstring> steam_libraries() {
  std::vector<std::wstring> out;
  wchar_t steam[MAX_PATH]{};
  DWORD size = sizeof(steam);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath", RRF_RT_REG_SZ, nullptr, steam, &size) !=
      ERROR_SUCCESS)
    return out;
  std::ifstream file(std::wstring(steam) + L"\\steamapps\\libraryfolders.vdf");
  std::string line;
  while (std::getline(file, line)) {
    const auto key = line.find("\"path\"");
    if (key == std::string::npos) continue;
    const auto open = line.find('"', key + 6);
    const auto close = open == std::string::npos ? open : line.find('"', open + 1);
    if (close == std::string::npos) continue;
    std::string path;
    for (std::size_t i = open + 1; i < close; ++i) {
      if (line[i] == '\\' && i + 1 < close && line[i + 1] == '\\') ++i;
      path += line[i];
    }
    const int length = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(length > 0 ? length : 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wide.data(), length);
    wide.resize(std::wcslen(wide.c_str()));
    out.push_back(wide);
  }
  return out;
}

std::wstring installed(const wchar_t* variable, const wchar_t* relative) {
  wchar_t path[MAX_PATH]{};
  if (GetEnvironmentVariableW(variable, path, MAX_PATH)) return path;
  for (const auto& library : steam_libraries()) {
    for (const wchar_t* game : {L"GarrysMod_PoC", L"GarrysMod"}) {
      const std::wstring candidate = library + L"\\steamapps\\common\\" + game + L"\\" + relative;
      if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) return candidate;
    }
  }
  return {};
}
}  // namespace

TEST_CASE("queue check: the material system's layout is found once in an installed game's materialsystem.dll") {
  const std::wstring path = installed(L"NL_MATERIALSYSTEM_DLL", L"bin\\win64\\materialsystem.dll");
  if (path.empty()) return;  // no game on this machine (CI)
  // Mapped as an image (sections where they load) but not relocated: the slots hold preferred-base addresses.
  const HMODULE mapped = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_AS_IMAGE_RESOURCE | LOAD_LIBRARY_AS_DATAFILE);
  REQUIRE(mapped != nullptr);
  const auto* base = reinterpret_cast<const std::uint8_t*>(address(mapped) & ~std::uintptr_t{3});
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + reinterpret_cast<const IMAGE_DOS_HEADER*>(base)->e_lfanew);
  const std::uintptr_t preferred = nt->OptionalHeader.ImageBase;
  const std::uintptr_t* vtable = qc::find_vtable(base, preferred, ".?AVCMaterialSystem@@");
  CHECK(vtable != nullptr);
  if (vtable) {
    // Its length: the slots that point into the image's code.
    const auto* sections = IMAGE_FIRST_SECTION(nt);
    auto in_code = [&](std::uintptr_t pointer) {
      if (pointer < preferred) return false;
      const std::uintptr_t rva = pointer - preferred;
      for (unsigned s = 0; s < nt->FileHeader.NumberOfSections; ++s)
        if ((sections[s].Characteristics & IMAGE_SCN_MEM_EXECUTE) && rva >= sections[s].VirtualAddress &&
            rva < sections[s].VirtualAddress + sections[s].Misc.VirtualSize)
          return true;
      return false;
    };
    std::size_t slots = 0;
    while (slots < qc::kMaxSlots && in_code(vtable[slots])) ++slots;
    CHECK(slots > 100);
    const qc::Layout layout = qc::find_layout(base, preferred, vtable, slots);
    if (!layout.found()) std::printf("  layout not found: %s\n", layout.reason.c_str());
    CHECK(layout.found());
    if (layout.found()) {
      std::printf("  AllowThreading slot %zu, Lock %zu, Unlock %zu; ForceSingleThreaded 0x%llx, EndQueue 0x%llx, "
                  "CallQueued 0x%llx; %u contexts at +0x%x, every 0x%x; the call list at +0x%x\n",
                  layout.allow_slot, layout.lock_slot, layout.unlock_slot,
                  static_cast<unsigned long long>(layout.force_rva), static_cast<unsigned long long>(layout.end_queue_rva),
                  static_cast<unsigned long long>(layout.call_queued_rva), layout.count, layout.contexts, layout.stride,
                  layout.list);
      CHECK(layout.count == 2);
      CHECK(layout.allow_slot != layout.lock_slot);
      CHECK(layout.lock_slot != layout.unlock_slot);
      CHECK(layout.stride >= layout.list + qc::kListHeader + 0x1000000);
      CHECK(layout.force_rva != 0 && layout.end_queue_rva != 0 && layout.call_queued_rva != 0);
      // The run check's site (ADR 0254): CallQueued's dispatch, the engine's ten bytes.
      std::printf("  CallQueued's dispatch at 0x%llx\n", static_cast<unsigned long long>(layout.dispatch_rva));
      CHECK(layout.dispatch_rva > layout.call_queued_rva);
      CHECK(std::memcmp(base + layout.dispatch_rva, "\x48\x8B\x4B\x08\x48\x8B\x01\xFF\x50\x18", 10) == 0);
    }
    // Shifted by one slot, AllowThreading is not where the layout wants it.
    const qc::Layout shifted = qc::find_layout(base, preferred, vtable + 1, slots - 1);
    CHECK(!shifted.found() || shifted.allow_slot + 1 == layout.allow_slot);
  }
  // Another class's vtable has none of it.
  const std::uintptr_t* other = qc::find_vtable(base, preferred, ".?AVCMatQueuedRenderContext@@");
  CHECK(other != nullptr);
  if (other) CHECK(!qc::find_layout(base, preferred, other, 64).found());
  FreeLibrary(mapped);
}

TEST_CASE("queue check: the judge tells live calls from stale ones on real memory") {
  Objects objects;
  CHECK(qc::judge_memory(address(&objects.live[0])) == qc::Why::live);
  CHECK(qc::judge_memory(0) == qc::Why::null_object);
  CHECK(qc::judge_memory(address(objects.freed)) == qc::Why::first_word_not_in_module);
  CHECK(qc::judge_memory(address(objects.writable)) == qc::Why::first_word_not_constant);
  CHECK(qc::judge_memory(address(objects.data_table)) == qc::Why::call_not_code);
  CHECK(qc::judge_memory(address(objects.reserved)) == qc::Why::unreadable);
  CHECK(std::strlen(qc::describe(qc::Why::first_word_not_in_module)) > 10);
}

TEST_CASE("queue check: stale calls are unlinked, live ones kept in order") {
  Objects objects;
  Arena arena(32);
  const std::uintptr_t first = arena.push(address(&objects.live[0]));
  arena.push(address(objects.freed));
  arena.push(address(&objects.live[1]));
  arena.push(0);
  arena.push(address(objects.writable));
  arena.push(address(objects.data_table));
  arena.push(address(objects.reserved));
  const std::uintptr_t last = arena.push(address(&objects.live[2]));
  const qc::Report report = qc::clean(&arena.list, 1, &judge, nullptr);
  CHECK(report.lists == 1);
  CHECK(report.calls[0] == 8);
  CHECK(report.dropped == 5);
  CHECK(report.recorded == 5);
  CHECK(report.broken == 0);
  const auto kept = arena.objects();
  REQUIRE(kept.size() == 3);
  CHECK(kept[0] == address(&objects.live[0]));
  CHECK(kept[1] == address(&objects.live[1]));
  CHECK(kept[2] == address(&objects.live[2]));
  CHECK(arena.words[0] == first);
  CHECK(arena.words[1] == last);
  // Each drop: its place, why, its first words, and the classes of the live calls around it.
  const qc::Why expected[] = {qc::Why::first_word_not_in_module, qc::Why::null_object, qc::Why::first_word_not_constant,
                              qc::Why::call_not_code, qc::Why::unreadable};
  const std::uint32_t positions[] = {1, 3, 4, 5, 6};
  const std::uintptr_t table = vtable_of(&objects.live[0]);
  for (std::uint32_t i = 0; i < 5; ++i) {
    CHECK(report.drops[i].why == expected[i]);
    CHECK(report.drops[i].position == positions[i]);
    CHECK(report.drops[i].length == 8);
    CHECK(report.drops[i].offset == positions[i] * qc::kElement);
    CHECK(report.drops[i].before == table);
    CHECK(report.drops[i].after == table);
  }
  CHECK(report.drops[0].words_read == 4);
  CHECK(report.drops[0].words[0] == objects.freed[0]);
  CHECK(report.drops[1].words_read == 0);  // no object
  CHECK(report.drops[4].words_read == 0);  // unreadable
  // A second walk finds nothing more.
  const qc::Report again = qc::clean(&arena.list, 1, &judge, nullptr);
  CHECK(again.dropped == 0);
  CHECK(again.calls[0] == 3);
}

TEST_CASE("queue check: the first, the last and every call can go") {
  Objects objects;
  {
    Arena arena(8);
    arena.push(address(objects.freed));
    const std::uintptr_t live = arena.push(address(&objects.live[0]));
    arena.push(address(objects.freed));
    const qc::Report report = qc::clean(&arena.list, 1, &judge, nullptr);
    CHECK(report.dropped == 2);
    CHECK(arena.words[0] == live);
    CHECK(arena.words[1] == live);
    CHECK(reinterpret_cast<const std::uintptr_t*>(live)[0] == 0);
    CHECK(report.drops[0].before == 0);  // nothing live before the first
    CHECK(report.drops[1].after == 0);   // nor after the last
  }
  {
    Arena arena(8);
    arena.push(0);
    arena.push(address(objects.freed));
    const qc::Report report = qc::clean(&arena.list, 1, &judge, nullptr);
    CHECK(report.dropped == 2);
    CHECK(arena.words[0] == 0);
    CHECK(arena.words[1] == 0);
    // An emptied list takes calls again where the engine's next free byte says.
    const std::uintptr_t next = arena.words[2];
    CHECK(qc::append(arena.list, address(&objects.live[1])));
    CHECK(arena.words[0] == next);
    CHECK(arena.objects().size() == 1);
  }
  {
    Arena arena(4);
    const qc::Report report = qc::clean(&arena.list, 1, &judge, nullptr);  // empty
    CHECK(report.dropped == 0);
    CHECK(report.broken == 0);
    CHECK(report.calls[0] == 0);
  }
}

TEST_CASE("queue check: several lists, drops recorded up to the limit") {
  Objects objects;
  Arena a(32), b(32);
  for (int i = 0; i < 12; ++i) a.push(address(objects.freed));
  b.push(address(&objects.live[0]));
  b.push(address(objects.freed));
  const qc::List lists[] = {a.list, b.list};
  const qc::Report report = qc::clean(lists, 2, &judge, nullptr);
  CHECK(report.lists == 2);
  CHECK(report.dropped == 13);
  CHECK(report.recorded == qc::kMaxDrops);
  CHECK(a.objects().empty());
  CHECK(b.objects().size() == 1);
}

TEST_CASE("queue check: a list that cannot be walked is left as it is") {
  Objects objects;
  {  // an element outside the arena
    Arena arena(8);
    const std::uintptr_t e = arena.push(address(objects.freed));
    arena.push(address(&objects.live[0]));
    reinterpret_cast<std::uintptr_t*>(e)[0] = address(&objects);
    const auto before = arena.words;
    const qc::Report report = qc::clean(&arena.list, 1, &judge, nullptr);
    CHECK(report.broken == 1);
    CHECK(report.dropped == 0);
    CHECK(arena.words == before);
  }
  {  // a cycle
    Arena arena(8);
    const std::uintptr_t e1 = arena.push(address(objects.freed));
    const std::uintptr_t e2 = arena.push(address(&objects.live[0]));
    reinterpret_cast<std::uintptr_t*>(e2)[0] = e1;
    const auto before = arena.words;
    CHECK(qc::clean(&arena.list, 1, &judge, nullptr).broken == 1);
    CHECK(arena.words == before);
  }
  {  // a tail that is not the last call
    Arena arena(8);
    const std::uintptr_t e1 = arena.push(address(objects.freed));
    arena.push(address(&objects.live[0]));
    arena.words[1] = e1;
    const auto before = arena.words;
    CHECK(qc::clean(&arena.list, 1, &judge, nullptr).broken == 1);
    CHECK(arena.words == before);
    CHECK(!qc::append(arena.list, address(&objects.live[1])));
  }
  {  // a tail with no head
    Arena arena(8);
    arena.words[1] = arena.list.arena_begin;
    CHECK(qc::clean(&arena.list, 1, &judge, nullptr).broken == 1);
  }
}

TEST_CASE("queue check: appending as the engine does") {
  Objects objects;
  Arena arena(2);
  arena.words[2] += 3;  // a next free byte the engine left unaligned: the element starts at the next 8
  const std::uintptr_t e = arena.push(address(&objects.live[0]));
  CHECK(e == arena.list.arena_begin + 8);
  CHECK(arena.words[2] == e + qc::kElement);
  CHECK(!qc::append(arena.list, address(&objects.live[1])));  // the arena is full
  CHECK(arena.objects().size() == 1);
}

TEST_CASE("queue check: RTTI names and vtables of this executable") {
  Call call;
  const std::string name = qc::rtti_name(vtable_of(&call));
  CHECK(name.find("Call@") != std::string::npos);
  CHECK(qc::rtti_name(0).empty());
  CHECK(qc::rtti_name(address(g_writable_table) + 8).empty());
  const HMODULE self = GetModuleHandleW(nullptr);
  const std::uintptr_t* table = qc::find_vtable(reinterpret_cast<const std::uint8_t*>(self), address(self), name);
  CHECK(table != nullptr);
  if (table) CHECK(address(table) == vtable_of(&call));
  CHECK(qc::find_vtable(reinterpret_cast<const std::uint8_t*>(self), address(self), ".?AVNoSuchClass@@") == nullptr);
}

TEST_CASE("queue check: nothing installs outside a Remix start") {
  if (GetModuleHandleW(L"d3d9.dll")) return;  // never in this test process
  const auto status = qc::install();
  CHECK(!status.installed);
  CHECK(status.reason == "not a Remix start");
  CHECK(!status.run_check);
  CHECK(qc::status().checks == 0);
  CHECK(qc::status().runs == 0);
}

TEST_CASE("queue check: the module installs it in every realm and publishes how it went") {
  std::ifstream file(NL_ENGINE_GUARD_MODULE_SOURCE);
  REQUIRE(file.good());
  std::stringstream read;
  read << file.rdbuf();
  const std::string text = read.str();
  const auto open = text.find("GMOD_MODULE_OPEN()");
  REQUIRE(open != std::string::npos);
  const auto call = text.find("queue_check::install()", open);
  const auto menu = text.find("if (menu) {", open);
  REQUIRE(call != std::string::npos);
  REQUIRE(menu != std::string::npos);
  CHECK(call < menu);
  const auto reason = text.find("SetField(-2, \"queue_check\")", open);
  const auto run_reason = text.find("SetField(-2, \"run_check\")", open);
  const auto function = text.find("SetField(-2, \"QueueCheck\")", open);
  CHECK(reason != std::string::npos && reason < menu);
  CHECK(run_reason != std::string::npos && run_reason < menu);
  CHECK(function != std::string::npos && function < menu);
}
