# vr_measure_probe.lua

Private measurement fixture appended inside the standard VR probe. Requires the read-only
nlvrqinspect helper. Attributes exclusive (nested callbacks subtracted) GetThreadTimes CPU ms,
QueryThreadCycleTime cycles and SysTime elapsed ms to module registry calls on the actual game
thread. CPU clocks are quantized; receipts explicitly include wrapper/clock overhead and never
substitute elapsed time for CPU time. Counts rendered frames and client nlvr sends/engine-reported
bytes by type. Outputs bounded console records through the standard emitter. Restores wrappers
at Exit and observes the absent off-state registry. Starts no SDK and changes no production code.

Requests the private server accounting reset at active start; the server's own receipt retains
its exact processed interval instead of including long fixture installation time.

Includes zero-call registry modules explicitly in CPU totals; those entries are measured zero callbacks, not omitted data.
The client denominator is distinct FrameNumber values at active PostRender, with the raw
PostRender callback count and first/last source frame also retained. It is not submitted eye
pairs. Earlier receipts with only PostRender counts remain explicitly labelled as such.

Also retains non-VR Lua net send counts separately by channel. These exclude engine user commands/snapshot datagrams; no payload contents are inspected.
