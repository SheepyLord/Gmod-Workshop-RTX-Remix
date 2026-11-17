// The load accelerator (R26, ADR 0140): two answers GMod's file system would give, from memory.
//
// A. The loose-folder negative cache. Every lookup of a game file tries each loose add-on folder under
//    garrysmod/addons on disk before the mounted .gma files, and a missed open is tried twice. Import hooks on
//    filesystem_stdio.dll's CreateFileA/W and GetFileAttributesExA/W answer "not there" for a path inside a cached
//    folder that a directory listing says does not exist, exactly as Windows would; everything else goes on to the
//    next function in the chain (the loader's hook or Windows) unchanged. A folder that changes stops being cached.
// B. The per-add-on find index. file.Find(pattern, addon title) makes GMod walk every entry of every mounted add-on
//    (Addon::FileSystem::FindFirst). The index is built once from GMod's own table (read only, never written) and
//    answers which of that add-on's files and directories match.
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace nl::fs_accel {

// ---- Paths (path_rules.cpp) -------------------------------------------------------------------------------------

// A path as the cache compares it: lower case ASCII, '\' separators, at most MAX_PATH - 1 characters.
struct PathBuffer {
  char text[260];
  std::size_t size = 0;
  std::string_view view() const { return {text, size}; }
};

// Copies `in` into `out` when the cache may answer for it: an absolute "X:\" path in printable ASCII, shorter than
// MAX_PATH, whose components are none of: empty (a doubled or trailing separator), "." or "..", ending in a dot or a
// space, a reserved device name, shaped like an 8.3 short name ('~' and a digit); and which holds no ':' after the
// drive and no wildcard or other character Windows refuses. Anything else must pass through.
bool normalize(std::string_view in, PathBuffer& out) noexcept;
bool normalize(std::wstring_view in, PathBuffer& out) noexcept;

// GMod's add-on file system wildcards: '*' any run of characters, '?' one; bytes compared exactly.
bool wildcard_match(std::string_view pattern, std::string_view name) noexcept;

// ---- A: the loose-folder negative cache (loose_cache.cpp) ----------------------------------------------------------

enum class Verdict { Pass, MissingFile, MissingPath };

// Shared with the other copy of the module and with the engine guard's load overlay (exported as nl_fs_accel_v1).
// Plain counters; the layout only grows at the end (version and size first).
struct Counters {
  std::uint32_t version = 1;
  std::uint32_t size = sizeof(Counters);
  std::atomic<std::uint64_t> calls{0};          // hooked calls seen
  std::atomic<std::uint64_t> answered{0};       // misses answered from memory
  std::atomic<std::uint64_t> passed{0};         // under a cached folder, passed on (there, or not answerable)
  std::atomic<std::uint64_t> listed{0};         // directories listed
  std::atomic<std::uint64_t> dropped{0};        // folders that stopped being cached
  std::atomic<std::uint64_t> disagreements{0};  // verify mode: a "missing" answer Windows did not give
  std::atomic<std::uint64_t> finds_served{0};   // B: file.Find calls answered from the index (all copies add here)
  std::atomic<std::uint64_t> finds_passed{0};   // B: file.Find calls left to GMod
  std::atomic<std::uint32_t> roots{0};          // folders cached
  // The switches, here so that the copy that did not install the hooks reaches them too.
  std::atomic<std::uint32_t> enabled{1};        // A answers (1) or only passes on (0)
  std::atomic<std::uint32_t> verify{0};         // A also asks Windows and counts disagreements (1)
  std::atomic<std::uint32_t> settled{0};        // a map has loaded with the hooks in (settle()): the marker may go
  // Load-speedup round 2 (ADR 0239): of `roots`, the links and junctions cached (their target, or its absence).
  std::atomic<std::uint32_t> links{0};
};

class LooseCache {
 public:
  LooseCache();
  ~LooseCache();
  LooseCache(const LooseCache&) = delete;
  LooseCache& operator=(const LooseCache&) = delete;

  // garrysmod: the game's "<root>\garrysmod" folder. Caches every folder directly under garrysmod\addons with an ASCII
  // name: a plain directory, or (ADR 0239) a junction or directory link that leads to a directory on a local fixed
  // drive (listed through the link; its target watched on its own) or whose target is missing (every path below it is
  // a missing path; the nearest folder on the way to the target is watched for it to appear); and garrysmod\workshop,
  // which is normally missing. Other reparse points, and links to network or removable drives, are not cached.
  bool init(const std::wstring& garrysmod, Counters* counters, std::string* reason);

  // The links and junctions cached, for the watcher: each one's key, the folder to watch (the target itself with its
  // subtree; or, for a missing target, the nearest folder that exists, its own entries only) and the link's own path
  // (opening it follows the link: whether a missing target appeared).
  struct LinkWatch {
    std::string key;
    std::wstring watch;
    bool subtree = false;
    bool missing = false;
    std::wstring link;
  };
  std::vector<LinkWatch> link_watches() const;

  // The verdict for a normalized full path. Pass for anything outside the cached folders, or that exists, or that the
  // cache cannot be sure of.
  Verdict lookup(std::string_view normalized) noexcept;

  // A write or create under a cached folder, or a change the watcher saw: that folder is not cached any more.
  void drop_path(std::string_view normalized) noexcept;
  void drop_key(std::string_view key) noexcept;  // "addons\<folder>" or "workshop"
  void drop_all() noexcept;
  // The watcher's probe: true while a change notification has arrived and is not read yet; every answer passes then.
  using PendingProbe = bool (*)(const void* context) noexcept;
  void set_pending_probe(PendingProbe probe, const void* context) noexcept {
    probe_context_ = context;
    probe_ = probe;
  }

  std::string_view prefix() const { return prefix_; }  // "<root>\garrysmod\", normalized
  std::vector<std::string> keys() const;
  std::size_t root_count() const { return roots_.size(); }

  struct Root;  // one cached folder (loose_cache.cpp)

 private:
  Root* find_root(std::string_view key) const noexcept;
  std::string prefix_;
  std::vector<std::unique_ptr<Root>> roots_;  // sorted by key
  Counters* counters_ = nullptr;
  std::atomic<PendingProbe> probe_{nullptr};
  const void* probe_context_ = nullptr;
};

// The watcher: one thread with ReadDirectoryChangesW on garrysmod\addons (the subtree) and on garrysmod (for a new
// workshop folder), and one on each cached link's target, or on the folder its missing target would appear in
// (ADR 0239). Armed before any listing is taken; a change under a cached folder drops it, an overflow drops all (a
// link's watch: that link). While a notification waits to be read the cache answers nothing (the cache's pending
// probe).
class Watcher {
 public:
  bool arm(const std::wstring& garrysmod, std::string* reason);  // before the cache lists anything
  // The thread; arms the cache's link watches first (a link that cannot be watched, or whose missing target appeared
  // meanwhile, is dropped), then sets the cache's probe.
  bool run(LooseCache* cache, std::string* reason);

  struct Impl;

 private:
  Impl* impl_ = nullptr;  // never freed: the thread lives for the process
};

// ---- The hooks on filesystem_stdio.dll (hooks.cpp) ---------------------------------------------------------------

struct InstallResult {
  bool installed = false;  // by this copy now, or found installed
  bool by_other = false;   // the other copy of the module (gmcl_/gmsv_) installed it
  std::string reason;
};

// Builds the cache for the game this process runs, starts the watcher and hooks filesystem_stdio.dll's imports, once
// per process. The other copy of the module finds the hooks in place and only reports them. A start-up marker (below)
// leaves the hooks out once after a start that ended within 20 s of installing them.
InstallResult install();
// What install() found (nothing installed yet: installed false, an empty reason).
InstallResult install_status();

// ---- The start-up marker (hooks.cpp) -----------------------------------------------------------------------------
// garrysmod\data\nativeloader\load_accel_pending.txt holds "<process id> <process creation time>" from just before
// the hooks go in until a map has loaded with them (settle(), from Lua) and at least 20 s have passed. A start that
// finds the marker of a process that is gone (a crash, a hang ended by force, or a quit before that) leaves the hooks
// out once, and both copies of the module in that process agree.

struct ProcessStamp {
  unsigned long pid = 0;
  unsigned long long created = 0;  // FILETIME of the process's creation
};
ProcessStamp current_stamp() noexcept;
enum class MarkerCheck {
  None,     // no marker, an unreadable one, or this process's own
  Running,  // the marker of another process that still runs (two games of one install)
  LeftOut,  // the marker of a process that is gone
};
MarkerCheck check_marker(const std::wstring& path, const ProcessStamp& self) noexcept;
bool write_marker(const std::wstring& path, const ProcessStamp& self) noexcept;  // creates its folder
bool clear_marker(const std::wstring& path, const ProcessStamp& self) noexcept;  // only when it is `self`'s
// A map has loaded with the hooks in: the marker comes off (20 s after the hooks went in, at the earliest).
void settle() noexcept;

// The game's "<root>\garrysmod" folder (from gmod.exe's path), or empty.
std::wstring garrysmod_folder();

// The counters of the copy that installed the hooks (this one or the other), or this copy's.
Counters& counters() noexcept;
void set_enabled(bool on) noexcept;
void set_verify(bool on) noexcept;

// For tests: the hook bodies against an explicit cache and next functions.
namespace testing {
using CreateA = void* (__stdcall*)(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);
using CreateW = void* (__stdcall*)(const wchar_t*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);
using AttributesA = int(__stdcall*)(const char*, int, void*);
using AttributesW = int(__stdcall*)(const wchar_t*, int, void*);
void bind(LooseCache* cache, CreateA create_a, CreateW create_w, AttributesA attributes_a, AttributesW attributes_w) noexcept;
void* create_a(const char*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*) noexcept;
void* create_w(const wchar_t*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*) noexcept;
int attributes_a(const char*, int, void*) noexcept;
int attributes_w(const wchar_t*, int, void*) noexcept;
}  // namespace testing

// ---- E: what a load read, read ahead for the next one (prefetch.cpp, ADR 0242) -------------------------------------
// While a map load is recorded, the import hooks on filesystem_stdio.dll's ReadFile (and the CreateFile hooks, which
// name the handles) note which 64 KiB blocks of which file the load read, in the order the files were first read. The
// record is saved as a list (garrysmod\data\nativeloader\prefetch\<map>.lst: Lua cannot write that extension); a
// prefetch reads a list's blocks on a thread of its own at low I/O priority, so that the next load finds them in
// Windows' file cache (a cold start after a reboot, or after the cache let them go).
namespace prefetch {

constexpr std::uint32_t kBlockShift = 16;  // 64 KiB blocks

struct Range {
  std::uint64_t first = 0;  // block
  std::uint64_t count = 0;  // blocks
};
struct Entry {
  std::wstring path;          // absolute "X:\..."
  std::uint64_t size = 0;     // the file's size when saved; a file of another size is passed over
  std::uint64_t written = 0;  // its last write time (FILETIME) when saved
  std::vector<Range> ranges;
};

// A map name a list may have: 1-64 of A-Z a-z 0-9 _ - . (not starting with a dot), else empty.
std::wstring list_name(std::string_view map);

// The record. start() clears it and begins; stop() ends it (false: nothing was recording). Called by the hooks:
// opened() when CreateFile gave a handle, read() before a ReadFile (offset from the OVERLAPPED, else the handle's
// position, asked of Windows).
void record_start() noexcept;
bool record_stop() noexcept;
bool recording() noexcept;
void opened(void* handle, const char* name) noexcept;
void opened(void* handle, const wchar_t* name) noexcept;
void read(void* handle, std::uint64_t bytes, const void* overlapped) noexcept;
// The record as a list, in first-read order: only files on a local fixed drive, not the game's cache\ folder (GMod
// writes it during a load), at most `budget` bytes in all.
std::vector<Entry> record_list(std::uint64_t budget);

// A list file: written whole (a temporary file renamed over it) and read back; false with a reason.
bool save_list(const std::wstring& path, const std::vector<Entry>& entries, std::string* why);
bool load_list(const std::wstring& path, std::vector<Entry>& entries, std::string* why);

// Reads a list's blocks on a thread of its own (a later start() supersedes it), at most `budget` bytes. Files that
// are gone, of another size, not on a local fixed drive or not plain files are passed over.
bool start(const std::wstring& list_path, std::uint64_t budget, std::string* why);
struct Status {
  bool recording = false;
  std::uint64_t record_files = 0;
  std::uint64_t record_blocks = 0;
  std::uint64_t record_reads = 0;  // reads recorded
  bool running = false;
  std::uint64_t files = 0;    // files read ahead by the last prefetch
  std::uint64_t bytes = 0;
  std::uint64_t skipped = 0;  // files passed over
  double seconds = 0;
  std::string list;           // the last prefetch's list (UTF-8)
};
Status status();
// The default budget: a quarter of the computer's memory, at most 4 GiB.
std::uint64_t default_budget() noexcept;
// Waits up to `ms` for a running prefetch to end (tests).
bool wait(unsigned long ms) noexcept;

}  // namespace prefetch

// ---- B: the per-add-on find index (addon_index.cpp) --------------------------------------------------------------

struct FindResult {
  std::vector<std::string> files;
  std::vector<std::string> dirs;
};

// Where GMod keeps its add-on table: the Addon::FileSystem object inside filesystem_stdio's file system object.
struct TableAddress {
  const void* addon_fs = nullptr;  // the object; its directory map at +0x08, its add-on list at +0x18
};

class AddonIndex {
 public:
  // Finds Addon::FileSystem in the loaded filesystem_stdio.dll by its export and RTTI names.
  static bool locate(TableAddress& out, std::string* reason) noexcept;

  // What file.Find(pattern, title) gives for the add-ons titled `title`, from the index: false (with a reason) when the
  // title is no add-on's or the table cannot be read; the caller then asks GMod.
  bool find(const TableAddress& table, std::string_view pattern, std::string_view title, FindResult& out,
            std::string* reason);
  void invalidate() noexcept;
  std::uint64_t builds() const { return builds_; }
  std::uint64_t last_build_ms() const { return last_build_ms_; }
  std::size_t entries() const;
  void set_min_rebuild_ms(std::uint64_t ms) { min_rebuild_ms_ = ms; }  // 2000 by default; tests set 0

  struct Data;  // the built index (addon_index.cpp)

 private:
  bool ensure(const TableAddress& table, std::string* reason);
  std::shared_ptr<Data> data_;
  std::uint64_t builds_ = 0;
  std::uint64_t last_build_ = 0;     // GetTickCount64() when the last build (or attempt) began; 0: none yet
  std::uint64_t last_build_ms_ = 0;  // how long the last build took
  std::uint64_t min_rebuild_ms_ = 2000;
};

}  // namespace nl::fs_accel
