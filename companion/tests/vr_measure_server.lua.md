# vr_measure_server.lua

Private server-realm instrumentation for nlvr send counts and net.BytesWritten bytes by type.
Injected through the ordinary test admin console. No probe network traffic is added. The report
names its monotonic wall interval, then restores all wrappers and removes the report command.
Outputs one console JSON record. Does not change messages, receivers, ownership or settings;
this is engine send accounting, not Ethernet/IP traffic. Only the test game's process is affected.

The client requests nlvr_q_net_begin at active measurement start; server counters/wall time reset
when that ordinary console command is processed. Report removes both private commands.

Also retains other Lua net channels separately; VR counts keep their type keys. Reports are engine send counts, not NIC packets.

Requires the same read-only nlvrqinspect helper in the server realm. The begin command also
wraps the server module registry, subtracts nested callbacks, counts actual server ticks and
reports Q-server-profile. Exact ticks, elapsed interval and module totals are retained, so
server CPU per tick is distinct from client CPU per rendered frame. Direct receiver work
outside the registry is excluded, and the clock/wrapper overhead is included. The report
restores the registry and removes its private Tick observer before the next session.
