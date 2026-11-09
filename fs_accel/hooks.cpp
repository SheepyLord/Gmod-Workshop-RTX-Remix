// The import hooks on filesystem_stdio.dll that let the loose-folder cache answer (R26, ADR 0140).
//
// Chained: each slot's value before the hook (the loader's own hook where it has one, which calls Windows through
// pointers of its own, or Windows' function) is what every call the cache does not answer goes to. Installed once per
// process: the gmcl_ and gmsv_ copies of the module are two images, and the second finds the first's hooks in place
// (the slot points into a module exporting nl_fs_accel_v1). The module is pinned and nothing is ever freed: a file
// system thread may be inside a hook at any time. The start-up marker (fs_accel.h) is written and read here too.
#include "fs_accel.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>

namespace nl::fs_accel {
namespace {

using CreateA = HANDLE(WINAPI*)(LPCSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using CreateW = HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD, LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using AttributesA = BOOL(WINAPI*)(LPCSTR, GET_FILEEX_INFO_LEVELS, LPVOID);
using AttributesW = BOOL(WINAPI*)(LPCWSTR, GET_FILEEX_INFO_LEVELS, LPVOID);

using ShutdownProbe = BOOLEAN(NTAPI*)();

struct Global {
  LooseCache own_cache;
  Watcher watcher;
  LooseCache* cache = nullptr;
  // ntdll's RtlDllShutdownInProgress: once the process is shutting down, other threads are gone, perhaps inside the
  // cache's lock, so nothing is answered and no lock is taken.
  ShutdownProbe shutting_down = nullptr;
  CreateA next_create_a = nullptr;
  CreateW next_create_w = nullptr;
  AttributesA next_attributes_a = nullptr;
  AttributesW next_attributes_w = nullptr;
  Counters own_counters;
  Counters* counters = &own_counters;
  bool attempted = false;
  InstallResult result;
  SRWLOCK lock = SRWLOCK_INIT;
};

Global& global() {
  static Global* g = new Global();  // never destroyed: hooks may run during process exit
  return *g;
}

DWORD error_of(Verdict verdict) { return verdict == Verdict::MissingPath ? ERROR_PATH_NOT_FOUND : ERROR_FILE_NOT_FOUND; }

// An open the cache may answer: it can only find an existing file, never create, delete or write one. A directory open
// (backup semantics) or a reparse point open passes.
bool answerable_open(DWORD access, DWORD disposition, DWORD flags) {
  constexpr DWORD kWrite = GENERIC_WRITE | GENERIC_ALL | FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA |
      FILE_WRITE_ATTRIBUTES | DELETE | WRITE_DAC | WRITE_OWNER;
  return disposition == OPEN_EXISTING && (access & kWrite) == 0 &&
      (flags & (FILE_FLAG_DELETE_ON_CLOSE | FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT)) == 0;
}

// An open that can create or delete a file under a cached folder: that folder is not cached any more.
bool may_change(DWORD access, DWORD disposition, DWORD flags) {
  return disposition != OPEN_EXISTING || (flags & FILE_FLAG_DELETE_ON_CLOSE) != 0 || (access & DELETE) != 0;
}

// The cache's verdict on an open, or Pass. Verify mode leaves the answer to Windows and counts a disagreement when
// Windows finds what the cache said was missing.
bool answering(const Global& g) noexcept {
  return g.cache && g.counters->enabled.load(std::memory_order_relaxed) != 0 && !(g.shutting_down && g.shutting_down());
}

template <class Char>
Verdict judge_open(Global& g, const Char* name, DWORD access, DWORD disposition, DWORD flags) noexcept {
  g.counters->calls.fetch_add(1, std::memory_order_relaxed);
  if (!name || !answering(g)) return Verdict::Pass;
  PathBuffer path;
  if (!normalize(std::basic_string_view<Char>(name), path)) return Verdict::Pass;
  if (may_change(access, disposition, flags)) {
    g.cache->drop_path(path.view());
    return Verdict::Pass;
  }
  if (!answerable_open(access, disposition, flags)) return Verdict::Pass;
  return g.cache->lookup(path.view());
}

template <class Char>
Verdict judge_attributes(Global& g, const Char* name) noexcept {
  g.counters->calls.fetch_add(1, std::memory_order_relaxed);
  if (!name || !answering(g)) return Verdict::Pass;
  PathBuffer path;
  if (!normalize(std::basic_string_view<Char>(name), path)) return Verdict::Pass;
  return g.cache->lookup(path.view());
}

void note_verify(Global& g, bool found, const PathBuffer* path) noexcept {
  if (!found) {
    g.counters->answered.fetch_add(1, std::memory_order_relaxed);  // Windows agreed: it would have been answered
    return;
  }
  g.counters->disagreements.fetch_add(1, std::memory_order_relaxed);
  if (path && g.cache) g.cache->drop_path(path->view());
}

template <class Char>
bool normalized(const Char* name, PathBuffer& path) noexcept {
  return name && normalize(std::basic_string_view<Char>(name), path);
}

HANDLE WINAPI hook_create_a(LPCSTR name, DWORD access, DWORD sharing, LPSECURITY_ATTRIBUTES security, DWORD disposition,
                            DWORD flags, HANDLE template_file) {
  Global& g = global();
  const Verdict verdict = judge_open(g, name, access, disposition, flags);
  if (verdict != Verdict::Pass) {
    if (g.counters->verify.load(std::memory_order_relaxed) != 0) {
      const HANDLE file = g.next_create_a(name, access, sharing, security, disposition, flags, template_file);
      const DWORD error = GetLastError();
      PathBuffer path;
      note_verify(g, file != INVALID_HANDLE_VALUE, normalized(name, path) ? &path : nullptr);
      SetLastError(error);
      return file;
    }
    g.counters->answered.fetch_add(1, std::memory_order_relaxed);
    SetLastError(error_of(verdict));
    return INVALID_HANDLE_VALUE;
  }
  return g.next_create_a(name, access, sharing, security, disposition, flags, template_file);
}

HANDLE WINAPI hook_create_w(LPCWSTR name, DWORD access, DWORD sharing, LPSECURITY_ATTRIBUTES security, DWORD disposition,
                            DWORD flags, HANDLE template_file) {
  Global& g = global();
  const Verdict verdict = judge_open(g, name, access, disposition, flags);
  if (verdict != Verdict::Pass) {
    if (g.counters->verify.load(std::memory_order_relaxed) != 0) {
      const HANDLE file = g.next_create_w(name, access, sharing, security, disposition, flags, template_file);
      const DWORD error = GetLastError();
      PathBuffer path;
      note_verify(g, file != INVALID_HANDLE_VALUE, normalized(name, path) ? &path : nullptr);
      SetLastError(error);
      return file;
    }
    g.counters->answered.fetch_add(1, std::memory_order_relaxed);
    SetLastError(error_of(verdict));
    return INVALID_HANDLE_VALUE;
  }
  return g.next_create_w(name, access, sharing, security, disposition, flags, template_file);
}

BOOL WINAPI hook_attributes_a(LPCSTR name, GET_FILEEX_INFO_LEVELS level, LPVOID data) {
  Global& g = global();
  const Verdict verdict = judge_attributes(g, name);
  if (verdict != Verdict::Pass) {
    if (g.counters->verify.load(std::memory_order_relaxed) != 0) {
      const BOOL found = g.next_attributes_a(name, level, data);
      const DWORD error = GetLastError();
      PathBuffer path;
      note_verify(g, found != FALSE, normalized(name, path) ? &path : nullptr);
      SetLastError(error);
      return found;
    }
    g.counters->answered.fetch_add(1, std::memory_order_relaxed);
    SetLastError(error_of(verdict));
    return FALSE;
  }
  return g.next_attributes_a(name, level, data);
}

BOOL WINAPI hook_attributes_w(LPCWSTR name, GET_FILEEX_INFO_LEVELS level, LPVOID data) {
  Global& g = global();
  const Verdict verdict = judge_attributes(g, name);
  if (verdict != Verdict::Pass) {
    if (g.counters->verify.load(std::memory_order_relaxed) != 0) {
      const BOOL found = g.next_attributes_w(name, level, data);
      const DWORD error = GetLastError();
      PathBuffer path;
      note_verify(g, found != FALSE, normalized(name, path) ? &path : nullptr);
      SetLastError(error);
      return found;
    }
    g.counters->answered.fetch_add(1, std::memory_order_relaxed);
    SetLastError(error_of(verdict));
    return FALSE;
  }
  return g.next_attributes_w(name, level, data);
}

// ---- Import slots --------------------------------------------------------------------------------------------------

bool kernel_import(const char* dll) {
  const auto starts = [&](const char* prefix) { return _strnicmp(dll, prefix, std::strlen(prefix)) == 0; };
  return starts("kernel32") || starts("kernelbase") || starts("api-ms-win-core-file");
}

// Every import slot of `function` (by name, from KERNEL32, KERNELBASE or an api-ms-win-core-file set) in `module`.
// Every RVA is checked against the mapped image.
std::vector<void**> import_slots(HMODULE module, const char* function) {
  std::vector<void**> out;
  auto* image = reinterpret_cast<std::uint8_t*>(module);
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return out;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return out;
  const std::uint64_t image_size = nt->OptionalHeader.SizeOfImage;
  const auto inside = [&](std::uint64_t rva, std::uint64_t size) { return rva < image_size && size <= image_size - rva; };
  const auto& directory = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (!directory.VirtualAddress || !inside(directory.VirtualAddress, sizeof(IMAGE_IMPORT_DESCRIPTOR))) return out;
  const auto* descriptor = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(image + directory.VirtualAddress);
  for (std::uint64_t d = 0; inside(directory.VirtualAddress + d * sizeof(IMAGE_IMPORT_DESCRIPTOR), sizeof(IMAGE_IMPORT_DESCRIPTOR)) &&
                            descriptor[d].Name;
       ++d) {
    const IMAGE_IMPORT_DESCRIPTOR& entry = descriptor[d];
    if (!inside(entry.Name, 1) || !kernel_import(reinterpret_cast<const char*>(image + entry.Name))) continue;
    if (!entry.OriginalFirstThunk || !inside(entry.OriginalFirstThunk, sizeof(IMAGE_THUNK_DATA64)) ||
        !inside(entry.FirstThunk, sizeof(IMAGE_THUNK_DATA64))) {
      continue;
    }
    const auto* names = reinterpret_cast<const IMAGE_THUNK_DATA64*>(image + entry.OriginalFirstThunk);
    auto* slots = reinterpret_cast<IMAGE_THUNK_DATA64*>(image + entry.FirstThunk);
    for (std::uint64_t i = 0; inside(entry.OriginalFirstThunk + i * sizeof(IMAGE_THUNK_DATA64), sizeof(IMAGE_THUNK_DATA64)) &&
                              inside(entry.FirstThunk + i * sizeof(IMAGE_THUNK_DATA64), sizeof(IMAGE_THUNK_DATA64)) &&
                              names[i].u1.AddressOfData;
         ++i) {
      if (IMAGE_SNAP_BY_ORDINAL64(names[i].u1.Ordinal)) continue;
      const std::uint64_t name_rva = names[i].u1.AddressOfData;
      if (!inside(name_rva, sizeof(IMAGE_IMPORT_BY_NAME))) continue;
      const auto* by_name = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(image + name_rva);
      const std::size_t room = static_cast<std::size_t>(image_size - name_rva - offsetof(IMAGE_IMPORT_BY_NAME, Name));
      const char* text = reinterpret_cast<const char*>(by_name->Name);
      if (strnlen(text, room) == room || std::strcmp(text, function) != 0) continue;
      out.push_back(reinterpret_cast<void**>(&slots[i].u1.Function));
    }
  }
  return out;
}

bool write_slot(void** slot, void* value) {
  DWORD previous = 0;
  if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &previous)) return false;
  InterlockedExchangePointer(slot, value);
  DWORD ignored = 0;
  VirtualProtect(slot, sizeof(void*), previous, &ignored);
  return true;
}

// The module an address lies in, if it exports nl_fs_accel_v1 (a copy of this module).
HMODULE accelerator_owning(void* address) {
  HMODULE owner = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          static_cast<LPCWSTR>(address), &owner)) {
    return nullptr;
  }
  return owner && GetProcAddress(owner, "nl_fs_accel_v1") ? owner : nullptr;
}

