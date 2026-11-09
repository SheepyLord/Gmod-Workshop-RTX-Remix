// B: the per-add-on find index (R26, ADR 0140).
//
// GMod keeps every mounted .gma in one table, Addon::FileSystem (filesystem_stdio.dll): a std::map from directory
// ("materials/models", lower case, '/') to a std::map from name to entry, and a std::list of the mounted add-ons.
// Each entry records the add-on it came from (+0x90) and whether it is a directory marker (+0x98: 1, its key the
// add-on's .gma path), and every directory an add-on has holds a marker of it. file.Find(pattern, title) reaches
// Addon::FileSystem::FindFirst once per list node with that title, which walks every directory and their entries
// (RESEARCH.md, R26). Here the table is read once (read only, under SEH, every link and size checked), and the same
// question is answered from an index of each add-on's directories and files.
#include "fs_accel.h"

#include <windows.h>

#include <algorithm>
#include <cstring>
#include <unordered_map>

namespace nl::fs_accel {
namespace {

// MSVC x64 layouts (the C++ standard library filesystem_stdio.dll was built with; checked as they are read).
constexpr std::size_t kTreeLeft = 0x00, kTreeParent = 0x08, kTreeRight = 0x10, kTreeIsNil = 0x19, kTreeValue = 0x20;
constexpr std::size_t kDirInnerHead = 0x40, kDirInnerSize = 0x48;          // the directory's entry map
constexpr std::size_t kEntryOwner = 0x90, kEntryFlag = 0x98;              // in an entry node
constexpr std::size_t kTableDirHead = 0x08, kTableDirSize = 0x10, kTableListHead = 0x18, kTableListSize = 0x20;
constexpr std::size_t kListTitle = 0x30, kListFilter = 0x50;              // in a list node
constexpr std::uint64_t kMaxText = 4096;
constexpr std::uint64_t kMaxDirs = 4'000'000, kMaxEntries = 64'000'000, kMaxNodes = 1'000'000;

struct RawText {
  const char* data;
  std::uint64_t size;
};

const std::uint8_t* ptr_at(const std::uint8_t* at) { return *reinterpret_cast<const std::uint8_t* const*>(at); }
std::uint64_t u64_at(const std::uint8_t* at) { return *reinterpret_cast<const std::uint64_t*>(at); }

// An MSVC std::string: its buffer or pointer (16 bytes), size, capacity. Called inside __try.
bool read_text(const std::uint8_t* at, RawText& out) {
  const std::uint64_t size = u64_at(at + 0x10);
  const std::uint64_t capacity = u64_at(at + 0x18);
  if (size > kMaxText || capacity < size || capacity < 15) return false;
  out.data = capacity >= 16 ? reinterpret_cast<const char*>(ptr_at(at)) : reinterpret_cast<const char*>(at);
  out.size = size;
  return out.data != nullptr;
}

bool is_nil(const std::uint8_t* node) { return node[kTreeIsNil] != 0; }

// The in-order successor of an MSVC tree node (its head is the only nil node reachable this way), or nullptr once
// `steps` is spent. A whole in-order walk of n nodes takes fewer than 2n steps; links that form a cycle (a layout
// that is not what it seems, or a tree changing while it is read) must not hold the game, and only an access
// violation would stop the walk otherwise.
const std::uint8_t* successor(const std::uint8_t* node, std::uint64_t& steps) {
  const std::uint8_t* right = ptr_at(node + kTreeRight);
  if (!is_nil(right)) {
    node = right;
    for (const std::uint8_t* left = ptr_at(node + kTreeLeft); !is_nil(left); left = ptr_at(node + kTreeLeft)) {
      if (steps-- == 0) return nullptr;
      node = left;
    }
    return node;
  }
  const std::uint8_t* parent = ptr_at(node + kTreeParent);
  while (!is_nil(parent) && node == ptr_at(parent + kTreeRight)) {
    if (steps-- == 0) return nullptr;
    node = parent;
    parent = ptr_at(node + kTreeParent);
  }
  return parent;
}

std::uint64_t walk_budget(std::uint64_t size) { return 2 * size + 64; }

const std::uint8_t* leftmost(const std::uint8_t* head) { return ptr_at(head + kTreeLeft); }

struct Counts {
  std::uint64_t dirs = 0, entries = 0, nodes = 0, text = 0;
};

struct Fingerprint {
  const void* table = nullptr;
  std::uint64_t words[4] = {};  // directory map head and size, list head and size
  std::uint64_t list = 0;       // every list node: its address, owner, title and path buffers and sizes, mixed
  bool operator==(const Fingerprint&) const = default;
};

std::uint64_t mix(std::uint64_t hash, std::uint64_t value) {
  hash ^= value + 0x9e3779b97f4a7c15ull + (hash << 6) + (hash >> 2);
  return hash;
}

struct RawDir {
  std::uint64_t key;  // offset into the text pool
  std::uint32_t key_size, first, count;
};
struct RawEntry {
  std::uint64_t name;
  std::uint32_t name_size;
  std::uint8_t marker;
  const void* owner;
};
struct RawNode {
  std::uint64_t title;
  std::uint32_t title_size;
  const void* filter;
};

// No C++ objects in these frames: they read GMod's memory under SEH.
// Every mount and unmount changes a list node (a new node, owner and strings), so a remount at the same place with the
// same number of directories is still seen; a directory map that changed size is seen by its size.
bool fingerprint_of(const std::uint8_t* table, Fingerprint& out) noexcept {
  __try {
    out.table = table;
    out.words[0] = u64_at(table + kTableDirHead);
    out.words[1] = u64_at(table + kTableDirSize);
    out.words[2] = u64_at(table + kTableListHead);
    out.words[3] = u64_at(table + kTableListSize);
    const std::uint8_t* list = ptr_at(table + kTableListHead);
    const std::uint64_t nodes = out.words[3];
    if (!list || nodes > kMaxNodes) return false;
    std::uint64_t hash = 0, seen = 0;
    for (const std::uint8_t* node = ptr_at(list); node != list; node = ptr_at(node)) {
      if (++seen > nodes) return false;
      hash = mix(hash, reinterpret_cast<std::uintptr_t>(node));
      hash = mix(hash, u64_at(node + kListFilter));
      hash = mix(hash, u64_at(node + 0x10));               // the .gma path's buffer (or its first bytes)
      hash = mix(hash, u64_at(node + 0x10 + 0x10));        // and its size
      hash = mix(hash, u64_at(node + kListTitle));         // the title's buffer (or its first bytes)
      hash = mix(hash, u64_at(node + kListTitle + 0x10));  // and its size
    }
    if (seen != nodes) return false;
    out.list = hash;
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// Counts what the table holds, checking every link and size; fills nothing.
bool count_table(const std::uint8_t* table, Counts& counts, const char** why) noexcept {
  __try {
    const std::uint8_t* head = ptr_at(table + kTableDirHead);
    const std::uint64_t dirs = u64_at(table + kTableDirSize);
    const std::uint8_t* list = ptr_at(table + kTableListHead);
    const std::uint64_t nodes = u64_at(table + kTableListSize);
    if (!head || !is_nil(head) || dirs > kMaxDirs || !list || nodes > kMaxNodes) {
      *why = "the add-on table's heads or sizes are not as expected";
      return false;
    }
    std::uint64_t seen = 0, steps = walk_budget(dirs);
    for (const std::uint8_t* dir = leftmost(head); dir != head; dir = successor(dir, steps)) {
      if (!dir) { *why = "the directory map's links do not end"; return false; }
      if (++seen > dirs) { *why = "the directory map is longer than its size"; return false; }
      RawText key;
      if (!read_text(dir + kTreeValue, key)) { *why = "a directory name is not a string"; return false; }
      counts.text += key.size;
      const std::uint8_t* inner = ptr_at(dir + kDirInnerHead);
      const std::uint64_t size = u64_at(dir + kDirInnerSize);
      if (!inner || !is_nil(inner) || size > kMaxEntries) { *why = "a directory's entries are not a map"; return false; }
      std::uint64_t count = 0, entry_steps = walk_budget(size);
      for (const std::uint8_t* entry = leftmost(inner); entry != inner; entry = successor(entry, entry_steps)) {
        if (!entry) { *why = "a directory's entry map's links do not end"; return false; }
        if (++count > size) { *why = "a directory's entry map is longer than its size"; return false; }
        RawText name;
        if (!read_text(entry + kTreeValue, name)) { *why = "an entry name is not a string"; return false; }
        const std::uint8_t flag = entry[kEntryFlag];
        if (flag > 1) { *why = "an entry's directory flag is not 0 or 1"; return false; }
        counts.text += name.size;
      }
      if (count != size) { *why = "a directory's entry map is shorter than its size"; return false; }
      counts.entries += count;
      if (counts.entries > kMaxEntries) { *why = "too many entries"; return false; }
    }
    if (seen != dirs) { *why = "the directory map is shorter than its size"; return false; }
    counts.dirs = dirs;
    std::uint64_t listed = 0;
    for (const std::uint8_t* node = ptr_at(list); node != list; node = ptr_at(node)) {
      if (++listed > nodes) { *why = "the add-on list is longer than its size"; return false; }
      if (ptr_at(ptr_at(node) + 8) != node) { *why = "the add-on list's links do not agree"; return false; }
      RawText title;
      if (!read_text(node + kListTitle, title)) { *why = "an add-on title is not a string"; return false; }
      counts.text += title.size;
    }
    if (listed != nodes) { *why = "the add-on list is shorter than its size"; return false; }
    counts.nodes = nodes;
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    *why = "the add-on table could not be read";
    return false;
  }
}

// Copies the table into arrays the caller sized from count_table's answer.
bool copy_table(const std::uint8_t* table, const Counts& limits, RawDir* dirs, RawEntry* entries, RawNode* nodes,
                char* text, const char** why) noexcept {
  __try {
    std::uint64_t used = 0, d = 0, e = 0, n = 0;
    const auto take = [&](const RawText& from, std::uint64_t& offset) {
      if (used + from.size > limits.text) return false;
      std::memcpy(text + used, from.data, static_cast<std::size_t>(from.size));
      offset = used;
      used += from.size;
      return true;
    };
    const std::uint8_t* head = ptr_at(table + kTableDirHead);
    std::uint64_t steps = walk_budget(limits.dirs);
    for (const std::uint8_t* dir = leftmost(head); dir != head; dir = successor(dir, steps)) {
      if (!dir || d >= limits.dirs) { *why = "the table changed while it was read"; return false; }
      RawText key;
      if (!read_text(dir + kTreeValue, key) || !take(key, dirs[d].key)) { *why = "the table changed while it was read"; return false; }
      dirs[d].key_size = static_cast<std::uint32_t>(key.size);
      dirs[d].first = static_cast<std::uint32_t>(e);
      const std::uint8_t* inner = ptr_at(dir + kDirInnerHead);
      const std::uint64_t size = u64_at(dir + kDirInnerSize);
      if (size > limits.entries) { *why = "the table changed while it was read"; return false; }
      std::uint64_t entry_steps = walk_budget(size);
      for (const std::uint8_t* entry = leftmost(inner); entry != inner; entry = successor(entry, entry_steps)) {
        if (!entry || e >= limits.entries) { *why = "the table changed while it was read"; return false; }
        RawText name;
        if (!read_text(entry + kTreeValue, name) || !take(name, entries[e].name)) { *why = "the table changed while it was read"; return false; }
        entries[e].name_size = static_cast<std::uint32_t>(name.size);
        entries[e].marker = entry[kEntryFlag];
        entries[e].owner = ptr_at(entry + kEntryOwner);
        ++e;
      }
      dirs[d].count = static_cast<std::uint32_t>(e - dirs[d].first);
      ++d;
    }
    const std::uint8_t* list = ptr_at(table + kTableListHead);
    for (const std::uint8_t* node = ptr_at(list); node != list; node = ptr_at(node)) {
      if (n >= limits.nodes) { *why = "the table changed while it was read"; return false; }
      RawText title;
      if (!read_text(node + kListTitle, title) || !take(title, nodes[n].title)) { *why = "the table changed while it was read"; return false; }
      nodes[n].title_size = static_cast<std::uint32_t>(title.size);
      nodes[n].filter = ptr_at(node + kListFilter);
      ++n;
    }
    if (d != limits.dirs || e != limits.entries || n != limits.nodes) { *why = "the table changed while it was read"; return false; }
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    *why = "the add-on table could not be read";
    return false;
  }
}

// The RTTI name of a polymorphic object of `image`, copied into `out`.
bool rtti_name(const void* object, const std::uint8_t* image, std::size_t image_size, char* out, std::size_t room) noexcept {
  __try {
    const auto* vtable = ptr_at(static_cast<const std::uint8_t*>(object));
    if (vtable < image || vtable >= image + image_size) return false;
    const auto* locator = ptr_at(vtable - 8);
    if (locator < image || locator + 24 > image + image_size) return false;
    if (*reinterpret_cast<const std::uint32_t*>(locator) != 1) return false;  // the x64 locator signature
    const std::uint32_t type_rva = *reinterpret_cast<const std::uint32_t*>(locator + 12);
    const std::uint32_t self_rva = *reinterpret_cast<const std::uint32_t*>(locator + 20);
    if (image + self_rva != locator || type_rva + 0x10u >= image_size) return false;
    const char* name = reinterpret_cast<const char*>(image + type_rva + 0x10);
    std::size_t i = 0;
    for (; i + 1 < room && name[i]; ++i) out[i] = name[i];
    out[i] = '\0';
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

std::uint64_t word_at(const void* object, std::size_t offset) noexcept {
  __try {
    return u64_at(static_cast<const std::uint8_t*>(object) + offset);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

std::string lower_pattern(std::string_view pattern) {
  std::string out;
  out.reserve(pattern.size());
  for (char c : pattern) {
    if (c == '\\') c = '/';
    out.push_back((c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c);
  }
  return out;
}

}  // namespace

struct AddonIndex::Data {
  Fingerprint print;
  std::string text;                                   // every name, pooled
  std::vector<std::string_view> dir_key;              // map order
  std::vector<std::int64_t> parent;                   // the parent directory's id; -1 for a top-level directory
  std::vector<std::string_view> leaf;                 // the last component
  std::unordered_map<std::string_view, std::uint32_t> dir_id;
  struct Owner {
    std::vector<std::uint32_t> dirs;                                       // where it has an entry, map order
    std::unordered_map<std::uint32_t, std::vector<std::string_view>> files;  // its files per directory
  };
  std::unordered_map<const void*, Owner> owners;
  std::unordered_map<std::string_view, std::vector<const void*>> titles;  // list order: repeated titles and mounts
  std::size_t entries = 0;
};

bool AddonIndex::locate(TableAddress& out, std::string* reason) noexcept {
  const HMODULE filesystem = GetModuleHandleW(L"filesystem_stdio.dll");
  if (!filesystem) {
    if (reason) *reason = "filesystem_stdio.dll is not loaded";
    return false;
  }
  const auto* image = reinterpret_cast<const std::uint8_t*>(filesystem);
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(image + reinterpret_cast<const IMAGE_DOS_HEADER*>(image)->e_lfanew);
  const std::size_t image_size = nt->OptionalHeader.SizeOfImage;
  const auto* global = reinterpret_cast<void* const*>(GetProcAddress(filesystem, "?g_pFullFileSystem@@3PEAVIFileSystem@@EA"));
  const void* system = global ? reinterpret_cast<const void*>(word_at(global, 0)) : nullptr;
  char name[96] = {};
  if (!system || !rtti_name(system, image, image_size, name, sizeof(name)) || std::strstr(name, "FileSystem") == nullptr) {
    if (reason) *reason = "the game's file system object was not found";
    return false;
  }
  // Addon::FileSystem is embedded in it (at +0x550 in the build of 2026-10-26): the first member whose RTTI says so.
  for (std::size_t offset = 8; offset < 0x4000; offset += 8) {
    const void* candidate = static_cast<const std::uint8_t*>(system) + offset;
    const std::uint64_t word = word_at(candidate, 0);
    if (word < reinterpret_cast<std::uintptr_t>(image) || word >= reinterpret_cast<std::uintptr_t>(image) + image_size) continue;
    if (rtti_name(candidate, image, image_size, name, sizeof(name)) && std::strcmp(name, ".?AVFileSystem@Addon@@") == 0) {
      out.addon_fs = candidate;
      return true;
    }
  }
  if (reason) *reason = "Addon::FileSystem was not found in the file system object";
  return false;
}

void AddonIndex::invalidate() noexcept { data_.reset(); }

std::size_t AddonIndex::entries() const { return data_ ? data_->entries : 0; }

bool AddonIndex::ensure(const TableAddress& table, std::string* reason) {
  const auto* raw = static_cast<const std::uint8_t*>(table.addon_fs);
  Fingerprint print;
  if (!raw || !fingerprint_of(raw, print)) {
    if (reason) *reason = "the add-on table could not be read";
    return false;
  }
  if (data_ && data_->print == print) return true;
  // A table that changes again and again (add-ons mounted one by one, a search between each) is left to GMod for a
  // moment instead of being read whole each time: at most one build (or attempt) every 2 s.
  const std::uint64_t now = GetTickCount64();
  if (last_build_ != 0 && now - last_build_ < min_rebuild_ms_) {
    data_.reset();
    if (reason) *reason = "GMod's add-on table is changing";
    return false;
  }
  data_.reset();
  last_build_ = now;
  const char* why = "";
  Counts counts;
  if (!count_table(raw, counts, &why)) {
    if (reason) *reason = why;
    return false;
  }
  std::vector<RawDir> dirs(static_cast<std::size_t>(counts.dirs));
  std::vector<RawEntry> entries(static_cast<std::size_t>(counts.entries));
  std::vector<RawNode> nodes(static_cast<std::size_t>(counts.nodes));
  auto data = std::make_shared<Data>();
  data->text.resize(static_cast<std::size_t>(counts.text));
  if (!copy_table(raw, counts, dirs.data(), entries.data(), nodes.data(), data->text.data(), &why)) {
    if (reason) *reason = why;
    return false;
  }
  Fingerprint after;
  if (!fingerprint_of(raw, after) || after != print) {
    if (reason) *reason = "the table changed while it was read";
    return false;
  }
  data->print = print;
  data->entries = entries.size();
  const std::string_view text(data->text);
  data->dir_key.reserve(dirs.size());
  for (const auto& dir : dirs) {
    const std::string_view key = text.substr(static_cast<std::size_t>(dir.key), dir.key_size);
    data->dir_id.emplace(key, static_cast<std::uint32_t>(data->dir_key.size()));
    data->dir_key.push_back(key);
  }
  data->parent.resize(dirs.size(), -1);
  data->leaf.resize(dirs.size());
  for (std::size_t i = 0; i < dirs.size(); ++i) {
    const std::string_view key = data->dir_key[i];
    const std::size_t slash = key.rfind('/');
    data->leaf[i] = slash == std::string_view::npos ? key : key.substr(slash + 1);
    if (key.empty()) {
      data->parent[i] = -4;  // files at the top level, if a table ever has them: not a directory of anything
    } else if (slash != std::string_view::npos) {
      const auto found = data->dir_id.find(key.substr(0, slash));
      data->parent[i] = found != data->dir_id.end() ? static_cast<std::int64_t>(found->second) : -2;  // -2: no parent entry
    }
  }
  for (std::size_t i = 0; i < dirs.size(); ++i) {
    for (std::uint32_t j = dirs[i].first; j < dirs[i].first + dirs[i].count; ++j) {
      const RawEntry& entry = entries[j];
      auto& owner = data->owners[entry.owner];
      if (owner.dirs.empty() || owner.dirs.back() != i) owner.dirs.push_back(static_cast<std::uint32_t>(i));
      if (!entry.marker) {
        owner.files[static_cast<std::uint32_t>(i)].push_back(text.substr(static_cast<std::size_t>(entry.name), entry.name_size));
      }
    }
  }
  for (const auto& node : nodes) {
    data->titles[text.substr(static_cast<std::size_t>(node.title), node.title_size)].push_back(node.filter);
  }
  data_ = std::move(data);
  ++builds_;
  last_build_ms_ = GetTickCount64() - now;
  return true;
}

bool AddonIndex::find(const TableAddress& table, std::string_view pattern, std::string_view title, FindResult& out,
                      std::string* reason) {
  out.files.clear();
  out.dirs.clear();
  if (!ensure(table, reason)) return false;
  const Data& data = *data_;
  const auto titled = data.titles.find(title);
  if (titled == data.titles.end()) {
    if (reason) *reason = "no add-on has this title";
    return false;
  }
  const std::string normalized = lower_pattern(pattern);
  const std::size_t slash = normalized.rfind('/');
  const std::string_view base = slash == std::string::npos ? std::string_view() : std::string_view(normalized).substr(0, slash);
  const std::string_view wildcard = slash == std::string::npos ? std::string_view(normalized)
                                                               : std::string_view(normalized).substr(slash + 1);
  // A wildcard in the folder part ("lua/?utorun/*"): GMod's own answer (none, in the build measured) is the one to give.
  if (base.find_first_of("*?") != std::string_view::npos) {
    if (reason) *reason = "a wildcard in the folder part";
    return false;
  }
  // The parent the matching directories have (-1: the top level) and the directory whose files match; -3: none.
  const auto found = data.dir_id.find(base);
  const std::int64_t base_id = found != data.dir_id.end() ? static_cast<std::int64_t>(found->second) : -3;
  const std::int64_t dirs_parent = base.empty() ? -1 : base_id;
  for (const void* filter : titled->second) {
    const auto owner = data.owners.find(filter);
    if (owner == data.owners.end()) continue;
    if (dirs_parent != -3) {
      for (const std::uint32_t dir : owner->second.dirs) {
        if (data.parent[dir] == dirs_parent && wildcard_match(wildcard, data.leaf[dir])) out.dirs.emplace_back(data.leaf[dir]);
      }
    }
    if (base_id >= 0) {
      const auto files = owner->second.files.find(static_cast<std::uint32_t>(base_id));
      if (files != owner->second.files.end()) {
        for (const std::string_view name : files->second) {
          if (wildcard_match(wildcard, name)) out.files.emplace_back(name);
        }
      }
    }
  }
  // Two add-ons with one title give a name once, as GMod's search does.
  std::sort(out.files.begin(), out.files.end());
  out.files.erase(std::unique(out.files.begin(), out.files.end()), out.files.end());
  std::sort(out.dirs.begin(), out.dirs.end());
  out.dirs.erase(std::unique(out.dirs.begin(), out.dirs.end()), out.dirs.end());
  return true;
}

}  // namespace nl::fs_accel
