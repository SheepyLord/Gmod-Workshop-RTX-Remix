#include "former_rtx.h"
#include "catalog.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/paths.h"
#include <windows.h>
#include <tlhelp32.h>

namespace nl::client {
namespace {
constexpr std::string_view kLock = "native-loader/lock";
constexpr std::string_view kWhy =
    "Files the RTX package (gmod-rtx-remix) found at its add-on and garrysmod/lua/bin paths when it was deployed, "
    "such as an earlier RTX installation. The loader kept them to put back, or left them in place, when the package "
    "goes; without the RTX runtime their Lua fails, so they are kept here instead and uninstalling RTX leaves the "
    "game without them (ADR 0188). To use one again, move it back to its path below the game folder.";

bool below(std::string_view folded, std::string_view prefix) {
  return folded.size() > prefix.size() && folded.compare(0, prefix.size(), prefix) == 0;
}

// The deployer's exclusive handle on native-loader/lock (deploy.cpp's Lock): no deployment runs while it is held.
class Lock {
 public:
  explicit Lock(const std::filesystem::path& file)
      : handle_(CreateFileW(fs::long_path(file).c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr)),
        error_(handle_ == INVALID_HANDLE_VALUE ? GetLastError() : 0) {}
  ~Lock() {
    if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
  }
  Lock(const Lock&) = delete;
  Lock& operator=(const Lock&) = delete;
  bool held() const { return handle_ != INVALID_HANDLE_VALUE; }
  unsigned long error() const { return error_; }

