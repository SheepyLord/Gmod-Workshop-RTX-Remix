#include "discovery.h"
#include <Windows.h>
#include <TlHelp32.h>
#include <cwchar>

namespace nl::vrprobe {
Json discover_steamvr() {
  wchar_t local[32768]{};
  const auto length = GetEnvironmentVariableW(L"LOCALAPPDATA", local, 32768);
  std::filesystem::path path;
  std::string error;
  std::vector<std::string> paths;
  bool installed = false;
  if (!length || length >= 32768) error = "LOCALAPPDATA is unavailable";
  else {
    path = std::filesystem::path(local) / L"openvr" / L"openvrpaths.vrpath";
    try {
      paths = runtime_paths(read_text(path, 1024 * 1024));
      for (const auto& p : paths) if (std::filesystem::is_directory(path_utf8(p))) installed = true;
    } catch (const std::exception& e) { error = e.what(); }
  }
  Json::Array processes;
  const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) throw std::runtime_error("process snapshot failed");
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  bool server = false, monitor = false, compositor = false;
  if (Process32FirstW(snapshot, &entry)) do {
    const bool s = _wcsicmp(entry.szExeFile, L"vrserver.exe") == 0;
    const bool m = _wcsicmp(entry.szExeFile, L"vrmonitor.exe") == 0;
    const bool c = _wcsicmp(entry.szExeFile, L"vrcompositor.exe") == 0;
    if (s || m || c) {
      server |= s; monitor |= m; compositor |= c;
      processes.push_back(object({{"name", Json::make_string(s ? "vrserver.exe" : m ? "vrmonitor.exe" : "vrcompositor.exe")},
        {"pid", number(entry.th32ProcessID)}}));
    }
  } while (Process32NextW(snapshot, &entry));
  CloseHandle(snapshot);
  const auto utf8 = path.u8string();
  return object({{"installed", Json::make_bool(installed)}, {"runtime_paths", strings(paths)},
    {"paths_file", Json::make_string(std::string(utf8.begin(), utf8.end()))}, {"error", Json::make_string(error)},
    {"vrserver", Json::make_bool(server)}, {"vrmonitor", Json::make_bool(monitor)},
    {"vrcompositor", Json::make_bool(compositor)}, {"processes", Json::make_array(std::move(processes))},
    {"openvr_loaded", Json::make_bool(GetModuleHandleW(L"openvr_api.dll") != nullptr)}});
}
}  // namespace nl::vrprobe