HMODULE this_module() {
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&global), &self);
  return self;
}

std::wstring game_garrysmod() {
  std::wstring exe(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
  if (!length || length >= exe.size()) return {};
  exe.resize(length);
  // <root>\bin\win64\gmod.exe (or <root>\gmod.exe for 32-bit layouts): the root holds garrysmod\.
  std::wstring dir = exe.substr(0, exe.find_last_of(L"\\/"));
  for (int up = 0; up < 3 && !dir.empty(); ++up) {
    const DWORD attributes = GetFileAttributesW((dir + L"\\garrysmod\\addons").c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY)) return dir + L"\\garrysmod";
    const auto cut = dir.find_last_of(L"\\/");
    if (cut == std::wstring::npos) break;
    dir.resize(cut);
  }
  return {};
}

// ---- The start-up marker ------------------------------------------------------------------------------------------

constexpr wchar_t kLeftOutVariable[] = L"NL_FS_ACCEL_LEFT_OUT";  // the id of the process that left the hooks out
constexpr char kLeftOutReason[] =
    "left out once: the last start with the hooks ended before a map had loaded with them "
    "(garrysmod/data/nativeloader/load_accel_pending.txt); the next start uses them again";
constexpr DWORD kSettledMs = 20000;

unsigned long long filetime_value(const FILETIME& time) {
  return (static_cast<unsigned long long>(time.dwHighDateTime) << 32) | time.dwLowDateTime;
}

