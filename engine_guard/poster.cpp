// GMod's `poster` command in RTX starts (ADR 0226); see poster.h.
#include "poster.h"

#include "load_eta.h"

#include <windows.h>

#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <iterator>
#include <mutex>
#include <string_view>

namespace nl::engine_guard::poster {

namespace {

struct Section {
  const std::uint8_t* data = nullptr;
  std::size_t size = 0;
  DWORD characteristics = 0;
};

// The module's sections, from its headers in memory.
int sections(const void* module, Section* out, int capacity) noexcept {
  int count = 0;
  __try {
    const auto* base = static_cast<const std::uint8_t*>(module);
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return 0;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) return 0;
    const auto* section = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections && count < capacity; ++i, ++section) {
      out[count].data = base + section->VirtualAddress;
      out[count].size = section->Misc.VirtualSize;
      out[count].characteristics = section->Characteristics;
      ++count;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
  return count;
}

bool read_only(const Section& s) {
  return (s.characteristics & IMAGE_SCN_MEM_READ) && !(s.characteristics & (IMAGE_SCN_MEM_WRITE | IMAGE_SCN_MEM_EXECUTE));
}
bool writable(const Section& s) { return (s.characteristics & IMAGE_SCN_MEM_WRITE) != 0; }
bool executable(const Section& s) { return (s.characteristics & IMAGE_SCN_MEM_EXECUTE) != 0; }

// Where `text` (with its terminating zero) starts in [data, data + size), up to `capacity` of them.
int find_text(const std::uint8_t* data, std::size_t size, const char* text, std::size_t length, std::uintptr_t* hits,
              int capacity) noexcept {
  int count = 0;
  __try {
    for (std::size_t at = 0; at + length + 1 <= size && count < capacity; ++at) {
      if (data[at] == static_cast<std::uint8_t>(text[0]) && data[at + length] == 0 &&
          std::memcmp(data + at, text, length) == 0) {
        hits[count++] = reinterpret_cast<std::uintptr_t>(data + at);
      }
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
  return count;
}

// Objects in [data, data + size), 8-byte aligned, that hold `value` at `offset`.
int find_pointer(const std::uint8_t* data, std::size_t size, std::uintptr_t value, std::size_t offset,
                 std::uintptr_t* hits, int capacity) noexcept {
  int count = 0;
  __try {
    const std::uintptr_t start = (reinterpret_cast<std::uintptr_t>(data) + 7) & ~std::uintptr_t(7);
    const std::uintptr_t end = reinterpret_cast<std::uintptr_t>(data) + size;
    for (std::uintptr_t at = start; at + offset + sizeof(std::uintptr_t) <= end && count < capacity; at += 8) {
      if (*reinterpret_cast<const std::uintptr_t*>(at + offset) == value) hits[count++] = at;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return -1;
  }
  return count;
}

bool read(const void* at, void* out, std::size_t size) noexcept {
  __try {
    std::memcpy(out, at, size);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
  return true;
}

bool inside(const Section* list, int count, std::uintptr_t address, bool (*kind)(const Section&)) {
  for (int i = 0; i < count; ++i) {
    const auto begin = reinterpret_cast<std::uintptr_t>(list[i].data);
    if (kind(list[i]) && address >= begin && address < begin + list[i].size) return true;
  }
  return false;
}

using Msg = void (*)(const char*, ...);
Msg tier0_msg() {
  static const Msg fn = [] {
    const HMODULE tier0 = GetModuleHandleW(L"tier0.dll");
    return tier0 ? reinterpret_cast<Msg>(GetProcAddress(tier0, "Msg")) : nullptr;
  }();
  return fn;
}

const char* error_text(int code) {
  switch (code) {
    case RTXPOSTER_E_BUSY: return "a poster is already being made";
    case RTXPOSTER_E_VR: return "not while VR runs";
    case RTXPOSTER_E_ARGUMENT: return "the runtime refused its arguments";
    case RTXPOSTER_E_NO_DEVICE: return "the RTX runtime has no device yet";
    default: return "the RTX runtime refused it";
  }
}

// The command as the module found it, and the poster this module started last, while poll() follows it.
std::mutex g_mutex;
Command g_command;
Status g_status;
struct Watch {
  bool active = false;
  std::uint32_t generation = 0;
  std::uint32_t last = RTXPOSTER_STATE_STARTING;
  std::string shown;  // the poster as the console names it: screenshots/<name>.png
} g_watch;

bool file_exists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring g_folder;  // <garrysmod>\screenshots, for poster_name's check
bool taken_in_folder(const std::wstring& name) { return file_exists(g_folder + L"\\" + name + L".png"); }

void command_hook(const void* command) {
  Callback original = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    original = g_command.callback;
  }
  std::vector<std::string> args;
  const Runtime rt = runtime();
  if (!rt.ready() || !arguments(command, args)) {
    if (original) original(command);
    return;
  }
  const Plan what = plan(args);
  const Msg msg = tier0_msg();
  if (what.kind == Plan::Kind::usage) {
    if (original) original(command);  // the engine prints its usage and does nothing else without a multiplier
    return;
  }
  if (what.kind == Plan::Kind::silly) {
    if (msg) msg("Cannot create a poster with silly size of %i.\n", what.multiplier);
    return;
  }
  if (what.kind == Plan::Kind::too_large) {
    if (msg) msg("Cannot create a poster of %i times the window with RTX: at most 16, and 16384 x 16384.\n", what.multiplier);
    return;
  }
  const std::wstring garrysmod = overlay::garrysmod_folder();
  if (garrysmod.empty()) {
    if (msg) msg("The poster was not made: the game's folder was not found.\n");
    return;
  }
  const std::time_t now = std::time(nullptr);
  std::tm local{};
  localtime_s(&local, &now);
  std::wstring name;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_folder = garrysmod + L"\\screenshots";
    CreateDirectoryW(g_folder.c_str(), nullptr);
    name = poster_name(local, taken_in_folder);
  }
  rtxposter_Request request{};
  request.structSize = sizeof(request);
  request.multiplier = static_cast<std::uint32_t>(what.multiplier);
  request.framesPerTile = 0;
  request.flags = what.tiles ? RTXPOSTER_SAVE_TILES : 0;
  const std::wstring path = garrysmod + L"\\screenshots\\" + name + L".png";
  wcsncpy_s(request.path, path.c_str(), _TRUNCATE);
  const int code = rt.start(&request);
  if (code != RTXPOSTER_OK) {
    if (msg) msg("The poster was not made: %s.\n", error_text(code));
    return;
  }
  rtxposter_Status status{};
  status.structSize = sizeof(status);
  rt.status(&status);
  if (msg) msg("Poster %ix with RTX: hold still until it is saved.\n", what.multiplier);
  std::lock_guard<std::mutex> lock(g_mutex);
  g_watch.active = true;
  g_watch.generation = status.generation;
  g_watch.last = RTXPOSTER_STATE_STARTING;
  g_watch.shown = shown_name(path.c_str());
}

}  // namespace

Command find(const void* module) noexcept {
  Command result;
  if (!module) {
    result.reason = "client.dll is not loaded";
    return result;
  }
  Section list[96];
  const int count = sections(module, list, 96);
  if (count <= 0) {
    result.reason = "client.dll's headers could not be read";
    return result;
  }
  // The help text, once in the read-only data.
  std::uintptr_t help[2]{};
  int helps = 0;
  for (int i = 0; i < count && helps < 2; ++i) {
    if (!read_only(list[i])) continue;
    const int found = find_text(list[i].data, list[i].size, kHelp, sizeof(kHelp) - 1, help + helps, 2 - helps);
    if (found < 0) {
      result.reason = "client.dll's read-only data could not be read";
      return result;
    }
    helps += found;
  }
  if (helps != 1) {
    result.reason = helps == 0 ? "client.dll has no poster command's help text" : "client.dll has the poster help text twice";
    return result;
  }
  // The one command object pointing at it, named "poster", with a callback that takes the arguments.
  std::uintptr_t candidates[8]{};
  int found = 0;
  std::uintptr_t object = 0;
  Callback callback = nullptr;
  for (int i = 0; i < count; ++i) {
    if (!writable(list[i])) continue;
    const int hits = find_pointer(list[i].data, list[i].size, help[0], kHelpOffset, candidates, 8);
    for (int h = 0; h < hits; ++h) {
      std::uintptr_t name = 0, function = 0;
      std::uint8_t kind = 0;
      char text[sizeof(kName)]{};
      if (!read(reinterpret_cast<const void*>(candidates[h] + kNameOffset), &name, sizeof(name)) ||
          !read(reinterpret_cast<const void*>(name), text, sizeof(text)) || std::memcmp(text, kName, sizeof(kName)) != 0 ||
          !read(reinterpret_cast<const void*>(candidates[h] + kCallbackOffset), &function, sizeof(function)) ||
          !read(reinterpret_cast<const void*>(candidates[h] + kKindOffset), &kind, sizeof(kind))) {
        continue;
      }
      if ((kind & (kKindArguments | kKindInterface)) != kKindArguments || !inside(list, count, function, executable)) continue;
      ++found;
      object = candidates[h];
      callback = reinterpret_cast<Callback>(function);
    }
  }
  if (found != 1) {
    result.reason = found == 0 ? "client.dll's poster command was not found" : "client.dll has more than one poster command";
    return result;
  }
  result.object = object;
  result.callback = callback;
  return result;
}

bool arguments(const void* command, std::vector<std::string>& out) noexcept {
  out.clear();
  const auto base = reinterpret_cast<std::uintptr_t>(command);
  int argc = 0;
  if (!command || !read(command, &argc, sizeof(argc)) || argc < 1 || argc > kMaxArgs) return false;
  std::uintptr_t argv[kMaxArgs]{};
  if (!read(reinterpret_cast<const void*>(base + kArgvOffset), argv, sizeof(std::uintptr_t) * static_cast<std::size_t>(argc))) {
    return false;
  }
  char text[kArgvOffset - kTextOffset];
  if (!read(reinterpret_cast<const void*>(base + kTextOffset), text, sizeof(text))) return false;
  std::vector<std::string> result;
  for (int i = 0; i < argc; ++i) {
    if (argv[i] < base + kTextOffset || argv[i] >= base + kArgvOffset) return false;
    const std::size_t at = argv[i] - (base + kTextOffset);
    const char* begin = text + at;
    const auto* end = static_cast<const char*>(std::memchr(begin, 0, sizeof(text) - at));
    if (!end) return false;
    result.emplace_back(begin, static_cast<std::size_t>(end - begin));
  }
  if (_stricmp(result[0].c_str(), kName) != 0) return false;
  out.swap(result);
  return true;
}

bool install(const Command& command, Callback hook) noexcept {
  if (!command.object || !command.callback || !hook) return false;
  auto* slot = reinterpret_cast<void* volatile*>(command.object + kCallbackOffset);
  return InterlockedCompareExchangePointer(slot, reinterpret_cast<void*>(hook), reinterpret_cast<void*>(command.callback)) ==
         reinterpret_cast<void*>(command.callback);
}

bool restore(const Command& command, Callback hook) noexcept {
  if (!command.object || !command.callback || !hook) return false;
  auto* slot = reinterpret_cast<void* volatile*>(command.object + kCallbackOffset);
  return InterlockedCompareExchangePointer(slot, reinterpret_cast<void*>(command.callback), reinterpret_cast<void*>(hook)) ==
         reinterpret_cast<void*>(hook);
}

Plan plan(const std::vector<std::string>& args) {
  Plan result;
  if (args.size() < 2) return result;  // usage
  // The engine: (int)atof(argv[1]), and the tiles when argv[2][0] == '1'.
  const double value = std::atof(args[1].c_str());
  result.multiplier = value >= 2147483647.0 ? 2147483647 : value <= -2147483647.0 ? -2147483647 : static_cast<int>(value);
  result.tiles = args.size() >= 3 && !args[2].empty() && args[2][0] == '1';
  if (result.multiplier < 1) {
    result.kind = Plan::Kind::silly;
  } else if (result.multiplier > 16) {
    result.kind = Plan::Kind::too_large;
  } else {
    result.kind = Plan::Kind::render;
  }
  return result;
}

std::wstring poster_name(const std::tm& now, bool (*taken)(const std::wstring& name)) {
  wchar_t stamp[64]{};
  std::wcsftime(stamp, 64, L"poster-%y-%m-%d %H-%M-%S", &now);
  std::wstring name = stamp;
  for (int n = 2; taken && taken(name) && n < 1000; ++n) name = std::wstring(stamp) + L" " + std::to_wstring(n);
  return name;
}

Runtime runtime() {
  Runtime result;
  const HMODULE d3d9 = GetModuleHandleW(L"d3d9.dll");
  if (!d3d9) return result;
  const auto version = reinterpret_cast<rtxposter_GetApiVersionFn>(GetProcAddress(d3d9, "rtxposter_GetApiVersion"));
  if (!version || version() != RTXPOSTER_API_VERSION) return result;
  result.start = reinterpret_cast<rtxposter_StartFn>(GetProcAddress(d3d9, "rtxposter_Start"));
  result.cancel = reinterpret_cast<rtxposter_CancelFn>(GetProcAddress(d3d9, "rtxposter_Cancel"));
  result.status = reinterpret_cast<rtxposter_GetStatusFn>(GetProcAddress(d3d9, "rtxposter_GetStatus"));
  if (!result.ready()) result = {};
  return result;
}

const char* state_name(std::uint32_t state) {
  switch (state) {
    case RTXPOSTER_STATE_STARTING: return "starting";
    case RTXPOSTER_STATE_RENDERING: return "rendering";
    case RTXPOSTER_STATE_WRITING: return "writing";
    case RTXPOSTER_STATE_DONE: return "done";
    case RTXPOSTER_STATE_FAILED: return "failed";
    default: return "idle";
  }
}

std::string utf8(const wchar_t* text) {
  if (!text || !*text) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string result(static_cast<std::size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, result.data(), size, nullptr, nullptr);
  return result;
}

std::string shown_name(const wchar_t* path) {
  if (!path || !*path) return {};
  const std::wstring_view text(path);
  // A drive's colon separates too: "C:poster.png" shows as "poster.png".
  const std::size_t cut = text.find_last_of(L"\\/:");
  const std::wstring_view leaf = cut == std::wstring_view::npos ? text : text.substr(cut + 1);
  if (leaf.empty()) return {};
  std::wstring_view folder;
  if (cut != std::wstring_view::npos && text[cut] != L':') {
    const std::wstring_view head = text.substr(0, cut);
    const std::size_t start = head.find_last_of(L"\\/:");
    folder = start == std::wstring_view::npos ? head : head.substr(start + 1);
  }
  const std::string name = utf8(std::wstring(leaf).c_str());
  constexpr wchar_t kFolder[] = L"screenshots";
  const bool screenshots = folder.size() == std::size(kFolder) - 1 && _wcsnicmp(folder.data(), kFolder, folder.size()) == 0;
  return screenshots ? "screenshots/" + name : name;
}

std::string shown_reason(const char* why, const wchar_t* path) {
  std::string text = why ? why : "";
  const std::string absolute = utf8(path);
  const std::string shown = shown_name(path);
  const auto replace = [&text](const std::string& from, const std::string& to) {
    if (from.empty()) return;
    for (std::size_t at = text.find(from); at != std::string::npos; at = text.find(from, at + to.size())) {
      text.replace(at, from.size(), to);
    }
  };
  // The whole path first (also the start of "<path>.part"), then its folder alone.
  replace(absolute, shown);
  const std::size_t cut = absolute.find_last_of("\\/");
  if (cut != std::string::npos && cut > 0) {
    const std::size_t slash = shown.rfind('/');
    replace(absolute.substr(0, cut), slash == std::string::npos ? std::string("the poster's folder") : shown.substr(0, slash));
  }
  return text;
}

std::optional<View> view(const Runtime& runtime) {
  rtxposter_Status status{};
  status.structSize = sizeof(status);
  if (!runtime.ready() || runtime.status(&status) != RTXPOSTER_OK) return std::nullopt;
  status.lastErrorText[sizeof(status.lastErrorText) - 1] = '\0';
  status.path[RTXPOSTER_PATH_CHARS - 1] = L'\0';
  View result;
  result.state = state_name(status.state);
  result.generation = status.generation;
  result.error = status.lastError;
  result.width = status.width;
  result.height = status.height;
  result.columns = status.columns;
  result.rows = status.rows;
  result.done = status.tilesDone;
  result.frame = status.frame;
  result.frames = status.framesPerTile;
  result.why = shown_reason(status.lastErrorText, status.path);
  result.path = shown_name(status.path);
  return result;
}

Status take_command() noexcept {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_status.installed) return g_status;
  if (!runtime().ready()) {
    g_status.reason = "the RTX runtime has no poster";
    return g_status;
  }
  // Pinned first: the command's callback is this module's code for the rest of the process.
  HMODULE self = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                          reinterpret_cast<LPCWSTR>(&command_hook), &self)) {
    g_status.reason = "this module could not be pinned";
    return g_status;
  }
  g_command = find(GetModuleHandleW(L"client.dll"));
  if (!g_command.object) {
    g_status.reason = g_command.reason;
    return g_status;
  }
  if (!install(g_command, command_hook)) {
    g_status.reason = "client.dll's poster command changed its callback";
    return g_status;
  }
  g_status.installed = true;
  g_status.reason = "installed";
  return g_status;
}

