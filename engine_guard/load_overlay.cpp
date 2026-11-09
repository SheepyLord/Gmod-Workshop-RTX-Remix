// The map-load overlay (R24, ADR 0134): see load_overlay.h.
#include "load_overlay.h"
#include "watchdog.h"
#include <windows.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <mutex>

namespace nl::engine_guard::overlay {

std::vector<std::string> resource_paths(const std::uint8_t* data, std::size_t size, std::size_t limit) {
  static const char* const kExtensions[] = {".vmt", ".vtf", ".mdl", ".vvd", ".vtx", ".phy", ".bsp", ".pcf",
                                            ".wav", ".mp3", ".ogg", ".ttf", ".png", ".jpg", ".ani"};
  static const char* const kRoots[] = {"materials/", "models/", "maps/", "particles/", "sound/", "resource/",
                                       "scripts/", "gamemodes/"};
  std::vector<std::string> paths;
  const auto path_char = [](std::uint8_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' ||
           c == '.' || c == '/' || c == '\\' || c == ' ' || c == ':' || c == '!' || c == '~' || c == '+' || c == '#';
  };
  for (std::size_t i = 0; i + 4 <= size && paths.size() < limit; ++i) {
    if (data[i] != '.') continue;
    const char* matched = nullptr;
    for (const char* extension : kExtensions) {
      bool same = true;
      for (std::size_t k = 1; k < 4 && same; ++k) same = (data[i + k] | 0x20) == static_cast<std::uint8_t>(extension[k]);
      if (same) { matched = extension; break; }
    }
    if (!matched) continue;
    if (i + 4 < size && path_char(data[i + 4]) && data[i + 4] != ' ') continue;  // ".vmtx", "foo.mdl.bak"
    std::size_t begin = i;
    while (begin > 0 && i - begin < 300 && path_char(data[begin - 1])) --begin;
    std::string path(reinterpret_cast<const char*>(data + begin), i + 4 - begin);
    while (!path.empty() && path.front() == ' ') path.erase(path.begin());
    std::replace(path.begin(), path.end(), '\\', '/');
    if (path.find('*') != std::string::npos || path.find('?') != std::string::npos) continue;
    std::string lower(path);
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    // An absolute or add-on path is cut to the game-relative part at the first game folder in it
    // ("h:/.../addons/x/materials/models/y.vtf" -> "materials/models/y.vtf").
    std::size_t cut = std::string::npos;
    for (const char* root : kRoots) {
      if (lower.rfind(root, 0) == 0) { cut = 0; break; }
      const std::size_t at = lower.find(std::string("/") + root);
      if (at != std::string::npos && (cut == std::string::npos || at + 1 < cut)) cut = at + 1;
    }
    if (cut == std::string::npos) continue;
    path.erase(0, cut);
    if (path.size() < 10 || path.find('/') == std::string::npos) continue;
    if (std::find(paths.begin(), paths.end(), path) == paths.end()) paths.push_back(std::move(path));
  }
  return paths;
}

std::string lua_display(std::string_view name) {
  if (!name.empty() && name.front() == '@') name.remove_prefix(1);
  std::string text(name);
  std::replace(text.begin(), text.end(), '\\', '/');
  // An absolute chunk name keeps what follows the game folder: "addons/x/lua/y.lua", "lua/y.lua".
  std::string lower(text);
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  const std::size_t at = lower.rfind("/garrysmod/");
  if (at != std::string::npos) text.erase(0, at + 11);
  return text;
}

std::string clipped(std::string_view text, std::size_t limit) {
  if (text.size() <= limit) return std::string(text);
  // Never in the middle of a UTF-8 sequence: back off while the first byte cut is a continuation byte.
  std::size_t end = limit;
  while (end > 0 && (static_cast<unsigned char>(text[end]) & 0xC0) == 0x80) --end;
  return std::string(text.substr(0, end));
}

std::string elapsed_text(std::uint64_t ms) {
  const std::uint64_t seconds = ms / 1000;
  char text[32];
  if (seconds >= 3600)
    std::snprintf(text, sizeof(text), "%llu:%02llu:%02llu", static_cast<unsigned long long>(seconds / 3600),
                  static_cast<unsigned long long>(seconds / 60 % 60), static_cast<unsigned long long>(seconds % 60));
  else
    std::snprintf(text, sizeof(text), "%llu:%02llu", static_cast<unsigned long long>(seconds / 60),
                  static_cast<unsigned long long>(seconds % 60));
  return text;
}

void Tally::add(const std::string& name) {
  for (auto& item : counts_) {
    if (item.first == name) {
      ++item.second;
      return;
    }
  }
  if (counts_.size() < kTallyLimit) counts_.emplace_back(name, 1);
}

std::vector<std::pair<std::string, std::uint64_t>> Tally::top(std::size_t n) const {
  auto sorted = counts_;
  std::sort(sorted.begin(), sorted.end(), [](const auto& a, const auto& b) {
    return a.second != b.second ? a.second > b.second : a.first < b.first;
  });
  if (sorted.size() > n) sorted.resize(n);
  return sorted;
}

namespace {
constexpr std::size_t kStackCopy = std::size_t{256} << 10;
constexpr UINT_PTR kTimer = 1;
constexpr std::uint64_t kKeepMs = 2000;  // a line stays this long after its name was last seen
constexpr wchar_t kClass[] = L"NativeLoaderLoadOverlay";

std::mutex g_lock;  // everything below that the Lua side writes
std::string g_heading, g_status, g_lua, g_file;
Labels g_labels;
Tally g_tally;
std::uint64_t g_began = 0, g_lua_seen = 0, g_file_seen = 0;
std::atomic<bool> g_active{false};
std::atomic<bool> g_thread_started{false};
HANDLE g_wake = nullptr;
// The sampled thread: written by start() before the window thread first reads it.
HANDLE g_main = nullptr;
std::uintptr_t g_stack_base = 0;
const NT_TIB* g_tib = nullptr;
std::uint8_t* g_buffer = nullptr;
HFONT g_font_bold = nullptr, g_font = nullptr;
int g_font_height = 0;
// The paint buffer, kept while the window keeps its size (the window thread's own).
HDC g_paint_dc = nullptr;
HBITMAP g_paint_bitmap = nullptr;
HGDIOBJ g_paint_old = nullptr;
int g_paint_width = 0, g_paint_height = 0;

bool copy_guarded(std::uint8_t* to, const std::uint8_t* from, std::size_t size) noexcept {
  __try {
    std::memcpy(to, from, size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// As the watchdog: the main thread is suspended only for GetThreadContext and one copy into a buffer
// allocated beforehand, so nothing here waits on a lock the suspended thread could hold.
std::size_t sample() noexcept {
  if (!g_main || !g_buffer || SuspendThread(g_main) == static_cast<DWORD>(-1)) return 0;
  std::size_t bytes = 0;
  CONTEXT context{};
  context.ContextFlags = CONTEXT_CONTROL;
  const std::uintptr_t limit = g_tib ? reinterpret_cast<std::uintptr_t>(g_tib->StackLimit) : g_stack_base;
  if (GetThreadContext(g_main, &context) && context.Rsp < g_stack_base) {
    const std::uintptr_t from = context.Rsp > limit ? context.Rsp : limit;
    const std::size_t available = static_cast<std::size_t>(g_stack_base - from);
    const std::size_t size = available < kStackCopy ? available : kStackCopy;
    if (size && copy_guarded(g_buffer, reinterpret_cast<const std::uint8_t*>(from), size)) bytes = size;
  }
  ResumeThread(g_main);
  return bytes;
}

std::wstring wide(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring out(static_cast<std::size_t>(length > 0 ? length : 0), L'\0');
  if (length > 0) MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), length);
  return out;
}

HWND game_window() {
  HWND hwnd = nullptr;
  const DWORD self = GetCurrentProcessId();
  while ((hwnd = FindWindowExW(nullptr, hwnd, L"Valve001", nullptr)) != nullptr) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == self) return hwnd;
  }
  return nullptr;
}

void tick(HWND hwnd) {
  if (!g_active.load()) {
    if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
    return;
  }
  const std::uint64_t now = GetTickCount64();
  const std::size_t bytes = sample();
  std::string lua, file;
  if (bytes) {
    const auto names = watchdog::lua_names(g_buffer, bytes, 1);
    if (!names.empty()) lua = lua_display(names.front());
    const auto paths = resource_paths(g_buffer, bytes, 1);
    if (!paths.empty()) file = paths.front();
  }
  std::uint64_t began = 0;
  {
    std::lock_guard<std::mutex> lock(g_lock);
    // finish() may have run since the check above (it clears g_began under this lock): nothing more of this load.
    if (g_began == 0 || !g_active.load()) {
      if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
      return;
    }
    if (!lua.empty()) {
      g_lua = lua;
      g_lua_seen = now;
      g_tally.add(lua);
    } else if (now - g_lua_seen > kKeepMs) {
      g_lua.clear();
    }
    if (!file.empty()) {
      g_file = file;
      g_file_seen = now;
    } else if (now - g_file_seen > kKeepMs) {
      g_file.clear();
    }
    began = g_began;
  }
  const HWND owner = GetWindow(hwnd, GW_OWNER);
  if (!owner || !IsWindowVisible(owner) || IsIconic(owner) || now - began < kShowAfterMs) {
    if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
    return;
  }
  RECT client{};
  POINT origin{0, 0};
  if (!GetClientRect(owner, &client) || !ClientToScreen(owner, &origin)) return;
  const int cw = client.right - client.left, ch = client.bottom - client.top;
  if (cw < 320 || ch < 200) return;
  const int line = std::max(16, ch / 32);
  const int margin = std::max(8, ch / 60);
  const int width = std::max(360, std::min(cw - 2 * margin, cw * 50 / 100));
  const int height = line * 4 + line / 2;
  SetWindowPos(hwnd, nullptr, origin.x + margin, origin.y + ch - height - margin, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd, nullptr, FALSE);
}

void paint(HWND hwnd) {
  PAINTSTRUCT ps;
  const HDC dc = BeginPaint(hwnd, &ps);
  RECT rect{};
  GetClientRect(hwnd, &rect);
  const int width = rect.right, height = rect.bottom;
  if (width <= 0 || height <= 0) {
    EndPaint(hwnd, &ps);
    return;
  }
  if (!g_paint_dc || width != g_paint_width || height != g_paint_height) {
    if (g_paint_dc) {
      SelectObject(g_paint_dc, g_paint_old);
      DeleteObject(g_paint_bitmap);
      DeleteDC(g_paint_dc);
    }
    g_paint_dc = CreateCompatibleDC(dc);
    g_paint_bitmap = g_paint_dc ? CreateCompatibleBitmap(dc, width, height) : nullptr;
    if (!g_paint_bitmap) {
      if (g_paint_dc) DeleteDC(g_paint_dc);
      g_paint_dc = nullptr;
      g_paint_width = g_paint_height = 0;
      EndPaint(hwnd, &ps);
      return;
    }
    g_paint_old = SelectObject(g_paint_dc, g_paint_bitmap);
    g_paint_width = width;
    g_paint_height = height;
  }
  const HDC memory = g_paint_dc;
  const HBRUSH background = CreateSolidBrush(RGB(22, 33, 46));
  FillRect(memory, &rect, background);
  DeleteObject(background);
  const HBRUSH edge = CreateSolidBrush(RGB(70, 142, 208));
  FrameRect(memory, &rect, edge);
  DeleteObject(edge);
  const int line = height * 2 / 9;
  const int pad = line / 2;
  if (line != g_font_height) {
    if (g_font) DeleteObject(g_font);
    if (g_font_bold) DeleteObject(g_font_bold);
    g_font = CreateFontW(-(line * 62 / 100), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                         CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    g_font_bold = CreateFontW(-(line * 66 / 100), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    g_font_height = line;
  }
  std::wstring lines[4];
  {
    std::lock_guard<std::mutex> lock(g_lock);
    lines[0] = wide(g_heading + "   " + elapsed_text(g_began ? GetTickCount64() - g_began : 0));
    lines[1] = wide(g_status);
    lines[2] = g_lua.empty() ? std::wstring() : wide(g_labels.lua + ": " + g_lua);
    lines[3] = g_file.empty() ? std::wstring() : wide(g_labels.file + ": " + g_file);
  }
  SetBkMode(memory, TRANSPARENT);
  for (int i = 0; i < 4; ++i) {
    SelectObject(memory, i == 0 ? g_font_bold : g_font);
    SetTextColor(memory, i == 0 ? RGB(237, 244, 255) : RGB(190, 206, 224));
    RECT box{pad, pad / 2 + i * line, width - pad, pad / 2 + (i + 1) * line};
    // A long path loses its middle, so the file's own name stays readable.
    const UINT ellipsis = i >= 2 ? DT_PATH_ELLIPSIS : DT_END_ELLIPSIS;
    DrawTextW(memory, lines[i].c_str(), -1, &box, DT_LEFT | DT_SINGLELINE | DT_VCENTER | ellipsis | DT_NOPREFIX);
  }
  BitBlt(dc, 0, 0, width, height, memory, 0, 0, SRCCOPY);
  EndPaint(hwnd, &ps);
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_TIMER:
      if (wparam == kTimer) tick(hwnd);
      return 0;
    case WM_PAINT:
      paint(hwnd);
      return 0;
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_ERASEBKGND:
      return 1;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

// The window thread: lives for the process (the module is pinned), idle between loads.
DWORD WINAPI run(void*) {
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&run), &self);
  WNDCLASSW wc{};
  wc.lpfnWndProc = window_proc;
  wc.hInstance = self;
  wc.lpszClassName = kClass;
  wc.hCursor = nullptr;
  RegisterClassW(&wc);
  HWND hwnd = nullptr;
  bool ticking = false;
  for (;;) {
    // When the game's window goes, ours (a window of this thread) is unowned, not destroyed: let it go and own the
    // next game window the next load finds.
    if (hwnd && (!IsWindow(hwnd) || !GetWindow(hwnd, GW_OWNER))) {
      if (IsWindow(hwnd)) DestroyWindow(hwnd);
      hwnd = nullptr;
      ticking = false;
    }
    if (!hwnd && g_active.load()) {
      const HWND owner = game_window();
      if (owner) {
        hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, kClass, L"",
                               WS_POPUP, 0, 0, 1, 1, owner, nullptr, self, nullptr);
        if (hwnd) SetLayeredWindowAttributes(hwnd, 0, 232, LWA_ALPHA);
      }
    }
    // The timer runs only during a load: between loads the thread waits for start() and costs nothing.
    if (hwnd && g_active.load() != ticking) {
      ticking = g_active.load();
      if (ticking) SetTimer(hwnd, kTimer, kSampleMs, nullptr);
      else KillTimer(hwnd, kTimer);
    }
    MsgWaitForMultipleObjects(1, &g_wake, FALSE, ticking || (g_active.load() && !hwnd) ? kSampleMs * 4 : INFINITE,
                              QS_ALLINPUT);
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    if (hwnd && !g_active.load() && IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
  }
}

}  // namespace

void start(std::string_view heading_text, const Labels& labels) noexcept {
  try {
    {
      std::lock_guard<std::mutex> lock(g_lock);
      g_heading = clipped(heading_text, 200);
      g_labels.lua = clipped(labels.lua, 40);
      g_labels.file = clipped(labels.file, 40);
      g_status.clear();
      g_lua.clear();
      g_file.clear();
      g_tally.clear();
      g_began = GetTickCount64();
    }
    if (!g_thread_started.load()) {
      // The thread runs this module's code after the Lua state that loaded it closes: pin it. What a failed attempt
      // got is kept for the next one (each made once); the window thread reads these only after CreateThread.
      HMODULE self = nullptr;
      GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                         reinterpret_cast<LPCWSTR>(&start), &self);
      if (!g_buffer)
        g_buffer = static_cast<std::uint8_t*>(VirtualAlloc(nullptr, kStackCopy, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
      if (!g_wake) g_wake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
      if (!g_main) {
        g_main = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, GetCurrentThreadId());
        g_tib = reinterpret_cast<const NT_TIB*>(NtCurrentTeb());
        g_stack_base = reinterpret_cast<std::uintptr_t>(g_tib->StackBase);
      }
      if (!g_buffer || !g_wake || !g_main) return;
      const HANDLE thread = CreateThread(nullptr, 0, run, nullptr, 0, nullptr);
      if (!thread) return;
      CloseHandle(thread);
      g_thread_started.store(true);
    }
    g_active.store(true);
    SetEvent(g_wake);
  } catch (...) {
  }
}

void heading(std::string_view text) noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_lock);
    g_heading = clipped(text, 200);
  } catch (...) {
  }
}

void status(std::string_view text) noexcept {
  try {
    std::lock_guard<std::mutex> lock(g_lock);
    g_status = clipped(text, 200);
  } catch (...) {
  }
}

Summary finish() noexcept {
  Summary summary;
  try {
    g_active.store(false);
    if (g_wake) SetEvent(g_wake);
    std::lock_guard<std::mutex> lock(g_lock);
    summary.seconds = g_began ? static_cast<double>(GetTickCount64() - g_began) / 1000.0 : 0.0;
    for (const auto& [name, count] : g_tally.top(3))
      summary.lua.emplace_back(name, static_cast<double>(count) * kSampleMs / 1000.0);
    g_tally.clear();
    g_began = 0;
  } catch (...) {
  }
  return summary;
}

}  // namespace nl::engine_guard::overlay