// A process's id with its creation time, which tells it from a later process that has the same id.
bool stamp_of(HANDLE process, DWORD pid, ProcessStamp& out) {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(process, &created, &exited, &kernel, &user)) return false;
  out.pid = pid;
  out.created = filetime_value(created);
  return true;
}

bool still_running(const ProcessStamp& stamp) {
  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, stamp.pid);
  if (!process) return false;  // gone, or the id is another user's process now
  ProcessStamp now;
  const bool same = stamp_of(process, stamp.pid, now) && now.created == stamp.created &&
      WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
  CloseHandle(process);
  return same;
}

bool read_marker(const std::wstring& path, ProcessStamp& out) {
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  char text[64]{};
  DWORD size = 0;
  const BOOL read = ReadFile(file, text, sizeof(text) - 1, &size, nullptr);
  CloseHandle(file);
  if (!read) return false;
  text[size] = '\0';
  char* end = nullptr;
  const unsigned long pid = std::strtoul(text, &end, 10);
  if (end == text || *end != ' ' || pid == 0) return false;
  const char* second = end + 1;
  const unsigned long long created = std::strtoull(second, &end, 10);
  if (end == second) return false;
  out.pid = pid;
  out.created = created;
  return true;
}

// The left-out start's refusal holds for the process: the module's other copy (gmcl_ against gmsv_) reads it here. A
// child process inherits the variable with an id that is not its own.
void remember_left_out(const ProcessStamp& self) {
  wchar_t text[16]{};
  swprintf_s(text, L"%lu", self.pid);
  SetEnvironmentVariableW(kLeftOutVariable, text);
}

