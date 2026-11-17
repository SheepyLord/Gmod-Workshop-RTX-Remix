// E: what a map load read, read again ahead of the next load (load-speedup round 3, ADR 0242).
//
// The record: while on, the ReadFile hook (hooks.cpp) reports each read of filesystem_stdio.dll with its handle; the
// handle's file comes from the CreateFile hooks (opened()) or, for a handle opened before the record began (the
// Workshop's archives are opened at start), from Windows (GetFinalPathNameByHandleW); its offset from the OVERLAPPED
// or, for a synchronous read, from the handle's position, asked before the read. Each file keeps a bitmap of the
// 64 KiB blocks read; the files keep the order they were first read in.
// The list: a text file, one file a line; written whole and renamed over the old one. Lua's file.Write cannot make
// a .lst file, so what a list names was read by this game.
// The prefetch: a thread of its own opens each file of a list in order, checks it is a plain file on a local fixed
// drive of the size the list names, gives its reads a low I/O priority, and reads the listed blocks into a buffer it
// throws away: Windows keeps them in its file cache for the game.
#include "fs_accel.h"

#include <windows.h>

#include <intrin.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <memory>
#include <mutex>
#include <unordered_map>

namespace nl::fs_accel::prefetch {
namespace {

constexpr std::uint64_t kBlock = 1ull << kBlockShift;
constexpr std::size_t kMaxFiles = 200000;
constexpr std::uint64_t kMaxBlockIndex = 1ull << 24;  // 1 TiB into a file
constexpr std::uint64_t kMaxListBytes = 32ull << 20;
constexpr DWORD kBufferBytes = 1u << 20;

// SRW lock scopes: released however the scope ends (an allocation may throw while the lock is held).
struct Exclusive {
  explicit Exclusive(SRWLOCK& l) : lock(l) { AcquireSRWLockExclusive(&lock); }
  ~Exclusive() { ReleaseSRWLockExclusive(&lock); }
  SRWLOCK& lock;
};
struct Shared {
  explicit Shared(SRWLOCK& l) : lock(l) { AcquireSRWLockShared(&lock); }
  ~Shared() { ReleaseSRWLockShared(&lock); }
  SRWLOCK& lock;
};

std::wstring lower(std::wstring text) {
  for (wchar_t& c : text) c = static_cast<wchar_t>(towlower(c));
  return text;
}

// "\\?\X:\..." (as Windows names a handle's file) or "X:\...": the plain drive path, else empty.
std::wstring plain_path(std::wstring path) {
  if (path.rfind(L"\\\\?\\", 0) == 0) path.erase(0, 4);
  if (path.size() < 3 || path[1] != L':' || path[2] != L'\\') return {};
  const wchar_t letter = path[0];
  if (!((letter >= L'A' && letter <= L'Z') || (letter >= L'a' && letter <= L'z'))) return {};
  return path;
}

bool local_fixed(const std::wstring& path) {
  if (plain_path(path).empty()) return false;
  const wchar_t root[4] = {path[0], L':', L'\\', 0};
  return GetDriveTypeW(root) == DRIVE_FIXED;
}

struct FileRec {
  std::wstring path;
  std::vector<std::uint64_t> bits;
  std::uint64_t blocks = 0;
  std::uint64_t first_read = UINT64_MAX;  // the order of its first read (files are listed in it)
};

// A read costs one lock and no allocation: each handle is mapped to its file's index once (at its open, or at its
// first read), and the read only sets bits.
struct Recorder {
  SRWLOCK lock = SRWLOCK_INIT;
  std::atomic<bool> on{false};
  std::unordered_map<void*, std::int32_t> handles;         // handle -> index in files (-1: not a file this records)
  std::unordered_map<std::wstring, std::int32_t> by_path;  // lower-case path -> index in files
  std::vector<FileRec> files;
  std::uint64_t blocks = 0;
  std::uint64_t reads_seen = 0;  // reads recorded (under the lock)
  std::uint64_t sequence = 0;
};

Recorder& recorder() {
  static Recorder* r = new Recorder();  // never destroyed: a file system thread may be in a hook at process exit
  return *r;
}

struct Runner {
  std::mutex lock;
  std::atomic<std::uint64_t> generation{0};
  std::atomic<bool> running{false};
  std::atomic<std::uint64_t> files{0}, bytes{0}, skipped{0};
  std::atomic<std::uint64_t> began{0}, ended{0};  // GetTickCount64()
  std::string list;
  HANDLE thread = nullptr;
};

Runner& runner() {
  static Runner* r = new Runner();
  return *r;
}

std::string utf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<std::size_t>(std::max(size, 0)), '\0');
  if (size > 0) WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring wide(std::string_view text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring out(static_cast<std::size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}

std::wstring full_path(const wchar_t* name) {
  wchar_t buffer[1024];
  const DWORD size = GetFullPathNameW(name, 1024, buffer, nullptr);
  if (size == 0 || size >= 1024) return {};
  return plain_path(std::wstring(buffer, size));
}

// The handle's file, under the lock: its index (created on first sight), or -1 for a path this does not record.
std::int32_t index_for(Recorder& r, const std::wstring& path) {
  if (path.empty()) return -1;
  const std::wstring key = lower(path);
  if (const auto it = r.by_path.find(key); it != r.by_path.end()) return it->second;
  if (r.files.size() >= kMaxFiles) return -1;
  const auto index = static_cast<std::int32_t>(r.files.size());
  r.files.push_back(FileRec{path, {}, 0, UINT64_MAX});
  r.by_path.emplace(key, index);
  return index;
}

// Returns the handle's index (-1: not recorded).
std::int32_t note_handle(void* handle, const std::wstring& path) noexcept {
  Recorder& r = recorder();
  try {
    Exclusive scope(r.lock);
    if (!r.on.load(std::memory_order_relaxed) || r.handles.size() >= kMaxFiles * 2) return -1;
    const std::int32_t index = index_for(r, path);
    r.handles[handle] = index;
    return index;
  } catch (...) {
    return -1;
  }
}

// Under the lock: the blocks of one read.
void mark(Recorder& r, std::int32_t index, std::uint64_t first, std::uint64_t last) {
  if (!r.on.load(std::memory_order_relaxed) || index < 0 || static_cast<std::size_t>(index) >= r.files.size()) return;
  FileRec& file = r.files[static_cast<std::size_t>(index)];
  ++r.reads_seen;
  if (file.first_read == UINT64_MAX) file.first_read = ++r.sequence;
  if (file.bits.size() <= (last >> 6)) file.bits.resize(static_cast<std::size_t>((last >> 6) + 1), 0);
  for (std::uint64_t block = first; block <= last; ++block) {
    std::uint64_t& word = file.bits[static_cast<std::size_t>(block >> 6)];
    const std::uint64_t bit = 1ull << (block & 63);
    if (!(word & bit)) {
      word |= bit;
      ++file.blocks;
      ++r.blocks;
    }
  }
}

}  // namespace

std::wstring list_name(std::string_view map) {
  if (map.empty() || map.size() > 64 || map.front() == '.') return {};
  for (const char c : map) {
    const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
    if (!ok) return {};
  }
  if (map.find("..") != std::string_view::npos) return {};
  return wide(map) + L".lst";
}

void record_start() noexcept {
  Recorder& r = recorder();
  Exclusive scope(r.lock);
  r.handles.clear();
  r.by_path.clear();
  r.files.clear();
  r.blocks = 0;
  r.reads_seen = 0;
  r.sequence = 0;
  r.on.store(true, std::memory_order_release);
}

bool record_stop() noexcept {
  return recorder().on.exchange(false, std::memory_order_acq_rel);
}

bool recording() noexcept { return recorder().on.load(std::memory_order_relaxed); }

void opened(void* handle, const char* name) noexcept {
  if (!recording() || !handle || handle == INVALID_HANDLE_VALUE || !name) return;
  wchar_t buffer[1024];
  const int size = MultiByteToWideChar(CP_ACP, 0, name, -1, buffer, 1024);
  if (size <= 0) return;
  try {
    note_handle(handle, full_path(buffer));
  } catch (...) {
  }
}

void opened(void* handle, const wchar_t* name) noexcept {
  if (!recording() || !handle || handle == INVALID_HANDLE_VALUE || !name) return;
  try {
    note_handle(handle, full_path(name));
  } catch (...) {
  }
}

void read(void* handle, std::uint64_t bytes, const void* overlapped) noexcept {
  Recorder& r = recorder();
  if (!r.on.load(std::memory_order_relaxed) || !handle || handle == INVALID_HANDLE_VALUE || bytes == 0) return;
  std::uint64_t offset = 0;
  if (overlapped) {
    const auto* ov = static_cast<const OVERLAPPED*>(overlapped);
    offset = (static_cast<std::uint64_t>(ov->OffsetHigh) << 32) | ov->Offset;
  } else {
    LARGE_INTEGER zero{}, position{};
    if (!SetFilePointerEx(handle, zero, &position, FILE_CURRENT) || position.QuadPart < 0) return;
    offset = static_cast<std::uint64_t>(position.QuadPart);
  }
  const std::uint64_t first = offset >> kBlockShift;
  const std::uint64_t last = (offset + bytes - 1) >> kBlockShift;
  if (last >= kMaxBlockIndex) return;
  try {
    // The handle's file: named at its open, or asked of Windows once (outside the lock).
    std::int32_t index = -1;
    bool known = false;
    {
      Exclusive scope(r.lock);
      if (const auto it = r.handles.find(handle); it != r.handles.end()) {
        index = it->second;
        known = true;
        if (index >= 0) mark(r, index, first, last);
      }
    }
    if (known) return;
    wchar_t buffer[1024];
    const DWORD size = GetFinalPathNameByHandleW(handle, buffer, 1024, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    index = note_handle(handle, size > 0 && size < 1024 ? plain_path(std::wstring(buffer, size)) : std::wstring());
    if (index < 0) return;
    Exclusive scope(r.lock);
    mark(r, index, first, last);
  } catch (...) {
    // Out of memory: this read is not recorded.
  }
}

std::vector<Entry> record_list(std::uint64_t budget) {
  std::vector<FileRec> files;
  {
    Recorder& r = recorder();
    try {
      Shared scope(r.lock);
      files = r.files;
    } catch (...) {
    }
  }
  // In the order of their first reads; files opened and never read are left out.
  files.erase(std::remove_if(files.begin(), files.end(), [](const FileRec& f) { return f.first_read == UINT64_MAX; }), files.end());
  std::sort(files.begin(), files.end(), [](const FileRec& a, const FileRec& b) { return a.first_read < b.first_read; });
  std::vector<Entry> out;
  std::uint64_t total = 0;
  for (const FileRec& file : files) {
    if (total >= budget) break;
    const std::wstring key = lower(file.path);
    // GMod writes the map's copy in cache\ during every load; this game's own data folder changes as it runs.
    if (key.find(L"\\garrysmod\\cache\\") != std::wstring::npos || key.find(L"\\garrysmod\\data\\") != std::wstring::npos) continue;
    if (!local_fixed(file.path)) continue;
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(file.path.c_str(), GetFileExInfoStandard, &data) || (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    Entry entry;
    entry.path = file.path;
    entry.size = (static_cast<std::uint64_t>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
    entry.written = (static_cast<std::uint64_t>(data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
    const std::uint64_t size_blocks = (entry.size + kBlock - 1) >> kBlockShift;
    for (std::size_t w = 0; w < file.bits.size() && total < budget; ++w) {
      std::uint64_t word = file.bits[w];
      while (word && total < budget) {
        unsigned long bit = 0;
        _BitScanForward64(&bit, word);
        const std::uint64_t block = (static_cast<std::uint64_t>(w) << 6) + bit;
        word &= word - 1;
        if (block >= size_blocks) continue;
        if (!entry.ranges.empty() && entry.ranges.back().first + entry.ranges.back().count == block) {
          ++entry.ranges.back().count;
        } else {
          entry.ranges.push_back({block, 1});
        }
        total += kBlock;
      }
    }
    if (!entry.ranges.empty()) out.push_back(std::move(entry));
  }
  return out;
}

bool save_list(const std::wstring& path, const std::vector<Entry>& entries, std::string* why) {
  std::string text = "nlprefetch 1\n";
  char number[64];
  for (const Entry& entry : entries) {
    std::snprintf(number, sizeof(number), "%llu\t%llu\t", static_cast<unsigned long long>(entry.size),
                  static_cast<unsigned long long>(entry.written));
    text += number;
    for (std::size_t i = 0; i < entry.ranges.size(); ++i) {
      std::snprintf(number, sizeof(number), i ? ";%llx+%llx" : "%llx+%llx",
                    static_cast<unsigned long long>(entry.ranges[i].first), static_cast<unsigned long long>(entry.ranges[i].count));
      text += number;
    }
    text += '\t';
    text += utf8(entry.path);
    text += '\n';
  }
  const std::wstring folder = path.substr(0, path.find_last_of(L'\\'));
  CreateDirectoryW(folder.c_str(), nullptr);
  const std::wstring temporary = path + L".tmp";
  const HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    if (why) *why = "the list could not be written (" + std::to_string(GetLastError()) + ")";
    return false;
  }
  DWORD written = 0;
  const bool ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) && written == text.size();
  CloseHandle(file);
  if (!ok || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING)) {
    DeleteFileW(temporary.c_str());
    if (why) *why = "the list could not be written";
    return false;
  }
  return true;
}

bool load_list(const std::wstring& path, std::vector<Entry>& entries, std::string* why) {
  entries.clear();
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    if (why) *why = "no list";
    return false;
  }
  LARGE_INTEGER size{};
  std::string text;
  bool ok = GetFileSizeEx(file, &size) && size.QuadPart > 0 && static_cast<std::uint64_t>(size.QuadPart) <= kMaxListBytes;
  if (ok) {
    text.resize(static_cast<std::size_t>(size.QuadPart));
    DWORD got = 0;
    ok = ReadFile(file, text.data(), static_cast<DWORD>(text.size()), &got, nullptr) && got == text.size();
  }
  CloseHandle(file);
  if (!ok || text.rfind("nlprefetch 1\n", 0) != 0) {
    if (why) *why = "the list is not one this module wrote";
    return false;
  }
  std::size_t at = std::strlen("nlprefetch 1\n");
  while (at < text.size() && entries.size() < kMaxFiles) {
    const std::size_t end = text.find('\n', at);
    if (end == std::string::npos) break;
    const std::string_view line(text.data() + at, end - at);
    at = end + 1;
    const std::size_t t1 = line.find('\t');
    const std::size_t t2 = t1 == std::string_view::npos ? t1 : line.find('\t', t1 + 1);
    const std::size_t t3 = t2 == std::string_view::npos ? t2 : line.find('\t', t2 + 1);
    if (t3 == std::string_view::npos) continue;
    Entry entry;
    entry.size = std::strtoull(std::string(line.substr(0, t1)).c_str(), nullptr, 10);
    entry.written = std::strtoull(std::string(line.substr(t1 + 1, t2 - t1 - 1)).c_str(), nullptr, 10);
    entry.path = plain_path(wide(line.substr(t3 + 1)));
    if (entry.path.empty()) continue;
    std::string_view ranges = line.substr(t2 + 1, t3 - t2 - 1);
    while (!ranges.empty()) {
      const std::size_t semicolon = ranges.find(';');
      const std::string_view item = ranges.substr(0, semicolon);
      const std::size_t plus = item.find('+');
      if (plus != std::string_view::npos) {
        Range range;
        range.first = std::strtoull(std::string(item.substr(0, plus)).c_str(), nullptr, 16);
        range.count = std::strtoull(std::string(item.substr(plus + 1)).c_str(), nullptr, 16);
        if (range.count > 0 && range.first < kMaxBlockIndex && range.count <= kMaxBlockIndex) entry.ranges.push_back(range);
      }
      if (semicolon == std::string_view::npos) break;
      ranges.remove_prefix(semicolon + 1);
    }
    if (!entry.ranges.empty()) entries.push_back(std::move(entry));
  }
  return true;
}

namespace {

struct Job {
  std::vector<Entry> entries;
  std::uint64_t budget = 0;
  std::uint64_t generation = 0;
};

DWORD WINAPI prefetch_main(void* parameter) {
  std::unique_ptr<Job> job(static_cast<Job*>(parameter));
  Runner& run = runner();
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
  std::unique_ptr<char[]> buffer(new (std::nothrow) char[kBufferBytes]);
  std::uint64_t left = job->budget;
  for (const Entry& entry : job->entries) {
    if (!buffer || left == 0 || run.generation.load(std::memory_order_relaxed) != job->generation) break;
    if (!local_fixed(entry.path)) {
      run.skipped.fetch_add(1, std::memory_order_relaxed);
      continue;
    }
    const HANDLE file = CreateFileW(entry.path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                    nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      run.skipped.fetch_add(1, std::memory_order_relaxed);
      continue;
    }
    BY_HANDLE_FILE_INFORMATION info{};
    const std::uint64_t size = GetFileInformationByHandle(file, &info)
        ? (static_cast<std::uint64_t>(info.nFileSizeHigh) << 32) | info.nFileSizeLow : ~0ull;
    if (GetFileType(file) != FILE_TYPE_DISK || (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || size != entry.size) {
      CloseHandle(file);
      run.skipped.fetch_add(1, std::memory_order_relaxed);
      continue;
    }
    FILE_IO_PRIORITY_HINT_INFO hint{};
    hint.PriorityHint = IoPriorityHintLow;
    SetFileInformationByHandle(file, FileIoPriorityHintInfo, &hint, sizeof(hint));
    for (const Range& range : entry.ranges) {
      std::uint64_t at = range.first << kBlockShift;
      const std::uint64_t end = std::min<std::uint64_t>((range.first + range.count) << kBlockShift, size);
      while (at < end && left > 0) {
        if (run.generation.load(std::memory_order_relaxed) != job->generation) break;
        const DWORD want = static_cast<DWORD>(std::min<std::uint64_t>({end - at, kBufferBytes, left}));
        OVERLAPPED position{};
        position.Offset = static_cast<DWORD>(at);
        position.OffsetHigh = static_cast<DWORD>(at >> 32);
        DWORD got = 0;
        if (!ReadFile(file, buffer.get(), want, &got, &position) || got == 0) break;
        at += got;
        left -= std::min<std::uint64_t>(left, got);
        run.bytes.fetch_add(got, std::memory_order_relaxed);
      }
    }
    CloseHandle(file);
    run.files.fetch_add(1, std::memory_order_relaxed);
  }
  if (run.generation.load(std::memory_order_relaxed) == job->generation) {
    run.ended.store(GetTickCount64(), std::memory_order_relaxed);
    run.running.store(false, std::memory_order_release);
  }
  return 0;
}

}  // namespace

bool start(const std::wstring& list_path, std::uint64_t budget, std::string* why) {
  auto job = std::make_unique<Job>();
  if (!load_list(list_path, job->entries, why)) return false;
  if (job->entries.empty()) {
    if (why) *why = "the list is empty";
    return false;
  }
  job->budget = budget ? budget : default_budget();
  Runner& run = runner();
  std::lock_guard<std::mutex> guard(run.lock);
  job->generation = run.generation.fetch_add(1, std::memory_order_acq_rel) + 1;
  run.files.store(0);
  run.bytes.store(0);
  run.skipped.store(0);
  run.began.store(GetTickCount64());
  run.ended.store(0);
  run.list = utf8(list_path);
  run.running.store(true, std::memory_order_release);
  if (run.thread) {
    CloseHandle(run.thread);
    run.thread = nullptr;
  }
  Job* raw = job.release();
  run.thread = CreateThread(nullptr, 0, &prefetch_main, raw, 0, nullptr);
  if (!run.thread) {
    delete raw;
    run.running.store(false);
    if (why) *why = "no thread for it";
    return false;
  }
  return true;
}

Status status() {
  Status out;
  {
    Recorder& r = recorder();
    Shared scope(r.lock);
    out.recording = r.on.load(std::memory_order_relaxed);
    out.record_files = r.files.size();
    out.record_blocks = r.blocks;
    out.record_reads = r.reads_seen;
  }
  Runner& run = runner();
  out.running = run.running.load(std::memory_order_acquire);
  out.files = run.files.load();
  out.bytes = run.bytes.load();
  out.skipped = run.skipped.load();
  const std::uint64_t began = run.began.load(), ended = run.ended.load();
  if (began) out.seconds = static_cast<double>((ended ? ended : GetTickCount64()) - began) / 1000.0;
  std::lock_guard<std::mutex> guard(run.lock);
  out.list = run.list;
  return out;
}

std::uint64_t default_budget() noexcept {
  MEMORYSTATUSEX memory{};
  memory.dwLength = sizeof(memory);
  std::uint64_t quarter = GlobalMemoryStatusEx(&memory) ? memory.ullTotalPhys / 4 : (1ull << 30);
  return std::max<std::uint64_t>(256ull << 20, std::min<std::uint64_t>(quarter, 4ull << 30));
}

bool wait(unsigned long ms) noexcept {
  const ULONGLONG until = GetTickCount64() + ms;
  while (runner().running.load(std::memory_order_acquire)) {
    if (GetTickCount64() >= until) return false;
    Sleep(5);
  }
  return true;
}

}  // namespace nl::fs_accel::prefetch
