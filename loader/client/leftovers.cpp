#include "leftovers.h"
#include "catalog.h"
#include "former_rtx.h"
#include "nl/deploy.h"
#include "nl/fs.h"
#include "nl/journal.h"
#include "nl/session.h"
#include <windows.h>
#include <tlhelp32.h>
#include <algorithm>
#include <map>
#include <optional>

namespace nl::client {
namespace {
constexpr std::size_t kMaxNotes = 40;

std::uint64_t created(HANDLE process) {
  FILETIME creation{}, exit{}, kernel{}, user{};
  if (!GetProcessTimes(process, &creation, &exit, &kernel, &user)) return 0;
  return (static_cast<std::uint64_t>(creation.dwHighDateTime) << 32) | creation.dwLowDateTime;
}
}  // namespace

bool another_game(const std::filesystem::path& root) {
  const auto exe = std::filesystem::absolute(root / L"bin" / L"win64" / L"gmod.exe").lexically_normal().wstring();
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return true;  // cannot tell: assume one does
  std::map<DWORD, DWORD> parents;
  std::vector<DWORD> games;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
    parents[entry.th32ProcessID] = entry.th32ParentProcessID;
    if (lstrcmpiW(entry.szExeFile, L"gmod.exe") == 0) games.push_back(entry.th32ProcessID);
  }
  CloseHandle(snapshot);
  const DWORD self = GetCurrentProcessId();
  const std::uint64_t since = created(GetCurrentProcess());
  for (const DWORD pid : games) {
    if (pid == self) continue;
    // This game's own helpers (Chromium's processes are gmod.exe of the same folder): their parents lead here, and
    // none was created before this game (a parent id Windows gave to this game after the real parent ended).
    bool below = false;
    DWORD at = pid;
    for (unsigned step = 0; step < 32; ++step) {
      const auto found = parents.find(at);
      if (found == parents.end() || found->second == 0 || found->second == at) break;
      if (found->second == self) {
        below = true;
        break;
      }
      at = found->second;
    }
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return true;  // a gmod.exe whose folder cannot be read may be this folder's
    if (below && since && created(process) >= since) {
      CloseHandle(process);
      continue;
    }
    wchar_t path[32768];
    DWORD size = static_cast<DWORD>(std::size(path));
    const bool same = QueryFullProcessImageNameW(process, 0, path, &size) &&
                      CompareStringOrdinal(path, static_cast<int>(size), exe.c_str(), static_cast<int>(exe.size()), TRUE) == CSTR_EQUAL;
    CloseHandle(process);
    if (same) return true;
  }
  return false;
}

namespace {

bool same_path(const std::wstring& a, const std::filesystem::path& b) {
  const auto x = std::filesystem::path(a).lexically_normal().wstring(), y = b.lexically_normal().wstring();
  return CompareStringOrdinal(x.c_str(), static_cast<int>(x.size()), y.c_str(), static_cast<int>(y.size()), TRUE) == CSTR_EQUAL;
}

void note(Removed& out, std::string text) {
  if (out.notes.size() < kMaxNotes) out.notes.push_back(std::move(text));
}
void notes(Removed& out, const std::vector<std::string>& more) {
  for (const auto& text : more) note(out, text);
}

std::size_t count(const deploy::Report& report, std::string_view action) {
  return static_cast<std::size_t>(std::count_if(report.changes.begin(), report.changes.end(),
                                                [&](const deploy::Change& change) { return change.action == action; }));
}

bool journal_left(const std::filesystem::path& root) { return fs::stat(fs::join(root, journal::kPath)).exists; }

// The console settings to put back, planned as the loader plans them at a start without RTX (session::plan), from the
// journal's session variables before the uninstall drops them.
struct Restore {
  session::Values values;
  std::optional<session::Record> after;  // the record to write afterwards
  bool drop = false;                      // or: remove it
};
Restore plan_restore(const std::filesystem::path& root, const journal::Generation& current, Removed& out) {
  Restore result;
  try {
    session::Values deployed;
    for (const auto& package : current.packages) {
      deployed.insert(deployed.end(), package.session.cvars.begin(), package.session.cvars.end());
    }
    fs::refuse_links(root, session::kRecordPath);
    const auto record_path = fs::join(root, session::kRecordPath);
    if (!fs::stat(record_path).exists) return result;  // nothing recorded, nothing to put back
    const auto record = session::parse_record(fs::read_file(record_path, std::size_t{1} << 20));
    fs::refuse_links(root, session::kConfigCfg);
    const auto config_path = fs::join(root, session::kConfigCfg);
    std::map<std::string, std::string> config;
    if (fs::stat(config_path).exists) config = session::parse_config(fs::read_file(config_path, std::size_t{8} << 20));
    const auto plan = session::plan(false, deployed, record, config);
    result.values = plan.restore;
    if (plan.record.empty()) result.drop = true;
    else result.after = session::Record{plan.record, plan.write_restore || record.restore_issued, plan.record_session};
  } catch (const std::exception& error) {
    note(out, std::string("console settings not put back: ") + error.what());
    result = {};
  }
  return result;
}

void finish_restore(const std::filesystem::path& root, const Restore& restore, Removed& out) {
  try {
    const auto record_path = fs::join(root, session::kRecordPath);
    if (restore.drop) {
      if (fs::stat(record_path).exists) fs::win32().remove_file(record_path);
    } else if (restore.after) {
      fs::write_atomic(fs::win32(), record_path, session::serialize(*restore.after));
    }
    out.restore = restore.values;
  } catch (const std::exception& error) {
    note(out, std::string("console settings not put back: ") + error.what());
  }
}
}  // namespace

