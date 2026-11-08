// The start-up watchdog (ADR 0130): see watchdog.h.
#include "watchdog.h"
#include "guard.h"
#include <windows.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>

namespace nl::engine_guard::watchdog {
namespace {
constexpr std::size_t kStackCopy = std::size_t{1} << 20;

std::atomic<bool> g_running{false};
std::atomic<bool> g_done{false};
std::atomic<bool> g_told{false};    // one message per process
std::atomic<bool> g_reported{false};  // this start was reported
std::atomic<std::uint64_t> g_deadline{0};  // finish_after(): GetTickCount64() at which the watch ends
HANDLE g_main = nullptr;            // the realm's main thread
HANDLE g_wake = nullptr;            // set by done()
std::uintptr_t g_stack_base = 0;
const NT_TIB* g_tib = nullptr;      // the main thread's, for its committed stack limit
std::uint8_t* g_buffer = nullptr;   // allocated before any suspension
std::mutex g_text;
std::string g_title = "Garry's Mod";
std::string g_body = "Garry's Mod has been running the same add-on file for 90 seconds while starting Lua:\n\n%s\n\n"
                     "If it does not go on, an add-on is stuck: end the game and disable the add-on that has this "
                     "file. The details are in garrysmod\\data\\native-loader\\startup-stall.json.";
std::string g_realm = "client";     // set once by start(), before the thread exists

bool copy_guarded(std::uint8_t* to, const std::uint8_t* from, std::size_t size) noexcept {
  __try {
    std::memcpy(to, from, size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

struct Raw {
  std::uintptr_t rip = 0;
  std::size_t bytes = 0;
};

// Suspends the main thread only for GetThreadContext and one copy into g_buffer: nothing here takes a
// lock the suspended thread could hold (no allocation, no loader or heap call).
Raw sample_raw() noexcept {
  Raw raw;
  if (SuspendThread(g_main) == static_cast<DWORD>(-1)) return raw;
  CONTEXT context{};
  context.ContextFlags = CONTEXT_CONTROL;
  // Only the committed stack, from StackLimit up: below it lies the guard page, and touching that from this
  // thread would take the guard away from the main thread's stack growth.
  const std::uintptr_t limit = g_tib ? reinterpret_cast<std::uintptr_t>(g_tib->StackLimit) : g_stack_base;
  if (GetThreadContext(g_main, &context) && context.Rsp < g_stack_base) {
    const std::uintptr_t from = context.Rsp > limit ? context.Rsp : limit;
    const std::size_t available = static_cast<std::size_t>(g_stack_base - from);
    const std::size_t size = available < kStackCopy ? available : kStackCopy;
    if (size && copy_guarded(g_buffer, reinterpret_cast<const std::uint8_t*>(from), size)) {
      raw.rip = context.Rip;
      raw.bytes = size;
    }
  }
  ResumeThread(g_main);
  return raw;
}

std::string where(std::uintptr_t address) {
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(address), &module))
    return "outside any module";
  wchar_t path[MAX_PATH]{};
  GetModuleFileNameW(module, path, MAX_PATH);
  const wchar_t* name = std::wcsrchr(path, L'\\');
  name = name ? name + 1 : path;
  char narrow[MAX_PATH]{};
  WideCharToMultiByte(CP_UTF8, 0, name, -1, narrow, MAX_PATH, nullptr, nullptr);
  char text[MAX_PATH + 32]{};
  std::snprintf(text, sizeof(text), "%s+0x%llx", narrow,
                static_cast<unsigned long long>(address - reinterpret_cast<std::uintptr_t>(module)));
  return text;
}

std::wstring wide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(static_cast<std::size_t>(size > 0 ? size : 0), L'\0');
  if (size > 0) MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}

std::wstring report_path() {
  wchar_t exe[MAX_PATH]{};
  GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring root(exe);
  for (int i = 0; i < 3; ++i) {  // ...\bin\win64\gmod.exe -> the game root
    const auto slash = root.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return {};
    root.erase(slash);
  }
  const std::wstring folder = root + L"\\garrysmod\\data\\native-loader";
  CreateDirectoryW(folder.c_str(), nullptr);
  return folder + L"\\startup-stall.json";
}

void write_report(const std::string& json) {
  const auto path = report_path();
  if (path.empty()) return;
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr);
  CloseHandle(file);
}

std::string utc_now() {
  SYSTEMTIME now{};
  GetSystemTime(&now);
  char text[40]{};
  std::snprintf(text, sizeof(text), "%04u-%02u-%02uT%02u:%02u:%02uZ", now.wYear, now.wMonth, now.wDay, now.wHour,
                now.wMinute, now.wSecond);
  return text;
}

// The first copy of the module to get here holds this name for the process's life; the other one
// (client and server are two images) then shows nothing.
bool first_message_in_process() {
  wchar_t name[64]{};
  swprintf_s(name, L"Local\\nlengineguard.message.%lu", GetCurrentProcessId());
  const HANDLE token = CreateMutexW(nullptr, FALSE, name);
  if (!token) return true;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(token);
    return false;
  }
  return true;  // kept open on purpose
}

