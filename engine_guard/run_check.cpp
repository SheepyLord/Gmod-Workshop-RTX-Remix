// Queued render calls checked again while the game runs them (ADR 0254). See run_check.h.
#include "run_check.h"

#include <windows.h>

#include <algorithm>
#include <cstring>

namespace nl::engine_guard::run_check {

const char* describe(Event event) noexcept {
  switch (event) {
    case Event::put_back:
      return "its words changed after the check (written over while the game ran the list): put back as the check saw "
             "them";
    case Event::object_changed:
      return "its call's object changed after the check: skipped";
    case Event::ran_twice:
      return "reached a second time in one run: skipped, and its list ends here";
    case Event::stranger:
      return "an element the check never saw, whose object is not live: skipped";
    case Event::next_put_back:
      return "its call changed the element's link to the next call: put back";
    case Event::ended:
      return "its link to the next call leads out of the list's arena: the list ends here";
  }
  return "?";
}

std::vector<std::uint8_t> dispatch_patch(std::uintptr_t site, std::uintptr_t slot) {
  // mov rcx,rbx; call [rip+disp32], whose next instruction is at site + 9; nop
  const std::int64_t displacement = static_cast<std::int64_t>(slot) - static_cast<std::int64_t>(site + 9);
  if (displacement < INT32_MIN || displacement > INT32_MAX) return {};
  std::vector<std::uint8_t> bytes = {0x48, 0x8B, 0xCB, 0xFF, 0x15};
  const auto d = static_cast<std::uint32_t>(static_cast<std::int32_t>(displacement));
  for (int i = 0; i < 4; ++i) bytes.push_back(static_cast<std::uint8_t>(d >> (8 * i)));
  bytes.push_back(0x90);
  return bytes;
}

void call_object(std::uintptr_t object) {
  using Call = void (*)(void* self);
  const auto* table = *reinterpret_cast<Call* const*>(object);
  table[queue_check::kCallSlot](reinterpret_cast<void*>(object));
}

namespace {
// Reads up to `count` words from `address` and stops at the first that cannot be read. SEH only: no unwinding here.
std::uint32_t read_words(std::uintptr_t address, std::uintptr_t* out, std::uint32_t count) noexcept {
  std::uint32_t read = 0;
  __try {
    for (; read < count; ++read) out[read] = reinterpret_cast<const volatile std::uintptr_t*>(address)[read];
  } __except (EXCEPTION_EXECUTE_HANDLER) {
  }
  return read;
}
}  // namespace

void Run::begin(const queue_check::List* lists, std::size_t count, Judge judge, void* judge_context,
                unsigned long thread, Caller caller) {
  end();
  count_ = std::min(count, kLists);
  for (std::size_t i = 0; i < kLists; ++i) {
    lists_[i] = i < count_ ? lists[i] : queue_check::List{};
    lengths_[i] = 0;
  }
  judge_ = judge;
  judge_context_ = judge_context;
  caller_ = caller ? caller : &call_object;
  thread_ = thread;
  entries_.clear();
  totals_ = {};
  recorded_ = 0;
  recent_next_ = 0;
  recent_count_ = 0;
}

bool Run::see() noexcept {
  try {
    entries_.clear();
    for (std::size_t l = 0; l < count_; ++l) {
      const queue_check::List& list = lists_[l];
      lengths_[l] = 0;
      if (!list.header || list.arena_end <= list.arena_begin) continue;
      const std::uintptr_t limit = (list.arena_end - list.arena_begin) / queue_check::kElement;
      // Walk it first: every element inside the arena and aligned, no more than the arena holds, the tail its last.
      std::uintptr_t length = 0, last = 0;
      bool walkable = true;
      for (std::uintptr_t e = list.header[0]; e; e = reinterpret_cast<const std::uintptr_t*>(e)[0]) {
        if (list_of(e) != static_cast<int>(l) || ++length > limit) {
          walkable = false;
          break;
        }
        last = e;
      }
      if (!walkable || last != list.header[1]) continue;  // its elements are judged as strangers
      lengths_[l] = static_cast<std::uint32_t>(length);
      std::uint32_t position = 0;
      for (std::uintptr_t e = list.header[0]; e; e = reinterpret_cast<const std::uintptr_t*>(e)[0]) {
        Entry entry;
        const auto* words = reinterpret_cast<const std::uintptr_t*>(e);
        entry.element = e;
        entry.next = words[0];
        entry.object = words[1];
        entry.list = static_cast<std::uint8_t>(l);
        entry.position = position++;
        if (entry.object)
          entry.words_read = static_cast<std::uint8_t>(read_words(entry.object, entry.words, kObjectWords));
        if (e >= list.arena_begin + 16) {
          entry.before[0] = words[-2];
          entry.before[1] = words[-1];
          entry.before_read = true;
        }
        entries_.push_back(entry);
      }
    }
    std::sort(entries_.begin(), entries_.end(),
              [](const Entry& a, const Entry& b) { return a.element < b.element; });
    for (std::size_t i = 1; i < entries_.size(); ++i)
      if (entries_[i].element == entries_[i - 1].element) return false;  // one element in two lists: not watched
    watching_ = true;
    return true;
  } catch (...) {
    entries_.clear();
    watching_ = false;
    return false;
  }
}

void Run::end() noexcept { watching_ = false; }

int Run::list_of(std::uintptr_t element) const noexcept {
  if (!element || (element & 7)) return -1;
  for (std::size_t i = 0; i < count_; ++i) {
    const queue_check::List& list = lists_[i];
    if (element >= list.arena_begin && list.arena_end >= queue_check::kElement &&
        element <= list.arena_end - queue_check::kElement)
      return static_cast<int>(i);
  }
  return -1;
}

Entry* Run::find(std::uintptr_t element) noexcept {
  const auto it = std::lower_bound(entries_.begin(), entries_.end(), element,
                                   [](const Entry& entry, std::uintptr_t value) { return entry.element < value; });
  return it != entries_.end() && it->element == element ? &*it : nullptr;
}

bool Run::plausible(int list, std::uintptr_t next) const noexcept { return !next || list_of(next) == list; }

bool Run::unchanged(const Entry& entry, std::uintptr_t* words_now, std::uint32_t& words) const noexcept {
  words = entry.object ? read_words(entry.object, words_now, entry.words_read) : 0;
  if (words != entry.words_read) return false;
  for (std::uint32_t i = 0; i < words; ++i)
    if (words_now[i] != entry.words[i]) return false;
  if (entry.before_read) {
    const auto* before = reinterpret_cast<const std::uintptr_t*>(entry.element) - 2;
    if (before[0] != entry.before[0] || before[1] != entry.before[1]) return false;
  }
  return entry.words_read > 0;  // an object whose first word could not be read when checked is never run
}

void Run::note(Event event, int list, const Entry* entry, std::uintptr_t element, const std::uintptr_t* words_now,
               std::uint32_t words) noexcept {
  if (recorded_ >= kMaxRecords) return;
  Record& r = records_[recorded_++];
  r = Record{};
  r.event = event;
  r.list = list >= 0 ? static_cast<std::uint32_t>(list) : UINT32_MAX;
  r.position = entry ? entry->position : UINT32_MAX;
  r.length = list >= 0 ? lengths_[list] : 0;
  r.offset = list >= 0 ? element - lists_[list].arena_begin : element;
  if (entry) {
    r.was[0] = entry->next;
    r.was[1] = entry->object;
    r.words = std::min<std::uint32_t>(entry->words_read, kObjectWords);
    for (std::uint32_t i = 0; i < r.words; ++i) r.words_was[i] = entry->words[i];
    r.before_was[0] = entry->before[0];
    r.before_was[1] = entry->before[1];
    r.before_read = entry->before_read;
    if (entry->before_read) {
      const auto* before = reinterpret_cast<const std::uintptr_t*>(element) - 2;
      r.before_now[0] = before[0];
      r.before_now[1] = before[1];
    }
  }
  if (list >= 0) {
    const auto* now = reinterpret_cast<const std::uintptr_t*>(element);
    r.now[0] = now[0];
    r.now[1] = now[1];
  }
  if (words_now)
    for (std::uint32_t i = 0; i < std::min<std::uint32_t>(words, kObjectWords); ++i) r.words_now[i] = words_now[i];
  r.element = element;
  for (std::uint32_t i = 0; i < recent_count_; ++i)
    r.recent[i] = recent_[(recent_next_ + kRecent - 1 - i) % kRecent];
  r.recent_count = recent_count_;
}

void Run::ran(int list, std::uint32_t position, std::uintptr_t table) noexcept {
  recent_[recent_next_] = Recent{static_cast<std::uint32_t>(list), position, table};
  recent_next_ = (recent_next_ + 1) % kRecent;
  if (recent_count_ < kRecent) ++recent_count_;
}

void Run::step(std::uintptr_t* element) noexcept {
  const auto e = reinterpret_cast<std::uintptr_t>(element);
  if (!watching_ || GetCurrentThreadId() != thread_) {
    caller_(element[1]);  // the engine's own dispatch
    return;
  }
  const int list = list_of(e);
  Entry* entry = list >= 0 ? find(e) : nullptr;
  if (entry) {
    if (entry->ran) {
      // A call is never run twice: the list was run again, or a link leads back. End whichever pass follows it.
      note(Event::ran_twice, list, entry, e, nullptr, 0);
      ++totals_.skipped;
      ++totals_.ended;
      element[0] = 0;
      return;
    }
    entry->ran = true;
    if (element[0] != entry->next || element[1] != entry->object) {
      note(Event::put_back, list, entry, e, nullptr, 0);
      element[0] = entry->next;
      element[1] = entry->object;
      ++totals_.put_back;
    }
    std::uintptr_t words_now[kObjectWords] = {};
    std::uint32_t words = 0;
    if (unchanged(*entry, words_now, words)) {
      ran(list, entry->position, entry->words[0]);
      ++totals_.run;
      caller_(entry->object);
    } else {
      note(Event::object_changed, list, entry, e, words_now, words);
      ++totals_.skipped;
    }
    // The link the engine follows next: as the check saw it, or an element appended after the list's last since.
    const std::uintptr_t next = element[0];
    if (next != entry->next) {
      const bool appended = entry->next == 0 && next > e && plausible(list, next) && !find(next);
      if (!appended) {
        note(Event::next_put_back, list, entry, e, nullptr, 0);
        element[0] = entry->next;
        ++totals_.put_back;
      }
    }
    return;
  }
  // An element the check never saw: one appended during the run, one of a list it could not keep, or a stray link.
  ++totals_.strangers;
  if (list < 0) {
    note(Event::stranger, list, nullptr, e, nullptr, 0);
    ++totals_.skipped;
    return;  // outside every arena: nothing of it is read or run
  }
  const std::uintptr_t object = element[1];
  std::uintptr_t table = 0;
  if (totals_.strangers <= kMaxStrangers && judge_ && judge_(judge_context_, object) == queue_check::Why::live &&
      read_words(object, &table, 1) == 1) {
    ran(list, UINT32_MAX, table);
    ++totals_.run;
    caller_(object);
  } else {
    note(Event::stranger, list, nullptr, e, nullptr, 0);
    ++totals_.skipped;
  }
  if (!plausible(list, element[0]) || totals_.strangers >= kMaxStrangers) {
    if (element[0]) {
      note(Event::ended, list, nullptr, e, nullptr, 0);
      element[0] = 0;
      ++totals_.ended;
    }
  }
}

}  // namespace nl::engine_guard::run_check
