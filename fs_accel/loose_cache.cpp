// A: the loose-folder negative cache and its watcher (R26, ADR 0140).
#include "fs_accel.h"

#include <windows.h>

#include <algorithm>
#include <map>

namespace nl::fs_accel {

struct LooseCache::Root {
  struct Entry {
    std::string name;  // lower case
    bool directory = false;
    bool reparse = false;
  };
  struct Listing {
    std::vector<Entry> entries;  // sorted by name
    bool unsafe = false;         // a name outside printable ASCII: Windows' case folding could match it; pass
  };

  std::string key;    // "addons\<folder>" or "workshop", normalized
  std::wstring dir;   // the folder on disk
  bool missing = false;  // the folder does not exist: every path under it is a missing path
  std::atomic<bool> dropped{false};
  SRWLOCK lock = SRWLOCK_INIT;
  std::map<std::string, std::unique_ptr<const Listing>, std::less<>> listings;  // "" is the folder itself
};

namespace {

bool ascii_name(std::wstring_view name) noexcept {
  for (const wchar_t c : name) {
    if (c < 0x20 || c >= 0x7f) return false;
  }
  return !name.empty();
}

std::string lower_ascii(std::wstring_view name) {
  std::string out;
  out.reserve(name.size());
  for (const wchar_t c : name) {
    const char ch = static_cast<char>(c);
    out.push_back((ch >= 'A' && ch <= 'Z') ? static_cast<char>(ch - 'A' + 'a') : ch);
  }
  return out;
}

std::wstring widen(std::string_view text) { return std::wstring(text.begin(), text.end()); }

// The listing of one directory, or nullptr when it cannot be listed (it went away, or access is denied).
std::unique_ptr<const LooseCache::Root::Listing> list_directory(const std::wstring& dir) {
  auto listing = std::make_unique<LooseCache::Root::Listing>();
  WIN32_FIND_DATAW data{};
  const std::wstring pattern = dir + L"\\*";
  const HANDLE search = FindFirstFileExW(pattern.c_str(), FindExInfoBasic, &data, FindExSearchNameMatch, nullptr,
                                         FIND_FIRST_EX_LARGE_FETCH);
  if (search == INVALID_HANDLE_VALUE) return nullptr;  // even an empty directory lists "." and ".."
  do {
    const std::wstring_view name(data.cFileName);
    if (name == L"." || name == L"..") continue;
    if (!ascii_name(name)) {
      listing->unsafe = true;
      continue;
    }
    LooseCache::Root::Entry entry;
    entry.name = lower_ascii(name);
    entry.directory = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    entry.reparse = (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    listing->entries.push_back(std::move(entry));
  } while (FindNextFileW(search, &data));
  const DWORD end = GetLastError();
  FindClose(search);
  if (end != ERROR_NO_MORE_FILES) return nullptr;
  std::sort(listing->entries.begin(), listing->entries.end(),
            [](const auto& a, const auto& b) { return a.name < b.name; });
  // Two names that fold to the same lower case (a case-sensitive directory): not ours to decide.
  for (std::size_t i = 1; i < listing->entries.size(); ++i) {
    if (listing->entries[i].name == listing->entries[i - 1].name) listing->unsafe = true;
  }
  return listing;
}

const LooseCache::Root::Entry* find_entry(const LooseCache::Root::Listing& listing, std::string_view name) noexcept {
  const auto it = std::lower_bound(listing.entries.begin(), listing.entries.end(), name,
                                   [](const auto& entry, std::string_view key) { return entry.name < key; });
  return it != listing.entries.end() && it->name == name ? &*it : nullptr;
}

// The listing of `relative` ("" or "a\b") in `root`, listed on first use. nullptr: pass.
const LooseCache::Root::Listing* listing_of(LooseCache::Root& root, std::string_view relative, Counters* counters) noexcept {
  try {
    AcquireSRWLockShared(&root.lock);
    const auto found = root.listings.find(relative);
    const LooseCache::Root::Listing* existing = found != root.listings.end() ? found->second.get() : nullptr;
    ReleaseSRWLockShared(&root.lock);
    if (existing) return existing;
    std::wstring dir = root.dir;
    if (!relative.empty()) dir += L"\\" + widen(relative);
    auto listed = list_directory(dir);
    if (!listed) return nullptr;
    AcquireSRWLockExclusive(&root.lock);
    const LooseCache::Root::Listing* result = nullptr;
    try {
      auto [it, inserted] = root.listings.try_emplace(std::string(relative), std::move(listed));
      result = it->second.get();
      if (inserted && counters) counters->listed.fetch_add(1, std::memory_order_relaxed);
    } catch (...) {
      result = nullptr;
    }
    ReleaseSRWLockExclusive(&root.lock);
    return result;
  } catch (...) {
    return nullptr;
  }
}

// The cache key of a normalized path below "<root>\garrysmod\" ("addons\<folder>" or "workshop") and the rest.
bool split_key(std::string_view rest, std::string_view& key, std::string_view& tail) noexcept {
  constexpr std::string_view kAddons = "addons\\";
  constexpr std::string_view kWorkshop = "workshop";
  if (rest.substr(0, kAddons.size()) == kAddons) {
    const std::string_view after = rest.substr(kAddons.size());
    const std::size_t slash = after.find('\\');
    if (slash == std::string_view::npos) {
      key = rest;  // the add-on folder itself
      tail = {};
      return true;
    }
    key = rest.substr(0, kAddons.size() + slash);
    tail = after.substr(slash + 1);
    return true;
  }
  if (rest == kWorkshop) {
    key = rest;
    tail = {};
    return true;
  }
  if (rest.substr(0, kWorkshop.size() + 1) == "workshop\\") {
    key = rest.substr(0, kWorkshop.size());
    tail = rest.substr(kWorkshop.size() + 1);
    return true;
  }
  return false;
}

}  // namespace

LooseCache::LooseCache() = default;
LooseCache::~LooseCache() = default;

bool LooseCache::init(const std::wstring& garrysmod, Counters* counters, std::string* reason) {
  counters_ = counters;
  PathBuffer normalized;
  if (!normalize(std::wstring_view(garrysmod), normalized)) {
    if (reason) *reason = "the game's folder is not a plain ASCII path";
    return false;
  }
  prefix_ = std::string(normalized.view()) + "\\";
  const std::wstring addons = garrysmod + L"\\addons";
  WIN32_FIND_DATAW data{};
  const HANDLE search = FindFirstFileExW((addons + L"\\*").c_str(), FindExInfoBasic, &data, FindExSearchNameMatch,
                                         nullptr, FIND_FIRST_EX_LARGE_FETCH);
  if (search != INVALID_HANDLE_VALUE) {
    do {
      const std::wstring_view name(data.cFileName);
      if (name == L"." || name == L"..") continue;
      if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
      if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) continue;  // a junction or link: a subtree watch misses it
      if (!ascii_name(name)) continue;
      const std::string folder = lower_ascii(name);
      if (folder.rfind("mmdhl_", 0) == 0) continue;  // written by the Model Hotloader's worker while the game runs
      PathBuffer check;
      if (!normalize(std::wstring_view(addons + L"\\" + std::wstring(name)), check)) continue;
      auto root = std::make_unique<Root>();
      root->key = "addons\\" + folder;
      root->dir = addons + L"\\" + std::wstring(name);
      roots_.push_back(std::move(root));
    } while (FindNextFileW(search, &data));
    FindClose(search);
  }
  const std::wstring workshop = garrysmod + L"\\workshop";
  const DWORD attributes = GetFileAttributesW(workshop.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
      auto root = std::make_unique<Root>();
      root->key = "workshop";
      root->dir = workshop;
      root->missing = true;
      roots_.push_back(std::move(root));
    }
  } else if ((attributes & FILE_ATTRIBUTE_DIRECTORY) && !(attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
    auto root = std::make_unique<Root>();
    root->key = "workshop";
    root->dir = workshop;
    roots_.push_back(std::move(root));
  }
  std::sort(roots_.begin(), roots_.end(), [](const auto& a, const auto& b) { return a->key < b->key; });
  if (counters_) counters_->roots.store(static_cast<std::uint32_t>(roots_.size()), std::memory_order_relaxed);
  return true;
}

LooseCache::Root* LooseCache::find_root(std::string_view key) const noexcept {
  const auto it = std::lower_bound(roots_.begin(), roots_.end(), key,
                                   [](const auto& root, std::string_view k) { return root->key < k; });
  return it != roots_.end() && (*it)->key == key ? it->get() : nullptr;
}

std::vector<std::string> LooseCache::keys() const {
  std::vector<std::string> out;
  for (const auto& root : roots_) {
    if (!root->dropped.load(std::memory_order_acquire)) out.push_back(root->key);
  }
  return out;
}

Verdict LooseCache::lookup(std::string_view path) noexcept {
  if (path.size() <= prefix_.size() || path.substr(0, prefix_.size()) != prefix_) return Verdict::Pass;
  std::string_view key, tail;
  if (!split_key(path.substr(prefix_.size()), key, tail)) return Verdict::Pass;
  Root* root = find_root(key);
  if (!root || root->dropped.load(std::memory_order_acquire)) return Verdict::Pass;
  const auto pass = [&] {
    if (counters_) counters_->passed.fetch_add(1, std::memory_order_relaxed);
    return Verdict::Pass;
  };
  const PendingProbe probe = probe_.load(std::memory_order_acquire);
  if (probe && probe(probe_context_)) return pass();
  if (root->missing) return tail.empty() ? Verdict::MissingFile : Verdict::MissingPath;
  if (tail.empty()) return pass();  // the folder itself
  std::size_t start = 0;
  for (;;) {
    const std::size_t slash = tail.find('\\', start);
    const bool last = slash == std::string_view::npos;
    const std::string_view name = tail.substr(start, last ? std::string_view::npos : slash - start);
    const std::string_view directory = start ? tail.substr(0, start - 1) : std::string_view();
    const Root::Listing* listing = listing_of(*root, directory, counters_);
    if (!listing || listing->unsafe) return pass();
    const Root::Entry* entry = find_entry(*listing, name);
    if (!entry) {
      // Checked again after the listing: a change the watcher has not read yet makes it pass.
      if (probe && probe(probe_context_)) return pass();
      if (root->dropped.load(std::memory_order_acquire)) return pass();
      return last ? Verdict::MissingFile : Verdict::MissingPath;
    }
    if (last) return pass();                            // it exists: Windows opens it
    if (!entry->directory || entry->reparse) return pass();  // a file as a folder, or a link: Windows decides
    start = slash + 1;
  }
}

void LooseCache::drop_key(std::string_view key) noexcept {
  Root* root = find_root(key);
  if (root && !root->dropped.exchange(true, std::memory_order_acq_rel) && counters_) {
    counters_->dropped.fetch_add(1, std::memory_order_relaxed);
    counters_->roots.fetch_sub(1, std::memory_order_relaxed);
  }
}

void LooseCache::drop_path(std::string_view path) noexcept {
  if (path.size() <= prefix_.size() || path.substr(0, prefix_.size()) != prefix_) return;
  std::string_view key, tail;
  if (split_key(path.substr(prefix_.size()), key, tail)) drop_key(key);
}

void LooseCache::drop_all() noexcept {
  for (const auto& root : roots_) drop_key(root->key);
}

// ---- The watcher ---------------------------------------------------------------------------------------------------

struct Watcher::Impl {
  struct Watch {
    HANDLE directory = INVALID_HANDLE_VALUE;
    OVERLAPPED overlapped{};
    alignas(DWORD) std::byte buffer[64 * 1024];
    bool subtree = false;
    std::atomic<bool> live{false};
  };
  Watch addons;  // garrysmod\addons, the subtree
  Watch game;    // garrysmod, its own entries (a new workshop folder)
  LooseCache* cache = nullptr;