void poll() noexcept {
  std::string shown;
  rtxposter_Status status{};
  status.structSize = sizeof(status);
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_watch.active) return;
    const Runtime rt = runtime();
    if (!rt.ready() || rt.status(&status) != RTXPOSTER_OK || status.generation != g_watch.generation) {
      g_watch.active = false;  // another poster, or no runtime: nothing more to say about this one
      return;
    }
    if (status.state == g_watch.last) return;
    g_watch.last = status.state;
    if (status.state == RTXPOSTER_STATE_DONE || status.state == RTXPOSTER_STATE_FAILED) g_watch.active = false;
    shown = g_watch.shown;
  }
  status.lastErrorText[sizeof(status.lastErrorText) - 1] = '\0';
  const Msg msg = tier0_msg();
  if (!msg) return;
  if (status.state == RTXPOSTER_STATE_RENDERING) {
    const unsigned tiles = status.columns * status.rows;
    msg("Rendering the poster at %u x %u: %u tile%s of the window's size, each path traced for %u frames.\n",
        status.width, status.height, tiles, tiles == 1 ? "" : "s", status.framesPerTile);
  } else if (status.state == RTXPOSTER_STATE_WRITING) {
    msg("Saving poster to '%s'\n", shown.c_str());
  } else if (status.state == RTXPOSTER_STATE_DONE) {
    msg("Saved poster to '%s' (%u x %u)\n", shown.c_str(), status.width, status.height);
  } else if (status.state == RTXPOSTER_STATE_FAILED) {
    msg("The poster was not made: %s\n", status.lastErrorText[0] ? status.lastErrorText : "it stopped");
  }
}

}  // namespace nl::engine_guard::poster
