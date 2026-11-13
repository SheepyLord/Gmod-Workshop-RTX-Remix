# nativeloader_vr_server.lua: Dormant server switch

Server autorun registers exactly one nlvr network string and receiver, no hook/timer/include while off. It rejects non-player and remote clients before reading a type, accepts only exact 40-bit START with finite scale 10..100 and exact 8-bit STOP. START includes nlvr/server.lua lazily and starts the local host; the last Stop discards that server object. Other messages route only to the active server core. No AddCSLuaFile: V2/V3 are for the package-owning local player; remote distribution is V5. No file writes or game/settings changes while off.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

Single-player only ([ADR 0197](../../../../../docs/decisions/0197-vr-is-single-player-only.md)): the stub accepts a request only while `game.SinglePlayer()` is true; the listen-server host is refused like any other player.