void tell(const std::string& file) {
  if (g_told.exchange(true) || !first_message_in_process()) return;
  std::string title, body;
  {
    std::lock_guard<std::mutex> lock(g_text);
    title = g_title;
    body = g_body;
  }
  const auto at = body.find("%s");
  if (at != std::string::npos) body.replace(at, 2, file);
  MessageBoxW(nullptr, wide(body).c_str(), wide(title).c_str(), MB_OK | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND);
}

DWORD WINAPI run(void*) {
  std::string top;
  const std::uint64_t began = GetTickCount64();
  std::uint64_t since = began;
  std::vector<Sample> recent;
  bool reported = false;
  while (WaitForSingleObject(g_wake, kSampleMs) == WAIT_TIMEOUT && !g_done.load()) {
    try {
      const std::uint64_t deadline = g_deadline.load();
      if (reported || GetTickCount64() - began > kGiveUpMs || (deadline && GetTickCount64() >= deadline)) break;
      const Raw raw = sample_raw();
      if (!raw.rip) continue;
      Sample sample;
      sample.where = where(raw.rip);
      sample.names = lua_names(g_buffer, raw.bytes, 8);
      const std::string now_top = sample.names.empty() ? std::string() : sample.names.front();
      recent.push_back(std::move(sample));
      if (recent.size() > 4) recent.erase(recent.begin());
      const std::uint64_t now = GetTickCount64();
      if (now_top != top) {
        top = now_top;
        since = now;
        continue;
      }
      if (top.empty() || now - since < kStallMs) continue;
      reported = true;
      g_reported.store(true);  // first: a StartupDone() meanwhile then removes the report
      write_report(report_json(utc_now(), g_realm, now - since, recent, status().cut));
      tell(top);
    } catch (...) {
    }
  }
  // The stack copy is the watch's only sizeable memory: give it back until the next Lua start
  // (start() allocates it again, and runs only once g_running is false).
  if (g_buffer) {
    VirtualFree(g_buffer, 0, MEM_RELEASE);
    g_buffer = nullptr;
  }
  g_running.store(false);
  return 0;
}
}  // namespace