bool left_out_in_process() {
  wchar_t text[16]{};
  const DWORD size = GetEnvironmentVariableW(kLeftOutVariable, text, 16);
  return size > 0 && size < 16 && std::wcstoul(text, nullptr, 10) == GetCurrentProcessId();
}

struct ClearLater {
  std::wstring path;
  ProcessStamp self;
  const Counters* counters;  // the installing copy's: settle() from either copy lands there
};

// The marker comes off once a map has loaded with the hooks in (most lookups are in a load: a menu start alone proves
// little) and at least 20 s after they went in. A game that quits before any map leaves it, and the next start goes
// without the hooks once.
DWORD WINAPI clear_when_settled(void* parameter) {
  const auto* job = static_cast<const ClearLater*>(parameter);
  const ULONGLONG start = GetTickCount64();
  while (GetTickCount64() - start < kSettledMs || job->counters->settled.load(std::memory_order_acquire) == 0) Sleep(1000);
  clear_marker(job->path, job->self);
  delete job;
  return 0;
}

bool clear_later(const std::wstring& path, const ProcessStamp& self, const Counters* counters) {
  auto* job = new ClearLater{path, self, counters};
  const HANDLE thread = CreateThread(nullptr, 0, &clear_when_settled, job, 0, nullptr);
  if (!thread) {
    delete job;
    return false;
  }
  CloseHandle(thread);
  return true;
}