bool loader_installed(const std::filesystem::path& root) {
  try {
    const auto bootstrap = fs::join(root, kBootstrapFile);
    if (fs::stat(bootstrap).exists) return true;
    if (const HMODULE winmm = GetModuleHandleW(L"winmm.dll")) {
      std::wstring path(32768, L'\0');
      const DWORD size = GetModuleFileNameW(winmm, path.data(), static_cast<DWORD>(path.size()));
      if (!size || size >= path.size()) return true;
      path.resize(size);
      if (same_path(path, std::filesystem::absolute(bootstrap))) return true;  // deleted while this game runs
    }
    return false;
  } catch (...) {
    return true;  // cannot tell: as if it were there
  }
}

std::string leftovers_refusal(const std::filesystem::path& root) {
  try {
    if (loader_installed(root)) return "the native loader is installed (" + std::string(kBootstrapFile) + ")";
    const auto journal = journal::load(root);
    if (!journal) return "the loader has deployed nothing here (no " + std::string(journal::kPath) + ")";
    const bool rtx = journal->current && std::any_of(journal->current->packages.begin(), journal->current->packages.end(),
                                                     [](const journal::Package& package) { return package.id == kPackage; });
    if (!rtx) return "the RTX package is not deployed here";
    return {};
  } catch (const std::exception& error) {
    return std::string("cannot tell: ") + error.what();
  }
}

Removed remove_leftovers(const std::filesystem::path& root, std::string_view stamp, std::uint32_t own_process) {
  Removed out;
  if (auto why = leftovers_refusal(root); !why.empty()) {
    out.outcome = "not needed";
    out.error = std::move(why);
    return out;
  }
  bool ran = false;  // the uninstall has started: the game folder may have changed
  try {
    if (another_game(root)) {
      out.outcome = "refused";
      out.error = "another Garry's Mod runs from this folder";
      return out;
    }
    deploy::Options options;
    options.exclude_process_id = own_process;
    // The deployer's own check would count this game's Chromium helpers (gmod.exe of this folder, measured on the PoC
    // on 2026-11-13) as another game and refuse; another_game() above has checked, without them.
    options.allow_running_game = true;
    auto journal = journal::load(root);
    if (journal && journal->pending) {
      const auto recovered = deploy::recover(root, options);
      if (!recovered.ok()) {
        out.outcome = "refused";
        out.error = recovered.error;
        return out;
      }
      journal = journal::load(root);
    }
    if (!journal || !journal->current) {
      out.outcome = "refused";
      out.error = "the loader's journal changed while it was read";
      return out;
    }
    const auto restore = plan_restore(root, *journal->current, out);
    // ADR 0188's moves, here without a verified RTX start: the uninstall must not put an earlier RTX installation back,
    // nor leave its adopted copies in the game.
    const auto originals = archive_former_rtx(root, *journal, stamp);
    const auto adopted = release_adopted(root, *journal, std::string(stamp) + "-adopted");
    out.former = originals.moved + adopted.moved;
    out.former_folder = !originals.folder.empty() ? originals.folder : adopted.folder;
    notes(out, originals.notes);
    notes(out, adopted.notes);

    ran = true;
    const auto removed = deploy::uninstall(root, options);
    if (!removed.ok()) {
      out.outcome = "refused";
      out.error = removed.error;
      notes(out, removed.notes);
      return out;
    }
    out.deleted = count(removed, "delete");
    out.restored = count(removed, "restore-original");
    std::vector<std::string> later = removed.notes;
    // What this game holds open (its binary modules, this one first) cannot be deleted while it runs; a loaded module
    // can be renamed, so it leaves the game folder and the uninstall finishes without it.
    if (journal_left(root)) {
      std::vector<journal::File> held;
      if (const auto left = journal::load(root)) {
        for (const auto& file : left->retired) {
          if (fs::stat(fs::join(root, file.path)).exists) held.push_back(file);
        }
      }
      if (!held.empty()) {
        const auto aside = set_aside_in_use(root, held, stamp);
        out.aside = aside.moved;
        out.aside_folder = aside.folder;
        notes(out, aside.notes);
        if (aside.moved) {
          const auto again = deploy::uninstall(root, options);
          out.deleted += count(again, "delete");
          out.restored += count(again, "restore-original");
          later = again.notes;
          if (!again.ok()) note(out, "the uninstall's second pass: " + again.error);
        }
      }
    }
    notes(out, later);
    out.outcome = journal_left(root) ? "partly removed" : "removed";
    finish_restore(root, restore, out);
  } catch (const std::exception& error) {
    out.error = error.what();
    bool left = true;
    try { left = journal_left(root); } catch (...) {}
    out.outcome = !ran ? "refused" : left ? "partly removed" : "removed";
  }
  return out;
}
}  // namespace nl::client
