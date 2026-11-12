# queued_draws_server.lua

Server Lua for [queued_draws_session.py](queued_draws_session.py.md), which puts the same `NLQD` settings table in
front of it as for [queued_draws_probe.lua](queued_draws_probe.lua.md) and sends it hex-encoded with `lua_run`
console lines (`poc_session.client_lua_lines`, `lua_run_cl` turned into `lua_run`)
([ADR 0192](../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)). Positions are relative to
the camera's yaw and to the ground under `center` (a downward trace against the world).

- **`stress`**: first `load` citizen ragdolls (default 24), frozen in rows behind the scene: studiorender skins them
  on the CPU (`r_forcehwskin 0`) on the render thread, which lengthens each frame's queued draws
  (`NLQD server render load <n> ragdolls`). Then a 0.05 s timer spawns, around the centre, a watermelon and a wooden crate (`prop_physics`) and breaks
  each the next tick with 1000 damage (client-side gibs), three solid props (a PHX cube, an oil drum, a can) removed
  after 0.1-0.4 s, and with a chance of 0.3 a door (`prop_door_rotating`, `door01_left`) opened at once and removed
  after 0.3-0.8 s; a prop that did not break is removed after a second. Every 10 s it prints
  `NLQD server spawned <n> removed <n> broken <n> doors <n> live <n>`.
- **`lighting`**: a still scene, the same every run: an oil drum, a crate, a watermelon, a PHX cube and a chair
  resting on the ground, a citizen ragdoll 40 units above it and a closed door, each frozen where it spawns. Prints
  `NLQD server lighting scene <n> props, door <true|false> ground <z>`.

Side effects: entities of that session's map only. Exit codes: none (server Lua).
