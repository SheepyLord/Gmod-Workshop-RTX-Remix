# Shared VR crash classification

Read-only bounded AMD64 minidump parser. The shared driver copies only the exact
`gmod.exe.<pid>.dmp` from the user-specified WER LocalDumps folder under the legacy
install into its own run evidence. It never creates, deletes, moves or writes a
source file there. Source size/time and complete SHA-256 are checked against the
copy; incomplete copies remain evidence and cannot authorize retry.

`python -B tools/vr_crash.py <copied dump> --out <out receipt> [--startup]` parses
the exception stream's context (not the thread-list context), finds the faulting
thread's captured stack at that RSP and scans aligned return-address words, bounded
to 8 MiB. Both Memory64List and MemoryList dumps are supported. No external parser,
SDK, target process or binary execution is required.

User-reviewed rule: gmcl_RTXFixesBinary_win64.dll timestamp `0x6af185ec` and stack
return `+0x41605b` is the known queued-render freed-entity crash. The separate known
NVIDIA rule requires startup and nvoglv64.dll exception RIP `+0xe622f8`. Unknown,
wrong-build, absent/truncated memory or a second consecutive crash cannot retry.
Receipts include exception context, scanned range and exact matched stack address;
they do not infer a new cause from a raw stack match. Standalone exit 0 means the
receipt was written, not that the crash is known; parser errors classify unknown.

Layouts follow Microsoft's [exception stream](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/ns-minidumpapiset-minidump_exception_stream),
[module record](https://learn.microsoft.com/en-us/windows/win32/api/minidumpapiset/ns-minidumpapiset-minidump_module)
and [AMD64 context](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-context).

The shared recorder keeps Application event1000 and all dump classifications in crash.json. Existing event evidence is retained. The copier refuses any destination under the legacy install or source folder. Windows unused directory padding is valid. Actual reviewed dumps for PID49376,22984,50472 match the timestamped return address using their exception RSPs. The driver re-executes the full caller for a single known-crash retry; a durable claim prevents another process reusing that permission.

Round5: after the reviewed queued-draw repair, any fixes stack marker (including an unreviewed build) stops; only the NVIDIA startup signature permits one restored fresh-folder retry. Old receipt flags cannot override current policy. The normal field-quit helper is driver-only; exit5 after a quit crash is fatal and its evidence is retained.
