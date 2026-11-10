// Windows Error Reporting's snapshot of a crashed game, switched off (R28, ADR 0142).
//
// When the game fails fast, Windows Error Reporting first copies the dying process (a copy-on-write snapshot)
// and Windows charges that copy the game's whole private memory again: with hundreds of add-ons under RTX
// 20 GB and more, at once. On a 24 GB computer that is the freeze, the memory gauge at 97-99 % and the
// gmod.exe that "refuses to close" of GitHub issue 2. With the two flags below the report is made from the
// suspended process itself: the same report and dump, no second copy (measured: +0.06 GB of commit instead
// of +23 GB, the game gone in 5.8 s instead of 11.8 s; docs/handover/issue-2-memory-report.md).
#pragma once

#include <string>

namespace nl::engine_guard::crash_report {

// werapi.h: WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH and _HANG.
inline constexpr unsigned long kNoCrashSnapshot = 128;
inline constexpr unsigned long kNoHangSnapshot = 256;

struct Result {
  bool applied = false;        // the process now has both flags (or the crash flag alone, see reason)
  unsigned long before = 0;    // the process's flags before the call (0 when they could not be read)
  unsigned long after = 0;     // and after it
  std::string reason;          // "ok" (with a note when the flags were set but could not be read back), or
                               // what kept the flags from being set
};

// The flags a process should end up with: what it had, plus the two above.
unsigned long with_snapshots_off(unsigned long flags);

// Sets the two flags for this process, once per process (later calls return the first result). Uses
// kernel32's WerGetFlags and WerSetFlags, resolved at run time; a Windows without them changes nothing.
Result disable_snapshots();

}  // namespace nl::engine_guard::crash_report
