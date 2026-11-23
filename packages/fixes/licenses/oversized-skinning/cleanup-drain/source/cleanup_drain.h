// GPL-2.0, like the rest of the RTX fixes. The native loader's ADR 0262: whether PerformTextureCleanup may uncache
// every material now. UncacheAllMaterials destroys the variables of every file-based material at once, on the calling
// thread. In queued rendering a material-variable setter made on the main thread (IMaterial:SetTexture, SetInt ...
// from Lua) does not write the variable: it waits in the list the main thread records, holding the raw variable
// pointer, and the render thread runs it at the end of the frame (or AllowThreading(false) when the game leaves
// threaded rendering). An uncache with such calls still queued leaves them pointing at freed memory: the field's
// crashes at disconnect (ADR 0261) and the same fault in the middle of a game through rtx_flush_textures or
// RTX_CleanupMapTextures. So the cleanup first has the native loader's engine guard run the calls queued so far,
// through its exported flush (nl_engine_guard_queue_flush_v1 in gmcl_ or gmsv_nlengineguard_win64.dll, the copy that
// installed its queue check), and does not run when nobody can make sure. A single-threaded material system never
// queues, so nothing needs to run first. No SDK and no Windows header: tests/cleanup_drain_test.cpp compiles this file
// alone; the module resolves the exports and passes them in.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace CleanupDrain {

// The engine guard's export (engine_guard/queue_check.cpp in the native loader's repository): -1 when this copy of the
// engine guard did not install its queue check, 1 when what the calling thread had queued has run, 0 when it could not
// make sure; `calls` gets the number of calls it ran, `why` a NUL-terminated reason of at most `size` bytes.
constexpr const char* kExport = "nl_engine_guard_queue_flush_v1";
using QueueFlush = int (*)(std::uint64_t* calls, char* why, std::size_t size);

// The engine guard's two copies, in the order the module asks them (both can be in the process; only one installs).
constexpr std::size_t kCopies = 2;
constexpr std::size_t kReasonSize = 256;

struct Result {
    bool mayRun = false;      // the cleanup may uncache now
    bool flushAsked = false;  // a copy of the engine guard was asked to run the queued calls
    std::uint64_t calls = 0;  // the calls it ran
    char why[kReasonSize] = {};
};

inline void SetReason(Result& result, const char* text) noexcept {
    if (!text) text = "";
    std::size_t n = std::strlen(text);
    if (n >= kReasonSize) n = kReasonSize - 1;
    std::memcpy(result.why, text, n);
    result.why[n] = 0;
}

// singleThreaded: materials && materials->GetThreadMode() == MATERIAL_SINGLE_THREADED. copies: the engine guard's
// exports, one per copy in the order to ask, null for a copy that is not loaded or has no such export. The first copy
// that answers 0 or 1 decides; a copy that answers anything else (-1: it did not install) passes to the next.
inline Result Decide(bool singleThreaded, const QueueFlush* copies, std::size_t count) noexcept {
    Result result;
    if (singleThreaded) {
        result.mayRun = true;
        SetReason(result, "the material system is single-threaded: nothing is queued");
        return result;
    }
    for (std::size_t i = 0; copies && i < count; ++i) {
        if (!copies[i]) continue;
        std::uint64_t calls = 0;
        char why[kReasonSize] = {};
        const int answer = copies[i](&calls, why, sizeof(why));
        why[kReasonSize - 1] = 0;  // whatever the copy wrote
        if (answer != 0 && answer != 1) continue;
        result.flushAsked = true;
        result.calls = calls;
        result.mayRun = answer == 1;
        if (why[0]) {
            SetReason(result, why);
        } else {
            SetReason(result, result.mayRun ? "the queued render calls ran"
                                            : "the engine guard could not make sure the queued render calls ran");
        }
        return result;
    }
    SetReason(result, "the engine guard's queue flush is not available");
    return result;
}

}  // namespace CleanupDrain