void start(std::string_view realm) noexcept {
  if (g_running.exchange(true)) return;
  try {
    g_realm.assign(realm);
    // The thread runs code of this module after the Lua state that loaded it closes: pin it.
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                       reinterpret_cast<LPCWSTR>(&start), &self);
    if (!g_buffer) g_buffer = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, kStackCopy, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
    if (!g_wake) g_wake = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (g_main) CloseHandle(g_main);
    g_main = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, GetCurrentThreadId());
    g_tib = reinterpret_cast<const NT_TIB*>(NtCurrentTeb());
    g_stack_base = reinterpret_cast<std::uintptr_t>(g_tib->StackBase);
    if (!g_buffer || !g_wake || !g_main) {
      g_running.store(false);
      return;
    }
    g_done.store(false);
    g_reported.store(false);
    g_deadline.store(0);
    ResetEvent(g_wake);
    const HANDLE thread = CreateThread(nullptr, 0, run, nullptr, 0, nullptr);
    if (!thread) {
      g_running.store(false);
      return;
    }
    CloseHandle(thread);
  } catch (...) {
    g_running.store(false);
  }
}

void finish_after(std::uint64_t ms) noexcept {
  std::uint64_t none = 0;
  g_deadline.compare_exchange_strong(none, GetTickCount64() + ms);
}

bool done() noexcept {
  g_done.store(true);
  if (g_wake) SetEvent(g_wake);
  return g_reported.exchange(false);
}

void set_message(std::string_view title, std::string_view body) noexcept {
  // The first call wins (the companion's, before any add-on runs); later Lua cannot set the text.
  static std::atomic<bool> set{false};
  if (set.exchange(true)) return;
  try {
    std::lock_guard<std::mutex> lock(g_text);
    if (!title.empty()) g_title.assign(title);
    if (body.find("%s") != std::string_view::npos) g_body.assign(body);
  } catch (...) {
  }
}

std::vector<std::string> lua_names(const std::uint8_t* data, std::size_t size, std::size_t limit) {
  std::vector<std::string> names;
  const auto path_char = [](std::uint8_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' ||
           c == '.' || c == '/' || c == '\\' || c == '@' || c == '!' || c == '~' || c == '+';
  };
  for (std::size_t i = 0; i + 4 <= size && names.size() < limit; ++i) {
    if (data[i] != '.' || (data[i + 1] | 0x20) != 'l' || (data[i + 2] | 0x20) != 'u' || (data[i + 3] | 0x20) != 'a') continue;
    if (i + 4 < size && path_char(data[i + 4]) && data[i + 4] != '.') continue;  // ".luac", ".lua_x"
    std::size_t begin = i;
    while (begin > 0 && i - begin < 260 && path_char(data[begin - 1])) --begin;
    std::string name(reinterpret_cast<const char*>(data + begin), i + 4 - begin);
    if (name.find('/') == std::string::npos && name.find('\\') == std::string::npos) continue;
    if (name.size() < 8) continue;
    bool seen = false;
    for (const auto& known : names) seen = seen || known == name;
    if (!seen) names.push_back(std::move(name));
  }
  return names;
}

std::string json_string(std::string_view text) {
  std::string out = "\"";
  for (const char c : text) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char code[8]{};
          std::snprintf(code, sizeof(code), "\\u%04x", static_cast<unsigned char>(c));
          out += code;
        } else {
          out += c;
        }
    }
  }
  return out + "\"";
}

std::string report_json(std::string_view utc, std::string_view realm, std::uint64_t stalled_ms,
                        const std::vector<Sample>& samples, unsigned guard_cut) {
  std::string out = "{\"schema\":1,\"utc\":" + json_string(utc) + ",\"realm\":" + json_string(realm) +
                    ",\"process_id\":" + std::to_string(GetCurrentProcessId()) +
                    ",\"stalled_seconds\":" + std::to_string(stalled_ms / 1000) +
                    ",\"guard_cut\":" + std::to_string(guard_cut) + ",\"samples\":[";
  for (std::size_t i = 0; i < samples.size(); ++i) {
    if (i) out += ",";
    out += "{\"where\":" + json_string(samples[i].where) + ",\"lua\":[";
    for (std::size_t j = 0; j < samples[i].names.size(); ++j) {
      if (j) out += ",";
      out += json_string(samples[i].names[j]);
    }
    out += "]}";
  }
  return out + "]}\n";
}

}  // namespace nl::engine_guard::watchdog