InstallResult install_locked(Global& g) {
  InstallResult result;
  if (left_out_in_process()) {
    result.reason = kLeftOutReason;
    return result;
  }
  const HMODULE filesystem = GetModuleHandleW(L"filesystem_stdio.dll");
  if (!filesystem) {
    result.reason = "filesystem_stdio.dll is not loaded";
    return result;
  }
  const auto create_a = import_slots(filesystem, "CreateFileA");
  const auto create_w = import_slots(filesystem, "CreateFileW");
  const auto attributes_a = import_slots(filesystem, "GetFileAttributesExA");
  const auto attributes_w = import_slots(filesystem, "GetFileAttributesExW");
  if (create_a.empty() || create_w.empty() || attributes_a.empty() || attributes_w.empty()) {
    result.reason = "filesystem_stdio.dll does not import CreateFileA/W and GetFileAttributesExA/W";
    return result;
  }
  // Another copy of this module (gmcl_ against gmsv_) hooked them already: report its hooks and counters.
  if (const HMODULE other = accelerator_owning(*create_a.front()); other && other != this_module()) {
    using Export = Counters* (*)();
    const auto shared = reinterpret_cast<Export>(GetProcAddress(other, "nl_fs_accel_v1"));
    Counters* counters = shared ? shared() : nullptr;
    if (counters && counters->version == 1 && counters->size >= sizeof(Counters)) g.counters = counters;
    result.installed = true;
    result.by_other = true;
    result.reason = "installed by the module's other copy";
    return result;
  }
  // Every slot of one function must hold the same function, or a pass-through could skip a hook.
  const auto same = [](const std::vector<void**>& slots) {
    for (void** slot : slots) {
      if (*slot != *slots.front()) return false;
    }
    return true;
  };
  if (!same(create_a) || !same(create_w) || !same(attributes_a) || !same(attributes_w)) {
    result.reason = "an import of filesystem_stdio.dll is bound to two different functions";
    return result;
  }
  const std::wstring garrysmod = game_garrysmod();
  if (garrysmod.empty()) {
    result.reason = "the game's garrysmod folder was not found";
    return result;
  }
  const std::wstring marker = garrysmod + L"\\data\\nativeloader\\load_accel_pending.txt";
  const ProcessStamp self = current_stamp();
  // Only when the marker could be removed: "once" must hold, or every start would refuse.
  if (check_marker(marker, self) == MarkerCheck::LeftOut && DeleteFileW(marker.c_str())) {
    remember_left_out(self);
    result.reason = kLeftOutReason;
    return result;
  }
  // The watch first, so that no change after a listing goes unseen.
  if (!g.watcher.arm(garrysmod, &result.reason)) return result;
  if (!g.own_cache.init(garrysmod, g.counters, &result.reason)) return result;
  if (!g.watcher.run(&g.own_cache, &result.reason)) return result;
  HMODULE pinned = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                          reinterpret_cast<LPCWSTR>(&global), &pinned)) {
    result.reason = "this module could not be pinned";
    return result;
  }
  g.next_create_a = reinterpret_cast<CreateA>(*create_a.front());
  g.next_create_w = reinterpret_cast<CreateW>(*create_w.front());
  g.next_attributes_a = reinterpret_cast<AttributesA>(*attributes_a.front());
  g.next_attributes_w = reinterpret_cast<AttributesW>(*attributes_w.front());
  if (const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll")) {
    g.shutting_down = reinterpret_cast<ShutdownProbe>(GetProcAddress(ntdll, "RtlDllShutdownInProgress"));
  }
  g.cache = &g.own_cache;
  // The marker goes down before the hooks go in, and comes off once the game has run on with them for 20 s.
  const bool marked = write_marker(marker, self);
  bool all = true;
  for (void** slot : create_a) all &= write_slot(slot, reinterpret_cast<void*>(&hook_create_a));
  for (void** slot : create_w) all &= write_slot(slot, reinterpret_cast<void*>(&hook_create_w));
  for (void** slot : attributes_a) all &= write_slot(slot, reinterpret_cast<void*>(&hook_attributes_a));
  for (void** slot : attributes_w) all &= write_slot(slot, reinterpret_cast<void*>(&hook_attributes_w));
  if (marked && !clear_later(marker, self, g.counters)) clear_marker(marker, self);
  result.installed = true;
  result.reason = all ? "installed" : "installed, but a slot could not be written";
  return result;
}

}  // namespace

InstallResult install() {
  Global& g = global();
  AcquireSRWLockExclusive(&g.lock);
  InstallResult result;
  try {
    if (!g.attempted) {
      g.attempted = true;
      g.result = install_locked(g);
    }
    result = g.result;
  } catch (...) {
    result.reason = "install failed (out of memory)";
  }
  ReleaseSRWLockExclusive(&g.lock);
  return result;
}

