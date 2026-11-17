// E (ADR 0242): the record of a load's reads, its list, and the prefetch that reads a list ahead.
#include "fs_accel.h"
#include "nl_test.h"

#include <windows.h>

#include <fstream>
#include <string>
#include <vector>

namespace {
namespace prefetch = nl::fs_accel::prefetch;

constexpr std::uint64_t kBlock = 1ull << prefetch::kBlockShift;

// A file of `blocks` 64 KiB blocks.
std::filesystem::path make_file(const std::filesystem::path& file, std::uint64_t blocks) {
  std::filesystem::create_directories(file.parent_path());
  std::ofstream out(file, std::ios::binary);
  const std::string block(static_cast<std::size_t>(kBlock), 'b');
  for (std::uint64_t i = 0; i < blocks; ++i) out << block;
  return file;
}

HANDLE open_read(const std::filesystem::path& file) {
  return CreateFileW(file.wstring().c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
}

// What the ReadFile hook does: the record first, then the read.
void hooked_read(HANDLE file, std::uint64_t offset, DWORD bytes, bool overlapped) {
  std::vector<char> buffer(bytes);
  DWORD got = 0;
  if (overlapped) {
    OVERLAPPED position{};
    position.Offset = static_cast<DWORD>(offset);
    position.OffsetHigh = static_cast<DWORD>(offset >> 32);
    prefetch::read(file, bytes, &position);
    ReadFile(file, buffer.data(), bytes, &got, &position);
  } else {
    LARGE_INTEGER to{};
    to.QuadPart = static_cast<LONGLONG>(offset);
    SetFilePointerEx(file, to, nullptr, FILE_BEGIN);
    prefetch::read(file, bytes, nullptr);
    ReadFile(file, buffer.data(), bytes, &got, nullptr);
  }
}

const prefetch::Entry* entry_for(const std::vector<prefetch::Entry>& entries, const std::filesystem::path& file) {
  const std::wstring want = file.wstring();
  for (const auto& entry : entries) {
    if (_wcsicmp(entry.path.c_str(), want.c_str()) == 0) return &entry;
  }
  return nullptr;
}
}  // namespace

TEST_CASE("fs_accel prefetch: list names") {
  CHECK(prefetch::list_name("gm_construct") == L"gm_construct.lst");
  CHECK(prefetch::list_name("modern_house") == L"modern_house.lst");
  CHECK(prefetch::list_name("rp_city-v2.final") == L"rp_city-v2.final.lst");
  CHECK(prefetch::list_name("").empty());
  CHECK(prefetch::list_name(".hidden").empty());
  CHECK(prefetch::list_name("a..b").empty());
  CHECK(prefetch::list_name("../x").empty());
  CHECK(prefetch::list_name("a/b").empty());
  CHECK(prefetch::list_name("a\\b").empty());
  CHECK(prefetch::list_name("c:x").empty());
  CHECK(prefetch::list_name(std::string(65, 'a')).empty());
}

TEST_CASE("fs_accel prefetch: a record names the blocks read, files in the order first read") {
  const auto root = nl::test::scratch_dir("fs_accel_prefetch_record");
  const auto first = make_file(root / "first.bin", 8);
  const auto second = make_file(root / "second.gma", 40);
  const auto cached = make_file(root / "garrysmod" / "cache" / "map_pack.bsp", 4);
  const auto unread = make_file(root / "unread.bin", 4);

  // Nothing is noted while no record runs.
  HANDLE h = open_read(first);
  REQUIRE(h != INVALID_HANDLE_VALUE);
  hooked_read(h, 0, 100, false);
  CloseHandle(h);
  CHECK(prefetch::record_list(1ull << 40).empty());

  prefetch::record_start();
  CHECK(prefetch::recording());
  // second: opened before the record (unknown handle: named by Windows), read with OVERLAPPED offsets.
  HANDLE second_h = open_read(second);
  REQUIRE(second_h != INVALID_HANDLE_VALUE);
  hooked_read(second_h, 10 * kBlock + 5, 3 * static_cast<DWORD>(kBlock), true);  // blocks 10-13
  // first: named at its open, read synchronously (offset from the handle's position).
  HANDLE first_h = open_read(first);
  REQUIRE(first_h != INVALID_HANDLE_VALUE);
  prefetch::opened(first_h, first.wstring().c_str());
  hooked_read(first_h, 0, 10, false);              // block 0
  hooked_read(first_h, 2 * kBlock, 2 * static_cast<DWORD>(kBlock), false);  // blocks 2-3
  hooked_read(second_h, 30 * kBlock, 1, true);     // block 30
  HANDLE cached_h = open_read(cached);
  prefetch::opened(cached_h, cached.wstring().c_str());
  hooked_read(cached_h, 0, 100, false);
  HANDLE unread_h = open_read(unread);
  prefetch::opened(unread_h, unread.wstring().c_str());  // opened, never read
  CHECK(prefetch::record_stop());
  CHECK(!prefetch::recording());
  hooked_read(first_h, 6 * kBlock, 10, false);  // after the record: not noted
  for (HANDLE handle : {first_h, second_h, cached_h, unread_h}) CloseHandle(handle);

  const auto entries = prefetch::record_list(1ull << 40);
  REQUIRE(entries.size() == 2);  // the cache folder and the unread file are left out
  CHECK(_wcsicmp(entries[0].path.c_str(), second.wstring().c_str()) == 0);
  CHECK(_wcsicmp(entries[1].path.c_str(), first.wstring().c_str()) == 0);
  const auto* s = entry_for(entries, second);
  REQUIRE(s != nullptr);
  CHECK(s->size == 40 * kBlock);
  REQUIRE(s->ranges.size() == 2);
  CHECK(s->ranges[0].first == 10);
  CHECK(s->ranges[0].count == 4);
  CHECK(s->ranges[1].first == 30);
  CHECK(s->ranges[1].count == 1);
  const auto* f = entry_for(entries, first);
  REQUIRE(f != nullptr);
  REQUIRE(f->ranges.size() == 2);
  CHECK(f->ranges[0].first == 0);
  CHECK(f->ranges[0].count == 1);
  CHECK(f->ranges[1].first == 2);
  CHECK(f->ranges[1].count == 2);

  // A budget keeps the first-read files first.
  const auto small = prefetch::record_list(4 * kBlock);
  REQUIRE(small.size() == 1);
  CHECK(small[0].ranges.size() == 1);
  CHECK(small[0].ranges[0].count == 4);
}

TEST_CASE("fs_accel prefetch: a list is written whole and read back") {
  const auto root = nl::test::scratch_dir("fs_accel_prefetch_list");
  std::vector<prefetch::Entry> entries(2);
  entries[0].path = (root / L"a bé.gma").wstring();
  entries[0].size = 123456789;
  entries[0].written = 133000000000000000ull;
  entries[0].ranges = {{0, 3}, {0x10, 0x200}};
  entries[1].path = (root / "c.vtf").wstring();
  entries[1].size = 70000;
  entries[1].ranges = {{1, 1}};
  const std::wstring path = (root / "prefetch" / "gm_test.lst").wstring();
  std::filesystem::create_directories(root / "prefetch");
  std::string why;
  REQUIRE(prefetch::save_list(path, entries, &why));
  CHECK(!std::filesystem::exists(path + L".tmp"));
  std::vector<prefetch::Entry> back;
  REQUIRE(prefetch::load_list(path, back, &why));
  REQUIRE(back.size() == 2);
  CHECK(back[0].path == entries[0].path);
  CHECK(back[0].size == entries[0].size);
  CHECK(back[0].written == entries[0].written);
  REQUIRE(back[0].ranges.size() == 2);
  CHECK(back[0].ranges[1].first == 0x10);
  CHECK(back[0].ranges[1].count == 0x200);
  CHECK(back[1].path == entries[1].path);

  // Not a list this module wrote; relative or network paths in a list are dropped.
  const auto other = root / "prefetch" / "other.lst";
  std::ofstream(other, std::ios::binary) << "something else\n";
  CHECK(!prefetch::load_list(other.wstring(), back, &why));
  std::ofstream(other, std::ios::binary | std::ios::trunc) << "nlprefetch 1\n1\t0\t0+1\tsome\\relative.gma\n1\t0\t0+1\t\\\\server\\share\\x.gma\n";
  REQUIRE(prefetch::load_list(other.wstring(), back, &why));
  CHECK(back.empty());
  CHECK(!prefetch::load_list((root / "missing.lst").wstring(), back, &why));
}

TEST_CASE("fs_accel prefetch: a list's blocks are read ahead, within the budget") {
  const auto root = nl::test::scratch_dir("fs_accel_prefetch_run");
  const auto a = make_file(root / "a.gma", 16);
  const auto b = make_file(root / "b.gma", 8);
  std::vector<prefetch::Entry> entries(3);
  entries[0].path = a.wstring();
  entries[0].size = 16 * kBlock;
  entries[0].ranges = {{0, 2}, {10, 4}, {14, 4}};  // the last range runs past the end: clipped
  entries[1].path = b.wstring();
  entries[1].size = 9 * kBlock;                    // another size: passed over
  entries[1].ranges = {{0, 1}};
  entries[2].path = (root / "gone.gma").wstring();
  entries[2].size = kBlock;
  entries[2].ranges = {{0, 1}};
  const std::wstring path = (root / "run.lst").wstring();
  std::string why;
  REQUIRE(prefetch::save_list(path, entries, &why));

  REQUIRE(prefetch::start(path, 1ull << 30, &why));
  REQUIRE(prefetch::wait(20000));
  auto status = prefetch::status();
  CHECK(!status.running);
  CHECK(status.files == 1);
  CHECK(status.skipped == 2);
  CHECK(status.bytes == 8 * kBlock);  // blocks 0-1, 10-13 and 14-15

  REQUIRE(prefetch::start(path, 3 * kBlock, &why));
  REQUIRE(prefetch::wait(20000));
  status = prefetch::status();
  CHECK(status.bytes == 3 * kBlock);

  CHECK(!prefetch::start((root / "missing.lst").wstring(), 0, &why));
  CHECK(prefetch::default_budget() >= (256ull << 20));
  CHECK(prefetch::default_budget() <= (4ull << 30));
}