  static bool open(Watch& watch, const std::wstring& dir, bool subtree) {
    watch.directory = CreateFileW(dir.c_str(), FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, nullptr);
    if (watch.directory == INVALID_HANDLE_VALUE) return false;
    watch.overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    watch.subtree = subtree;
    return watch.overlapped.hEvent != nullptr && arm(watch);
  }

  static bool arm(Watch& watch) {
    ResetEvent(watch.overlapped.hEvent);
    const DWORD filter = FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_ATTRIBUTES;
    const bool armed = ReadDirectoryChangesW(watch.directory, watch.buffer, sizeof(watch.buffer),
                                             watch.subtree ? TRUE : FALSE, filter, nullptr, &watch.overlapped,
                                             nullptr) != FALSE;
    watch.live.store(armed, std::memory_order_release);
    return armed;
  }

  // True while a notification has arrived and is not read yet (or a watch broke): the cache answers nothing then.
  static bool pending(const void* context) noexcept {
    const auto* self = static_cast<const Impl*>(context);
    const auto waiting = [](const Watch& watch) {
      return !watch.live.load(std::memory_order_acquire) ||
          watch.overlapped.Internal != static_cast<ULONG_PTR>(STATUS_PENDING);
    };
    return waiting(self->addons) || waiting(self->game);
  }

