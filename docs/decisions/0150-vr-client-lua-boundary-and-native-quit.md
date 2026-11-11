# 0150: Any client script can call the VR module, so Lua cannot choose code or filesystem paths

- Status: Accepted 2026-11-10 after the first independent review.
- Context: [Q's review follow-up](../handover/VR-V1-Q-review-report.md). Once a client binary
  module is loaded, every client script can call its Lua functions, including scripts supplied
  by a server. The companion page's host checks are presentation rules, not an authorization boundary.

## Decision

The module finds `openvr_api.dll` and the action manifest from its own installed folder. Lua
Start options named `openvr_dll`, `runtime_dll` or `manifest` are refused. Only a native test
host can supply alternative native paths. Probe returns SDK presence rather than an absolute
DLL path. No string passed by Lua names executable code or a manifest to load
(`vr/native/lua_policy.h:9`, called from `vr/native/module.cpp:81`).

Capture and a scripted timeline take a name of 1 to 64 ASCII letters, digits, underscores or
hyphens. Captures go to `garrysmod/data/nlvr/captures/NAME/`; a timeline is read from
`garrysmod/data/nlvr/timelines/NAME.json`. Windows device names and links are refused. The
launching process alone may set the absolute environment variable `NLVR_TEST_ROOT` to give a
native test another root. `tools/vr_session.py` chooses a folder under `out`, copies a supplied
timeline there and collects the captures afterwards. Lua has no option to change that root.

Client scripts may control their local VR session, input reads, haptics, owned overlays and
these data images. They cannot select a DLL, read an arbitrary timeline path, write an arbitrary
capture folder, operate another application's overlays or change SteamVR settings through this
API. This boundary does not make the page a gate against client scripts stopping local VR.

The native worker polls OpenVR events every 20 ms independently of Lua. A SteamVR quit is
answered with AcknowledgeQuit_Exiting, then ordered session shutdown; the reason survives in
the off state. The page polls from PreRender using RealTime, because a single-player pause stops
CurTime and Lua timers. It shows Stopping VR until off acknowledges SDK release and only then
enables Start again. A native timeline quit event tests this path without quitting SteamVR.

Every Lua caller reads the error result as well as the value, logs a message when it changes
and ends a persistently failing session with the reason on the page. The add-on stops after
30 consecutive frame failures; the page stops after 10 consecutive failed lifecycle polls.
An overlay setup failure makes Start fail. A missing new pose repeats the last pushed camera,
and invalid tracking never supplies an invalid raw head matrix to the compositor.

## Consequences

The module README describes the boundary for each function. Offline tests refuse the removed
path keys, escaping data names, reserved names and linked roots; native paths still support
stand-ins. Lifecycle tests check acknowledgement, restart only after off, last-camera reuse,
changed-message logging, failure thresholds and controller visibility. The PoC's safe quit test
advanced wall time by 9.713 s while CurTime advanced only 0.00835 s, and still acknowledged and
cleaned up the session. SteamVR remained running.

## Alternatives considered

- Trusting only the page's Lua arguments ignores other client scripts calling the same table.
- Allowing an absolute capture path only for tests would expose the same disk write to every
  client script. A launcher-set environment root keeps that choice outside Lua.
- Relying on a Lua timer to answer SteamVR quit leaves a paused single-player game unresponsive
  to the event and lets SteamVR's shutdown policy decide the game's fate.
