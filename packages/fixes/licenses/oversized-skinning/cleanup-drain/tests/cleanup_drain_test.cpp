// GPL-2.0. The native loader's ADR 0262: regression for source/cleanup_drain.h, whether PerformTextureCleanup may
// uncache every material after asking the engine guard to run the render calls queued so far. Compiles alone (no SDK):
// cl /EHsc /std:c++17 /W4 /WX /UNDEBUG tests/cleanup_drain_test.cpp
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include "../source/cleanup_drain.h"

namespace {

int g_asked[2] = {};

void Reset() { g_asked[0] = g_asked[1] = 0; }

void Write(char* why, std::size_t size, const char* text) {
    if (!why || !size) return;
    std::size_t n = std::strlen(text);
    if (n >= size) n = size - 1;
    std::memcpy(why, text, n);
    why[n] = 0;
}

// Stand-ins for nl_engine_guard_queue_flush_v1 in the engine guard's two copies.
int NotInstalledA(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[0];
    if (calls) *calls = 7;  // ignored: this copy did not answer
    Write(why, size, "not installed");
    return -1;
}
int NotInstalledB(std::uint64_t*, char*, std::size_t) {
    ++g_asked[1];
    return -1;
}
int RanA(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[0];
    if (calls) *calls = 234;
    Write(why, size, "ran 234 queued render call(s)");
    return 1;
}
int RanB(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[1];
    if (calls) *calls = 12;
    Write(why, size, "ran 12 queued render call(s)");
    return 1;
}
int RefusedA(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[0];
    if (calls) *calls = 0;
    Write(why, size, "not on the main thread");
    return 0;
}
int RefusedSilentA(std::uint64_t*, char*, std::size_t) {
    ++g_asked[0];
    return 0;
}
int HugeA(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[0];
    if (calls) *calls = std::numeric_limits<std::uint64_t>::max();
    Write(why, size, "ran");
    return 1;
}
int RanSilentB(std::uint64_t* calls, char*, std::size_t) {
    ++g_asked[1];
    if (calls) *calls = 3;
    return 1;
}
int UnterminatedA(std::uint64_t* calls, char* why, std::size_t size) {
    ++g_asked[0];
    if (calls) *calls = 1;
    for (std::size_t i = 0; i < size; ++i) why[i] = 'x';  // no NUL: the decision ends it
    return 1;
}

std::string Why(const CleanupDrain::Result& result) { return std::string(result.why); }

}  // namespace

int main() {
    using CleanupDrain::Decide;
    using CleanupDrain::QueueFlush;

    // Single-threaded: nothing is ever queued; the cleanup runs and no copy is asked.
    {
        Reset();
        const QueueFlush copies[2] = {RanA, RanB};
        const auto result = Decide(true, copies, 2);
        assert(result.mayRun && !result.flushAsked && result.calls == 0 && !Why(result).empty());
        assert(g_asked[0] == 0 && g_asked[1] == 0 && "no flush asked when single-threaded");
        const auto none = Decide(true, nullptr, 0);
        assert(none.mayRun && !none.flushAsked);
    }
    // The first copy runs the calls: its count and reason; the second is not asked.
    {
        Reset();
        const QueueFlush copies[2] = {RanA, RanB};
        const auto result = Decide(false, copies, 2);
        assert(result.mayRun && result.flushAsked && result.calls == 234);
        assert(Why(result) == "ran 234 queued render call(s)");
        assert(g_asked[0] == 1 && g_asked[1] == 0);
    }
    // The first did not install (-1), the second ran them: the second decides, the first's count is not kept.
    {
        Reset();
        const QueueFlush copies[2] = {NotInstalledA, RanB};
        const auto result = Decide(false, copies, 2);
        assert(result.mayRun && result.flushAsked && result.calls == 12 && Why(result) == "ran 12 queued render call(s)");
        assert(g_asked[0] == 1 && g_asked[1] == 1);
    }
    // The first could not make sure (0): refused with its reason; the second is not asked.
    {
        Reset();
        const QueueFlush copies[2] = {RefusedA, RanB};
        const auto result = Decide(false, copies, 2);
        assert(!result.mayRun && result.flushAsked && result.calls == 0 && Why(result) == "not on the main thread");
        assert(g_asked[0] == 1 && g_asked[1] == 0);
    }
    // Both copies loaded, neither installed: refused, not available.
    {
        Reset();
        const QueueFlush copies[2] = {NotInstalledA, NotInstalledB};
        const auto result = Decide(false, copies, 2);
        assert(!result.mayRun && !result.flushAsked && result.calls == 0);
        assert(Why(result) == "the engine guard's queue flush is not available");
        assert(g_asked[0] == 1 && g_asked[1] == 1);
    }
    // No copy loaded (or no such export): refused.
    {
        const QueueFlush copies[2] = {nullptr, nullptr};
        const auto result = Decide(false, copies, 2);
        assert(!result.mayRun && !result.flushAsked && Why(result) == "the engine guard's queue flush is not available");
        const auto none = Decide(false, nullptr, 2);
        assert(!none.mayRun && !none.flushAsked);
    }
    // A null between: passed over.
    {
        Reset();
        const QueueFlush copies[3] = {nullptr, NotInstalledB, RanA};
        const auto result = Decide(false, copies, 3);
        assert(result.mayRun && result.calls == 234 && g_asked[0] == 1 && g_asked[1] == 1);
    }
    // A huge count is kept as it is.
    {
        Reset();
        const QueueFlush copies[2] = {HugeA, RanB};
        const auto result = Decide(false, copies, 2);
        assert(result.mayRun && result.calls == std::numeric_limits<std::uint64_t>::max());
    }
    // An empty reason: a text of its own, for either answer.
    {
        Reset();
        const QueueFlush refused[2] = {RefusedSilentA, RanB};
        const auto no = Decide(false, refused, 2);
        assert(!no.mayRun && no.flushAsked && !Why(no).empty() && g_asked[1] == 0);
        const QueueFlush ran[2] = {nullptr, RanSilentB};
        const auto yes = Decide(false, ran, 2);
        assert(yes.mayRun && yes.calls == 3 && !Why(yes).empty());
    }
    // A reason the copy did not end: cut at the buffer's size.
    {
        Reset();
        const QueueFlush copies[1] = {UnterminatedA};
        const auto result = Decide(false, copies, 1);
        assert(result.mayRun && Why(result).size() == CleanupDrain::kReasonSize - 1);
    }
    assert(std::string(CleanupDrain::kExport) == "nl_engine_guard_queue_flush_v1");
    std::cout << "PASS cleanup drain: no flush when single-threaded; the first engine guard copy that answers 0 or 1 "
                 "decides (its count and reason kept), -1 and missing copies passed over, none answering refuses\n";
    return 0;
}