  void handle(Watch& watch, DWORD bytes) {
    if (bytes == 0) {  // the buffer overflowed: anything may have changed
      cache->drop_all();
      return;
    }
    const std::byte* at = watch.buffer;
    for (;;) {
      const auto* info = reinterpret_cast<const FILE_NOTIFY_INFORMATION*>(at);
      const std::wstring_view name(info->FileName, info->FileNameLength / sizeof(wchar_t));
      const std::wstring_view first = name.substr(0, name.find(L'\\'));
      if (ascii_name(first)) {
        const std::string folder = lower_ascii(first);
        if (&watch == &addons) {
          cache->drop_key("addons\\" + folder);
        } else if (folder == "workshop") {
          cache->drop_key("workshop");
        } else if (folder == "addons") {
          cache->drop_all();
        }
      }
      if (!info->NextEntryOffset) break;
      at += info->NextEntryOffset;
    }
  }

  void loop() {
    HANDLE events[2] = {addons.overlapped.hEvent, game.overlapped.hEvent};
    for (;;) {
      const DWORD which = WaitForMultipleObjects(2, events, FALSE, INFINITE);
      if (which != WAIT_OBJECT_0 && which != WAIT_OBJECT_0 + 1) {
        cache->drop_all();
        return;
      }
      Watch& watch = which == WAIT_OBJECT_0 ? addons : game;
      DWORD bytes = 0;
      if (!GetOverlappedResult(watch.directory, &watch.overlapped, &bytes, FALSE)) {
        watch.live.store(false, std::memory_order_release);
        cache->drop_all();
        return;
      }
      handle(watch, bytes);
      if (!arm(watch)) {
        cache->drop_all();
        return;
      }
    }
  }

  static DWORD WINAPI thread(void* context) {
    static_cast<Impl*>(context)->loop();
    return 0;
  }
};

bool Watcher::arm(const std::wstring& garrysmod, std::string* reason) {
  impl_ = new Impl();
  if (!Impl::open(impl_->addons, garrysmod + L"\\addons", true) || !Impl::open(impl_->game, garrysmod, false)) {
    if (reason) *reason = "the add-on folders cannot be watched (error " + std::to_string(GetLastError()) + ")";
    return false;
  }
  return true;
}

bool Watcher::run(LooseCache* cache, std::string* reason) {
  if (!impl_) return false;
  impl_->cache = cache;
  cache->set_pending_probe(&Impl::pending, impl_);
  const HANDLE thread = CreateThread(nullptr, 0, &Impl::thread, impl_, 0, nullptr);
  if (!thread) {
    if (reason) *reason = "the watcher thread could not start";
    return false;
  }
  SetThreadPriority(thread, THREAD_PRIORITY_ABOVE_NORMAL);
  CloseHandle(thread);
  return true;
}

}  // namespace nl::fs_accel
