// The load overlay's estimate and the history file it is learned from (ADR 0215): see load_eta.h.
#include "load_eta.h"
#include <windows.h>
#include <algorithm>

namespace nl::engine_guard::overlay {
namespace {

// Exactly one '%' in the text, and it starts "%s".
bool one_value(std::string_view text) {
  const std::size_t at = text.find('%');
  return at != std::string_view::npos && at + 1 < text.size() && text[at + 1] == 's' &&
         text.find('%', at + 1) == std::string_view::npos;
}

}  // namespace

std::string fill_value(std::string_view format, std::string_view fallback, std::string_view value) {
  const std::string_view chosen = one_value(format) ? format : fallback;
  if (!one_value(chosen)) return std::string(value);
  const std::size_t at = chosen.find("%s");
  std::string out(chosen.substr(0, at));
  out += value;
  out += chosen.substr(at + 2);
  return out;
}

Remaining remaining(std::uint64_t ms) {
  const std::uint64_t seconds = ms / 1000 + (ms % 1000 ? 1 : 0);
  Remaining said;
  if (seconds >= 90) {
    said.minutes = true;
    const std::uint64_t minutes = (seconds + 59) / 60;
    said.value = static_cast<unsigned>(std::min<std::uint64_t>(minutes, 9999));
  } else if (seconds >= 20) {
    said.value = static_cast<unsigned>((seconds + 4) / 5 * 5);
  } else {
    said.value = static_cast<unsigned>(seconds ? seconds : 1);
  }
  return said;
}

double bar_fraction(double anchor, std::uint64_t anchor_ms, std::uint64_t now_ms, std::uint64_t end_ms) {
  anchor = std::clamp(anchor, 0.0, kBarLimit);
  if (now_ms < end_ms) {
    if (anchor >= kBarCap || end_ms <= anchor_ms) return anchor;
    const double done = now_ms > anchor_ms ? static_cast<double>(now_ms - anchor_ms) / static_cast<double>(end_ms - anchor_ms) : 0.0;
    return std::max(anchor, anchor + (kBarCap - anchor) * std::min(done, 1.0));
  }
  // Past the estimate: half of what is left to kBarLimit every 20 s, so the bar still moves and never fills.
  const double over = static_cast<double>(now_ms - end_ms) / 1000.0;
  const double base = std::max(anchor, kBarCap);
  return base + (kBarLimit - base) * (over / (over + 20.0));
}

std::wstring garrysmod_folder() {
  std::wstring exe(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
  if (!length || length >= exe.size()) return {};
  exe.resize(length);
  // <root>\bin\win64\gmod.exe (or <root>\gmod.exe): the root holds garrysmod\data.
  std::wstring folder = exe.substr(0, exe.find_last_of(L"\\/"));
  for (int up = 0; up < 3 && !folder.empty(); ++up) {
    const DWORD attributes = GetFileAttributesW((folder + L"\\garrysmod\\data").c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY)) return folder + L"\\garrysmod";
    const auto cut = folder.find_last_of(L"\\/");
    if (cut == std::wstring::npos) break;
    folder.resize(cut);
  }
  return {};
}

std::wstring history_path(const std::wstring& garrysmod) {
  if (garrysmod.empty()) return {};
  return garrysmod + L"\\data\\nativeloader\\load_times.txt";
}

std::optional<std::string> read_history(const std::wstring& path) {
  if (path.empty()) return std::nullopt;
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::nullopt;
  std::optional<std::string> text;
  LARGE_INTEGER size{};
  if (GetFileSizeEx(file, &size) && size.QuadPart >= 0 && size.QuadPart <= static_cast<LONGLONG>(kHistoryLimit)) {
    std::string data(static_cast<std::size_t>(size.QuadPart), '\0');
    DWORD read = 0;
    if (data.empty() ||
        (ReadFile(file, data.data(), static_cast<DWORD>(data.size()), &read, nullptr) && read == data.size()))
      text = std::move(data);
  }
  CloseHandle(file);
  return text;
}

bool write_history(const std::wstring& path, std::string_view text) {
  if (path.empty() || text.size() > kHistoryLimit || text.find('\0') != std::string_view::npos) return false;
  const auto slash = path.find_last_of(L"\\/");
  if (slash != std::wstring::npos) CreateDirectoryW(path.substr(0, slash).c_str(), nullptr);  // data\nativeloader
  const std::wstring temporary = path + L".tmp";
  const HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const bool wrote = text.empty() ||
                     (WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size());
  CloseHandle(file);
  if (!wrote || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

}  // namespace nl::engine_guard::overlay