 private:
  HANDLE handle_;
  unsigned long error_;
};

// Makes every missing folder of `relative` below `root`; each one that is there must be an ordinary folder.
void make_folders(const std::filesystem::path& root, const std::string& relative) {
  fs::refuse_links(root, relative);
  for (std::size_t at = 0;;) {
    const auto slash = relative.find('/', at);
    const std::string part = relative.substr(0, slash);
    const auto path = fs::join(root, part);
    const auto found = fs::stat(path);
    if (!found.exists) fs::win32().create_directory(path);
    else if (!found.directory || found.link) throw fs::Error(part + " is not an ordinary folder", 0);
    if (slash == std::string::npos) return;
    at = slash + 1;
  }
}

struct Move {
  std::string from;             // relative to the root
  const journal::File* record;  // what the journal says about the file
};

// Moves each file to kFormerRtx/<stamp>/<record path> under the deployer's lock, with an index.json.
Archived move_all(const std::filesystem::path& root, const std::vector<Move>& moves, std::string_view stamp,
                  Archived out) {
  if (moves.empty()) return out;
  const Lock lock(fs::join(root, kLock));
  if (!lock.held()) {
    out.notes.push_back(lock.error() == ERROR_SHARING_VIOLATION
                            ? std::string("another deployment holds native-loader/lock; the former RTX files move later")
                            : "cannot open native-loader/lock (Windows error " + std::to_string(lock.error()) +
                                  "); the former RTX files move later");
    return out;
  }
  const std::string base = std::string(kFormerRtx) + "/" + std::string(stamp);
  std::string folder = base;
  for (unsigned n = 2; fs::stat(fs::join(root, folder)).exists; ++n) {
    if (n > 99) throw fs::Error("no free folder for " + base, 0);
    folder = base + "-" + std::to_string(n);
  }
  std::string index;
  for (const Move& move : moves) {
    const std::string to = folder + "/" + move.record->path;
    try {
      make_folders(root, to.substr(0, to.rfind('/')));
      fs::refuse_links(root, to);
      fs::win32().move(fs::join(root, move.from), fs::join(root, to), false);
      ++out.moved;
      index += std::string(index.empty() ? "\n    " : ",\n    ") + "{\"path\": " + json::quote(move.record->path) +
               ", \"size\": " + std::to_string(move.record->size) + ", \"sha256\": " + json::quote(move.record->sha256) +
               ", \"was\": " + json::quote(move.record->adopted ? "adopted" : "original") + "}";
    } catch (const fs::Error& error) {
      out.notes.push_back(move.from + ": could not be moved (" + error.what() + "); an uninstall would leave it");
    }
  }
  if (!out.moved) return out;
  out.folder = folder;
  const std::string text = "{\n  \"schema\": 1,\n  \"why\": " + json::quote(kWhy) + ",\n  \"files\": [" + index + "\n  ]\n}\n";
  try {
    fs::write_atomic(fs::win32(), fs::join(root, folder + "/index.json"), text);
  } catch (const fs::Error& error) {
    out.notes.push_back(folder + "/index.json: not written (" + error.what() + ")");
  }
  return out;
}
}  // namespace

bool former_rtx(const journal::File& file) {
  if (file.package != kPackage || !paths::is_safe(file.path)) return false;
  const std::string path = paths::fold(file.path);
  return below(path, "garrysmod/addons/") || below(path, "garrysmod/lua/bin/");
}

Archived archive_former_rtx(const std::filesystem::path& root, const journal::Journal& journal, std::string_view stamp) {
  Archived out;
  std::vector<Move> moves;
  for (const auto& original : journal.originals) {
    if (!former_rtx(original)) continue;
    const std::string kept = std::string(journal::kOriginals) + "/" + original.path;
    try {
      fs::refuse_links(root, kept);
      const auto file = fs::stat(fs::join(root, kept));
      if (!file.exists) continue;  // moved already, or put back
      if (file.directory || file.size != original.size) {
        out.notes.push_back(kept + ": not the recorded original any more, so it stays (the loader does not put it back either)");
        continue;
      }
      moves.push_back({kept, &original});
    } catch (const fs::Error& error) {
      out.notes.push_back(kept + ": stays where it is (" + error.what() + ")");
    }
  }
  return move_all(root, moves, stamp, std::move(out));
}

Archived release_adopted(const std::filesystem::path& root, const journal::Journal& journal, std::string_view stamp) {
  Archived out;
  if (!journal.current || journal.pending) return out;
  std::vector<Move> moves;
  for (const auto& file : journal.current->files) {
    if (!file.adopted || !former_rtx(file)) continue;
    try {
      fs::refuse_links(root, file.path);
      const auto found = fs::stat(fs::join(root, file.path));
      if (!found.exists) continue;  // gone already: the next deployment installs the package's copy
      if (found.directory || found.size != file.size || found.mtime != file.mtime) {
        out.notes.push_back(file.path + ": changed since the loader found it, so it stays");
        continue;
      }
      moves.push_back({file.path, &file});
    } catch (const fs::Error& error) {
      out.notes.push_back(file.path + ": stays where it is (" + error.what() + ")");
    }
  }
  return move_all(root, moves, stamp, std::move(out));
}

bool another_game_running(const std::filesystem::path& root) {
  const auto exe = std::filesystem::absolute(root / L"bin" / L"win64" / L"gmod.exe").lexically_normal().wstring();
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return true;  // cannot tell: assume one does
  bool found = false;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (BOOL more = Process32FirstW(snapshot, &entry); more && !found; more = Process32NextW(snapshot, &entry)) {
    if (entry.th32ProcessID == GetCurrentProcessId() || lstrcmpiW(entry.szExeFile, L"gmod.exe") != 0) continue;
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID);
    if (!process) {
      found = true;  // a gmod.exe whose folder cannot be read may be this one
      continue;
    }
    wchar_t path[32768];
    DWORD size = static_cast<DWORD>(std::size(path));
    if (QueryFullProcessImageNameW(process, 0, path, &size)) {
      found = CompareStringOrdinal(path, static_cast<int>(size), exe.c_str(), static_cast<int>(exe.size()), TRUE) == CSTR_EQUAL;
    }
    CloseHandle(process);
  }
  CloseHandle(snapshot);
  return found;
}
}  // namespace nl::client
