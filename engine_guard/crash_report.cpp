#include "crash_report.h"

#include <windows.h>

#include <mutex>

namespace nl::engine_guard::crash_report {

unsigned long with_snapshots_off(unsigned long flags) { return flags | kNoCrashSnapshot | kNoHangSnapshot; }

namespace {
using GetFlags = HRESULT(WINAPI*)(HANDLE, PDWORD);
using SetFlags = HRESULT(WINAPI*)(DWORD);

Result apply() {
  Result result;
  const HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
  const auto get = kernel ? reinterpret_cast<GetFlags>(GetProcAddress(kernel, "WerGetFlags")) : nullptr;
  const auto set = kernel ? reinterpret_cast<SetFlags>(GetProcAddress(kernel, "WerSetFlags")) : nullptr;
  if (!get || !set) {
    result.reason = "this Windows has no WerGetFlags/WerSetFlags";
    return result;
  }
  DWORD flags = 0;
  // A process that never set a flag has none; a failed read is treated the same (nothing else to keep).
  if (FAILED(get(GetCurrentProcess(), &flags))) flags = 0;
  result.before = flags;
  result.after = flags;
  const DWORD wanted = with_snapshots_off(flags);
  if (wanted == flags) {
    result.applied = true;
    result.reason = "ok";
    return result;
  }
  DWORD expected = wanted;
  HRESULT status = set(wanted);
  if (FAILED(status)) {
    // An older Windows may know the crash flag alone.
    expected = flags | kNoCrashSnapshot;
    status = set(expected);
    if (FAILED(status)) {
      result.reason = "WerSetFlags failed (0x" + [](unsigned long value) {
        char text[9] = {};
        static const char digits[] = "0123456789abcdef";
        for (int i = 7; i >= 0; --i, value >>= 4) text[i] = digits[value & 0xF];
        return std::string(text);
      }(static_cast<unsigned long>(status)) + ")";
      return result;
    }
    result.reason = "crash snapshots off; this Windows refused the hang flag";
  } else {
    result.reason = "ok";
  }
  DWORD now = expected;
  if (FAILED(get(GetCurrentProcess(), &now))) {
    // Set, by the call's own word; they cannot be read back to confirm it, and the reason says so.
    result.after = expected;
    result.applied = true;
    result.reason += " (set; the flags could not be read back)";
    return result;
  }
  result.after = now;
  result.applied = (now & kNoCrashSnapshot) != 0;
  if (!result.applied) result.reason = "WerSetFlags reported success but the flag is not set";
  return result;
}
}  // namespace

Result disable_snapshots() {
  static std::once_flag once;
  static Result first;
  std::call_once(once, [] { first = apply(); });
  return first;
}

}  // namespace nl::engine_guard::crash_report