InstallResult install_status() {
  Global& g = global();
  AcquireSRWLockShared(&g.lock);
  InstallResult result;
  try {
    result = g.result;
  } catch (...) {
  }
  ReleaseSRWLockShared(&g.lock);
  return result;
}

ProcessStamp current_stamp() noexcept {
  ProcessStamp stamp;
  stamp.pid = GetCurrentProcessId();
  ProcessStamp timed;
  if (stamp_of(GetCurrentProcess(), stamp.pid, timed)) stamp = timed;
  return stamp;
}

MarkerCheck check_marker(const std::wstring& path, const ProcessStamp& self) noexcept {
  ProcessStamp written;
  if (!read_marker(path, written)) return MarkerCheck::None;
  if (written.pid == self.pid && written.created == self.created) return MarkerCheck::None;
  return still_running(written) ? MarkerCheck::Running : MarkerCheck::LeftOut;
}

bool write_marker(const std::wstring& path, const ProcessStamp& self) noexcept {
  try {
    // garrysmod\data, then its nativeloader folder.
    const auto folder = path.substr(0, path.find_last_of(L'\\'));
    CreateDirectoryW(folder.substr(0, folder.find_last_of(L'\\')).c_str(), nullptr);
    CreateDirectoryW(folder.c_str(), nullptr);
  } catch (...) {
    return false;
  }
  char text[64]{};
  const int size = std::snprintf(text, sizeof(text), "%lu %llu\r\n", self.pid, self.created);
  if (size <= 0 || size >= static_cast<int>(sizeof(text))) return false;
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool ok = WriteFile(file, text, static_cast<DWORD>(size), &written, nullptr) && written == static_cast<DWORD>(size);
  CloseHandle(file);
  if (!ok) DeleteFileW(path.c_str());
  return ok;
}

bool clear_marker(const std::wstring& path, const ProcessStamp& self) noexcept {
  ProcessStamp written;
  if (!read_marker(path, written) || written.pid != self.pid || written.created != self.created) return false;
  return DeleteFileW(path.c_str()) != FALSE;
}

Counters& counters() noexcept { return *global().counters; }

void settle() noexcept { global().counters->settled.store(1, std::memory_order_release); }

// The switches of the hooks in this process: the counters of the copy that installed them.
void set_enabled(bool on) noexcept { global().counters->enabled.store(on ? 1 : 0, std::memory_order_relaxed); }

void set_verify(bool on) noexcept { global().counters->verify.store(on ? 1 : 0, std::memory_order_relaxed); }

namespace testing {
void bind(LooseCache* cache, CreateA create_a, CreateW create_w, AttributesA attributes_a, AttributesW attributes_w) noexcept {
  Global& g = global();
  g.cache = cache;
  g.next_create_a = reinterpret_cast<::nl::fs_accel::CreateA>(create_a);
  g.next_create_w = reinterpret_cast<::nl::fs_accel::CreateW>(create_w);
  g.next_attributes_a = reinterpret_cast<::nl::fs_accel::AttributesA>(attributes_a);
  g.next_attributes_w = reinterpret_cast<::nl::fs_accel::AttributesW>(attributes_w);
}
void* create_a(const char* name, unsigned long access, unsigned long sharing, void* security, unsigned long disposition,
               unsigned long flags, void* template_file) noexcept {
  return hook_create_a(name, access, sharing, static_cast<LPSECURITY_ATTRIBUTES>(security), disposition, flags, template_file);
}
void* create_w(const wchar_t* name, unsigned long access, unsigned long sharing, void* security, unsigned long disposition,
               unsigned long flags, void* template_file) noexcept {
  return hook_create_w(name, access, sharing, static_cast<LPSECURITY_ATTRIBUTES>(security), disposition, flags, template_file);
}
int attributes_a(const char* name, int level, void* data) noexcept {
  return hook_attributes_a(name, static_cast<GET_FILEEX_INFO_LEVELS>(level), data);
}
int attributes_w(const wchar_t* name, int level, void* data) noexcept {
  return hook_attributes_w(name, static_cast<GET_FILEEX_INFO_LEVELS>(level), data);
}
}  // namespace testing

}  // namespace nl::fs_accel

// The counters of this copy, for the module's other copy and the engine guard's load overlay.
extern "C" __declspec(dllexport) nl::fs_accel::Counters* nl_fs_accel_v1() { return &nl::fs_accel::counters(); }
